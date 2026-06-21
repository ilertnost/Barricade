package ws

import (
	"encoding/json"
	"log"
	"time"

	"barricade/internal/db"
	"barricade/internal/model"

	"github.com/google/uuid"
)

type pendingOfferEntry struct {
	targetID string
	msg      OutgoingMessage
}

type Hub struct {
	DB              *db.DB
	clients         map[string]*Client
	channels        map[string]map[string]*Client
	Register        chan *Client
	Unregister      chan *Client
	pendingOffers   map[string]OutgoingMessage
	pendingOfferReq chan pendingOfferEntry
}

func NewHub(database *db.DB) *Hub {
	return &Hub{
		DB:              database,
		clients:         make(map[string]*Client),
		channels:        make(map[string]map[string]*Client),
		Register:        make(chan *Client),
		Unregister:      make(chan *Client),
		pendingOffers:   make(map[string]OutgoingMessage),
		pendingOfferReq: make(chan pendingOfferEntry, 64),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.clients[client.UserID] = client
			if offer, ok := h.pendingOffers[client.UserID]; ok {
				log.Printf("delivering pending offer to user %s", client.Username)
				client.SendJSON(offer)
				delete(h.pendingOffers, client.UserID)
			}
			log.Printf("user %s connected", client.Username)
			go h.broadcastPresence(client.UserID, true)

		case client := <-h.Unregister:
			delete(h.clients, client.UserID)
			for chID := range h.channels {
				delete(h.channels[chID], client.UserID)
			}
			close(client.Send)
			go func() {
				h.DB.UpdateLastSeen(client.UserID)
				h.broadcastPresence(client.UserID, false)
			}()
			log.Printf("user %s disconnected", client.Username)

		case entry := <-h.pendingOfferReq:
			h.pendingOffers[entry.targetID] = entry.msg
		}
	}
}

func (h *Hub) broadcastPresence(userID string, online bool) {
	channels, err := h.DB.GetUserChannels(userID)
	if err != nil {
		return
	}
	notified := map[string]bool{}
	for _, ch := range channels {
		members, _ := h.DB.GetChannelMembers(ch.ID)
		for _, m := range members {
			if m.ID != userID && !notified[m.ID] {
				notified[m.ID] = true
				h.BroadcastToUser(m.ID, OutgoingMessage{
					Type: "user_presence",
					Payload: map[string]interface{}{
						"user_id": userID,
						"online":  online,
					},
				})
			}
		}
	}
}

func (h *Hub) handleMessage(client *Client, raw []byte) {
	var msg IncomingMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		client.SendError("invalid message format")
		return
	}

	switch msg.Type {
	case "send_message":
		h.handleSendMessage(client, msg.Payload)
	case "edit_message":
		h.handleEditMessage(client, msg.Payload)
	case "delete_message":
		h.handleDeleteMessage(client, msg.Payload)
	case "create_channel":
		h.handleCreateChannel(client, msg.Payload)
	case "join_channel":
		h.handleJoinChannel(client, msg.Payload)
	case "typing":
		h.handleTyping(client, msg.Payload)
	case "voice_state_update":
		h.handleVoiceStateUpdate(client, msg.Payload)
	case "reaction_add":
		h.handleAddReaction(client, msg.Payload)
	case "reaction_remove":
		h.handleRemoveReaction(client, msg.Payload)
	case "webrtc":
		h.handleWebRTC(client, msg.Payload)
	case "message_read":
		h.handleReadMessage(client, msg.Payload)
	default:
		client.SendError("unknown message type")
	}
}

func (h *Hub) handleSendMessage(client *Client, payload json.RawMessage) {
	var p SendMessagePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	if !h.isMember(client.UserID, p.ChannelID) {
		client.SendError("not a member of this channel")
		return
	}
	// Broadcast channels (type "guild"): only owner/admin may post.
	if ch, err := h.DB.GetChannel(p.ChannelID); err == nil && ch.Type == "guild" {
		role, _ := h.DB.GetMemberRole(p.ChannelID, client.UserID)
		if role != "owner" && role != "admin" {
			client.SendError("only admins can post in this channel")
			return
		}
	}

	mimeType := ""
	if p.FileID != nil {
		f, err := h.DB.GetFile(*p.FileID)
		if err == nil {
			mimeType = f.MimeType
		}
	}
	msg := &model.Message{
		ID:                uuid.New().String(),
		ChannelID:         p.ChannelID,
		SenderID:          client.UserID,
		SenderUsername:    client.Username,
		SenderDisplayName: client.DisplayName,
		Content:           p.Content,
		FileID:            p.FileID,
		MimeType:          mimeType,
		ReplyToID:         p.ReplyToID,
		CreatedAt:         time.Now().UTC(),
		Reactions:         []model.Reaction{},
	}
	if err := h.DB.SaveMessage(msg); err != nil {
		log.Printf("save message: %v", err)
		client.SendError("failed to save message")
		return
	}
	h.broadcast(p.ChannelID, OutgoingMessage{Type: "new_message", Payload: msg})
}

func (h *Hub) handleEditMessage(client *Client, payload json.RawMessage) {
	var p EditMessagePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	msg, err := h.DB.GetMessage(p.MessageID)
	if err != nil {
		client.SendError("message not found")
		return
	}
	if msg.SenderID != client.UserID {
		client.SendError("not your message")
		return
	}
	if err := h.DB.EditMessage(p.MessageID, p.Content); err != nil {
		client.SendError("failed to edit message")
		return
	}
	msg.Content = p.Content
	now := time.Now().UTC()
	msg.EditedAt = &now
	h.broadcast(msg.ChannelID, OutgoingMessage{Type: "message_updated", Payload: msg})
}

func (h *Hub) handleDeleteMessage(client *Client, payload json.RawMessage) {
	var p DeleteMessagePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	msg, err := h.DB.GetMessage(p.MessageID)
	if err != nil {
		client.SendError("message not found")
		return
	}
	if msg.SenderID != client.UserID {
		client.SendError("not your message")
		return
	}
	if err := h.DB.DeleteMessage(p.MessageID); err != nil {
		client.SendError("failed to delete message")
		return
	}
	h.broadcast(msg.ChannelID, OutgoingMessage{
		Type: "message_deleted",
		Payload: map[string]string{
			"message_id": p.MessageID,
			"channel_id": msg.ChannelID,
		},
	})
}

func (h *Hub) handleCreateChannel(client *Client, payload json.RawMessage) {
	var p CreateChannelPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}

	now := time.Now().UTC()
	ch := &model.Channel{
		ID:        uuid.New().String(),
		Name:      p.Name,
		Type:      model.ChannelType(p.Type),
		OwnerID:   client.UserID,
		CreatedAt: now,
	}
	if err := h.DB.CreateChannel(ch); err != nil {
		client.SendError("failed to create channel")
		return
	}

	members := append(p.MemberIDs, client.UserID)
	for _, uid := range members {
		h.DB.AddChannelMember(&model.ChannelMember{
			ChannelID: ch.ID,
			UserID:    uid,
			Role:      "member",
			JoinedAt:  now,
		})
	}
	msg := OutgoingMessage{Type: "channel_created", Payload: ch}
	h.BroadcastToUser(client.UserID, msg)
	for _, uid := range p.MemberIDs {
		h.BroadcastToUser(uid, msg)
	}
}

func (h *Hub) handleJoinChannel(client *Client, payload json.RawMessage) {
	var p struct {
		ChannelID string `json:"channel_id"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	if _, ok := h.channels[p.ChannelID]; !ok {
		h.channels[p.ChannelID] = make(map[string]*Client)
	}
	h.channels[p.ChannelID][client.UserID] = client
	log.Printf("user %s joined channel %s", client.Username, p.ChannelID)
}

func (h *Hub) handleTyping(client *Client, payload json.RawMessage) {
	var p TypingPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	h.broadcast(p.ChannelID, OutgoingMessage{
		Type: "typing",
		Payload: map[string]string{
			"channel_id": p.ChannelID,
			"user_id":    client.UserID,
			"username":   client.Username,
		},
	})
}

func (h *Hub) handleVoiceStateUpdate(client *Client, payload json.RawMessage) {
	var p VoiceStateUpdatePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	vs := &model.VoiceState{
		UserID:    client.UserID,
		ChannelID: p.ChannelID,
		Muted:     p.Muted,
		Deafened:  p.Deafened,
	}
	h.DB.SetVoiceState(vs)
	h.broadcast(p.ChannelID, OutgoingMessage{
		Type:    "voice_state_updated",
		Payload: vs,
	})
}

func (h *Hub) handleWebRTC(client *Client, payload json.RawMessage) {
	var p WebRTCPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid webrtc payload")
		return
	}
	msg := OutgoingMessage{
		Type: "webrtc",
		Payload: map[string]interface{}{
			"channel_id": p.ChannelID,
			"type":       p.Type,
			"data":       p.Data,
			"from_id":    client.UserID,
		},
	}
	if p.Type != "offer" {
		// Only pending-offer on disconnect makes sense; other types (answer, candidate, end_call)
		// are only meaningful when the target is connected.
		if target, ok := h.clients[p.TargetID]; ok {
			target.SendJSON(msg)
		}
		return
	}
	// For offers: check if target is online first, then try direct send.
	// If target is not in clients map, store via the serialized channel.
	if target, ok := h.clients[p.TargetID]; ok {
		target.SendJSON(msg)
	} else {
		h.pendingOfferReq <- pendingOfferEntry{targetID: p.TargetID, msg: msg}
		log.Printf("stored pending offer for user %s", p.TargetID)
	}
}

func (h *Hub) handleAddReaction(client *Client, payload json.RawMessage) {
	var p AddReactionPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	msg, err := h.DB.GetMessage(p.MessageID)
	if err != nil {
		client.SendError("message not found")
		return
	}
	if !h.isMember(client.UserID, msg.ChannelID) {
		client.SendError("not a member of this channel")
		return
	}
	if err := h.DB.AddReaction(p.MessageID, client.UserID, p.Emoji, client.Username); err != nil {
		log.Printf("add reaction: %v", err)
		client.SendError("failed to add reaction")
		return
	}
	h.broadcast(msg.ChannelID, OutgoingMessage{
		Type: "reaction_add",
		Payload: map[string]interface{}{
			"message_id": p.MessageID,
			"user_id":    client.UserID,
			"emoji":      p.Emoji,
			"username":   client.Username,
		},
	})
}

func (h *Hub) handleRemoveReaction(client *Client, payload json.RawMessage) {
	var p RemoveReactionPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	msg, err := h.DB.GetMessage(p.MessageID)
	if err != nil {
		client.SendError("message not found")
		return
	}
	if !h.isMember(client.UserID, msg.ChannelID) {
		client.SendError("not a member of this channel")
		return
	}
	if err := h.DB.RemoveReaction(p.MessageID, client.UserID, p.Emoji); err != nil {
		log.Printf("remove reaction: %v", err)
		client.SendError("failed to remove reaction")
		return
	}
	h.broadcast(msg.ChannelID, OutgoingMessage{
		Type: "reaction_remove",
		Payload: map[string]interface{}{
			"message_id": p.MessageID,
			"user_id":    client.UserID,
			"emoji":      p.Emoji,
		},
	})
}

func (h *Hub) broadcast(channelID string, msg OutgoingMessage) {
	data, _ := json.Marshal(msg)
	if clients, ok := h.channels[channelID]; ok {
		for _, client := range clients {
			select {
			case client.Send <- data:
			default:
			}
		}
	}
}

func (h *Hub) BroadcastToUser(userID string, msg OutgoingMessage) {
	data, _ := json.Marshal(msg)
	if client, ok := h.clients[userID]; ok {
		select {
		case client.Send <- data:
		default:
		}
	}
}

func (h *Hub) BroadcastToChannel(channelID string, msg OutgoingMessage) {
	data, _ := json.Marshal(msg)
	for _, client := range h.channels[channelID] {
		select {
		case client.Send <- data:
		default:
		}
	}
}

func (h *Hub) IsUserOnline(userID string) bool {
	_, ok := h.clients[userID]
	return ok
}

func (h *Hub) isMember(userID, channelID string) bool {
	members, err := h.DB.GetChannelMembers(channelID)
	if err != nil {
		return false
	}
	for _, m := range members {
		if m.ID == userID {
			return true
		}
	}
	return false
}

func (h *Hub) handleReadMessage(client *Client, payload json.RawMessage) {
	var p ReadMessagePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		client.SendError("invalid payload")
		return
	}
	if !h.isMember(client.UserID, p.ChannelID) {
		return
	}
	h.DB.UpdateMessagesReadByChannel(p.ChannelID, client.UserID)
	h.BroadcastToChannel(p.ChannelID, OutgoingMessage{
		Type: "message_status_updated",
		Payload: map[string]interface{}{
			"channel_id": p.ChannelID,
			"status":     "read",
			"read_by":    client.UserID,
		},
	})
}
