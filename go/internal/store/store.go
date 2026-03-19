package store

import (
	"database/sql"
	"fmt"
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
	return nil
}

func (s *Store) SaveMessage(conversationID, role, content string) error {
	id := fmt.Sprintf("%s-%d", role, time.Now().UnixNano())
	_, err := s.db.Exec(
		`INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)`,
		id, conversationID, role, content, time.Now().Unix(),
	)
	return err
}

type Conversation struct {
	ID        string `json:"id"`
	ModelID   string `json:"model_id"`
	ModelName string `json:"model_name"`
	Title     string `json:"title"`
	IsTEE     bool   `json:"is_tee"`
	UpdatedAt int64  `json:"updated_at"`
}

func (s *Store) ListConversations(limit int) ([]Conversation, error) {
	rows, err := s.db.Query(
		`SELECT id, model_id, COALESCE(model_name,''), COALESCE(title,''), is_tee, updated_at 
		 FROM conversations ORDER BY updated_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Conversation
	for rows.Next() {
		var c Conversation
		var isTee int
		if err := rows.Scan(&c.ID, &c.ModelID, &c.ModelName, &c.Title, &isTee, &c.UpdatedAt); err != nil {
			return nil, err
		}
		c.IsTEE = isTee != 0
		out = append(out, c)
	}
	return out, rows.Err()
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
