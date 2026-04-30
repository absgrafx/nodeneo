package gateway

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
)

// handleEmbeddings handles POST /v1/embeddings (OpenAI-compatible).
//
// This endpoint is what powers IDE features like "@codebase" semantic search:
// the IDE chunks the workspace, sends each chunk's text here, and stores the
// returned vector for similarity lookup at query time. Behaviour mirrors
// handleChatCompletions — verbatim passthrough so any provider-specific fields
// (encoding_format, dimensions, etc.) flow through both ways.
func (g *Gateway) handleEmbeddings(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeOpenAIError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "failed to read body")
		return
	}
	defer r.Body.Close()

	var req sdk.EmbeddingsRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "invalid JSON: "+err.Error())
		return
	}

	model := string(req.Model)
	if model == "" {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "model field is required")
		return
	}

	sess, err := g.resolveSession(r.Context(), model)
	if err != nil {
		g.log("embeddings session resolve error: %v", err)
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", err.Error())
		return
	}

	chatID := r.Header.Get("X-Chat-Id")
	convID := g.recordGatewaySession(chatID, "embeddings", sess)
	g.persistEmbeddingsRequest(convID, &req)

	resp, err := g.sdk.SendEmbeddings(r.Context(), sess.SessionID, &req)
	if err != nil {
		g.log("embeddings error: %v", err)
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", err.Error())
		return
	}
	if resp == nil {
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", "empty response from provider")
		return
	}

	g.persistEmbeddingsResponse(convID, resp)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(resp)
}

// persistEmbeddingsRequest records a short audit message describing the
// inputs of an embeddings call. We don't store full input text (it can be
// large and there's no UI for browsing embedding inputs) — just enough for a
// chat history list to show the user which session was used and roughly when.
func (g *Gateway) persistEmbeddingsRequest(convID string, req *sdk.EmbeddingsRequest) {
	if g.store == nil || convID == "" {
		return
	}
	count, totalLen := embeddingsInputStats(req)
	summary := fmt.Sprintf("[embeddings request: %d input(s), ~%d chars]", count, totalLen)
	_ = g.store.SaveMessage(convID, "user", summary)
}

// persistEmbeddingsResponse records the dimensionality and usage metadata of
// the upstream embeddings response. The vector itself is NOT stored — clients
// keep that on their side. This row is purely an audit / cost-accounting
// trail that mirrors what chat completions persist.
func (g *Gateway) persistEmbeddingsResponse(convID string, body json.RawMessage) {
	if g.store == nil || convID == "" {
		return
	}
	var probe struct {
		Data []struct {
			Embedding []float64 `json:"embedding"`
		} `json:"data"`
		Model string          `json:"model"`
		Usage json.RawMessage `json:"usage"`
	}
	_ = json.Unmarshal(body, &probe)
	dim := 0
	if len(probe.Data) > 0 {
		dim = len(probe.Data[0].Embedding)
	}
	summary := fmt.Sprintf("[embeddings response: %d vector(s), %d-dim]", len(probe.Data), dim)
	meta, _ := json.Marshal(struct {
		Source string          `json:"source"`
		Kind   string          `json:"kind"`
		Model  string          `json:"model,omitempty"`
		Count  int             `json:"count"`
		Dim    int             `json:"dim"`
		Usage  json.RawMessage `json:"usage,omitempty"`
	}{Source: "api", Kind: "embeddings", Model: probe.Model, Count: len(probe.Data), Dim: dim, Usage: probe.Usage})
	_ = g.store.SaveMessageWithMetadata(convID, "assistant", summary, string(meta))
}

// embeddingsInputStats returns (count, total-character-length) for the
// `input` field of an embeddings request, which OpenAI permits as either a
// single string, an array of strings, or an array of token-id arrays. Token
// arrays don't contribute to the char count.
func embeddingsInputStats(req *sdk.EmbeddingsRequest) (count, totalChars int) {
	if req == nil || req.Input == nil {
		return 0, 0
	}
	raw, err := json.Marshal(req.Input)
	if err != nil || len(raw) == 0 || string(raw) == "null" {
		return 0, 0
	}
	var single string
	if err := json.Unmarshal(raw, &single); err == nil {
		if single == "" {
			return 0, 0
		}
		return 1, len(single)
	}
	var many []string
	if err := json.Unmarshal(raw, &many); err == nil {
		total := 0
		for _, s := range many {
			total += len(s)
		}
		return len(many), total
	}
	var generic []json.RawMessage
	if err := json.Unmarshal(raw, &generic); err == nil {
		return len(generic), 0
	}
	return 0, 0
}
