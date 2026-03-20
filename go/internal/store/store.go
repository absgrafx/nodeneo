package store

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct {
	db *sql.DB
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

func (s *Store) SaveMessage(conversationID, role, content string) error {
	id := fmt.Sprintf("%s-%d", role, time.Now().UnixNano())
	now := time.Now().Unix()
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(
		`INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)`,
		id, conversationID, role, content, now,
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
	ID              string `json:"id"`
	ModelID         string `json:"model_id"`
	ModelName       string `json:"model_name"`
	Title           string `json:"title"`
	IsTEE           bool   `json:"is_tee"`
	Pinned          bool   `json:"pinned"`
	UpdatedAt       int64  `json:"updated_at"`
	SessionID       string `json:"session_id,omitempty"`
	SessionEndsAt   int64  `json:"session_ends_at,omitempty"` // unix seconds from chain; 0 omitted
}

func (s *Store) ListConversations(limit int) ([]Conversation, error) {
	rows, err := s.db.Query(
		`SELECT id, model_id, COALESCE(model_name,''), COALESCE(title,''), is_tee, COALESCE(pinned,0), updated_at, COALESCE(session_id,'') 
		 FROM conversations ORDER BY pinned DESC, updated_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Conversation
	for rows.Next() {
		var c Conversation
		var isTee, pinned int
		if err := rows.Scan(&c.ID, &c.ModelID, &c.ModelName, &c.Title, &isTee, &pinned, &c.UpdatedAt, &c.SessionID); err != nil {
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
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) CreateConversation(id, modelID, modelName, provider string, isTEE bool) error {
	now := time.Now().Unix()
	tee := 0
	if isTEE {
		tee = 1
	}
	_, err := s.db.Exec(
		`INSERT INTO conversations (id, model_id, model_name, provider, is_tee, created_at, updated_at) 
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, modelID, modelName, provider, tee, now, now,
	)
	return err
}

// LatestEmptyConversationForModel returns the most recently touched conversation for this model
// that has no rows in messages (user opened chat then left before sending).
func (s *Store) LatestEmptyConversationForModel(modelID string) (Conversation, bool, error) {
	var c Conversation
	var isTee, pinned int
	err := s.db.QueryRow(
		`SELECT c.id, c.model_id, COALESCE(c.model_name,''), COALESCE(c.title,''), c.is_tee, COALESCE(c.pinned,0), c.updated_at, COALESCE(c.session_id,'')
		 FROM conversations c
		 WHERE c.model_id = ?
		   AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id)
		 ORDER BY c.updated_at DESC
		 LIMIT 1`,
		modelID,
	).Scan(&c.ID, &c.ModelID, &c.ModelName, &c.Title, &isTee, &pinned, &c.UpdatedAt, &c.SessionID)
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
