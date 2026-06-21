package api

import (
	"encoding/json"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"mime"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"barricade/internal/auth"
	"barricade/internal/db"
	"barricade/internal/file"
	"barricade/internal/model"
	"barricade/internal/ws"

	"github.com/google/uuid"
)

type Handler struct {
	DB    *db.DB
	Store *file.Store
	Hub   *ws.Hub
}

func NewHandler(database *db.DB, store *file.Store, hub *ws.Hub) *Handler {
	return &Handler{DB: database, Store: store, Hub: hub}
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username       string `json:"username"`
		Password       string `json:"password"`
		DeviceID       string `json:"device_id"`
		RecoveryPhrase string `json:"recovery_phrase"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	if len(req.Username) < 3 || len(req.Password) < 4 {
		jsonError(w, "username min 3 chars, password min 4 chars", http.StatusBadRequest)
		return
	}
	if _, err := h.DB.GetUserByUsername(req.Username); err == nil {
		jsonError(w, "username taken", http.StatusConflict)
		return
	}
	// device_id uniqueness intentionally NOT enforced — multiple accounts may be
	// registered from the same device (useful for testing groups/DMs solo).

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}

	user := &model.User{
		ID:           uuid.New().String(),
		Username:     req.Username,
		DisplayName:  req.Username,
		PasswordHash: hash,
		DeviceID:     req.DeviceID,
		CreatedAt:    time.Now().UTC(),
	}
	if err := h.DB.CreateUser(user); err != nil {
		jsonError(w, "failed to create user", http.StatusInternalServerError)
		return
	}
	// Store recovery phrase hash (optional) for self-service password reset.
	if req.RecoveryPhrase != "" {
		if rh, err := auth.HashPassword(req.RecoveryPhrase); err == nil {
			h.DB.SetRecoveryHash(user.ID, rh)
		}
	}

	token, err := auth.GenerateToken(user.ID, user.Username, user.DisplayName)
	if err != nil {
		jsonError(w, "failed to generate token", http.StatusInternalServerError)
		return
	}

	jsonResp(w, http.StatusCreated, map[string]interface{}{
		"token": token,
		"user":  user,
	})
}

func (h *Handler) CheckDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	if req.DeviceID == "" {
		jsonResp(w, http.StatusOK, map[string]interface{}{"registered": false})
		return
	}
	_, err := h.DB.GetUserByDeviceID(req.DeviceID)
	jsonResp(w, http.StatusOK, map[string]interface{}{"registered": err == nil})
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}

	user, err := h.DB.GetUserByUsername(req.Username)
	if err != nil {
		jsonError(w, "invalid credentials", http.StatusUnauthorized)
		return
	}
	if !auth.CheckPassword(req.Password, user.PasswordHash) {
		jsonError(w, "invalid credentials", http.StatusUnauthorized)
		return
	}

	token, err := auth.GenerateToken(user.ID, user.Username, user.DisplayName)
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}

	jsonResp(w, http.StatusOK, map[string]interface{}{
		"token": token,
		"user":  user,
	})
}

// ResetPassword: public. Verify recovery phrase, then set a new password.
func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username       string `json:"username"`
		RecoveryPhrase string `json:"recovery_phrase"`
		NewPassword    string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	if len(req.NewPassword) < 4 {
		jsonError(w, "password min 4 chars", http.StatusBadRequest)
		return
	}
	recoveryHash, userID, err := h.DB.GetRecoveryByUsername(req.Username)
	if err != nil {
		jsonError(w, "invalid username or recovery phrase", http.StatusUnauthorized)
		return
	}
	if recoveryHash == "" {
		jsonError(w, "no recovery phrase set for this account", http.StatusBadRequest)
		return
	}
	if !auth.CheckPassword(req.RecoveryPhrase, recoveryHash) {
		jsonError(w, "invalid username or recovery phrase", http.StatusUnauthorized)
		return
	}
	hash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	h.DB.UpdatePassword(userID, hash)
	jsonResp(w, http.StatusOK, map[string]string{"status": "ok"})
}

// ChangePassword: authed. Verify old password, then set a new one.
func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	var req struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	if len(req.NewPassword) < 4 {
		jsonError(w, "password min 4 chars", http.StatusBadRequest)
		return
	}
	user, err := h.DB.GetUser(userID)
	if err != nil {
		jsonError(w, "user not found", http.StatusNotFound)
		return
	}
	if !auth.CheckPassword(req.OldPassword, user.PasswordHash) {
		jsonError(w, "current password is incorrect", http.StatusUnauthorized)
		return
	}
	hash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	h.DB.UpdatePassword(userID, hash)
	jsonResp(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	user, err := h.DB.GetUser(userID)
	if err != nil {
		jsonError(w, "user not found", http.StatusNotFound)
		return
	}
	jsonResp(w, http.StatusOK, user)
}

func (h *Handler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	var req struct {
		Username    *string `json:"username"`
		DisplayName *string `json:"display_name"`
		AvatarID    *string `json:"avatar_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	if req.Username != nil {
		if len(*req.Username) < 3 {
			jsonError(w, "username min 3 chars", http.StatusBadRequest)
			return
		}
		if existing, err := h.DB.GetUserByUsername(*req.Username); err == nil && existing.ID != userID {
			jsonError(w, "username taken", http.StatusConflict)
			return
		}
		if err := h.DB.UpdateUsername(userID, *req.Username); err != nil {
			jsonError(w, "failed to update username", http.StatusInternalServerError)
			return
		}
	}
	if req.DisplayName != nil {
		if err := h.DB.UpdateUserDisplayName(userID, *req.DisplayName); err != nil {
			jsonError(w, "failed to update display name", http.StatusInternalServerError)
			return
		}
	}
	if req.AvatarID != nil {
		if err := h.DB.UpdateUserAvatar(userID, req.AvatarID); err != nil {
			jsonError(w, "failed to update avatar", http.StatusInternalServerError)
			return
		}
	}
	user, err := h.DB.GetUser(userID)
	if err != nil {
		jsonError(w, "user not found", http.StatusNotFound)
		return
	}
	jsonResp(w, http.StatusOK, user)
}

func (h *Handler) GetUsers(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	var users []*model.User
	var err error
	if query != "" {
		users, err = h.DB.SearchUsers(query)
	} else {
		users, err = h.DB.GetUsers()
	}
	if err != nil {
		jsonError(w, "failed to get users", http.StatusInternalServerError)
		return
	}
	jsonResp(w, http.StatusOK, users)
}

func (h *Handler) CreateChannel(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	var req struct {
		Name       string   `json:"name"`
		Username   string   `json:"username"`
		Type       string   `json:"type"`
		MemberIDs  []string `json:"member_ids"`
		Visibility string   `json:"visibility"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		jsonError(w, "name required", http.StatusBadRequest)
		return
	}
	if req.Type == "" {
		req.Type = "group"
	}
	if req.Type != "group" && req.Type != "guild" && req.Type != "dm" {
		jsonError(w, "type must be dm, group or guild", http.StatusBadRequest)
		return
	}
	if req.Visibility == "" {
		req.Visibility = "public"
	}
	req.Username = strings.ToLower(strings.TrimSpace(req.Username))
	if req.Username != "" {
		if !validChannelUsername(req.Username) {
			jsonError(w, "username must be 3-32 chars: a-z, 0-9, _", http.StatusBadRequest)
			return
		}
		if _, err := h.DB.GetChannelByUsername(req.Username); err == nil {
			jsonError(w, "channel username taken", http.StatusConflict)
			return
		}
	}
	ch := &model.Channel{
		ID:         uuid.New().String(),
		Name:       req.Name,
		Username:   req.Username,
		Type:       model.ChannelType(req.Type),
		OwnerID:    userID,
		Visibility: req.Visibility,
		CreatedAt:  time.Now().UTC(),
	}
	if err := h.DB.CreateChannel(ch); err != nil {
		jsonError(w, "failed to create channel", http.StatusInternalServerError)
		return
	}
	h.DB.AddChannelMember(&model.ChannelMember{
		ChannelID: ch.ID,
		UserID:    userID,
		Role:      "owner",
		JoinedAt:  time.Now().UTC(),
	})
	memberIDs := append([]string{}, req.MemberIDs...)
	for _, mid := range req.MemberIDs {
		h.DB.AddChannelMember(&model.ChannelMember{
			ChannelID: ch.ID,
			UserID:    mid,
			Role:      "member",
			JoinedAt:  time.Now().UTC(),
		})
	}
	jsonResp(w, http.StatusCreated, ch)
	// broadcast via WebSocket to all members so their client list updates
	allIDs := append(memberIDs, userID)
	for _, uid := range allIDs {
		h.Hub.BroadcastToUser(uid, ws.OutgoingMessage{Type: "channel_created", Payload: ch})
	}
}

func (h *Handler) DeleteChannel(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")

	ch, err := h.DB.GetChannel(channelID)
	if err != nil {
		jsonError(w, "channel not found", http.StatusNotFound)
		return
	}
	if ch.OwnerID != userID && ch.Type != model.ChannelDM {
		jsonError(w, "only owner can delete channel", http.StatusForbidden)
		return
	}

	members, _ := h.DB.GetChannelMembers(channelID)
	memberIDs := make([]string, len(members))
	for i, m := range members {
		memberIDs[i] = m.ID
	}

	if err := h.DB.DeleteChannel(channelID); err != nil {
		jsonError(w, "failed to delete channel", http.StatusInternalServerError)
		return
	}

	jsonResp(w, http.StatusOK, map[string]string{"status": "deleted"})

	for _, uid := range memberIDs {
		h.Hub.BroadcastToUser(uid, ws.OutgoingMessage{
			Type: "channel_deleted",
			Payload: map[string]string{
				"channel_id": channelID,
			},
		})
	}
}

func (h *Handler) GetChannels(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channels, err := h.DB.GetUserChannels(userID)
	if err != nil {
		jsonError(w, "failed to get channels", http.StatusInternalServerError)
		return
	}
	jsonResp(w, http.StatusOK, channels)
}

func (h *Handler) SearchAll(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	query := r.URL.Query().Get("q")
	if query == "" {
		jsonResp(w, http.StatusOK, map[string]interface{}{"users": []*model.User{}, "channels": []*model.Channel{}})
		return
	}
	users, _ := h.DB.SearchUsers(query)
	channels, _ := h.DB.SearchChannels(query, userID)
	jsonResp(w, http.StatusOK, map[string]interface{}{
		"users":    users,
		"channels": channels,
	})
}

func (h *Handler) UpdateChannelSettings(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	var req struct {
		Name       *string `json:"name"`
		Username   *string `json:"username"`
		Visibility *string `json:"visibility"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid request", http.StatusBadRequest)
		return
	}
	ch, err := h.DB.GetChannel(channelID)
	if err != nil {
		jsonError(w, "channel not found", http.StatusNotFound)
		return
	}
	if ch.OwnerID != userID {
		jsonError(w, "only owner can change settings", http.StatusForbidden)
		return
	}
	if req.Visibility != nil {
		if *req.Visibility != "public" && *req.Visibility != "private" {
			jsonError(w, "visibility must be public or private", http.StatusBadRequest)
			return
		}
		if err := h.DB.UpdateChannelVisibility(channelID, *req.Visibility); err != nil {
			jsonError(w, "failed to update channel", http.StatusInternalServerError)
			return
		}
	}
	if req.Name != nil || req.Username != nil {
		name := ch.Name
		if req.Name != nil && *req.Name != "" {
			name = *req.Name
		}
		username := ch.Username
		if req.Username != nil {
			u := strings.ToLower(strings.TrimSpace(*req.Username))
			if u != "" && !validChannelUsername(u) {
				jsonError(w, "username must be 3-32 chars: a-z, 0-9, _", http.StatusBadRequest)
				return
			}
			if u != "" && u != ch.Username {
				if _, err := h.DB.GetChannelByUsername(u); err == nil {
					jsonError(w, "channel username taken", http.StatusConflict)
					return
				}
			}
			username = u
		}
		if err := h.DB.UpdateChannelNameUsername(channelID, name, username); err != nil {
			jsonError(w, "failed to update channel", http.StatusInternalServerError)
			return
		}
	}
	updated, _ := h.DB.GetChannel(channelID)
	jsonResp(w, http.StatusOK, updated)
}

// validChannelUsername: 3-32 chars, lowercase letters, digits, underscore.
func validChannelUsername(s string) bool {
	if len(s) < 3 || len(s) > 32 {
		return false
	}
	for _, c := range s {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') {
			return false
		}
	}
	return true
}

// roleRank ranks channel roles for authorization (higher = more power).
func roleRank(role string) int {
	switch role {
	case "owner":
		return 3
	case "admin":
		return 2
	case "member":
		return 1
	default:
		return 0
	}
}

// requireRole returns the caller's role if it ranks >= min, else writes an error.
func (h *Handler) requireRole(w http.ResponseWriter, channelID, userID string, min int) (string, bool) {
	role, err := h.DB.GetMemberRole(channelID, userID)
	if err != nil || roleRank(role) < min {
		jsonError(w, "insufficient permissions", http.StatusForbidden)
		return "", false
	}
	return role, true
}

func (h *Handler) GetChannelMembers(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	if _, ok := h.requireRole(w, channelID, userID, 1); !ok {
		return
	}
	members, err := h.DB.GetChannelMembersWithRole(channelID)
	if err != nil {
		jsonError(w, "failed to get members", http.StatusInternalServerError)
		return
	}
	jsonResp(w, http.StatusOK, members)
}

func (h *Handler) AddChannelMember(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	if _, ok := h.requireRole(w, channelID, userID, 2); !ok { // admin+
		return
	}
	var req struct {
		UserID string `json:"user_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.UserID == "" {
		jsonError(w, "user_id required", http.StatusBadRequest)
		return
	}
	h.DB.AddChannelMember(&model.ChannelMember{
		ChannelID: channelID, UserID: req.UserID, Role: "member", JoinedAt: time.Now().UTC(),
	})
	ch, _ := h.DB.GetChannel(channelID)
	h.Hub.BroadcastToUser(req.UserID, ws.OutgoingMessage{Type: "channel_created", Payload: ch})
	jsonResp(w, http.StatusOK, map[string]string{"status": "added"})
}

func (h *Handler) RemoveChannelMember(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	targetID := r.PathValue("userId")
	// Anyone can remove themselves (leave). Admins can remove others.
	if targetID != userID {
		if _, ok := h.requireRole(w, channelID, userID, 2); !ok {
			return
		}
	}
	ch, err := h.DB.GetChannel(channelID)
	if err != nil {
		jsonError(w, "channel not found", http.StatusNotFound)
		return
	}
	if targetID == ch.OwnerID {
		jsonError(w, "cannot remove the owner", http.StatusBadRequest)
		return
	}
	h.DB.RemoveChannelMember(channelID, targetID)
	h.Hub.BroadcastToUser(targetID, ws.OutgoingMessage{
		Type: "channel_deleted", Payload: map[string]string{"channel_id": channelID},
	})
	jsonResp(w, http.StatusOK, map[string]string{"status": "removed"})
}

func (h *Handler) UpdateChannelMemberRole(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	targetID := r.PathValue("userId")
	// Only the owner may promote/demote.
	if _, ok := h.requireRole(w, channelID, userID, 3); !ok {
		return
	}
	var req struct {
		Role string `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || (req.Role != "admin" && req.Role != "member") {
		jsonError(w, "role must be admin or member", http.StatusBadRequest)
		return
	}
	h.DB.UpdateMemberRole(channelID, targetID, req.Role)
	jsonResp(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (h *Handler) JoinChannel(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	ch, err := h.DB.GetChannel(channelID)
	if err != nil {
		jsonError(w, "channel not found", http.StatusNotFound)
		return
	}
	if ch.Type == model.ChannelDM {
		jsonError(w, "cannot join a DM", http.StatusBadRequest)
		return
	}
	if ch.Visibility != "public" {
		jsonError(w, "channel is private", http.StatusForbidden)
		return
	}
	h.DB.AddChannelMember(&model.ChannelMember{
		ChannelID: channelID, UserID: userID, Role: "member", JoinedAt: time.Now().UTC(),
	})
	jsonResp(w, http.StatusOK, ch)
}

func (h *Handler) GetChannelMedia(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	channelID := r.PathValue("id")
	if _, ok := h.requireRole(w, channelID, userID, 1); !ok {
		return
	}
	kind := r.URL.Query().Get("kind")
	before := r.URL.Query().Get("before")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	msgs, err := h.DB.GetChannelMedia(channelID, kind, before, limit)
	if err != nil {
		jsonError(w, "failed to get media", http.StatusInternalServerError)
		return
	}
	jsonResp(w, http.StatusOK, msgs)
}

func (h *Handler) GetChannelMessages(w http.ResponseWriter, r *http.Request) {
	channelID := r.PathValue("id")
	before := r.URL.Query().Get("before")
	limitStr := r.URL.Query().Get("limit")
	limit := 50
	if n, err := strconv.Atoi(limitStr); err == nil && n > 0 && n <= 100 {
		limit = n
	}

	msgs, err := h.DB.GetMessages(channelID, before, limit)
	if err != nil {
		jsonError(w, "failed to get messages", http.StatusInternalServerError)
		return
	}
	jsonResp(w, http.StatusOK, msgs)
}

// maxUploadSize caps a single uploaded file. Generous on purpose — this is a
// self-hosted LAN messenger where sending large files (games, videos) matters.
const maxUploadSize = 2 << 30 // 2 GiB

func (h *Handler) UploadFile(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(string)
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadSize)
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		jsonError(w, "file too large or malformed upload", http.StatusBadRequest)
		return
	}

	fileData, header, err := r.FormFile("file")
	if err != nil {
		jsonError(w, "file required", http.StatusBadRequest)
		return
	}
	defer fileData.Close()

	fileID := uuid.New().String()
	mimeType := header.Header.Get("Content-Type")
	if mimeType == "" || mimeType == "application/octet-stream" {
		if detected := mimeByExt(header.Filename); detected != "" {
			mimeType = detected
		}
	}
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}

	// Media metadata is computed client-side (avoids ffprobe on a phone-server)
	// and sent as optional form fields. Telegram does the same.
	width, _ := strconv.Atoi(r.FormValue("width"))
	height, _ := strconv.Atoi(r.FormValue("height"))
	duration, _ := strconv.ParseFloat(r.FormValue("duration"), 64)

	f := &model.File{
		ID:           fileID,
		OriginalName: header.Filename,
		MimeType:     mimeType,
		Size:         header.Size,
		Width:        width,
		Height:       height,
		Duration:     duration,
		UploadedBy:   userID,
		CreatedAt:    time.Now().UTC(),
	}

	if err := h.Store.Save(fileID, fileData); err != nil {
		jsonError(w, "failed to save file", http.StatusInternalServerError)
		return
	}

	// Server-side fallback for image dimensions when the client didn't send them.
	if (f.Width == 0 || f.Height == 0) && strings.HasPrefix(mimeType, "image/") {
		if osFile, openErr := h.Store.Open(fileID); openErr == nil {
			if cfg, _, cfgErr := image.DecodeConfig(osFile); cfgErr == nil {
				f.Width, f.Height = cfg.Width, cfg.Height
			}
			osFile.Close()
		}
	}

	if err := h.DB.SaveFile(f); err != nil {
		h.Store.Delete(fileID)
		jsonError(w, "failed to save file metadata", http.StatusInternalServerError)
		return
	}

	jsonResp(w, http.StatusCreated, f)
}

func (h *Handler) GetFileInfo(w http.ResponseWriter, r *http.Request) {
	fileID := r.PathValue("id")
	f, err := h.DB.GetFile(fileID)
	if err != nil {
		jsonError(w, "file not found", http.StatusNotFound)
		return
	}
	if f.MimeType == "application/octet-stream" {
		if m := mimeByExt(f.OriginalName); m != "" {
			f.MimeType = m
		}
	}
	jsonResp(w, http.StatusOK, f)
}

func (h *Handler) GetFile(w http.ResponseWriter, r *http.Request) {
	fileID := r.PathValue("id")
	f, err := h.DB.GetFile(fileID)
	if err != nil {
		jsonError(w, "file not found", http.StatusNotFound)
		return
	}

	osFile, err := h.Store.Open(fileID)
	if err != nil {
		jsonError(w, "file not found on disk", http.StatusNotFound)
		return
	}
	defer osFile.Close()

	modTime := f.CreatedAt
	if stat, statErr := osFile.Stat(); statErr == nil {
		modTime = stat.ModTime()
	}

	// Set Content-Type explicitly so ServeContent doesn't sniff/override it.
	w.Header().Set("Content-Type", f.MimeType)
	w.Header().Set("Content-Disposition", "inline; filename=\""+f.OriginalName+"\"")
	// ServeContent handles Range requests (206 Partial Content, Accept-Ranges,
	// Content-Range) and sets Content-Length — enabling audio/video seeking
	// without downloading the whole file.
	http.ServeContent(w, r, f.OriginalName, modTime, osFile)
}

// extMime covers common media types that aren't in Go's built-in mime table
// and that have no /etc/mime.types on Android (where this server runs), so
// mime.TypeByExtension would otherwise return "" and files fall back to
// application/octet-stream (breaking audio/video detection on the client).
var extMime = map[string]string{
	".m4a": "audio/mp4", ".mp3": "audio/mpeg", ".aac": "audio/aac",
	".ogg": "audio/ogg", ".oga": "audio/ogg", ".opus": "audio/opus",
	".wav": "audio/wav", ".flac": "audio/flac", ".amr": "audio/amr",
	".weba": "audio/webm",
	".mp4": "video/mp4", ".m4v": "video/mp4", ".mov": "video/quicktime",
	".webm": "video/webm", ".mkv": "video/x-matroska", ".3gp": "video/3gpp",
	".avi": "video/x-msvideo",
	".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
	".gif": "image/gif", ".webp": "image/webp", ".bmp": "image/bmp",
	".heic": "image/heic", ".heif": "image/heif",
}

func mimeByExt(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	if m, ok := extMime[ext]; ok {
		return m
	}
	if m := mime.TypeByExtension(ext); m != "" {
		return strings.Split(m, ";")[0]
	}
	return ""
}

func jsonResp(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func jsonError(w http.ResponseWriter, msg string, status int) {
	jsonResp(w, status, map[string]string{"error": msg})
}
