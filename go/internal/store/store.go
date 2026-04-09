package store

import (
	"crypto/cipher"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

type Store struct {
	db  *sql.DB
	gcm cipher.AEAD // nil until SetEncryptionKey is called
}

func New(dbPath string) (*Store, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("store: open %s: %w", dbPath, err)
	}

	// WAL mode for concurrent reads during streaming
	if _, err := db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		db.Close()
		return nil, fmt.Errorf("store: set WAL: %w", err)
	}

	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}

	return s, nil
}

func (s *Store) Close() error {
	return s.db.Close()
}

func (s *Store) migrate() error {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS conversations (
			id          TEXT PRIMARY KEY,
			model_id    TEXT NOT NULL,
			model_name  TEXT,
			provider    TEXT,
			is_tee      INTEGER DEFAULT 0,
			created_at  INTEGER NOT NULL,
			updated_at  INTEGER NOT NULL,
			title       TEXT
		)`,
		`CREATE TABLE IF NOT EXISTS messages (
			id              TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL REFERENCES conversations(id),
			role            TEXT NOT NULL,
			content         TEXT NOT NULL,
			tokens_used     INTEGER,
			latency_ms      INTEGER,
			tee_verified    INTEGER DEFAULT 0,
			created_at      INTEGER NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at)`,
		`CREATE TABLE IF NOT EXISTS model_cache (
			id          TEXT PRIMARY KEY,
			name        TEXT,
			provider    TEXT,
			is_tee      INTEGER DEFAULT 0,
			tags        TEXT,
			stake       TEXT,
			updated_at  INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS preferences (
			key   TEXT PRIMARY KEY,
			value TEXT
		)`,
	}

	for _, m := range migrations {
		if _, err := s.db.Exec(m); err != nil {
			return fmt.Errorf("store: migrate: %w", err)
		}
	}
	// Idempotent schema upgrades (existing installs).
	if err := s.ensureConversationSessionIDColumn(); err != nil {
		return err
	}
	if err := s.ensureConversationPinnedColumn(); err != nil {
		return err
	}
	if err := s.ensureConversationSourceColumn(); err != nil {
		return err
	}
	if err := s.ensureAPIKeysTable(); err != nil {
		return err
	}
	return nil
}

func (s *Store) ensureConversationSessionIDColumn() error {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('conversations') WHERE name = 'session_id'`).Scan(&n)
	if err != nil {
		return fmt.Errorf("store: pragma session_id: %w", err)
	}
	if n > 0 {
		return nil
	}
	if _, err := s.db.Exec(`ALTER TABLE conversations ADD COLUMN session_id TEXT`); err != nil {
		return fmt.Errorf("store: add session_id column: %w", err)
	}
	return nil
}

func (s *Store) ensureConversationPinnedColumn() error {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('conversations') WHERE name = 'pinned'`).Scan(&n)
	if err != nil {
		return fmt.Errorf("store: pragma pinned: %w", err)
	}
	if n > 0 {
		return nil
	}
	if _, err := s.db.Exec(`ALTER TABLE conversations ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0`); err != nil {
		return fmt.Errorf("store: add pinned column: %w", err)
	}
	return nil
}

func (s *Store) ensureConversationSourceColumn() error {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('conversations') WHERE name = 'source'`).Scan(&n)
	if err != nil {
		return fmt.Errorf("store: pragma source: %w", err)
	}
	if n > 0 {
		return nil
	}
	if _, err := s.db.Exec(`ALTER TABLE conversations ADD COLUMN source TEXT DEFAULT 'ui'`); err != nil {
		return fmt.Errorf("store: add source column: %w", err)
	}
	return nil
}

func (s *Store) ensureAPIKeysTable() error {
	_, err := s.db.Exec(`CREATE TABLE IF NOT EXISTS api_keys (
		id         TEXT PRIMARY KEY,
		key_hash   TEXT NOT NULL,
		key_prefix TEXT NOT NULL,
		name       TEXT DEFAULT '',
		created_at INTEGER NOT NULL,
		last_used  INTEGER DEFAULT 0
	)`)
	if err != nil {
		return fmt.Errorf("store: create api_keys: %w", err)
	}
	return nil
}

// --- API Key management ---

type APIKeyInfo struct {
	ID        string `json:"id"`
	Prefix    string `json:"prefix"`
	Name      string `json:"name"`
	CreatedAt int64  `json:"created_at"`
	LastUsed  int64  `json:"last_used"`
}

// GenerateAPIKey creates a new API key with the given name.
// Returns the full key (shown once) and the stored metadata.
func (s *Store) GenerateAPIKey(name string) (fullKey string, info APIKeyInfo, err error) {
	raw := make([]byte, 32)
	if _, err = rand.Read(raw); err != nil {
		return "", APIKeyInfo{}, fmt.Errorf("store: generate key: %w", err)
	}
	fullKey = "sk-" + hex.EncodeToString(raw)
	prefix := fullKey[:9]

	hash, err := bcrypt.GenerateFromPassword([]byte(fullKey), bcrypt.DefaultCost)
	if err != nil {
		return "", APIKeyInfo{}, fmt.Errorf("store: hash key: %w", err)
	}

	id := fmt.Sprintf("key-%d", time.Now().UnixNano())
	now := time.Now().Unix()

	if _, err := s.db.Exec(
		`INSERT INTO api_keys (id, key_hash, key_prefix, name, created_at) VALUES (?, ?, ?, ?, ?)`,
		id, string(hash), prefix, name, now,
	); err != nil {
		return "", APIKeyInfo{}, err
	}

	info = APIKeyInfo{ID: id, Prefix: prefix, Name: name, CreatedAt: now}
	return fullKey, info, nil
}

// ValidateAPIKey checks whether rawKey is a valid, non-revoked key.
// Returns the key info on success.
func (s *Store) ValidateAPIKey(rawKey string) (APIKeyInfo, bool, error) {
	if len(rawKey) < 9 {
		return APIKeyInfo{}, false, nil
	}
	prefix := rawKey[:9]

	rows, err := s.db.Query(
		`SELECT id, key_hash, key_prefix, name, created_at, last_used FROM api_keys WHERE key_prefix = ?`, prefix)
	if err != nil {
		return APIKeyInfo{}, false, err
	}
	defer rows.Close()

	for rows.Next() {
		var info APIKeyInfo
		var hash string
		if err := rows.Scan(&info.ID, &hash, &info.Prefix, &info.Name, &info.CreatedAt, &info.LastUsed); err != nil {
			return APIKeyInfo{}, false, err
		}
		if bcrypt.CompareHashAndPassword([]byte(hash), []byte(rawKey)) == nil {
			return info, true, nil
		}
	}
	return APIKeyInfo{}, false, rows.Err()
}

// UpdateAPIKeyLastUsed bumps the last_used timestamp.
func (s *Store) UpdateAPIKeyLastUsed(id string) error {
	_, err := s.db.Exec(`UPDATE api_keys SET last_used = ? WHERE id = ?`, time.Now().Unix(), id)
	return err
}

// ListAPIKeys returns all active keys (never exposes hashes).
func (s *Store) ListAPIKeys() ([]APIKeyInfo, error) {
	rows, err := s.db.Query(`SELECT id, key_prefix, name, created_at, last_used FROM api_keys ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []APIKeyInfo
	for rows.Next() {
		var k APIKeyInfo
		if err := rows.Scan(&k.ID, &k.Prefix, &k.Name, &k.CreatedAt, &k.LastUsed); err != nil {
			return nil, err
		}
		out = append(out, k)
	}
	if out == nil {
		out = []APIKeyInfo{}
	}
	return out, rows.Err()
}

// RevokeAPIKey deletes a key, immediately blocking further use.
func (s *Store) RevokeAPIKey(id string) error {
	res, err := s.db.Exec(`DELETE FROM api_keys WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("store: no api key %q", id)
	}
	return nil
}

func (s *Store) SaveMessage(conversationID, role, content string) error {
	id := fmt.Sprintf("%s-%d", role, time.Now().UnixNano())
	now := time.Now().Unix()
	stored := s.encrypt(content)
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(
		`INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)`,
		id, conversationID, role, stored, now,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE conversations SET updated_at = ? WHERE id = ?`, now, conversationID); err != nil {
		return err
	}
	if role == "user" {
		if err := s.maybeAutofillConversationTitle(tx, conversationID, content); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) maybeAutofillConversationTitle(tx *sql.Tx, conversationID, userContent string) error {
	var title sql.NullString
	err := tx.QueryRow(`SELECT title FROM conversations WHERE id = ?`, conversationID).Scan(&title)
	if err != nil {
		return err
	}
	if title.Valid && strings.TrimSpace(title.String) != "" {
		return nil
	}
	t := strings.TrimSpace(userContent)
	t = strings.ReplaceAll(t, "\n", " ")
	if len(t) > 72 {
		t = t[:72] + "…"
	}
	if t == "" {
		return nil
	}
	_, err = tx.Exec(`UPDATE conversations SET title = ? WHERE id = ?`, t, conversationID)
	return err
}

type Conversation struct {
	ID            string `json:"id"`
	ModelID       string `json:"model_id"`
	ModelName     string `json:"model_name"`
	Title         string `json:"title"`
	IsTEE         bool   `json:"is_tee"`
	Pinned        bool   `json:"pinned"`
	UpdatedAt     int64  `json:"updated_at"`
	SessionID     string `json:"session_id,omitempty"`
	SessionEndsAt int64  `json:"session_ends_at,omitempty"` // unix seconds from chain; 0 omitted
	Source        string `json:"source,omitempty"`           // "ui" or "api"
}

func (s *Store) ListConversations(limit int) ([]Conversation, error) {
	rows, err := s.db.Query(
		`SELECT id, model_id, COALESCE(model_name,''), COALESCE(title,''), is_tee, COALESCE(pinned,0), updated_at, COALESCE(session_id,''), COALESCE(source,'ui')
		 FROM conversations ORDER BY pinned DESC, updated_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Conversation
	for rows.Next() {
		var c Conversation
		var isTee, pinned int
		if err := rows.Scan(&c.ID, &c.ModelID, &c.ModelName, &c.Title, &isTee, &pinned, &c.UpdatedAt, &c.SessionID, &c.Source); err != nil {
			return nil, err
		}
		c.IsTEE = isTee != 0
		c.Pinned = pinned != 0
		out = append(out, c)
	}
	return out, rows.Err()
}

// SetConversationSession stores the on-chain MOR session id for resume-after-unlock UX.
func (s *Store) SetConversationSession(conversationID, sessionID string) error {
	now := time.Now().Unix()
	res, err := s.db.Exec(
		`UPDATE conversations SET session_id = ?, updated_at = ? WHERE id = ?`,
		sessionID, now, conversationID,
	)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("store: no conversation %q", conversationID)
	}
	return nil
}

func normalizeSessionIDKey(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	s = strings.TrimPrefix(s, "0x")
	return s
}

// ClearConversationSessionBySessionID sets session_id to NULL for conversations tied to this
// on-chain session. Compares normalized hex so 0x prefix / casing differences still match.
func (s *Store) ClearConversationSessionBySessionID(sessionID string) error {
	target := normalizeSessionIDKey(sessionID)
	if target == "" {
		return nil
	}
	now := time.Now().Unix()
	rows, err := s.db.Query(
		`SELECT id, COALESCE(session_id,'') FROM conversations WHERE session_id IS NOT NULL AND TRIM(session_id) != ''`,
	)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id, sid string
		if err := rows.Scan(&id, &sid); err != nil {
			return err
		}
		if normalizeSessionIDKey(sid) != target {
			continue
		}
		if _, err := s.db.Exec(`UPDATE conversations SET session_id = NULL, updated_at = ? WHERE id = ?`, now, id); err != nil {
			return err
		}
	}
	return rows.Err()
}

// ReconcileConversationSessions clears local session_id when that id is not in the open on-chain
// set. Keys in openKeys must be normalizeSessionIDKey(sessionID) form.
func (s *Store) ReconcileConversationSessions(openKeys map[string]bool) error {
	rows, err := s.db.Query(
		`SELECT id, COALESCE(session_id,'') FROM conversations WHERE session_id IS NOT NULL AND TRIM(session_id) != ''`,
	)
	if err != nil {
		return err
	}
	defer rows.Close()
	now := time.Now().Unix()
	for rows.Next() {
		var id, sid string
		if err := rows.Scan(&id, &sid); err != nil {
			return err
		}
		k := normalizeSessionIDKey(sid)
		if k == "" {
			continue
		}
		if openKeys[k] {
			continue
		}
		if _, err := s.db.Exec(`UPDATE conversations SET session_id = NULL, updated_at = ? WHERE id = ?`, now, id); err != nil {
			return err
		}
	}
	return rows.Err()
}

// SetConversationTitle sets the display title for history lists (user-defined or auto).
func (s *Store) SetConversationTitle(conversationID, title string) error {
	now := time.Now().Unix()
	res, err := s.db.Exec(
		`UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?`,
		strings.TrimSpace(title), now, conversationID,
	)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("store: no conversation %q", conversationID)
	}
	return nil
}

// SetConversationPinned pins a thread to the top of local history.
func (s *Store) SetConversationPinned(conversationID string, pinned bool) error {
	now := time.Now().Unix()
	v := 0
	if pinned {
		v = 1
	}
	res, err := s.db.Exec(`UPDATE conversations SET pinned = ?, updated_at = ? WHERE id = ?`, v, now, conversationID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("store: no conversation %q", conversationID)
	}
	return nil
}

type Message struct {
	ID        string `json:"id"`
	Role      string `json:"role"`
	Content   string `json:"content"`
	CreatedAt int64  `json:"created_at"`
}

func (s *Store) GetMessages(conversationID string) ([]Message, error) {
	rows, err := s.db.Query(
		`SELECT id, role, content, created_at FROM messages 
		 WHERE conversation_id = ? ORDER BY created_at ASC`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Message
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.Role, &m.Content, &m.CreatedAt); err != nil {
			return nil, err
		}
		m.Content = s.decrypt(m.Content)
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) CreateConversation(id, modelID, modelName, provider string, isTEE bool) error {
	return s.createConversation(id, modelID, modelName, provider, isTEE, "ui")
}

func (s *Store) CreateConversationWithSource(id, modelID, modelName, provider string, isTEE bool, source string) error {
	return s.createConversation(id, modelID, modelName, provider, isTEE, source)
}

func (s *Store) createConversation(id, modelID, modelName, provider string, isTEE bool, source string) error {
	now := time.Now().Unix()
	tee := 0
	if isTEE {
		tee = 1
	}
	if source == "" {
		source = "ui"
	}
	_, err := s.db.Exec(
		`INSERT INTO conversations (id, model_id, model_name, provider, is_tee, created_at, updated_at, source) 
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		id, modelID, modelName, provider, tee, now, now, source,
	)
	return err
}

// LatestEmptyConversationForModel returns the most recently touched conversation for this model
// that has no rows in messages (user opened chat then left before sending).
func (s *Store) LatestEmptyConversationForModel(modelID string) (Conversation, bool, error) {
	var c Conversation
	var isTee, pinned int
	err := s.db.QueryRow(
		`SELECT c.id, c.model_id, COALESCE(c.model_name,''), COALESCE(c.title,''), c.is_tee, COALESCE(c.pinned,0), c.updated_at, COALESCE(c.session_id,''), COALESCE(c.source,'ui')
		 FROM conversations c
		 WHERE c.model_id = ?
		   AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id)
		 ORDER BY c.updated_at DESC
		 LIMIT 1`,
		modelID,
	).Scan(&c.ID, &c.ModelID, &c.ModelName, &c.Title, &isTee, &pinned, &c.UpdatedAt, &c.SessionID, &c.Source)
	if err == sql.ErrNoRows {
		return Conversation{}, false, nil
	}
	if err != nil {
		return Conversation{}, false, err
	}
	c.IsTEE = isTee != 0
	c.Pinned = pinned != 0
	return c, true, nil
}

// DeleteOtherEmptyConversationsForModel removes other message-less conversations for the same model
// (dedupe after re-opening a model from the list).
func (s *Store) DeleteOtherEmptyConversationsForModel(modelID, keepID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	rows, err := tx.Query(
		`SELECT id FROM conversations
		 WHERE model_id = ? AND id != ?
		   AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = conversations.id)`,
		modelID, keepID,
	)
	if err != nil {
		return err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, id := range ids {
		if _, err := tx.Exec(`DELETE FROM messages WHERE conversation_id = ?`, id); err != nil {
			return err
		}
		if _, err := tx.Exec(`DELETE FROM conversations WHERE id = ?`, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// UpdateConversationModelMeta refreshes display fields when reusing an empty draft row.
func (s *Store) UpdateConversationModelMeta(conversationID, modelName, provider string, isTEE bool) error {
	now := time.Now().Unix()
	tee := 0
	if isTEE {
		tee = 1
	}
	_, err := s.db.Exec(
		`UPDATE conversations SET model_name = ?, provider = ?, is_tee = ?, updated_at = ? WHERE id = ?`,
		modelName, provider, tee, now, conversationID,
	)
	return err
}

// CountConversationsWithSessionID returns how many local threads reference this on-chain session
// (normalized hex compare). Used to avoid closing a shared on-chain session when deleting one topic.
func (s *Store) CountConversationsWithSessionID(sessionID string) (int, error) {
	target := normalizeSessionIDKey(sessionID)
	if target == "" {
		return 0, nil
	}
	rows, err := s.db.Query(
		`SELECT COALESCE(session_id,'') FROM conversations WHERE session_id IS NOT NULL AND TRIM(session_id) != ''`,
	)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	n := 0
	for rows.Next() {
		var sid string
		if err := rows.Scan(&sid); err != nil {
			return 0, err
		}
		if normalizeSessionIDKey(sid) == target {
			n++
		}
	}
	return n, rows.Err()
}

// GetConversationSessionID returns the stored on-chain session id for this conversation, if any.
func (s *Store) GetConversationSessionID(conversationID string) (string, error) {
	var sid sql.NullString
	err := s.db.QueryRow(`SELECT session_id FROM conversations WHERE id = ?`, conversationID).Scan(&sid)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("store: no conversation %q", conversationID)
	}
	if err != nil {
		return "", err
	}
	if !sid.Valid {
		return "", nil
	}
	return strings.TrimSpace(sid.String), nil
}

// DeleteConversation removes a thread and all messages (local only).
func (s *Store) DeleteConversation(conversationID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM messages WHERE conversation_id = ?`, conversationID); err != nil {
		return err
	}
	res, err := tx.Exec(`DELETE FROM conversations WHERE id = ?`, conversationID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("store: no conversation %q", conversationID)
	}
	return tx.Commit()
}

func (s *Store) SetPreference(key, value string) error {
	_, err := s.db.Exec(
		`INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)`, key, value)
	return err
}

func (s *Store) GetPreference(key string) (string, error) {
	var val string
	err := s.db.QueryRow(`SELECT value FROM preferences WHERE key = ?`, key).Scan(&val)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return val, err
}
