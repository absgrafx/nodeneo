package gateway

import (
	"encoding/json"
	"strings"
	"testing"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	openai "github.com/sashabaranov/go-openai"
)

func intPtr(i int) *int { return &i }

// TestMergeToolCallDeltas covers the streaming accumulation pattern OpenAI
// uses for tool calls: the first delta carries id+name, subsequent deltas
// append to function.arguments. Multiple parallel calls are tracked by Index.
func TestMergeToolCallDeltas(t *testing.T) {
	tests := []struct {
		name   string
		deltas [][]openai.ToolCall
		want   []openai.ToolCall
	}{
		{
			name: "single tool call assembled from fragments",
			deltas: [][]openai.ToolCall{
				{{Index: intPtr(0), ID: "call_1", Type: "function", Function: openai.FunctionCall{Name: "read_file", Arguments: ""}}},
				{{Index: intPtr(0), Function: openai.FunctionCall{Arguments: "{\"path"}}},
				{{Index: intPtr(0), Function: openai.FunctionCall{Arguments: "\":\"llms.txt\"}"}}},
			},
			want: []openai.ToolCall{
				{Index: intPtr(0), ID: "call_1", Type: "function", Function: openai.FunctionCall{Name: "read_file", Arguments: "{\"path\":\"llms.txt\"}"}},
			},
		},
		{
			name: "two parallel tool calls",
			deltas: [][]openai.ToolCall{
				{{Index: intPtr(0), ID: "call_a", Type: "function", Function: openai.FunctionCall{Name: "read_file"}}},
				{{Index: intPtr(1), ID: "call_b", Type: "function", Function: openai.FunctionCall{Name: "grep"}}},
				{{Index: intPtr(0), Function: openai.FunctionCall{Arguments: "{\"path\":\"a.txt\"}"}}},
				{{Index: intPtr(1), Function: openai.FunctionCall{Arguments: "{\"pattern\":\"foo\"}"}}},
			},
			want: []openai.ToolCall{
				{Index: intPtr(0), ID: "call_a", Type: "function", Function: openai.FunctionCall{Name: "read_file", Arguments: "{\"path\":\"a.txt\"}"}},
				{Index: intPtr(1), ID: "call_b", Type: "function", Function: openai.FunctionCall{Name: "grep", Arguments: "{\"pattern\":\"foo\"}"}},
			},
		},
		{
			name: "delta without index is appended",
			deltas: [][]openai.ToolCall{
				{{ID: "call_x", Type: "function", Function: openai.FunctionCall{Name: "no_index", Arguments: "{}"}}},
			},
			want: []openai.ToolCall{
				{ID: "call_x", Type: "function", Function: openai.FunctionCall{Name: "no_index", Arguments: "{}"}},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var acc []openai.ToolCall
			for _, batch := range tt.deltas {
				acc = mergeToolCallDeltas(acc, batch)
			}
			if len(acc) != len(tt.want) {
				t.Fatalf("len mismatch: got %d, want %d (%+v)", len(acc), len(tt.want), acc)
			}
			for i := range tt.want {
				if acc[i].ID != tt.want[i].ID {
					t.Errorf("[%d] ID: got %q, want %q", i, acc[i].ID, tt.want[i].ID)
				}
				if acc[i].Type != tt.want[i].Type {
					t.Errorf("[%d] Type: got %q, want %q", i, acc[i].Type, tt.want[i].Type)
				}
				if acc[i].Function.Name != tt.want[i].Function.Name {
					t.Errorf("[%d] Function.Name: got %q, want %q", i, acc[i].Function.Name, tt.want[i].Function.Name)
				}
				if acc[i].Function.Arguments != tt.want[i].Function.Arguments {
					t.Errorf("[%d] Function.Arguments: got %q, want %q", i, acc[i].Function.Arguments, tt.want[i].Function.Arguments)
				}
			}
		})
	}
}

// TestStreamingDeltaProbe asserts our minimal probe correctly surfaces tool
// calls and finish_reason from a verbatim provider chunk so persistence works.
func TestStreamingDeltaProbe(t *testing.T) {
	chunk := []byte(`{
		"id":"chatcmpl-x",
		"object":"chat.completion.chunk",
		"choices":[{
			"index":0,
			"delta":{
				"role":"assistant",
				"content":null,
				"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"llms.txt\"}"}}]
			},
			"finish_reason":"tool_calls"
		}]
	}`)

	var probe streamingDeltaProbe
	if err := json.Unmarshal(chunk, &probe); err != nil {
		t.Fatalf("unmarshal probe: %v", err)
	}
	if len(probe.Choices) != 1 {
		t.Fatalf("expected 1 choice, got %d", len(probe.Choices))
	}
	c := probe.Choices[0]
	if c.FinishReason != "tool_calls" {
		t.Errorf("finish_reason: got %q, want tool_calls", c.FinishReason)
	}
	if len(c.Delta.ToolCalls) != 1 {
		t.Fatalf("expected 1 tool call, got %d", len(c.Delta.ToolCalls))
	}
	tc := c.Delta.ToolCalls[0]
	if tc.Function.Name != "read_file" {
		t.Errorf("tool name: got %q", tc.Function.Name)
	}
	if !strings.Contains(tc.Function.Arguments, "llms.txt") {
		t.Errorf("tool args missing path: %q", tc.Function.Arguments)
	}
}

// TestFlattenMessageContent makes sure vision (MultiContent) requests round-trip
// safely: text parts are concatenated for the searchable column, images become
// placeholders, and pure-text messages pass through unchanged.
func TestFlattenMessageContent(t *testing.T) {
	t.Run("plain text", func(t *testing.T) {
		text, hasParts := flattenMessageContent(openai.ChatCompletionMessage{
			Role:    "user",
			Content: "hello",
		})
		if hasParts {
			t.Error("hasParts should be false for plain content")
		}
		if text != "hello" {
			t.Errorf("got %q", text)
		}
	})
	t.Run("multi content with image", func(t *testing.T) {
		text, hasParts := flattenMessageContent(openai.ChatCompletionMessage{
			Role: "user",
			MultiContent: []openai.ChatMessagePart{
				{Type: openai.ChatMessagePartTypeText, Text: "What's in this screenshot?"},
				{Type: openai.ChatMessagePartTypeImageURL, ImageURL: &openai.ChatMessageImageURL{URL: "data:image/png;base64,iVBOR..."}},
			},
		})
		if !hasParts {
			t.Error("hasParts should be true for MultiContent")
		}
		if !strings.Contains(text, "What's in this screenshot?") {
			t.Errorf("text part lost: %q", text)
		}
		if !strings.Contains(text, "[image]") {
			t.Errorf("image placeholder missing: %q", text)
		}
	})
}

// TestEncodeAssistantMetadata checks the metadata sidecar JSON shape stored in
// the messages.metadata column for assistant turns that include tool_calls.
func TestEncodeAssistantMetadata(t *testing.T) {
	tc := openai.ToolCall{
		Index:    intPtr(0),
		ID:       "call_1",
		Type:     "function",
		Function: openai.FunctionCall{Name: "read_file", Arguments: `{"path":"llms.txt"}`},
	}
	meta := encodeAssistantMetadata("", []openai.ToolCall{tc}, "tool_calls", json.RawMessage(`{"id":"chatcmpl-x"}`))

	var got struct {
		Source           string            `json:"source"`
		Content          string            `json:"content"`
		ToolCalls        []openai.ToolCall `json:"tool_calls"`
		FinishReason     string            `json:"finish_reason"`
		ProviderResponse json.RawMessage   `json:"provider_response"`
	}
	if err := json.Unmarshal([]byte(meta), &got); err != nil {
		t.Fatalf("metadata is not valid JSON: %v\n%s", err, meta)
	}
	if got.Source != "api" {
		t.Errorf("source: got %q", got.Source)
	}
	if got.FinishReason != "tool_calls" {
		t.Errorf("finish_reason: got %q", got.FinishReason)
	}
	if len(got.ToolCalls) != 1 || got.ToolCalls[0].Function.Name != "read_file" {
		t.Errorf("tool_calls round-trip failed: %+v", got.ToolCalls)
	}
	if !strings.Contains(string(got.ProviderResponse), "chatcmpl-x") {
		t.Errorf("provider_response chunk lost: %s", got.ProviderResponse)
	}
}

// TestSummarizeToolCalls verifies the searchable-column fallback used when an
// assistant turn has no textual content (pure tool-call response).
func TestSummarizeToolCalls(t *testing.T) {
	got := summarizeToolCalls([]openai.ToolCall{
		{Function: openai.FunctionCall{Name: "read_file"}},
		{Function: openai.FunctionCall{Name: "grep"}},
	})
	if !strings.Contains(got, "read_file") || !strings.Contains(got, "grep") {
		t.Errorf("expected names in summary, got %q", got)
	}
	if got := summarizeToolCalls(nil); got != "" {
		t.Errorf("expected empty summary for nil, got %q", got)
	}
}

// TestOpenAIErrorEnvelope verifies the wire shape clients (Zed, Cursor,
// LangChain) expect: { "error": { "message", "type", ... } }.
func TestOpenAIErrorEnvelope(t *testing.T) {
	body := openAIError("invalid_request_error", "model field is required")
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	var parsed map[string]map[string]string
	if err := json.Unmarshal(b, &parsed); err != nil {
		t.Fatalf("envelope must be { error: { … } }: %v", err)
	}
	if parsed["error"]["message"] != "model field is required" {
		t.Errorf("message: got %q", parsed["error"]["message"])
	}
	if parsed["error"]["type"] != "invalid_request_error" {
		t.Errorf("type: got %q", parsed["error"]["type"])
	}
}

// TestParseChatRequestPreservesUnknownFields makes sure the gateway's JSON
// parsing does not silently drop fields like response_format,
// reasoning_effort, or stream_options.include_usage that downstream providers
// care about. This exercises the same OpenAICompletionRequestExtra path the
// gateway handler uses, which embeds openai.ChatCompletionRequest plus an
// Extra map for unknown keys.
func TestParseChatRequestPreservesUnknownFields(t *testing.T) {
	raw := []byte(`{
		"model":"glm-5.1",
		"messages":[{"role":"user","content":"hi"}],
		"stream":true,
		"stream_options":{"include_usage":true},
		"tools":[{"type":"function","function":{"name":"read_file","parameters":{"type":"object"}}}],
		"tool_choice":"auto",
		"parallel_tool_calls":false,
		"response_format":{"type":"json_object"},
		"reasoning_effort":"medium"
	}`)

	var req sdk.ChatCompletionRequestExtra
	if err := json.Unmarshal(raw, &req); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	roundTripped, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	for _, marker := range []string{
		`"tools"`,
		`"tool_choice":"auto"`,
		`"parallel_tool_calls":false`,
		`"response_format"`,
		`"stream_options"`,
		`"reasoning_effort":"medium"`,
	} {
		if !strings.Contains(string(roundTripped), marker) {
			t.Errorf("field dropped during parse/marshal: missing %s\n%s", marker, roundTripped)
		}
	}
}
