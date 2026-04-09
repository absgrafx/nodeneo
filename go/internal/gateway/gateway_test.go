package gateway

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/absgrafx/nodeneo/internal/store"
)

func testStore(t *testing.T) *store.Store {
	t.Helper()
	s, err := store.New(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("store.New: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestAuthMiddleware_NoKey(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	handler := gw.authMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", rr.Code)
	}
}

func TestAuthMiddleware_InvalidKey(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	handler := gw.authMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	req.Header.Set("Authorization", "Bearer sk-bogus12345")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", rr.Code)
	}
}

func TestAuthMiddleware_ValidKey(t *testing.T) {
	st := testStore(t)
	fullKey, _, err := st.GenerateAPIKey("test")
	if err != nil {
		t.Fatalf("GenerateAPIKey: %v", err)
	}

	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	var gotInfo bool
	handler := gw.authMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, ok := apiKeyFromContext(r.Context())
		gotInfo = ok
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	req.Header.Set("Authorization", "Bearer "+fullKey)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", rr.Code)
	}
	if !gotInfo {
		t.Error("expected API key info in context")
	}
}

func TestHealth(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rr := httptest.NewRecorder()
	gw.handleHealth(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", rr.Code)
	}
	var body map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("expected status ok, got %q", body["status"])
	}
}

func TestChatCompletions_BadMethod(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	req := httptest.NewRequest(http.MethodGet, "/v1/chat/completions", nil)
	rr := httptest.NewRecorder()
	gw.handleChatCompletions(rr, req)

	if rr.Code != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", rr.Code)
	}
}

func TestChatCompletions_MissingModel(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	body := `{"messages":[{"role":"user","content":"hi"}]}`
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	gw.handleChatCompletions(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rr.Code)
	}
}

func TestCORS(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", gw.handleHealth)
	handler := gw.corsMiddleware(mux)

	req := httptest.NewRequest(http.MethodOptions, "/health", nil)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("expected 204 for OPTIONS, got %d", rr.Code)
	}
	if got := rr.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("expected CORS *, got %q", got)
	}
}

func TestConversationReuse(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	sess := sessionResult{SessionID: "0x123", ModelID: "m1", ModelName: "Test"}
	id1, new1 := gw.getOrCreateConversation("chat-abc", sess)
	if !new1 {
		t.Error("first call should be new")
	}
	id2, new2 := gw.getOrCreateConversation("chat-abc", sess)
	if new2 {
		t.Error("second call with same chatID should reuse")
	}
	if id1 != id2 {
		t.Errorf("expected same conv id, got %q vs %q", id1, id2)
	}

	id3, new3 := gw.getOrCreateConversation("", sess)
	if !new3 {
		t.Error("empty chatID should always create new")
	}
	if id3 == id1 {
		t.Error("different chatID (empty) should produce different conv id")
	}
}

func TestHandleModels_FromActiveMorOrg(t *testing.T) {
	mockPayload := `{"models":[
		{"Id":"0xabc","Name":"glm-5.1","Tags":["LLM"],"ModelType":"LLM","CreatedAt":1700000000,"IsDeleted":false},
		{"Id":"0xdef","Name":"llama3","Tags":["LLM","tee"],"ModelType":"LLM","CreatedAt":1700000001,"IsDeleted":false},
		{"Id":"0xdead","Name":"old-model","Tags":[],"ModelType":"LLM","CreatedAt":1600000000,"IsDeleted":true}
	]}`

	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("ETag", `"test-etag-1"`)
		fmt.Fprint(w, mockPayload)
	}))
	defer mockServer.Close()

	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	// Seed cache directly from mock (bypassing const URL by calling the HTTP logic path
	// through the handler, which in production hits active.mor.org).
	// Instead, manually populate the cache for this test.
	var envelope struct {
		Models []activeModel `json:"models"`
	}
	if err := json.Unmarshal([]byte(mockPayload), &envelope); err != nil {
		t.Fatal(err)
	}
	active := make([]activeModel, 0)
	for _, m := range envelope.Models {
		if !m.IsDeleted && m.Name != "" {
			active = append(active, m)
		}
	}
	gw.setCachedModels(active, `"test-etag-1"`)

	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	rr := httptest.NewRecorder()
	gw.handleModels(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}

	var resp modelsListResponse
	if err := json.NewDecoder(rr.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if resp.Object != "list" {
		t.Errorf("expected object=list, got %q", resp.Object)
	}
	if len(resp.Data) != 2 {
		t.Fatalf("expected 2 active models (deleted filtered out), got %d", len(resp.Data))
	}

	m0 := resp.Data[0]
	if m0.ID != "glm-5.1" {
		t.Errorf("expected id=glm-5.1, got %q", m0.ID)
	}
	if m0.Object != "model" {
		t.Errorf("expected object=model, got %q", m0.Object)
	}
	if m0.BlockchainID != "0xabc" {
		t.Errorf("expected blockchainID=0xabc, got %q", m0.BlockchainID)
	}
	if m0.ModelType != "LLM" {
		t.Errorf("expected modelType=LLM, got %q", m0.ModelType)
	}
}

func TestModelsCache_TTL(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	models := []activeModel{
		{ID: "0x1", Name: "test-model", Tags: []string{"LLM"}, ModelType: "LLM", CreatedAt: 1700000000},
	}
	gw.setCachedModels(models, "etag1")

	// Cache should be valid
	cached, ok := gw.getCachedModels()
	if !ok || len(cached) != 1 {
		t.Fatal("expected cache hit")
	}

	// Expire the cache manually
	gw.modelCache.mu.Lock()
	gw.modelCache.cachedAt = time.Now().Add(-10 * time.Minute)
	gw.modelCache.mu.Unlock()

	_, ok = gw.getCachedModels()
	if ok {
		t.Error("expected cache miss after expiry")
	}
}

func TestFindModelByName(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	models := []activeModel{
		{ID: "0xabc", Name: "glm-5.1", Tags: []string{"LLM"}, ModelType: "LLM", CreatedAt: 1700000000},
		{ID: "0xdef", Name: "llama3", Tags: []string{"LLM", "tee"}, ModelType: "LLM", CreatedAt: 1700000001},
	}
	gw.setCachedModels(models, "etag1")

	entry, ok := gw.findModelByName("glm-5.1")
	if !ok {
		t.Fatal("expected to find glm-5.1")
	}
	if entry.ID != "glm-5.1" || entry.BlockchainID != "0xabc" {
		t.Errorf("unexpected entry: %+v", entry)
	}

	// Case-insensitive
	entry, ok = gw.findModelByName("GLM-5.1")
	if !ok {
		t.Fatal("expected case-insensitive match")
	}
	if entry.ID != "glm-5.1" {
		t.Errorf("expected id=glm-5.1, got %q", entry.ID)
	}

	_, ok = gw.findModelByName("nonexistent")
	if ok {
		t.Error("expected no match for nonexistent model")
	}
}
