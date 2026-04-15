package store

import (
	"archive/zip"
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// BackupManifest is included in every export zip.
type BackupManifest struct {
	Version       int    `json:"version"`
	AppVersion    string `json:"app_version"`
	ExportDate    string `json:"export_date"`
	WalletPrefix  string `json:"wallet_prefix"`
	Conversations int    `json:"conversations"`
	Messages      int    `json:"messages"`
}

// ExportBackup exports all conversations, messages, and preferences into an
// AES-256-GCM encrypted zip file. The encryption key is SHA-256 of passphrase.
// Returns the path to the written file.
func (s *Store) ExportBackup(outputPath, passphrase, appVersion, walletPrefix string) error {
	key := deriveKey(passphrase)

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	convos, err := s.exportAllConversations()
	if err != nil {
		return fmt.Errorf("export conversations: %w", err)
	}
	msgs, err := s.exportAllMessages()
	if err != nil {
		return fmt.Errorf("export messages: %w", err)
	}
	prefs, err := s.exportAllPreferences()
	if err != nil {
		return fmt.Errorf("export preferences: %w", err)
	}

	manifest := BackupManifest{
		Version:       1,
		AppVersion:    appVersion,
		ExportDate:    time.Now().UTC().Format(time.RFC3339),
		WalletPrefix:  walletPrefix,
		Conversations: len(convos),
		Messages:      len(msgs),
	}

	if err := writeJSONToZip(zw, "manifest.json", manifest); err != nil {
		return err
	}
	if err := writeJSONToZip(zw, "conversations.json", convos); err != nil {
		return err
	}
	if err := writeJSONToZip(zw, "messages.json", msgs); err != nil {
		return err
	}
	if err := writeJSONToZip(zw, "preferences.json", prefs); err != nil {
		return err
	}

	if err := zw.Close(); err != nil {
		return fmt.Errorf("close zip: %w", err)
	}

	encrypted, err := encryptAESGCM(key, buf.Bytes())
	if err != nil {
		return fmt.Errorf("encrypt: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}
	return os.WriteFile(outputPath, encrypted, 0o600)
}

// ImportBackup reads an encrypted backup, decrypts, validates, and
// destructively replaces all conversations, messages, and preferences.
func (s *Store) ImportBackup(inputPath, passphrase string) (*BackupManifest, error) {
	key := deriveKey(passphrase)

	encrypted, err := os.ReadFile(inputPath)
	if err != nil {
		return nil, fmt.Errorf("read backup: %w", err)
	}

	plaintext, err := decryptAESGCM(key, encrypted)
	if err != nil {
		return nil, fmt.Errorf("decrypt failed (wrong passphrase?): %w", err)
	}

	zr, err := zip.NewReader(bytes.NewReader(plaintext), int64(len(plaintext)))
	if err != nil {
		return nil, fmt.Errorf("open zip: %w", err)
	}

	var manifest BackupManifest
	if err := readJSONFromZip(zr, "manifest.json", &manifest); err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}
	if manifest.Version != 1 {
		return nil, fmt.Errorf("unsupported backup version %d", manifest.Version)
	}

	var convos []map[string]interface{}
	if err := readJSONFromZip(zr, "conversations.json", &convos); err != nil {
		return nil, fmt.Errorf("read conversations: %w", err)
	}
	var msgs []map[string]interface{}
	if err := readJSONFromZip(zr, "messages.json", &msgs); err != nil {
		return nil, fmt.Errorf("read messages: %w", err)
	}
	var prefs []map[string]interface{}
	if err := readJSONFromZip(zr, "preferences.json", &prefs); err != nil {
		return nil, fmt.Errorf("read preferences: %w", err)
	}

	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Destructive: wipe existing data.
	for _, table := range []string{"messages", "conversations", "preferences"} {
		if _, err := tx.Exec("DELETE FROM " + table); err != nil {
			return nil, fmt.Errorf("clear %s: %w", table, err)
		}
	}

	for _, c := range convos {
		if _, err := tx.Exec(
			`INSERT OR REPLACE INTO conversations (id, model_id, model_name, provider, title, is_tee, pinned, source, tuning_params, system_prompt, session_id, created_at, updated_at)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			c["id"], c["model_id"], c["model_name"], c["provider"], c["title"],
			intVal(c["is_tee"]), intVal(c["pinned"]), strVal(c["source"]),
			strVal(c["tuning_params"]), strVal(c["system_prompt"]), strVal(c["session_id"]),
			intVal(c["created_at"]), intVal(c["updated_at"]),
		); err != nil {
			return nil, fmt.Errorf("import conversation: %w", err)
		}
	}

	for _, m := range msgs {
		if _, err := tx.Exec(
			`INSERT OR REPLACE INTO messages (id, conversation_id, role, content, metadata, created_at)
			 VALUES (?, ?, ?, ?, ?, ?)`,
			m["id"], m["conversation_id"], m["role"], m["content"],
			strVal(m["metadata"]), intVal(m["created_at"]),
		); err != nil {
			return nil, fmt.Errorf("import message: %w", err)
		}
	}

	for _, p := range prefs {
		if _, err := tx.Exec(
			`INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)`,
			p["key"], p["value"],
		); err != nil {
			return nil, fmt.Errorf("import preference: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &manifest, nil
}

// --- internal helpers ---

func deriveKey(passphrase string) []byte {
	h := sha256.Sum256([]byte(passphrase))
	return h[:]
}

func encryptAESGCM(key, plaintext []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	return gcm.Seal(nonce, nonce, plaintext, nil), nil
}

func decryptAESGCM(key, ciphertext []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	ns := gcm.NonceSize()
	if len(ciphertext) < ns {
		return nil, fmt.Errorf("ciphertext too short")
	}
	return gcm.Open(nil, ciphertext[:ns], ciphertext[ns:], nil)
}

func writeJSONToZip(zw *zip.Writer, name string, v interface{}) error {
	w, err := zw.Create(name)
	if err != nil {
		return err
	}
	return json.NewEncoder(w).Encode(v)
}

func readJSONFromZip(zr *zip.Reader, name string, v interface{}) error {
	for _, f := range zr.File {
		if f.Name == name {
			rc, err := f.Open()
			if err != nil {
				return err
			}
			defer rc.Close()
			return json.NewDecoder(rc).Decode(v)
		}
	}
	return fmt.Errorf("file %q not found in archive", name)
}

func (s *Store) exportAllConversations() ([]map[string]interface{}, error) {
	rows, err := s.db.Query(
		`SELECT id, model_id, COALESCE(model_name,''), COALESCE(provider,''), COALESCE(title,''),
		        is_tee, COALESCE(pinned,0), COALESCE(source,'ui'), COALESCE(tuning_params,''),
		        COALESCE(system_prompt,''), COALESCE(session_id,''), created_at, updated_at
		 FROM conversations ORDER BY created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []map[string]interface{}
	for rows.Next() {
		var id, modelID, modelName, provider, title, source, tuning, systemPrompt, sessionID string
		var isTee, pinned int
		var createdAt, updatedAt int64
		if err := rows.Scan(&id, &modelID, &modelName, &provider, &title,
			&isTee, &pinned, &source, &tuning, &systemPrompt, &sessionID, &createdAt, &updatedAt); err != nil {
			return nil, err
		}
		out = append(out, map[string]interface{}{
			"id": id, "model_id": modelID, "model_name": modelName,
			"provider": provider, "title": title, "is_tee": isTee,
			"pinned": pinned, "source": source, "tuning_params": tuning,
			"system_prompt": systemPrompt, "session_id": sessionID,
			"created_at": createdAt, "updated_at": updatedAt,
		})
	}
	return out, rows.Err()
}

func (s *Store) exportAllMessages() ([]map[string]interface{}, error) {
	rows, err := s.db.Query(
		`SELECT id, conversation_id, role, content, COALESCE(metadata,''), created_at
		 FROM messages ORDER BY created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []map[string]interface{}
	for rows.Next() {
		var id, convID, role, content, metadata string
		var createdAt int64
		if err := rows.Scan(&id, &convID, &role, &content, &metadata, &createdAt); err != nil {
			return nil, err
		}
		out = append(out, map[string]interface{}{
			"id": id, "conversation_id": convID, "role": role,
			"content": content, "metadata": metadata, "created_at": createdAt,
		})
	}
	return out, rows.Err()
}

func (s *Store) exportAllPreferences() ([]map[string]interface{}, error) {
	rows, err := s.db.Query(`SELECT key, value FROM preferences`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []map[string]interface{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		out = append(out, map[string]interface{}{"key": k, "value": v})
	}
	return out, rows.Err()
}

func strVal(v interface{}) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	return fmt.Sprintf("%v", v)
}

func intVal(v interface{}) int64 {
	if v == nil {
		return 0
	}
	switch n := v.(type) {
	case float64:
		return int64(n)
	case int64:
		return n
	case int:
		return int64(n)
	case json.Number:
		i, _ := n.Int64()
		return i
	}
	return 0
}
