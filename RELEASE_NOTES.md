## What's New in v3.2.0

### Cursor / Zed-Class AI Gateway
The local AI Gateway is now a drop-in OpenAI-compatible target for IDE agents and developer tools (Cursor, Zed, Continue.dev, Claude Desktop, LangChain). The full Chat Completions surface flows through verbatim:

- **Tool / function calling** — `tools`, `tool_choice`, `parallel_tool_calls` forwarded; `tool_calls` deltas, `finish_reason`, and assistant tool-call messages persisted unchanged
- **Reasoning models** — `reasoning_content` deltas relayed; `<think>` tag fallback preserved for vLLM/ollama
- **Multi-modal & control fields** — `MultiContent`, `response_format`, `seed`, `logit_bias`, `n`, and `stream_options.include_usage` honoured end-to-end
- **Verbatim passthrough** — `json.RawMessage` plumbing keeps unknown OpenAI fields intact across the SDK and gateway boundaries

### Embeddings & Legacy Completions Endpoints
Two new endpoints round out OpenAI compatibility:

- **`POST /v1/embeddings`** — forwards to a Morpheus embeddings model (e.g. `text-embedding-bge-m3`); response shape and usage metadata pass through unchanged
- **`POST /v1/completions`** — legacy text completion for tools that haven't moved to chat; streaming + non-streaming both supported

Both paths persist a conversation row in the local DB (titled `API · embeddings · {model}` / `API · completions · {model}`) so gateway-driven activity shows up in the conversation list alongside UI chats. Empty-content reasoning-model responses get a breadcrumb so `finish_reason: length` is visible to the operator.

### Model Capability Flags in `/v1/models`
The model list now advertises `supports_tools`, `supports_vision`, and `supports_reasoning` so client agents can match a model to a workflow without trial-and-error.

### Session Duration Follows Preferences
Sessions opened by the gateway now read the live `session_duration_seconds` preference on every `OpenSession` call — no gateway restart required. Set 10 minutes for cheap embeddings runs or 60 minutes for long coding sessions; the slider in Preferences applies immediately to both UI and gateway flows.

### Three-Layer Provider Endpoint Redaction
Provider IPs and host:port pairs are scrubbed before they leave the device, at every boundary:

- **SDK boundary** (`proxy-router/mobile/redact.go`) — wraps errors with `redactedError`, preserving `errors.Is` / `errors.As`
- **Gateway error envelope** (`go/internal/gateway/redact.go`) — sanitizes the OpenAI-style error JSON
- **Flutter UI** (`lib/utils/error_redaction.dart`) — defence-in-depth for chat error toasts

All three patterns are kept in lockstep so a curl `connection refused` and an in-app error look identical to the user.

### Gateway-Opened Sessions in Conversation List
Sessions started by the AI Gateway (Cursor, Zed, curl) now create `source="api"` rows in the local store with descriptive titles, `updated_at` timestamps that float them to the top of the history, and full message persistence. The store helpers `LatestEmptyConversationForModel` and `DeleteOtherEmptyConversationsForModel` filter on `source='ui'` so UI dedup logic can no longer hijack or delete API audit rows.

### UX Polish

- **Affordability filter** — the "Show all" toggle is hidden when no models are filtered out, and reads `Show all (N hidden)` when it has work to do, so users don't see a switch with no effect
- **Session reuse** — tapping a model with an active session skips the stake-confirmation modal and shows a lightweight "Active session — Continue / Start Fresh" sheet with `~N min left`
- **Copy URL** — the Expert screen's gateway "Copy" button now copies the bare base URL (e.g. `http://127.0.0.1:8083/v1`) instead of the labelled `Base URL: …` string
- **Preferences scope notice** — the Preferences screen now leads with an explicit banner: in-app system prompt and tuning apply to UI chats only; AI Gateway requests are governed by the calling agent (Cursor, Zed, etc.)

### Engineering

- **HTTP `ReadTimeout`** raised to accommodate slow upstream providers without 408ing tool-heavy IDE traffic
- **`X-Request-Id`** generated and echoed on every request for correlation with provider logs
- **OpenAI error envelope** standardised across all gateway error paths (`{ "error": { "type", "message", "code", "param" } }`)
- **iOS build verified clean** — gateway code compiles for `ios/arm64` but is gated by `PlatformCaps.supportsGateway = isDesktop`; mobile binaries ship with the symbols dead-coded, no behavioural impact
- **`.cursor/rules/proxy-router-workflow.mdc`** documents the cross-repo SDK workflow (PR `mobile/<feature>` branches to upstream `MorpheusAIs/Morpheus-Lumerin-Node` `dev`)

---

## Previous Releases

Full notes for each prior release are pinned to its tag page on GitHub.

| Version | Date | Headline |
|---------|------|----------|
| [v3.1.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.1.0) | 2026-04-24 | Chat reliability patch — reasoning-only stream completions no longer surface as a false error ([#66](https://github.com/absgrafx/nodeneo/pull/66)) |
| [v3.0.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.0.0) | 2026-04-24 | Full TEE compliance with proxy-router v7.0.0 on macOS + iPhone, pre-session confirmation flow, in-place affordability, wallet card redesign, provider-endpoint redaction, RPC failover, Flutter 3.41.7 |
| [v2.7.0](https://github.com/absgrafx/nodeneo/releases/tag/v2.7.0) | 2026-04 | iOS (iPhone) first light, two-zone thinking/reasoning model support, stop/cancel generation, MOR scanner fix, collapsible wallet card, factory reset via "DELETE ALL" |
| [Older](https://github.com/absgrafx/nodeneo/releases) | — | Full release archive |
