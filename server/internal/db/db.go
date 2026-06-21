package db

import (
	"database/sql"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
	"barricade/internal/model"
)

type DB struct {
	*sql.DB
}

func New(path string) (*DB, error) {
	db, err := sql.Open("sqlite", path+"?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping db: %w", err)
	}
	d := &DB{db}
	if err := d.migrate(); err != nil {
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return d, nil
}

func (d *DB) migrate() error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id TEXT PRIMARY KEY,
			username TEXT UNIQUE NOT NULL,
			display_name TEXT NOT NULL DEFAULT '',
			password_hash TEXT NOT NULL,
			avatar_id TEXT,
			device_id TEXT NOT NULL DEFAULT '',
			created_at INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS channels (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL DEFAULT '',
			type TEXT NOT NULL CHECK(type IN ('dm','group','guild')),
			owner_id TEXT NOT NULL REFERENCES users(id),
			visibility TEXT NOT NULL DEFAULT 'public',
			created_at INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS channel_members (
			channel_id TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			role TEXT NOT NULL DEFAULT 'member',
			joined_at INTEGER NOT NULL,
			PRIMARY KEY (channel_id, user_id)
		)`,
		`CREATE TABLE IF NOT EXISTS messages (
			id TEXT PRIMARY KEY,
			channel_id TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
			sender_id TEXT NOT NULL REFERENCES users(id),
			content TEXT NOT NULL DEFAULT '',
			file_id TEXT,
			mime_type TEXT NOT NULL DEFAULT '',
			reply_to_id TEXT,
			created_at INTEGER NOT NULL,
			edited_at INTEGER
		)`,
		`CREATE TABLE IF NOT EXISTS files (
			id TEXT PRIMARY KEY,
			original_name TEXT NOT NULL,
			mime_type TEXT NOT NULL,
			size INTEGER NOT NULL,
			width INTEGER NOT NULL DEFAULT 0,
			height INTEGER NOT NULL DEFAULT 0,
			duration REAL NOT NULL DEFAULT 0,
			uploaded_by TEXT NOT NULL REFERENCES users(id),
			created_at INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS reactions (
			message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
			user_id TEXT NOT NULL REFERENCES users(id),
			emoji TEXT NOT NULL,
			username TEXT NOT NULL DEFAULT '',
			created_at INTEGER NOT NULL,
			PRIMARY KEY (message_id, user_id, emoji)
		)`,
		`CREATE TABLE IF NOT EXISTS voice_states (
			user_id TEXT NOT NULL,
			channel_id TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
			muted INTEGER NOT NULL DEFAULT 0,
			deafened INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (user_id, channel_id)
		)`,
		`PRAGMA journal_mode=WAL`,
	}
	for _, stmt := range statements {
		if _, err := d.Exec(stmt); err != nil {
			return err
		}
	}
	d.Exec(`ALTER TABLE users ADD COLUMN device_id TEXT NOT NULL DEFAULT ''`)
	// device_id is no longer unique — multiple accounts per device are allowed.
	// Drop the old unique index if a previous DB created it.
	d.Exec(`DROP INDEX IF EXISTS idx_users_device_id`)
	d.Exec(`ALTER TABLE channels ADD COLUMN visibility TEXT NOT NULL DEFAULT 'public'`)
	d.Exec(`ALTER TABLE messages ADD COLUMN status TEXT NOT NULL DEFAULT 'sent'`)
	d.Exec(`ALTER TABLE messages ADD COLUMN mime_type TEXT NOT NULL DEFAULT ''`)
	// Channel @username (handle) for search/join. Unique among non-empty values.
	d.Exec(`ALTER TABLE channels ADD COLUMN username TEXT NOT NULL DEFAULT ''`)
	d.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_channels_username ON channels(username) WHERE username != ''`)
	// Optional recovery phrase (bcrypt hash) for self-service password reset.
	d.Exec(`ALTER TABLE users ADD COLUMN recovery_hash TEXT NOT NULL DEFAULT ''`)
	d.Exec(`ALTER TABLE users ADD COLUMN last_seen INTEGER NOT NULL DEFAULT 0`)
	d.Exec(	`CREATE TABLE IF NOT EXISTS fcm_tokens (
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		token TEXT NOT NULL,
		created_at INTEGER NOT NULL,
		PRIMARY KEY (user_id)
	)`)
	d.Exec(`CREATE TABLE IF NOT EXISTS blacklist (
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		created_at INTEGER NOT NULL,
		PRIMARY KEY (user_id, blocked_id)
	)`)
	d.Exec(`CREATE TABLE IF NOT EXISTS contacts (
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		contact_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		display_name TEXT NOT NULL DEFAULT '',
		created_at INTEGER NOT NULL,
		PRIMARY KEY (user_id, contact_id)
	)`)
	return nil
}

func (d *DB) SetRecoveryHash(userID, hash string) error {
	_, err := d.Exec(`UPDATE users SET recovery_hash = ? WHERE id = ?`, hash, userID)
	return err
}

// GetRecoveryByUsername returns the recovery hash and user id for a username.
func (d *DB) GetRecoveryByUsername(username string) (recoveryHash, userID string, err error) {
	err = d.QueryRow(`SELECT COALESCE(recovery_hash,''), id FROM users WHERE username = ?`, username).Scan(&recoveryHash, &userID)
	return
}

func (d *DB) UpdatePassword(userID, hash string) error {
	_, err := d.Exec(`UPDATE users SET password_hash = ? WHERE id = ?`, hash, userID)
	return err
}

func scanUser(row interface{ Scan(dest ...interface{}) error }) (*model.User, error) {
	var u model.User
	var createdAt int64
	var lastSeen int64
	err := row.Scan(&u.ID, &u.Username, &u.DisplayName, &u.PasswordHash, &u.AvatarID, &u.DeviceID, &createdAt, &lastSeen)
	if err != nil {
		return nil, err
	}
	u.CreatedAt = time.Unix(createdAt, 0).UTC()
	if lastSeen > 0 {
		t := time.Unix(lastSeen, 0).UTC()
		u.LastSeen = &t
	}
	return &u, nil
}

func (d *DB) CreateUser(u *model.User) error {
	_, err := d.Exec(
		`INSERT INTO users (id, username, display_name, password_hash, avatar_id, device_id, created_at) VALUES (?,?,?,?,?,?,?)`,
		u.ID, u.Username, u.DisplayName, u.PasswordHash, u.AvatarID, u.DeviceID, u.CreatedAt.Unix(),
	)
	return err
}

func (d *DB) GetUserByUsername(username string) (*model.User, error) {
	row := d.QueryRow(`SELECT id, username, display_name, password_hash, avatar_id, device_id, created_at, COALESCE(last_seen,0) FROM users WHERE username = ?`, username)
	return scanUser(row)
}

func (d *DB) GetUser(id string) (*model.User, error) {
	row := d.QueryRow(`SELECT id, username, display_name, password_hash, avatar_id, device_id, created_at, COALESCE(last_seen,0) FROM users WHERE id = ?`, id)
	return scanUser(row)
}

func (d *DB) GetUserByDevice(deviceID string) (*model.User, error) {
	row := d.QueryRow(`SELECT id, username, display_name, password_hash, avatar_id, device_id, created_at, COALESCE(last_seen,0) FROM users WHERE device_id = ?`, deviceID)
	return scanUser(row)
}

func (d *DB) GetAllUsers() ([]*model.User, error) {
	rows, err := d.Query(`SELECT id, username, display_name, password_hash, avatar_id, device_id, created_at, COALESCE(last_seen,0) FROM users ORDER BY username`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []*model.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func (d *DB) SearchUsers(query string) ([]*model.User, error) {
	rows, err := d.Query(`SELECT id, username, display_name, password_hash, avatar_id, device_id, created_at, COALESCE(last_seen,0) FROM users WHERE username LIKE ? ORDER BY username LIMIT 20`, "%"+query+"%")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []*model.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func scanChannel(row interface{ Scan(dest ...interface{}) error }) (*model.Channel, error) {
	var c model.Channel
	var createdAt int64
	err := row.Scan(&c.ID, &c.Name, &c.Username, &c.Type, &c.OwnerID, &c.Visibility, &createdAt)
	if err != nil {
		return nil, err
	}
	c.CreatedAt = time.Unix(createdAt, 0).UTC()
	return &c, nil
}

func (d *DB) CreateChannel(c *model.Channel) error {
	if c.Visibility == "" {
		c.Visibility = "public"
	}
	_, err := d.Exec(
		`INSERT INTO channels (id, name, username, type, owner_id, visibility, created_at) VALUES (?,?,?,?,?,?,?)`,
		c.ID, c.Name, c.Username, c.Type, c.OwnerID, c.Visibility, c.CreatedAt.Unix(),
	)
	return err
}

func (d *DB) DeleteChannel(id string) error {
	_, err := d.Exec(`DELETE FROM channels WHERE id = ?`, id)
	return err
}

func (d *DB) GetChannel(id string) (*model.Channel, error) {
	row := d.QueryRow(`SELECT id, name, COALESCE(username,''), type, owner_id, visibility, created_at FROM channels WHERE id = ?`, id)
	return scanChannel(row)
}

func (d *DB) GetChannelByUsername(username string) (*model.Channel, error) {
	row := d.QueryRow(`SELECT id, name, COALESCE(username,''), type, owner_id, visibility, created_at FROM channels WHERE username = ?`, username)
	return scanChannel(row)
}

func (d *DB) GetUserChannels(userID string) ([]*model.Channel, error) {
	rows, err := d.Query(`
		SELECT c.id, c.name, COALESCE(c.username,''), c.type, c.owner_id, c.visibility, c.created_at
		FROM channels c
		JOIN channel_members cm ON cm.channel_id = c.id
		WHERE cm.user_id = ?
		ORDER BY c.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	channels := []*model.Channel{}
	for rows.Next() {
		c, err := scanChannel(rows)
		if err != nil {
			return nil, err
		}
		channels = append(channels, c)
	}
	return channels, nil
}

func (d *DB) AddChannelMember(cm *model.ChannelMember) error {
	_, err := d.Exec(
		`INSERT OR IGNORE INTO channel_members (channel_id, user_id, role, joined_at) VALUES (?,?,?,?)`,
		cm.ChannelID, cm.UserID, cm.Role, cm.JoinedAt.Unix(),
	)
	return err
}

func (d *DB) GetChannelMembers(channelID string) ([]*model.User, error) {
	rows, err := d.Query(`
		SELECT u.id, u.username, u.display_name, u.password_hash, u.avatar_id, u.device_id, u.created_at, COALESCE(u.last_seen,0)
		FROM users u
		JOIN channel_members cm ON cm.user_id = u.id
		WHERE cm.channel_id = ?`, channelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []*model.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func (d *DB) GetChannelMembersWithRole(channelID string) ([]*model.MemberInfo, error) {
	rows, err := d.Query(`
		SELECT u.id, u.username, u.display_name, u.avatar_id, cm.role, COALESCE(u.last_seen,0)
		FROM channel_members cm
		JOIN users u ON u.id = cm.user_id
		WHERE cm.channel_id = ?
		ORDER BY CASE cm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, u.display_name`, channelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var members []*model.MemberInfo
	for rows.Next() {
		var m model.MemberInfo
		var lastSeen int64
		if err := rows.Scan(&m.ID, &m.Username, &m.DisplayName, &m.AvatarID, &m.Role, &lastSeen); err != nil {
			return nil, err
		}
		if lastSeen > 0 {
			t := time.Unix(lastSeen, 0).UTC()
			m.LastSeen = &t
		}
		members = append(members, &m)
	}
	return members, nil
}

func (d *DB) GetMemberRole(channelID, userID string) (string, error) {
	var role string
	err := d.QueryRow(`SELECT role FROM channel_members WHERE channel_id = ? AND user_id = ?`, channelID, userID).Scan(&role)
	return role, err
}

func (d *DB) RemoveChannelMember(channelID, userID string) error {
	_, err := d.Exec(`DELETE FROM channel_members WHERE channel_id = ? AND user_id = ?`, channelID, userID)
	return err
}

func (d *DB) UpdateMemberRole(channelID, userID, role string) error {
	_, err := d.Exec(`UPDATE channel_members SET role = ? WHERE channel_id = ? AND user_id = ?`, role, channelID, userID)
	return err
}

func (d *DB) UpdateChannelNameUsername(channelID, name, username string) error {
	_, err := d.Exec(`UPDATE channels SET name = ?, username = ? WHERE id = ?`, name, username, channelID)
	return err
}

// GetChannelMedia returns messages of a channel filtered by kind:
// "media" (images+video), "music" (audio), "files" (other attachments),
// "links" (text containing a URL).
func (d *DB) GetChannelMedia(channelID, kind string, before string, limit int) ([]*model.Message, error) {
	if limit <= 0 || limit > 100 {
		limit = 60
	}
	var filter string
	switch kind {
	case "media":
		filter = `m.file_id IS NOT NULL AND (m.mime_type LIKE 'image/%' OR m.mime_type LIKE 'video/%')`
	case "music":
		filter = `m.file_id IS NOT NULL AND m.mime_type LIKE 'audio/%'`
	case "files":
		filter = `m.file_id IS NOT NULL AND m.mime_type NOT LIKE 'image/%' AND m.mime_type NOT LIKE 'video/%' AND m.mime_type NOT LIKE 'audio/%'`
	case "links":
		filter = `(m.content LIKE '%http://%' OR m.content LIKE '%https://%')`
	default:
		filter = `m.file_id IS NOT NULL`
	}
	query := `
		SELECT m.id, m.channel_id, m.sender_id, m.content, m.file_id, COALESCE(m.mime_type,''), m.reply_to_id, COALESCE(m.status,'sent'), m.created_at, m.edited_at,
		       u.username, u.display_name
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		WHERE m.channel_id = ? AND ` + filter
	args := []interface{}{channelID}
	if before != "" {
		query += ` AND m.created_at < (SELECT created_at FROM messages WHERE id = ?)`
		args = append(args, before)
	}
	query += ` ORDER BY m.created_at DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var msgs []*model.Message
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}
	if len(msgs) > 0 {
		ids := make([]string, len(msgs))
		for i, m := range msgs {
			ids[i] = m.ID
		}
		rmap, err := d.GetMessagesReactions(ids)
		if err == nil {
			for _, m := range msgs {
				m.Reactions = rmap[m.ID]
			}
		}
	}
	return msgs, nil
}

func scanMessage(row interface{ Scan(dest ...interface{}) error }) (*model.Message, error) {
	var m model.Message
	var createdAt int64
	var editedAt *int64
	err := row.Scan(&m.ID, &m.ChannelID, &m.SenderID, &m.Content, &m.FileID, &m.MimeType, &m.ReplyToID, &m.Status, &createdAt, &editedAt, &m.SenderUsername, &m.SenderDisplayName)
	if err != nil {
		return nil, err
	}
	m.CreatedAt = time.Unix(createdAt, 0).UTC()
	if editedAt != nil {
		t := time.Unix(*editedAt, 0).UTC()
		m.EditedAt = &t
	}
	return &m, nil
}

func (d *DB) SaveMessage(msg *model.Message) error {
	_, err := d.Exec(
		`INSERT INTO messages (id, channel_id, sender_id, content, file_id, mime_type, reply_to_id, created_at) VALUES (?,?,?,?,?,?,?,?)`,
		msg.ID, msg.ChannelID, msg.SenderID, msg.Content, msg.FileID, msg.MimeType, msg.ReplyToID, msg.CreatedAt.Unix(),
	)
	return err
}

func (d *DB) GetMessages(channelID string, before string, limit int) ([]*model.Message, error) {
	if limit <= 0 {
		limit = 50
	}
	query := `
		SELECT m.id, m.channel_id, m.sender_id, m.content, m.file_id, COALESCE(m.mime_type,''), m.reply_to_id, COALESCE(m.status,'sent'), m.created_at, m.edited_at,
		       u.username, u.display_name
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		WHERE m.channel_id = ?`
	var args []interface{}
	args = append(args, channelID)

	if before != "" {
		query += ` AND m.created_at < (SELECT created_at FROM messages WHERE id = ?)`
		args = append(args, before)
	}
	query += ` ORDER BY m.created_at DESC LIMIT ?`
	args = append(args, limit)

	rows, err := d.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var msgs []*model.Message
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}
	// attach reactions
	if len(msgs) > 0 {
		ids := make([]string, len(msgs))
		for i, m := range msgs {
			ids[i] = m.ID
		}
		rmap, err := d.GetMessagesReactions(ids)
		if err == nil {
			for _, m := range msgs {
				m.Reactions = rmap[m.ID]
			}
		}
	}
	return msgs, nil
}

func (d *DB) GetMessage(id string) (*model.Message, error) {
	row := d.QueryRow(`
		SELECT m.id, m.channel_id, m.sender_id, m.content, m.file_id, COALESCE(m.mime_type,''), m.reply_to_id, COALESCE(m.status,'sent'), m.created_at, m.edited_at,
		       u.username, u.display_name
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		WHERE m.id = ?`, id)
	return scanMessage(row)
}

func (d *DB) UpdateMessageStatus(id, status string) error {
	_, err := d.Exec(`UPDATE messages SET status = ? WHERE id = ?`, status, id)
	return err
}

func (d *DB) UpdateMessagesReadByChannel(channelID, readerID string) error {
	_, err := d.Exec(
		`UPDATE messages SET status = 'read' WHERE channel_id = ? AND sender_id != ? AND status != 'read'`,
		channelID, readerID)
	return err
}

func (d *DB) UpdateLastSeen(userID string) error {
	_, err := d.Exec(`UPDATE users SET last_seen = ? WHERE id = ?`, time.Now().Unix(), userID)
	return err
}

func (d *DB) EditMessage(id, content string) error {
	_, err := d.Exec(`UPDATE messages SET content = ?, edited_at = ? WHERE id = ?`, content, time.Now().Unix(), id)
	return err
}

func (d *DB) DeleteMessage(id string) error {
	_, err := d.Exec(`DELETE FROM messages WHERE id = ?`, id)
	return err
}

// reactions

func (d *DB) AddReaction(messageID, userID, emoji, username string) error {
	_, err := d.Exec(
		`INSERT OR IGNORE INTO reactions (message_id, user_id, emoji, username, created_at) VALUES (?,?,?,?,?)`,
		messageID, userID, emoji, username, time.Now().Unix(),
	)
	return err
}

func (d *DB) RemoveReaction(messageID, userID, emoji string) error {
	_, err := d.Exec(`DELETE FROM reactions WHERE message_id = ? AND user_id = ? AND emoji = ?`, messageID, userID, emoji)
	return err
}

func (d *DB) GetMessageReactions(messageID string) ([]model.Reaction, error) {
	rows, err := d.Query(`SELECT message_id, user_id, emoji, username, created_at FROM reactions WHERE message_id = ?`, messageID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []model.Reaction
	for rows.Next() {
		var r model.Reaction
		var createdAt int64
		if err := rows.Scan(&r.MessageID, &r.UserID, &r.Emoji, &r.Username, &createdAt); err != nil {
			return nil, err
		}
		r.CreatedAt = time.Unix(createdAt, 0).UTC()
		out = append(out, r)
	}
	return out, nil
}

func (d *DB) GetMessagesReactions(messageIDs []string) (map[string][]model.Reaction, error) {
	if len(messageIDs) == 0 {
		return nil, nil
	}
	query := `SELECT message_id, user_id, emoji, username, created_at FROM reactions WHERE message_id IN (`
	args := make([]interface{}, len(messageIDs))
	for i, id := range messageIDs {
		if i > 0 {
			query += ","
		}
		query += "?"
		args[i] = id
	}
	query += `) ORDER BY created_at`
	rows, err := d.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[string][]model.Reaction)
	for rows.Next() {
		var r model.Reaction
		var createdAt int64
		if err := rows.Scan(&r.MessageID, &r.UserID, &r.Emoji, &r.Username, &createdAt); err != nil {
			return nil, err
		}
		r.CreatedAt = time.Unix(createdAt, 0).UTC()
		result[r.MessageID] = append(result[r.MessageID], r)
	}
	return result, nil
}

func (d *DB) UpdateUserDisplayName(userID, displayName string) error {
	_, err := d.Exec(`UPDATE users SET display_name = ? WHERE id = ?`, displayName, userID)
	return err
}

func (d *DB) UpdateUsername(userID, newUsername string) error {
	_, err := d.Exec(`UPDATE users SET username = ? WHERE id = ?`, newUsername, userID)
	return err
}

func (d *DB) SearchChannels(query string, userID string) ([]*model.Channel, error) {
	// Discovery: public channels matching name/username, plus any channel the
	// user is already a member of (so private ones they belong to still appear).
	rows, err := d.Query(`
		SELECT c.id, c.name, COALESCE(c.username,''), c.type, c.owner_id, c.visibility, c.created_at
		FROM channels c
		LEFT JOIN channel_members cm ON cm.channel_id = c.id AND cm.user_id = ?
		WHERE c.type != 'dm'
		  AND (c.name LIKE ? OR c.username LIKE ?)
		  AND (c.visibility = 'public' OR cm.user_id IS NOT NULL)
		GROUP BY c.id
		ORDER BY c.created_at DESC
		LIMIT 20`, userID, "%"+query+"%", "%"+query+"%")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var channels []*model.Channel
	for rows.Next() {
		c, err := scanChannel(rows)
		if err != nil {
			return nil, err
		}
		channels = append(channels, c)
	}
	return channels, nil
}

func (d *DB) UpdateChannelVisibility(channelID, visibility string) error {
	_, err := d.Exec(`UPDATE channels SET visibility = ? WHERE id = ?`, visibility, channelID)
	return err
}

func (d *DB) UpdateUserAvatar(userID string, avatarID *string) error {
	_, err := d.Exec(`UPDATE users SET avatar_id = ? WHERE id = ?`, avatarID, userID)
	return err
}

func (d *DB) SaveFile(f *model.File) error {
	_, err := d.Exec(
		`INSERT INTO files (id, original_name, mime_type, size, width, height, duration, uploaded_by, created_at) VALUES (?,?,?,?,?,?,?,?,?)`,
		f.ID, f.OriginalName, f.MimeType, f.Size, f.Width, f.Height, f.Duration, f.UploadedBy, f.CreatedAt.Unix(),
	)
	return err
}

func (d *DB) GetFile(id string) (*model.File, error) {
	var f model.File
	var createdAt int64
	err := d.QueryRow(`SELECT id, original_name, mime_type, size, width, height, duration, uploaded_by, created_at FROM files WHERE id = ?`, id).
		Scan(&f.ID, &f.OriginalName, &f.MimeType, &f.Size, &f.Width, &f.Height, &f.Duration, &f.UploadedBy, &createdAt)
	if err != nil {
		return nil, err
	}
	f.CreatedAt = time.Unix(createdAt, 0).UTC()
	return &f, nil
}

func (d *DB) SetVoiceState(vs *model.VoiceState) error {
	_, err := d.Exec(`
		INSERT INTO voice_states (user_id, channel_id, muted, deafened) VALUES (?,?,?,?)
		ON CONFLICT(user_id, channel_id) DO UPDATE SET muted=excluded.muted, deafened=excluded.deafened`,
		vs.UserID, vs.ChannelID, boolToInt(vs.Muted), boolToInt(vs.Deafened))
	return err
}

func (d *DB) GetVoiceStates(channelID string) ([]*model.VoiceState, error) {
	rows, err := d.Query(`SELECT user_id, channel_id, muted, deafened FROM voice_states WHERE channel_id = ?`, channelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var states []*model.VoiceState
	for rows.Next() {
		var vs model.VoiceState
		var muted, deafened int
		if err := rows.Scan(&vs.UserID, &vs.ChannelID, &muted, &deafened); err != nil {
			return nil, err
		}
		vs.Muted = muted != 0
		vs.Deafened = deafened != 0
		states = append(states, &vs)
	}
	return states, nil
}

func (d *DB) SetFCMToken(userID, token string) error {
	_, err := d.Exec(`
		INSERT INTO fcm_tokens (user_id, token, created_at) VALUES (?,?,?)
		ON CONFLICT(user_id) DO UPDATE SET token=excluded.token, created_at=excluded.created_at`,
		userID, token, time.Now().Unix())
	return err
}

func (d *DB) GetFCMToken(userID string) (string, error) {
	var token string
	err := d.QueryRow(`SELECT token FROM fcm_tokens WHERE user_id = ?`, userID).Scan(&token)
	return token, err
}

func (d *DB) BlockUser(userID, blockedID string) error {
	_, err := d.Exec(`INSERT OR IGNORE INTO blacklist (user_id, blocked_id, created_at) VALUES (?,?,?)`,
		userID, blockedID, time.Now().Unix())
	return err
}

func (d *DB) UnblockUser(userID, blockedID string) error {
	_, err := d.Exec(`DELETE FROM blacklist WHERE user_id = ? AND blocked_id = ?`, userID, blockedID)
	return err
}

func (d *DB) GetBlacklist(userID string) ([]string, error) {
	rows, err := d.Query(`SELECT blocked_id FROM blacklist WHERE user_id = ? ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}

func (d *DB) IsBlocked(userID, targetID string) (bool, error) {
	var count int
	err := d.QueryRow(`SELECT COUNT(*) FROM blacklist WHERE user_id = ? AND blocked_id = ?`, userID, targetID).Scan(&count)
	return count > 0, err
}

func (d *DB) AddContact(userID, contactID, displayName string) error {
	if displayName == "" {
		u, err := d.GetUser(contactID)
		if err != nil {
			return err
		}
		displayName = u.DisplayName
	}
	_, err := d.Exec(`INSERT OR IGNORE INTO contacts (user_id, contact_id, display_name, created_at) VALUES (?,?,?,?)`,
		userID, contactID, displayName, time.Now().Unix())
	return err
}

func (d *DB) RemoveContact(userID, contactID string) error {
	_, err := d.Exec(`DELETE FROM contacts WHERE user_id = ? AND contact_id = ?`, userID, contactID)
	return err
}

func (d *DB) GetContacts(userID string) ([]*model.Contact, error) {
	rows, err := d.Query(`SELECT contact_id, display_name, created_at FROM contacts WHERE user_id = ? ORDER BY display_name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var contacts []*model.Contact
	for rows.Next() {
		c := &model.Contact{}
		if err := rows.Scan(&c.ContactID, &c.DisplayName, &c.CreatedAt); err != nil {
			return nil, err
		}
		contacts = append(contacts, c)
	}
	return contacts, nil
}

func (d *DB) UpdateContactName(userID, contactID, displayName string) error {
	_, err := d.Exec(`UPDATE contacts SET display_name = ? WHERE user_id = ? AND contact_id = ?`,
		displayName, userID, contactID)
	return err
}

func (d *DB) IsContact(userID, contactID string) (bool, error) {
	var count int
	err := d.QueryRow(`SELECT COUNT(*) FROM contacts WHERE user_id = ? AND contact_id = ?`, userID, contactID).Scan(&count)
	return count > 0, err
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}


