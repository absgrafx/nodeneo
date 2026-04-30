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

// handleCompletions handles POST /v1/completions (the OpenAI legacy text
// completion endpoint).
//
// Modern agent IDEs (Cursor, Zed) use /v1/chat/completions exclusively, but
// some autocomplete plugins, FIM-aware editors, and LangChain `OpenAI` (vs
// `ChatOpenAI`) wrappers still target this surface. The Morpheus proxy-router
// upstream only speaks chat completions, so this handler:
//
//  1. Parses the legacy request.
//  2. Wraps `prompt` in a single user chat message.
//  3. Forwards through the same SDK passthrough used by chat completions.
//  4. Translates each response chunk back into the `text_completion` envelope
//     (choices[].text instead of choices[].message.content / delta.content).
//
// Tools, response_format, and other chat-only features are deliberately not
// surfaced — they have no analogue in the legacy API.
func (g *Gateway) handleCompletions(w http.ResponseWriter, r *http.Request) {
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

	var legacy legacyCompletionRequest
	if err := json.Unmarshal(body, &legacy); err != nil {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "invalid JSON: "+err.Error())
		return
	}
	if legacy.Model == "" {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "model field is required")
		return
	}

	prompts, err := legacy.flattenPrompts()
	if err != nil {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", err.Error())
		return
	}
	if len(prompts) == 0 {
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "prompt field is required")
		return
	}
	if len(prompts) > 1 {
		// Batched legacy prompts (n × prompt) would each need their own
		// completion. Implementing batching cleanly across streaming +
		// non-streaming is non-trivial and rarely needed today; reject up
		// front so callers know to send single-prompt requests.
		writeOpenAIError(w, http.StatusBadRequest, "invalid_request_error", "batched prompt arrays are not supported; send one prompt per request")
		return
	}

	chatReq := legacy.toChatRequest(prompts[0])

	sess, err := g.resolveSession(r.Context(), legacy.Model)
	if err != nil {
		g.log("completions session resolve error: %v", err)
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", err.Error())
		return
	}

	chatID := r.Header.Get("X-Chat-Id")
	convID := g.recordGatewaySession(chatID, "completions", sess)
	if g.store != nil && convID != "" {
		_ = g.store.SaveMessage(convID, "user", prompts[0])
	}

	if legacy.Stream {
		g.streamLegacyCompletion(w, r, sess, &chatReq, &legacy, convID)
	} else {
		g.nonStreamLegacyCompletion(w, r, sess, &chatReq, &legacy, convID)
	}
}

// legacyCompletionRequest captures the fields of the OpenAI v1 text completion
// request that we translate into a chat request. Unknown keys are accepted
// silently; chat-only fields (tools, response_format) are ignored.
type legacyCompletionRequest struct {
	Model            string          `json:"model"`
	Prompt           json.RawMessage `json:"prompt"`
	MaxTokens        int             `json:"max_tokens,omitempty"`
	Temperature      float32         `json:"temperature,omitempty"`
	TopP             float32         `json:"top_p,omitempty"`
	N                int             `json:"n,omitempty"`
	Stream           bool            `json:"stream,omitempty"`
	Stop             json.RawMessage `json:"stop,omitempty"`
	PresencePenalty  float32         `json:"presence_penalty,omitempty"`
	FrequencyPenalty float32         `json:"frequency_penalty,omitempty"`
	Seed             *int            `json:"seed,omitempty"`
	User             string          `json:"user,omitempty"`
}

// flattenPrompts normalises the OpenAI `prompt` field which may be a string,
// an array of strings, an array of integers (token IDs — not supported), or
// an array of arrays. Only the string variants are accepted.
func (l *legacyCompletionRequest) flattenPrompts() ([]string, error) {
	if len(l.Prompt) == 0 {
		return nil, nil
	}
	var single string
	if err := json.Unmarshal(l.Prompt, &single); err == nil {
		if single == "" {
			return nil, nil
		}
		return []string{single}, nil
	}
	var arr []string
	if err := json.Unmarshal(l.Prompt, &arr); err == nil {
		return arr, nil
	}
	return nil, fmt.Errorf("prompt must be a string or array of strings (token-id arrays are not supported)")
}

func (l *legacyCompletionRequest) toChatRequest(prompt string) sdk.ChatCompletionRequestExtra {
	var req sdk.ChatCompletionRequestExtra
	req.Model = l.Model
	req.Messages = []openai.ChatCompletionMessage{
		{Role: openai.ChatMessageRoleUser, Content: prompt},
	}
	req.MaxTokens = l.MaxTokens
	req.Temperature = l.Temperature
	req.TopP = l.TopP
	req.N = l.N
	req.Stream = l.Stream
	req.PresencePenalty = l.PresencePenalty
	req.FrequencyPenalty = l.FrequencyPenalty
	req.User = l.User
	if l.Seed != nil {
		seed := *l.Seed
		req.Seed = &seed
	}
	if len(l.Stop) > 0 {
		var stopOne string
		if err := json.Unmarshal(l.Stop, &stopOne); err == nil {
			req.Stop = []string{stopOne}
		} else {
			var stopMany []string
			if err := json.Unmarshal(l.Stop, &stopMany); err == nil {
				req.Stop = stopMany
			}
		}
	}
	return req
}

// chatStreamProbe extracts the fields we need from each upstream chat chunk to
// rebuild a legacy text_completion chunk.
type chatStreamProbe struct {
	ID      string `json:"id"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index        int    `json:"index"`
		FinishReason string `json:"finish_reason"`
		Delta        struct {
			Content string `json:"content"`
		} `json:"delta"`
	} `json:"choices"`
	Usage json.RawMessage `json:"usage"`
}

type chatNonStreamProbe struct {
	ID      string `json:"id"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index        int    `json:"index"`
		FinishReason string `json:"finish_reason"`
		Message      struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Usage json.RawMessage `json:"usage"`
}

// legacyCompletionChunk is the streaming wire shape (object: text_completion).
type legacyCompletionChunk struct {
	ID      string                  `json:"id"`
	Object  string                  `json:"object"`
	Created int64                   `json:"created"`
	Model   string                  `json:"model"`
	Choices []legacyCompletionChoice `json:"choices"`
	Usage   json.RawMessage         `json:"usage,omitempty"`
}

type legacyCompletionChoice struct {
	Text         string `json:"text"`
	Index        int    `json:"index"`
	Logprobs     any    `json:"logprobs"`
	FinishReason string `json:"finish_reason,omitempty"`
}

func (g *Gateway) streamLegacyCompletion(w http.ResponseWriter, r *http.Request, sess sessionResult, chatReq *sdk.ChatCompletionRequestExtra, legacy *legacyCompletionRequest, convID string) {
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

	requestID := fmt.Sprintf("cmpl-%d", time.Now().UnixNano())
	streamFailed := false
	var (
		assistantText strings.Builder
		finalFinish   string
		lastChunk     json.RawMessage
	)

	err := g.sdk.SendChatCompletion(r.Context(), sess.SessionID, chatReq, func(chunk json.RawMessage, isLast bool) error {
		if chunk == nil && isLast {
			_, _ = fmt.Fprint(w, "data: [DONE]\n\n")
			flusher.Flush()
			return nil
		}

		var probe chatStreamProbe
		if err := json.Unmarshal(chunk, &probe); err != nil {
			return nil
		}
		lastChunk = chunk

		legacyChunk := legacyCompletionChunk{
			ID:      firstNonEmpty(probe.ID, requestID),
			Object:  "text_completion",
			Created: nonZero(probe.Created, time.Now().Unix()),
			Model:   firstNonEmpty(probe.Model, legacy.Model),
			Usage:   probe.Usage,
		}
		legacyChunk.Choices = make([]legacyCompletionChoice, 0, len(probe.Choices))
		for _, c := range probe.Choices {
			if c.Delta.Content != "" {
				assistantText.WriteString(c.Delta.Content)
			}
			if c.FinishReason != "" {
				finalFinish = c.FinishReason
			}
			legacyChunk.Choices = append(legacyChunk.Choices, legacyCompletionChoice{
				Text:         c.Delta.Content,
				Index:        c.Index,
				FinishReason: c.FinishReason,
			})
		}

		out, err := json.Marshal(legacyChunk)
		if err != nil {
			return err
		}
		if _, werr := fmt.Fprintf(w, "data: %s\n\n", out); werr != nil {
			streamFailed = true
			return werr
		}
		flusher.Flush()
		return nil
	})

	if err != nil && !streamFailed {
		g.log("legacy completion stream error: %v", err)
		data, _ := json.Marshal(openAIErrorWithRequestID(w, "provider_error", err.Error()))
		_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
		_, _ = fmt.Fprint(w, "data: [DONE]\n\n")
		flusher.Flush()
	}

	g.persistLegacyCompletionResponse(convID, assistantText.String(), finalFinish, lastChunk)
}

func (g *Gateway) nonStreamLegacyCompletion(w http.ResponseWriter, r *http.Request, sess sessionResult, chatReq *sdk.ChatCompletionRequestExtra, legacy *legacyCompletionRequest, convID string) {
	var lastChunk json.RawMessage
	err := g.sdk.SendChatCompletion(r.Context(), sess.SessionID, chatReq, func(chunk json.RawMessage, isLast bool) error {
		if chunk != nil {
			lastChunk = chunk
		}
		return nil
	})
	if err != nil {
		g.log("legacy completion error: %v", err)
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", err.Error())
		return
	}
	if lastChunk == nil {
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", "empty response from provider")
		return
	}

	var probe chatNonStreamProbe
	if err := json.Unmarshal(lastChunk, &probe); err != nil {
		writeOpenAIError(w, http.StatusBadGateway, "provider_error", "could not translate provider response: "+err.Error())
		return
	}

	resp := legacyCompletionChunk{
		ID:      firstNonEmpty(probe.ID, fmt.Sprintf("cmpl-%d", time.Now().UnixNano())),
		Object:  "text_completion",
		Created: nonZero(probe.Created, time.Now().Unix()),
		Model:   firstNonEmpty(probe.Model, legacy.Model),
		Usage:   probe.Usage,
	}
	resp.Choices = make([]legacyCompletionChoice, 0, len(probe.Choices))
	var assistantText strings.Builder
	var finalFinish string
	for _, c := range probe.Choices {
		assistantText.WriteString(c.Message.Content)
		if c.FinishReason != "" {
			finalFinish = c.FinishReason
		}
		resp.Choices = append(resp.Choices, legacyCompletionChoice{
			Text:         c.Message.Content,
			Index:        c.Index,
			FinishReason: c.FinishReason,
		})
	}

	g.persistLegacyCompletionResponse(convID, assistantText.String(), finalFinish, lastChunk)
	writeJSON(w, http.StatusOK, resp)
}

// persistLegacyCompletionResponse stores the assistant turn for a /v1/completions
// call alongside the user prompt that was already saved before forwarding.
// Mirrors handleChatCompletions persistence so legacy completions show up in
// the same conversation history with the same level of detail (raw provider
// JSON kept in metadata for future debugging).
func (g *Gateway) persistLegacyCompletionResponse(convID, content, finishReason string, lastChunk json.RawMessage) {
	if g.store == nil || convID == "" {
		return
	}
	display := content
	if display == "" && finishReason != "" {
		// Reasoning models can exhaust max_tokens on internal thought before
		// emitting any text — leave a breadcrumb so the user can spot it in
		// the audit trail rather than seeing a blank assistant bubble.
		display = fmt.Sprintf("[no content; finish_reason=%s — try a non-thinking model or raise max_tokens]", finishReason)
	}
	meta := encodeAssistantMetadata(content, nil, finishReason, lastChunk)
	if meta == "" {
		_ = g.store.SaveMessage(convID, "assistant", display)
		return
	}
	_ = g.store.SaveMessageWithMetadata(convID, "assistant", display, meta)
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func nonZero(values ...int64) int64 {
	for _, v := range values {
		if v != 0 {
			return v
		}
	}
	return 0
}
