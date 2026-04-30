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

// TestLatestEmptyConversationForModel_SkipsAPISource is a regression guard
// for the bug where a model-tile tap could "claim" an empty api-source
// conversation as a UI draft, silently rebinding the gateway's audit row to
// a UI thread (renaming it, attaching a different system prompt, etc.). The
// SQL filter must keep api rows invisible to the UI's empty-draft path.
func TestLatestEmptyConversationForModel_SkipsAPISource(t *testing.T) {
	s := tempStore(t)

	if err := s.CreateConversationWithSource("conv-api-empty", "model-x", "M", "", false, "api"); err != nil {
		t.Fatalf("create api conv: %v", err)
	}
	// API row is empty (no messages saved). It must NOT be returned.
	if _, ok, err := s.LatestEmptyConversationForModel("model-x"); err != nil {
		t.Fatalf("query: %v", err)
	} else if ok {
		t.Error("api-source empty conversation must not be returned to the UI's empty-draft path")
	}

	// A UI-source empty conv should still be returned.
	if err := s.CreateConversation("conv-ui-empty", "model-x", "M", "", false); err != nil {
		t.Fatalf("create ui conv: %v", err)
	}
	got, ok, err := s.LatestEmptyConversationForModel("model-x")
	if err != nil {
		t.Fatalf("query: %v", err)
	}
	if !ok || got.ID != "conv-ui-empty" {
		t.Errorf("expected UI conv-ui-empty, got ok=%v id=%q", ok, got.ID)
	}
}

// TestDeleteOtherEmptyConversationsForModel_SkipsAPISource ensures the UI's
// empty-draft dedupe never deletes an api-source row even when it has no
// messages — embeddings sessions in particular may have a brief empty
// window between conversation creation and the first audit message write.
func TestDeleteOtherEmptyConversationsForModel_SkipsAPISource(t *testing.T) {
	s := tempStore(t)

	if err := s.CreateConversationWithSource("conv-api", "model-y", "M", "", false, "api"); err != nil {
		t.Fatalf("create api conv: %v", err)
	}
	if err := s.CreateConversation("conv-ui-keep", "model-y", "M", "", false); err != nil {
		t.Fatalf("create ui keep: %v", err)
	}
	if err := s.CreateConversation("conv-ui-other", "model-y", "M", "", false); err != nil {
		t.Fatalf("create ui other: %v", err)
	}

	if err := s.DeleteOtherEmptyConversationsForModel("model-y", "conv-ui-keep"); err != nil {
		t.Fatalf("DeleteOtherEmptyConversationsForModel: %v", err)
	}

	// Re-list. api conv must survive; the empty UI sibling should be gone;
	// the kept UI conv should remain.
	convos, err := s.ListConversations(10)
	if err != nil {
		t.Fatalf("ListConversations: %v", err)
	}
	survivors := map[string]bool{}
	for _, c := range convos {
		survivors[c.ID] = true
	}
	if !survivors["conv-api"] {
		t.Error("api-source row was deleted by UI dedupe — must be preserved")
	}
	if !survivors["conv-ui-keep"] {
		t.Error("kept UI row was deleted")
	}
	if survivors["conv-ui-other"] {
		t.Error("other UI empty row should have been deleted")
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
