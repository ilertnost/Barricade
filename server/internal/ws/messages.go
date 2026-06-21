package ws

import "encoding/json"

type IncomingMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

type OutgoingMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

type SendMessagePayload struct {
	ChannelID string  `json:"channel_id"`
	Content   string  `json:"content"`
	FileID    *string `json:"file_id,omitempty"`
	ReplyToID *string `json:"reply_to_id,omitempty"`
}

type EditMessagePayload struct {
	MessageID string `json:"message_id"`
	Content   string `json:"content"`
}

type DeleteMessagePayload struct {
	MessageID string `json:"message_id"`
}

type CreateChannelPayload struct {
	Name     string   `json:"name"`
	Type     string   `json:"type"`
	MemberIDs []string `json:"member_ids"`
}

type VoiceStateUpdatePayload struct {
	ChannelID string `json:"channel_id"`
	Muted     bool   `json:"muted"`
	Deafened  bool   `json:"deafened"`
}

type WebRTCPayload struct {
	ChannelID string          `json:"channel_id"`
	Type      string          `json:"type"`
	Data      json.RawMessage `json:"data"`
	TargetID  string          `json:"target_id"`
}

type TypingPayload struct {
	ChannelID string `json:"channel_id"`
}

type AddReactionPayload struct {
	MessageID string `json:"message_id"`
	Emoji     string `json:"emoji"`
}

type RemoveReactionPayload struct {
	MessageID string `json:"message_id"`
	Emoji     string `json:"emoji"`
}

type ReadMessagePayload struct {
	ChannelID string `json:"channel_id"`
}
