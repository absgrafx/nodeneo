package store

import (
	"os"
	"path/filepath"
	"testing"
)

func tempStore(t *testing.T) *Store {
	t.Helper()
	dir := t.TempDir()
	s, err := New(filepath.Join(dir, "test.db"))
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestAPIKeyRoundTrip(t *testing.T) {
	s := tempStore(t)

	fullKey, info, err := s.GenerateAPIKey("test-key")
	if err != nil {
		t.Fatalf("GenerateAPIKey: %v", err)
	}
	if fullKey == "" || info.ID == "" {
		t.Fatal("empty key or id")
	}
	if info.Prefix != fullKey[:9] {
		t.Fatalf("prefix mismatch: %q vs %q", info.Prefix, fullKey[:9])
	}

	got, ok, err := s.ValidateAPIKey(fullKey)
	if err != nil {
		t.Fatalf("ValidateAPIKey: %v", err)
	}
	if !ok {
		t.Fatal("valid key not recognized")
	}
	if got.ID != info.ID {
		t.Fatalf("id mismatch: %q vs %q", got.ID, info.ID)
	}

	_, ok, err = s.ValidateAPIKey("sk-bogus0000000000000000000000000000000000000000000000000000000000000")
	if err != nil {
		t.Fatalf("ValidateAPIKey bogus: %v", err)
	}
	if ok {
		t.Fatal("bogus key should not validate")
	}

	keys, err := s.ListAPIKeys()
	if err != nil {
		t.Fatalf("ListAPIKeys: %v", err)
	}
	if len(keys) != 1 {
		t.Fatalf("expected 1 key, got %d", len(keys))
	}

	if err := s.RevokeAPIKey(info.ID); err != nil {
		t.Fatalf("RevokeAPIKey: %v", err)
	}

	_, ok, err = s.ValidateAPIKey(fullKey)
	if err != nil {
		t.Fatalf("ValidateAPIKey after revoke: %v", err)
	}
	if ok {
		t.Fatal("revoked key should not validate")
	}
}

func TestConversationSource(t *testing.T) {
	s := tempStore(t)

	if err := s.CreateConversationWithSource("conv-api-1", "model-1", "TestModel", "prov", false, "api"); err != nil {
		t.Fatalf("CreateConversationWithSource: %v", err)
	}
	if err := s.CreateConversation("conv-ui-1", "model-1", "TestModel", "prov", false); err != nil {
		t.Fatalf("CreateConversation: %v", err)
	}

	convos, err := s.ListConversations(10)
	if err != nil {
		t.Fatalf("ListConversations: %v", err)
	}
	if len(convos) != 2 {
		t.Fatalf("expected 2 conversations, got %d", len(convos))
	}

	sources := map[string]string{}
	for _, c := range convos {
		sources[c.ID] = c.Source
	}
	if sources["conv-api-1"] != "api" {
		t.Errorf("conv-api-1 source = %q, want %q", sources["conv-api-1"], "api")
	}
	if sources["conv-ui-1"] != "ui" {
		t.Errorf("conv-ui-1 source = %q, want %q", sources["conv-ui-1"], "ui")
	}
}

func TestMigrationIdempotent(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "idem.db")

	s1, err := New(dbPath)
	if err != nil {
		t.Fatalf("New 1: %v", err)
	}
	s1.Close()

	s2, err := New(dbPath)
	if err != nil {
		t.Fatalf("New 2: %v", err)
	}
	s2.Close()

	_ = os.Remove(dbPath)
}
