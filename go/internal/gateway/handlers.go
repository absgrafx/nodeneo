package gateway

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	openai "github.com/sashabaranov/go-openai"
)

// handleChatCompletions handles POST /v1/chat/completions (OpenAI-compatible).
func (g *Gateway) handleChatCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read body"})
		return
	}
	defer r.Body.Close()

	var req openai.ChatCompletionRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.Model == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "model field is required"})
		return
	}
	if len(req.Messages) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "messages field is required"})
		return
	}

	ctx := r.Context()

	sess, err := g.resolveSession(ctx, req.Model)
	if err != nil {
		g.log("session resolve error: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}

	// Create or reuse conversation for persistence in the UI
	chatID := r.Header.Get("X-Chat-Id")
	convID, isNew := g.getOrCreateConversation(chatID, sess)
	if isNew {
		if err := g.store.CreateConversationWithSource(convID, sess.ModelID, sess.ModelName, "", false, "api"); err != nil {
			g.log("create conversation error: %v", err)
		}
		if err := g.store.SetConversationSession(convID, sess.SessionID); err != nil {
			g.log("set conversation session error: %v", err)
		}
	}

	// Persist user messages
	lastUserContent := ""
	for _, m := range req.Messages {
		if m.Role == "user" {
			lastUserContent = m.Content
		}
	}
	if lastUserContent != "" {
		_ = g.store.SaveMessage(convID, "user", lastUserContent)
	}

	if req.Stream {
		g.handleStreamingCompletion(w, r, sess, req, convID)
	} else {
		g.handleNonStreamingCompletion(w, r, sess, req, convID)
	}
}

func (g *Gateway) handleStreamingCompletion(w http.ResponseWriter, r *http.Request, sess sessionResult, req openai.ChatCompletionRequest, convID string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "streaming not supported"})
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	requestID := fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano())
	var fullResponse string
	params := chatParamsFromRequest(req)

	_, err := g.sdk.SendPromptWithMessagesAndParams(r.Context(), sess.SessionID, req.Messages, true, params, func(text string, isLast bool) error {
		if isLast {
			_, _ = fmt.Fprintf(w, "data: [DONE]\n\n")
			flusher.Flush()
			return nil
		}

		fullResponse += text
		chunk := openai.ChatCompletionStreamResponse{
			ID:      requestID,
			Object:  "chat.completion.chunk",
			Created: time.Now().Unix(),
			Model:   req.Model,
			Choices: []openai.ChatCompletionStreamChoice{
				{
					Index: 0,
					Delta: openai.ChatCompletionStreamChoiceDelta{
						Content: text,
						Role:    "assistant",
					},
				},
			},
		}
		data, _ := json.Marshal(chunk)
		_, err := fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
		return err
	})

	if err != nil {
		g.log("streaming prompt error: %v", err)
		errChunk := map[string]interface{}{
			"error": map[string]string{"message": err.Error(), "type": "provider_error"},
		}
		data, _ := json.Marshal(errChunk)
		fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
	}

	if fullResponse != "" {
		_ = g.store.SaveMessage(convID, "assistant", fullResponse)
	}
}

func (g *Gateway) handleNonStreamingCompletion(w http.ResponseWriter, r *http.Request, sess sessionResult, req openai.ChatCompletionRequest, convID string) {
	var fullResponse string
	params := chatParamsFromRequest(req)
	_, err := g.sdk.SendPromptWithMessagesAndParams(r.Context(), sess.SessionID, req.Messages, false, params, func(text string, isLast bool) error {
		fullResponse += text
		return nil
	})
	if err != nil {
		g.log("prompt error: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}

	if fullResponse != "" {
		_ = g.store.SaveMessage(convID, "assistant", fullResponse)
	}

	resp := openai.ChatCompletionResponse{
		ID:      fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion",
		Created: time.Now().Unix(),
		Model:   req.Model,
		Choices: []openai.ChatCompletionChoice{
			{
				Index: 0,
				Message: openai.ChatCompletionMessage{
					Role:    "assistant",
					Content: fullResponse,
				},
				FinishReason: openai.FinishReasonStop,
			},
		},
		Usage: openai.Usage{},
	}

	writeJSON(w, http.StatusOK, resp)
}

// handleModels handles GET /v1/models (OpenAI-compatible).
// Fetches models directly from active.mor.org (same source the UI uses),
// with in-memory caching and SDK fallback. Response format matches
// the Morpheus Marketplace API: OpenAI list envelope + Morpheus fields.
func (g *Gateway) handleModels(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	entries, err := g.fetchActiveModels(r.Context())
	if err != nil {
		g.log("list models error: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, modelsListResponse{Object: "list", Data: entries})
}

// handleHealth handles GET /health.
func (g *Gateway) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

// chatParamsFromRequest extracts tuning parameters from an OpenAI chat request.
func chatParamsFromRequest(req openai.ChatCompletionRequest) *sdk.ChatParams {
	p := &sdk.ChatParams{}
	hasOverride := false
	if req.Temperature != 0 {
		t := req.Temperature
		p.Temperature = &t
		hasOverride = true
	}
	if req.TopP != 0 {
		tp := req.TopP
		p.TopP = &tp
		hasOverride = true
	}
	if req.MaxTokens != 0 {
		p.MaxTokens = &req.MaxTokens
		hasOverride = true
	}
	if req.FrequencyPenalty != 0 {
		fp := req.FrequencyPenalty
		p.FrequencyPenalty = &fp
		hasOverride = true
	}
	if req.PresencePenalty != 0 {
		pp := req.PresencePenalty
		p.PresencePenalty = &pp
		hasOverride = true
	}
	if !hasOverride {
		return nil
	}
	return p
}

// getOrCreateConversation returns a conversation ID for this API request.
// If chatID is provided and known, reuse it; otherwise generate a new one.
func (g *Gateway) getOrCreateConversation(chatID string, sess sessionResult) (convID string, isNew bool) {
	g.convMu.Lock()
	defer g.convMu.Unlock()

	if chatID != "" {
		if existing, ok := g.chatIDMap[chatID]; ok {
			return existing, false
		}
	}

	convID = fmt.Sprintf("api-%d", time.Now().UnixNano())
	if chatID != "" {
		g.chatIDMap[chatID] = convID
	}
	return convID, true
}
