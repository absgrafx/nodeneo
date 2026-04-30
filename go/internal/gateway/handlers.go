package gateway

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	openai "github.com/sashabaranov/go-openai"
)

// handleChatCompletions handles POST /v1/chat/completions (OpenAI-compatible).
//
// The handler operates as a near-pure passthrough: it parses just enough of the
// request to resolve the model and persist a conversation entry, then forwards
// the full request to the upstream Morpheus provider via the SDK and relays
// each chunk back to the client unchanged. This preserves tool_calls,
// reasoning_content, response_format, stream_options.include_usage, finish
// reasons, and any other OpenAI-compatible fields the proxy-router or the
// provider may emit.
func (g *Gateway) handleChatCompletions(w http.ResponseWriter, r *http.Request) {
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

	var req sdk.ChatCompletionRequestExtra
	if err := json.Unmarshal(body, &req); err != nil {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "invalid JSON: "+err.Error())
		return
	}

	if req.Model == "" {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "model field is required")
		return
	}
	if len(req.Messages) == 0 {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "messages field is required")
		return
	}

	ctx := r.Context()

	sess, err := g.resolveSession(ctx, req.Model)
	if err != nil {
		g.log("session resolve error: %v", err)
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", err.Error())
		return
	}

	chatID := r.Header.Get("X-Chat-Id")
	convID := g.recordGatewaySession(chatID, "chat", sess)

	g.persistInboundMessages(convID, req.Messages)

	if req.Stream {
		g.handleStreamingCompletion(w, r, sess, &req, convID)
	} else {
		g.handleNonStreamingCompletion(w, r, sess, &req, convID)
	}
}

func (g *Gateway) handleStreamingCompletion(w http.ResponseWriter, r *http.Request, sess sessionResult, req *sdk.ChatCompletionRequestExtra, convID string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeOpenAIError(w, http.StatusInternalServerError, "server_error", "streaming not supported")
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	var (
		assistantText strings.Builder
		toolCalls     []openai.ToolCall
		finishReason  string
		lastChunk     json.RawMessage
		streamFailed  bool
	)

	err := g.sdk.SendChatCompletion(r.Context(), sess.SessionID, req, func(chunk json.RawMessage, isLast bool) error {
		if chunk == nil && isLast {
			_, _ = fmt.Fprint(w, "data: [DONE]\n\n")
			flusher.Flush()
			return nil
		}

		if _, werr := fmt.Fprintf(w, "data: %s\n\n", chunk); werr != nil {
			streamFailed = true
			return werr
		}
		flusher.Flush()
		lastChunk = chunk

		var delta streamingDeltaProbe
		if err := json.Unmarshal(chunk, &delta); err == nil {
			for _, ch := range delta.Choices {
				if ch.Delta.Content != "" {
					assistantText.WriteString(ch.Delta.Content)
				}
				if len(ch.Delta.ToolCalls) > 0 {
					toolCalls = mergeToolCallDeltas(toolCalls, ch.Delta.ToolCalls)
				}
				if ch.FinishReason != "" {
					finishReason = ch.FinishReason
				}
			}
		}
		return nil
	})

	if err != nil && !streamFailed {
		g.log("streaming prompt error: %v", err)
		data, _ := json.Marshal(openAIErrorWithRequestID(w, "provider_error", err.Error()))
		_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
		_, _ = fmt.Fprint(w, "data: [DONE]\n\n")
		flusher.Flush()
	}

	g.persistAssistantTurn(convID, assistantText.String(), toolCalls, finishReason, lastChunk)
}

func (g *Gateway) handleNonStreamingCompletion(w http.ResponseWriter, r *http.Request, sess sessionResult, req *sdk.ChatCompletionRequestExtra, convID string) {
	var lastChunk json.RawMessage

	err := g.sdk.SendChatCompletion(r.Context(), sess.SessionID, req, func(chunk json.RawMessage, isLast bool) error {
		if chunk != nil {
			lastChunk = chunk
		}
		return nil
	})
	if err != nil {
		g.log("prompt error: %v", err)
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", err.Error())
		return
	}

	if lastChunk == nil {
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", "empty response from provider")
		return
	}

	g.persistAssistantNonStreaming(convID, lastChunk)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(lastChunk)
}

// streamingDeltaProbe is the minimal shape we extract from each upstream
// streaming chunk for local persistence and merging. The chunk itself is
// forwarded verbatim — this struct only inspects it.
type streamingDeltaProbe struct {
	Choices []struct {
		Delta struct {
			Content   string            `json:"content"`
			ToolCalls []openai.ToolCall `json:"tool_calls"`
		} `json:"delta"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
}

// nonStreamingResponseProbe extracts the assistant turn from a non-streaming
// response so we can mirror it into the local conversation store.
type nonStreamingResponseProbe struct {
	Choices []struct {
		Message struct {
			Content   string            `json:"content"`
			ToolCalls []openai.ToolCall `json:"tool_calls"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
}

// mergeToolCallDeltas accumulates streamed tool-call fragments into complete
// ToolCall objects. OpenAI streams tool calls as a sequence of delta objects
// keyed by Index — the first delta carries the id/name, subsequent deltas
// append to function.arguments.
func mergeToolCallDeltas(existing []openai.ToolCall, deltas []openai.ToolCall) []openai.ToolCall {
	for _, d := range deltas {
		idx := -1
		if d.Index != nil {
			idx = *d.Index
		}
		if idx < 0 {
			existing = append(existing, d)
			continue
		}
		for len(existing) <= idx {
			existing = append(existing, openai.ToolCall{})
		}
		tc := &existing[idx]
		if d.ID != "" {
			tc.ID = d.ID
		}
		if d.Type != "" {
			tc.Type = d.Type
		}
		if d.Function.Name != "" {
			tc.Function.Name = d.Function.Name
		}
		if d.Function.Arguments != "" {
			tc.Function.Arguments += d.Function.Arguments
		}
		if tc.Index == nil {
			i := idx
			tc.Index = &i
		}
	}
	return existing
}

// handleModels handles GET /v1/models (OpenAI-compatible).
// Fetches models directly from active.mor.org (same source the UI uses),
// with in-memory caching and SDK fallback. Response format matches
// the Morpheus Marketplace API: OpenAI list envelope + Morpheus fields.
func (g *Gateway) handleModels(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeOpenAIError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
		return
	}

	entries, err := g.fetchActiveModels(r.Context())
	if err != nil {
		g.log("list models error: %v", err)
		writeOpenAIError(w, http.StatusInternalServerError, "server_error", err.Error())
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
	_ = json.NewEncoder(w).Encode(v)
}

// openAIError shapes an error payload to match OpenAI's envelope so clients
// (Zed, Cursor, LangChain, etc.) parse it the same way they parse api.openai.com
// errors.
//
// The request_id field is a NodeNeo extension that mirrors the X-Request-Id
// response header inside the body. The motivation: error logs end up in the
// IDE's error toast / Sentry / Datadog without the response headers, so
// embedding the id in the body makes "user pasted a stack trace, now find the
// matching gateway log line" trivial.
type openAIErrorBody struct {
	Error openAIErrorPayload `json:"error"`
}

type openAIErrorPayload struct {
	Message   string `json:"message"`
	Type      string `json:"type,omitempty"`
	Code      string `json:"code,omitempty"`
	Param     string `json:"param,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

// openAIError builds the canonical OpenAI-compatible error envelope.
// The message is run through redactProviderEndpoints so raw provider URLs
// / IPs / host:port pairs that bubble up from the proxy-router are scrubbed
// before they reach external API clients (Cursor, Zed, scripts).
func openAIError(errType, message string) openAIErrorBody {
	return openAIErrorBody{Error: openAIErrorPayload{Message: redactProviderEndpoints(message), Type: errType}}
}

// openAIErrorWithRequestID returns the error envelope with request_id populated
// from the response header set earlier by requestIDMiddleware.
func openAIErrorWithRequestID(w http.ResponseWriter, errType, message string) openAIErrorBody {
	body := openAIError(errType, message)
	if rid := w.Header().Get("X-Request-Id"); rid != "" {
		body.Error.RequestID = rid
	}
	return body
}

func writeOpenAIError(w http.ResponseWriter, status int, errType, message string) {
	writeJSON(w, status, openAIErrorWithRequestID(w, errType, message))
}

// getOrCreateConversation returns a conversation ID for this API request.
//
// Resolution order:
//  1. If `chatID` (X-Chat-Id) is provided and previously seen this gateway
//     run, reuse the cached row.
//  2. Otherwise key off the on-chain session id ("sess:<id>") so non-chat
//     endpoints (embeddings, legacy completions) still pin one conversation
//     row per on-chain session — multiple requests on the same session share
//     a row instead of polluting history with one row per request.
//  3. Falls through to the SQLite store (FindLatestConversationBySessionID)
//     so existing rows are re-attached across gateway restarts.
//  4. Only when none of the above hits do we mint a fresh "api-<ns>" id.
func (g *Gateway) getOrCreateConversation(chatID string, sess sessionResult) (convID string, isNew bool) {
	g.convMu.Lock()
	defer g.convMu.Unlock()

	cacheKeys := make([]string, 0, 2)
	if chatID != "" {
		cacheKeys = append(cacheKeys, chatID)
	}
	if sess.SessionID != "" {
		cacheKeys = append(cacheKeys, "sess:"+sess.SessionID)
	}

	for _, k := range cacheKeys {
		if existing, ok := g.chatIDMap[k]; ok {
			return existing, false
		}
	}

	if g.store != nil && sess.SessionID != "" {
		if id, found, err := g.store.FindLatestConversationBySessionID(sess.SessionID); err == nil && found {
			for _, k := range cacheKeys {
				g.chatIDMap[k] = id
			}
			return id, false
		}
	}

	convID = fmt.Sprintf("api-%d", time.Now().UnixNano())
	for _, k := range cacheKeys {
		g.chatIDMap[k] = convID
	}
	return convID, true
}

// recordGatewaySession ensures every on-chain session opened (or reused) by
// the gateway has a corresponding conversation row in the local SQLite store
// with `source="api"` and `session_id` set. This is what makes API-driven
// sessions appear in NodeNeo's conversation list and stake-accounting flows
// alongside chat-UI sessions, so the user can see/audit them even though the
// underlying API surfaces (embeddings, /v1/completions) aren't an interactive
// chat thread.
//
// `kind` should be a short tag describing the surface that triggered the
// session — "chat", "embeddings", or "completions" — and is used to set a
// human-readable title on first creation. Does nothing if the store is nil
// (which only happens in narrow tests).
func (g *Gateway) recordGatewaySession(chatID, kind string, sess sessionResult) string {
	convID, isNew := g.getOrCreateConversation(chatID, sess)
	if g.store == nil {
		return convID
	}
	if isNew {
		if err := g.store.CreateConversationWithSource(convID, sess.ModelID, sess.ModelName, "", false, "api"); err != nil {
			g.log("create api conversation error: %v", err)
		}
		if sess.SessionID != "" {
			if err := g.store.SetConversationSession(convID, sess.SessionID); err != nil {
				g.log("set api conversation session error: %v", err)
			}
		}
		// Chat completions intentionally leave the title empty so the UI
		// auto-derives it from the first message; non-chat surfaces have no
		// messages worth previewing, so seed a stable title for the list.
		if title := titleForKind(kind, sess.ModelName); title != "" {
			if err := g.store.SetConversationTitle(convID, title); err != nil {
				g.log("set api conversation title error: %v", err)
			}
		}
	} else {
		// Bump updated_at so the existing row floats to the top of the
		// conversation list on each reuse.
		if err := g.store.TouchConversation(convID); err != nil {
			g.log("touch api conversation error: %v", err)
		}
	}
	return convID
}

func titleForKind(kind, modelName string) string {
	kind = strings.TrimSpace(strings.ToLower(kind))
	switch kind {
	case "embeddings":
		if modelName != "" {
			return "API · embeddings · " + modelName
		}
		return "API · embeddings"
	case "completions":
		if modelName != "" {
			return "API · completions · " + modelName
		}
		return "API · completions"
	default:
		return ""
	}
}

// persistInboundMessages writes the user (and tool-result) turns of an
// incoming chat completion request into the local conversation store. Plain
// text user messages are stored without metadata so the Flutter chat UI does
// not render a spurious "Response Info" icon next to them. MultiContent
// (vision) and tool messages keep a metadata sidecar so the original
// structured turn can be reconstructed on reload.
func (g *Gateway) persistInboundMessages(convID string, messages []openai.ChatCompletionMessage) {
	if len(messages) == 0 {
		return
	}

	last := messages[len(messages)-1]
	switch last.Role {
	case openai.ChatMessageRoleUser:
		text, hasParts := flattenMessageContent(last)
		if text == "" && !hasParts {
			return
		}
		if !hasParts {
			_ = g.store.SaveMessage(convID, "user", text)
			return
		}
		_ = g.store.SaveMessageWithMetadata(convID, "user", text, encodeMessageMetadata(last))
	case openai.ChatMessageRoleTool:
		// Tool results echoed back from the IDE; record them so the
		// conversation thread reads correctly on reload.
		text := last.Content
		if text == "" {
			return
		}
		_ = g.store.SaveMessageWithMetadata(convID, "tool", text, encodeMessageMetadata(last))
	}
}

// persistAssistantTurn records the assistant's response from a streaming run.
// Content, tool_calls, finish_reason, and the last raw chunk are stored in the
// metadata column as a structured JSON sidecar so the UI can reconstruct the
// agent turn (incl. tool calls and pending tool results) on reload.
func (g *Gateway) persistAssistantTurn(convID, content string, toolCalls []openai.ToolCall, finishReason string, lastChunk json.RawMessage) {
	if content == "" && len(toolCalls) == 0 {
		return
	}
	displayText := content
	if displayText == "" && len(toolCalls) > 0 {
		displayText = summarizeToolCalls(toolCalls)
	}
	meta := encodeAssistantMetadata(content, toolCalls, finishReason, lastChunk)
	_ = g.store.SaveMessageWithMetadata(convID, "assistant", displayText, meta)
}

// persistAssistantNonStreaming mirrors persistAssistantTurn but extracts the
// fields from a single non-streaming response body.
func (g *Gateway) persistAssistantNonStreaming(convID string, body json.RawMessage) {
	var probe nonStreamingResponseProbe
	if err := json.Unmarshal(body, &probe); err != nil || len(probe.Choices) == 0 {
		return
	}
	choice := probe.Choices[0]
	g.persistAssistantTurn(convID, choice.Message.Content, choice.Message.ToolCalls, choice.FinishReason, body)
}

// flattenMessageContent returns the textual content of a message, joining
// MultiContent text parts and substituting placeholders for non-text parts.
// hasParts is true when MultiContent is populated, so callers can decide
// whether to persist a metadata sidecar even if the flattened text is empty.
func flattenMessageContent(m openai.ChatCompletionMessage) (text string, hasParts bool) {
	if len(m.MultiContent) == 0 {
		return m.Content, false
	}
	var b strings.Builder
	for _, part := range m.MultiContent {
		switch part.Type {
		case openai.ChatMessagePartTypeText:
			if b.Len() > 0 {
				b.WriteString("\n")
			}
			b.WriteString(part.Text)
		case openai.ChatMessagePartTypeImageURL:
			if b.Len() > 0 {
				b.WriteString("\n")
			}
			b.WriteString("[image]")
		}
	}
	return b.String(), true
}

// encodeMessageMetadata serialises a message verbatim for the metadata column.
// This preserves MultiContent parts, tool_call_id, name, etc. so the local UI
// can re-render the original turn even though the searchable content column
// only carries flattened text.
func encodeMessageMetadata(m openai.ChatCompletionMessage) string {
	b, err := json.Marshal(struct {
		Source  string                        `json:"source"`
		Message openai.ChatCompletionMessage `json:"message"`
	}{Source: "api", Message: m})
	if err != nil {
		return ""
	}
	return string(b)
}

// encodeAssistantMetadata stores the structured assistant turn alongside the
// last raw provider chunk for diagnostics. The field name `provider_response`
// matches the shape Flutter's chat screen renders in its Response Info sheet
// (see _buildProviderSummaryRows in lib/screens/chat/chat_screen.dart) so API
// conversations open in NodeNeo's UI with the same rich metadata view as
// directly-authored ones.
func encodeAssistantMetadata(content string, toolCalls []openai.ToolCall, finishReason string, lastChunk json.RawMessage) string {
	payload := struct {
		Source           string            `json:"source"`
		Content          string            `json:"content,omitempty"`
		ToolCalls        []openai.ToolCall `json:"tool_calls,omitempty"`
		FinishReason     string            `json:"finish_reason,omitempty"`
		ProviderResponse json.RawMessage   `json:"provider_response,omitempty"`
	}{
		Source:           "api",
		Content:          content,
		ToolCalls:        toolCalls,
		FinishReason:     finishReason,
		ProviderResponse: lastChunk,
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return ""
	}
	return string(b)
}

// summarizeToolCalls returns a short human-readable description of a set of
// tool calls, used as the searchable content column when the assistant turn
// has no textual content (pure tool-call response).
func summarizeToolCalls(toolCalls []openai.ToolCall) string {
	if len(toolCalls) == 0 {
		return ""
	}
	names := make([]string, 0, len(toolCalls))
	for _, tc := range toolCalls {
		if tc.Function.Name != "" {
			names = append(names, tc.Function.Name)
		}
	}
	if len(names) == 0 {
		return "[tool_calls]"
	}
	return "[tool_calls: " + strings.Join(names, ", ") + "]"
}
