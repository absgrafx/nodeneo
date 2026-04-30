package gateway

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
)

// TestCapabilityInference covers the supports_tools / supports_vision /
// supports_reasoning heuristics. These flags are advisory but several clients
// auto-configure features from them, so it's worth pinning the behaviour.
func TestCapabilityInference(t *testing.T) {
	cases := []struct {
		name      string
		modelName string
		tags      []string
		tools     bool
		vision    bool
		reason    bool
	}{
		{name: "glm-5.1 tools + reasoning", modelName: "glm-5.1", tools: true, reason: true},
		{name: "glm-5.0 tools + reasoning", modelName: "glm-5.0", tools: true, reason: true},
		{name: "llama-3.1 tools", modelName: "llama-3.1-70b", tools: true},
		{name: "deepseek-r1 reasoning + tools", modelName: "deepseek-r1", tools: true, reason: true},
		{name: "qwen2.5-vl multimodal", modelName: "qwen2.5-vl-72b", tools: true, vision: true},
		{name: "tag override marks tools", modelName: "obscure-model", tags: []string{"tools"}, tools: true},
		{name: "vision tag override", modelName: "obscure-model", tags: []string{"vision"}, vision: true},
		{name: "reasoning tag override", modelName: "obscure-model", tags: []string{"reasoning"}, reason: true},
		{name: "vanilla llama-2 has none", modelName: "llama-2-13b", tools: false, vision: false, reason: false},
		{name: "case insensitive name match", modelName: "GLM-5.1", tools: true, reason: true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := supportsTools(tc.modelName, tc.tags); got != tc.tools {
				t.Errorf("supports_tools(%q,%v): got %v, want %v", tc.modelName, tc.tags, got, tc.tools)
			}
			if got := supportsVision(tc.modelName, tc.tags); got != tc.vision {
				t.Errorf("supports_vision(%q,%v): got %v, want %v", tc.modelName, tc.tags, got, tc.vision)
			}
			if got := supportsReasoning(tc.modelName, tc.tags); got != tc.reason {
				t.Errorf("supports_reasoning(%q,%v): got %v, want %v", tc.modelName, tc.tags, got, tc.reason)
			}
		})
	}
}

// TestModelsResponseSurfacesCapabilities asserts the JSON written by
// /v1/models carries the new capability flags so consumers can see them.
// Capability flags are always serialised — `false` is emitted explicitly
// rather than elided — so clients can tell apart "gateway does not know" (no
// field) from "gateway examined this model and concluded false" (field set
// to false).
func TestModelsResponseSurfacesCapabilities(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)
	gw.setCachedModels([]activeModel{
		{ID: "0xabc", Name: "glm-5.1", Tags: []string{"LLM"}, ModelType: "LLM", CreatedAt: 1700000000},
		{ID: "0xdef", Name: "llama-2-7b", Tags: []string{"LLM"}, ModelType: "LLM", CreatedAt: 1700000001},
	}, "etag")

	rr := httptest.NewRecorder()
	gw.handleModels(rr, httptest.NewRequest(http.MethodGet, "/v1/models", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("got %d: %s", rr.Code, rr.Body.String())
	}
	var resp modelsListResponse
	if err := json.NewDecoder(rr.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Data) != 2 {
		t.Fatalf("expected 2 models, got %d", len(resp.Data))
	}
	for _, m := range resp.Data {
		switch m.ID {
		case "glm-5.1":
			if !m.SupportsTools {
				t.Error("glm-5.1 should advertise supports_tools=true")
			}
			if !m.SupportsReasoning {
				t.Error("glm-5.1 should advertise supports_reasoning=true (it streams reasoning_content)")
			}
		case "llama-2-7b":
			if m.SupportsTools {
				t.Error("llama-2-7b should NOT advertise supports_tools=true")
			}
		}
	}

	// Confirm the JSON wire shape includes explicit booleans for the
	// false case rather than omitting the field. We do this by re-marshaling
	// the struct, which round-trips through the `json:` tags.
	bodyBytes, _ := json.Marshal(resp.Data[1]) // llama-2-7b
	bodyStr := string(bodyBytes)
	for _, marker := range []string{`"supports_tools":false`, `"supports_vision":false`, `"supports_reasoning":false`} {
		if !strings.Contains(bodyStr, marker) {
			t.Errorf("expected explicit false for capability flag, missing %s\n%s", marker, bodyStr)
		}
	}
}

// TestRequestIDMiddleware verifies X-Request-Id is generated when missing,
// echoed when supplied, and made available on the request context.
func TestRequestIDMiddleware(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	t.Run("generated when absent", func(t *testing.T) {
		var seenID string
		handler := gw.requestIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			seenID = requestIDFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

		rr := httptest.NewRecorder()
		handler.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil))

		if seenID == "" {
			t.Error("handler did not see a request id on context")
		}
		if rr.Header().Get("X-Request-Id") != seenID {
			t.Errorf("response header (%q) does not match context id (%q)", rr.Header().Get("X-Request-Id"), seenID)
		}
		if !strings.HasPrefix(seenID, "req-") {
			t.Errorf("generated id should be prefixed req-, got %q", seenID)
		}
	})

	t.Run("echoed when supplied", func(t *testing.T) {
		var seenID string
		handler := gw.requestIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			seenID = requestIDFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/health", nil)
		req.Header.Set("X-Request-Id", "client-supplied-abc123")
		rr := httptest.NewRecorder()
		handler.ServeHTTP(rr, req)

		if seenID != "client-supplied-abc123" {
			t.Errorf("expected echoed id, got %q", seenID)
		}
		if rr.Header().Get("X-Request-Id") != "client-supplied-abc123" {
			t.Errorf("response header not echoed, got %q", rr.Header().Get("X-Request-Id"))
		}
	})
}

// TestLegacyCompletionsRequestTranslation covers the prompt → messages
// transformation, including string and array prompt forms, and rejection of
// unsupported batch / token-id arrays.
func TestLegacyCompletionsRequestTranslation(t *testing.T) {
	t.Run("string prompt becomes single user message", func(t *testing.T) {
		raw := []byte(`{"model":"glm-5.1","prompt":"hello","max_tokens":50,"temperature":0.7}`)
		var legacy legacyCompletionRequest
		if err := json.Unmarshal(raw, &legacy); err != nil {
			t.Fatal(err)
		}
		prompts, err := legacy.flattenPrompts()
		if err != nil {
			t.Fatal(err)
		}
		if len(prompts) != 1 || prompts[0] != "hello" {
			t.Fatalf("got %v", prompts)
		}
		chatReq := legacy.toChatRequest(prompts[0])
		if chatReq.Model != "glm-5.1" {
			t.Errorf("model not preserved: %q", chatReq.Model)
		}
		if len(chatReq.Messages) != 1 || chatReq.Messages[0].Content != "hello" || chatReq.Messages[0].Role != "user" {
			t.Errorf("messages translation failed: %+v", chatReq.Messages)
		}
		if chatReq.MaxTokens != 50 {
			t.Errorf("max_tokens not propagated: %d", chatReq.MaxTokens)
		}
		if chatReq.Temperature != 0.7 {
			t.Errorf("temperature not propagated: %v", chatReq.Temperature)
		}
	})

	t.Run("stop string vs array", func(t *testing.T) {
		raw := []byte(`{"model":"x","prompt":"y","stop":"###"}`)
		var legacy legacyCompletionRequest
		if err := json.Unmarshal(raw, &legacy); err != nil {
			t.Fatal(err)
		}
		chatReq := legacy.toChatRequest("y")
		if len(chatReq.Stop) != 1 || chatReq.Stop[0] != "###" {
			t.Errorf("stop string not translated: %+v", chatReq.Stop)
		}

		raw = []byte(`{"model":"x","prompt":"y","stop":["###","END"]}`)
		legacy = legacyCompletionRequest{}
		if err := json.Unmarshal(raw, &legacy); err != nil {
			t.Fatal(err)
		}
		chatReq = legacy.toChatRequest("y")
		if len(chatReq.Stop) != 2 || chatReq.Stop[0] != "###" || chatReq.Stop[1] != "END" {
			t.Errorf("stop array not translated: %+v", chatReq.Stop)
		}
	})

	t.Run("token-id array rejected", func(t *testing.T) {
		raw := []byte(`{"model":"x","prompt":[1,2,3]}`)
		var legacy legacyCompletionRequest
		if err := json.Unmarshal(raw, &legacy); err != nil {
			t.Fatal(err)
		}
		_, err := legacy.flattenPrompts()
		if err == nil {
			t.Error("expected error for token-id array prompt")
		}
	})
}

// TestLegacyCompletionsBatchRejected ensures the gateway rejects multi-prompt
// batches with a clear error rather than silently truncating to the first.
func TestLegacyCompletionsBatchRejected(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	body := strings.NewReader(`{"model":"glm-5.1","prompt":["one","two"]}`)
	req := httptest.NewRequest(http.MethodPost, "/v1/completions", body)
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	gw.handleCompletions(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for batch prompt, got %d: %s", rr.Code, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), "batched") {
		t.Errorf("expected batch error message, got %s", rr.Body.String())
	}
}

// TestEmbeddings_BadMethod covers the simple guard.
func TestEmbeddings_BadMethod(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	req := httptest.NewRequest(http.MethodGet, "/v1/embeddings", nil)
	rr := httptest.NewRecorder()
	gw.handleEmbeddings(rr, req)

	if rr.Code != http.StatusMethodNotAllowed {
		t.Errorf("got %d", rr.Code)
	}
}

// TestEmbeddings_MissingModel checks the model field is required.
func TestEmbeddings_MissingModel(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	req := httptest.NewRequest(http.MethodPost, "/v1/embeddings", strings.NewReader(`{"input":"hello"}`))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	gw.handleEmbeddings(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Errorf("got %d, body %s", rr.Code, rr.Body.String())
	}
}

// TestCompletions_BadMethod covers the simple guard.
func TestCompletions_BadMethod(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	req := httptest.NewRequest(http.MethodGet, "/v1/completions", nil)
	rr := httptest.NewRecorder()
	gw.handleCompletions(rr, req)

	if rr.Code != http.StatusMethodNotAllowed {
		t.Errorf("got %d", rr.Code)
	}
}

// TestErrorEnvelopeCarriesRequestID verifies that the X-Request-Id set by the
// middleware is mirrored into the error body so it survives across IDE error
// toasts / Sentry events that drop response headers.
func TestErrorEnvelopeCarriesRequestID(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	// Wire up the same middleware order the gateway uses in production so the
	// X-Request-Id header is set before the handler emits the error.
	handler := gw.requestIDMiddleware(http.HandlerFunc(gw.handleChatCompletions))

	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Request-Id", "req-test-12345")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rr.Code)
	}
	if got := rr.Header().Get("X-Request-Id"); got != "req-test-12345" {
		t.Errorf("response header request id: got %q", got)
	}

	var body openAIErrorBody
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v\n%s", err, rr.Body.String())
	}
	if body.Error.RequestID != "req-test-12345" {
		t.Errorf("error.request_id not propagated: got %q", body.Error.RequestID)
	}
	if body.Error.Type != "invalid_request_error" {
		t.Errorf("error.type: got %q", body.Error.Type)
	}
}

// TestAuthErrorUsesOpenAIEnvelope ensures the auth middleware was migrated
// off the legacy {"error":"…"} string shape to the structured envelope, and
// that it also picks up the request id when present.
func TestAuthErrorUsesOpenAIEnvelope(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	handler := gw.requestIDMiddleware(gw.authMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})))

	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	req.Header.Set("X-Request-Id", "req-auth-99")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}

	var body openAIErrorBody
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("auth error must be valid OpenAI envelope: %v\n%s", err, rr.Body.String())
	}
	if body.Error.Message == "" {
		t.Error("expected non-empty error.message")
	}
	if body.Error.Type == "" {
		t.Error("expected error.type set")
	}
	if body.Error.RequestID != "req-auth-99" {
		t.Errorf("error.request_id: got %q", body.Error.RequestID)
	}
}

// TestRecordGatewaySession_PersistsAndReuses verifies the helper that
// underpins API-driven session accounting:
//   - new on-chain session → fresh conversation row with source="api",
//     session_id set, and a kind-specific title;
//   - subsequent reuse → same row, updated_at bumped (no duplicates);
//   - non-chat surfaces (embeddings, completions) emit a non-empty title so
//     the row is identifiable in the conversation list even without messages.
func TestRecordGatewaySession_PersistsAndReuses(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	sess := sessionResult{SessionID: "0xabc", ModelID: "0xmodel", ModelName: "text-embedding-bge-m3"}

	conv1 := gw.recordGatewaySession("", "embeddings", sess)
	if conv1 == "" {
		t.Fatal("expected non-empty conversation id")
	}
	row, found, err := st.GetConversationByID(conv1)
	if err != nil {
		t.Fatalf("GetConversationByID: %v", err)
	}
	if !found {
		t.Fatal("expected conversation row to exist")
	}
	if row.Source != "api" {
		t.Errorf("source: got %q, want api", row.Source)
	}
	if row.SessionID == "" {
		t.Error("session_id must be persisted on the row")
	}
	if !strings.Contains(row.Title, "embeddings") {
		t.Errorf("title should reflect kind, got %q", row.Title)
	}
	firstUpdated := row.UpdatedAt

	// Second record on same session → reuse, no new row.
	time.Sleep(1100 * time.Millisecond) // updated_at is unix seconds
	conv2 := gw.recordGatewaySession("", "embeddings", sess)
	if conv2 != conv1 {
		t.Errorf("expected reuse, got %q vs %q", conv2, conv1)
	}
	row2, _, _ := st.GetConversationByID(conv1)
	if row2.UpdatedAt <= firstUpdated {
		t.Errorf("updated_at should be bumped on reuse, %d -> %d", firstUpdated, row2.UpdatedAt)
	}
}

// TestRecordGatewaySession_ChatKindLeavesTitleEmpty makes sure the chat
// completions surface still leaves the title blank so the existing UI
// auto-derives it from the first turn — only the audit-only surfaces get a
// fixed "API · …" title.
func TestRecordGatewaySession_ChatKindLeavesTitleEmpty(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	sess := sessionResult{SessionID: "0xchat", ModelID: "0xm", ModelName: "glm-5.1"}
	conv := gw.recordGatewaySession("chat-zed-1", "chat", sess)
	row, found, err := st.GetConversationByID(conv)
	if err != nil {
		t.Fatalf("GetConversationByID: %v", err)
	}
	if !found {
		t.Fatal("expected conversation row to exist")
	}
	if row.Title != "" {
		t.Errorf("chat kind must keep title empty for UI auto-derivation, got %q", row.Title)
	}
	if row.Source != "api" {
		t.Errorf("source: got %q, want api", row.Source)
	}
}

// TestEmbeddingsInputStats sanity checks the audit summary helper across the
// three OpenAI input shapes (single string, string array, token-id array).
func TestEmbeddingsInputStats(t *testing.T) {
	cases := []struct {
		name      string
		input     interface{}
		wantCount int
		wantMin   int
	}{
		{"single string", "hello world", 1, 11},
		{"string slice", []string{"hello", "world"}, 2, 10},
		{"token id array", [][]int{{1, 2, 3}, {4, 5}}, 2, 0},
		{"nil input", nil, 0, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := &sdk.EmbeddingsRequest{}
			req.Input = tc.input
			gotCount, gotChars := embeddingsInputStats(req)
			if gotCount != tc.wantCount {
				t.Errorf("count: got %d, want %d", gotCount, tc.wantCount)
			}
			if gotChars < tc.wantMin {
				t.Errorf("chars: got %d, want >= %d", gotChars, tc.wantMin)
			}
		})
	}
}

// TestResolveSessionDuration_FollowsPreference makes sure the gateway opens
// sessions using the same `session_duration_seconds` preference the chat UI
// writes to via SessionDurationStore. Updating the preference between calls
// must change the next resolved value without a gateway restart, so
// API-driven sessions and chat-UI sessions stay in lockstep.
func TestResolveSessionDuration_FollowsPreference(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	if got := gw.resolveSessionDuration(); got != 3600 {
		t.Fatalf("default fallback: got %d, want 3600", got)
	}

	if err := st.SetPreference("session_duration_seconds", "600"); err != nil {
		t.Fatalf("SetPreference: %v", err)
	}
	if got := gw.resolveSessionDuration(); got != 600 {
		t.Errorf("after pref=600: got %d, want 600", got)
	}

	if err := st.SetPreference("session_duration_seconds", "7200"); err != nil {
		t.Fatalf("SetPreference: %v", err)
	}
	if got := gw.resolveSessionDuration(); got != 7200 {
		t.Errorf("after pref=7200: got %d, want 7200", got)
	}

	// Below the network minimum (600s) → fall back to the constructor default
	// rather than open an unusable session.
	if err := st.SetPreference("session_duration_seconds", "30"); err != nil {
		t.Fatalf("SetPreference: %v", err)
	}
	if got := gw.resolveSessionDuration(); got != 3600 {
		t.Errorf("below floor must fall back: got %d, want 3600", got)
	}

	// Garbage values are ignored, not crashed on.
	if err := st.SetPreference("session_duration_seconds", "not-a-number"); err != nil {
		t.Fatalf("SetPreference: %v", err)
	}
	if got := gw.resolveSessionDuration(); got != 3600 {
		t.Errorf("malformed pref must fall back: got %d, want 3600", got)
	}
}
