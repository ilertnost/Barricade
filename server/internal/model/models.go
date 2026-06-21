package model

import "time"

type User struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	DisplayName  string    `json:"display_name"`
	PasswordHash string    `json:"-"`
	AvatarID     *string   `json:"avatar_id"`
	DeviceID     string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type Message struct {
	ID                string      `json:"id"`
	ChannelID         string      `json:"channel_id"`
	SenderID          string      `json:"sender_id"`
	SenderUsername    string      `json:"sender_username"`
	SenderDisplayName string      `json:"sender_display_name"`
	Content           string      `json:"content"`
	FileID            *string     `json:"file_id"`
	MimeType          string      `json:"mime_type"`
	ReplyToID         *string     `json:"reply_to_id"`
	Status            string      `json:"status"`
	CreatedAt         time.Time   `json:"created_at"`
	EditedAt          *time.Time  `json:"edited_at,omitempty"`
	Reactions         []Reaction  `json:"reactions,omitempty"`
}

type Reaction struct {
	MessageID string    `json:"message_id"`
	UserID    string    `json:"user_id"`
	Emoji     string    `json:"emoji"`
	Username  string    `json:"username,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type ChannelType string

const (
	ChannelDM      ChannelType = "dm"
	ChannelGroup   ChannelType = "group"
	ChannelGuild   ChannelType = "guild"
)

type Channel struct {
	ID         string      `json:"id"`
	Name       string      `json:"name"`
	Username   string      `json:"username"`
	Type       ChannelType `json:"type"`
	OwnerID    string      `json:"owner_id"`
	Visibility string      `json:"visibility"`
	CreatedAt  time.Time   `json:"created_at"`
}

// MemberInfo is a channel member's profile plus their role in that channel.
type MemberInfo struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	DisplayName string `json:"display_name"`
	AvatarID    *string `json:"avatar_id"`
	Role        string `json:"role"`
}

type ChannelMember struct {
	ChannelID string    `json:"channel_id"`
	UserID    string    `json:"user_id"`
	Role      string    `json:"role"`
	JoinedAt  time.Time `json:"joined_at"`
}

type File struct {
	ID           string    `json:"id"`
	OriginalName string    `json:"original_name"`
	MimeType     string    `json:"mime_type"`
	Size         int64     `json:"size"`
	Width        int       `json:"width,omitempty"`
	Height       int       `json:"height,omitempty"`
	Duration     float64   `json:"duration,omitempty"`
	UploadedBy   string    `json:"uploaded_by"`
	CreatedAt    time.Time `json:"created_at"`
}

type VoiceState struct {
	UserID    string `json:"user_id"`
	ChannelID string `json:"channel_id"`
	Muted     bool   `json:"muted"`
	Deafened  bool   `json:"deafened"`
}

type WSMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

type SendMessagePayload struct {
	ChannelID string  `json:"channel_id"`
	Content   string  `json:"content"`
	FileID    *string `json:"file_id,omitempty"`
	ReplyToID *string `json:"reply_to_id,omitempty"`
}
