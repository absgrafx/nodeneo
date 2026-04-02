package store

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"io"
	"strings"
)

const encPrefix = "enc:v1:" // prefix distinguishing encrypted blobs from legacy plaintext

// encrypt returns "enc:v1:<base64(nonce+ciphertext)>" or the raw string if no key is set.
func (s *Store) encrypt(plain string) string {
	if s.gcm == nil {
		return plain
	}
	nonce := make([]byte, s.gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return plain // degrade gracefully
	}
	ct := s.gcm.Seal(nonce, nonce, []byte(plain), nil)
	return encPrefix + base64.StdEncoding.EncodeToString(ct)
}

// decrypt reverses encrypt. Legacy plaintext (no prefix) is returned as-is.
func (s *Store) decrypt(stored string) string {
	if s.gcm == nil || !strings.HasPrefix(stored, encPrefix) {
		return stored
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(stored, encPrefix))
	if err != nil {
		return stored
	}
	ns := s.gcm.NonceSize()
	if len(raw) < ns {
		return stored
	}
	plain, err := s.gcm.Open(nil, raw[:ns], raw[ns:], nil)
	if err != nil {
		return stored // corrupted or wrong key — return raw
	}
	return string(plain)
}

// SetEncryptionKey derives an AES-256-GCM cipher from a 32-byte hex key.
// Call after Init once the mnemonic is available. Idempotent.
func (s *Store) SetEncryptionKey(key []byte) error {
	if len(key) != 32 {
		return nil // silently ignore bad keys; no encryption
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}
	s.gcm = gcm
	return nil
}
