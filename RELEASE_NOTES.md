## What's New in v3.1.0

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
- **`.cursor/rules/proxy-router-workflow.mdc`** documents the cross-repo SDK workflow (no fork — PR to `MorpheusAIs/Morpheus-Lumerin-Node` `dev` from `mobile/<feature>` branches)

---

## What's New in v3.0.0

### Full TEE Compliance with proxy-router v7.0.0
**Node Neo is now a first-class v7.0.0 TEE client on both macOS and iPhone.** This is the headline change of the release — everything else is built on top of it.

- **Upstream merge:** the embedded `proxy-router/mobile` SDK is pinned to `absgrafx/Morpheus-Lumerin-Node` at the current `main` tip, which carries the full upstream `MorpheusAIs/Morpheus-Lumerin-Node` **v7.0.0** merge: redesigned TEE attestation pipeline, tightened session maintenance loop, new eth-client retry contract.
- **TDX attestation end-to-end on device:** CPU quote fetch → SecretAI portal cryptographic verification → RTMR3 compared against **cosign-verified golden values** for the fork's exact build version. No trust-on-first-use anywhere in the path.
- **TLS fingerprint anti-spoofing:** the attestation quote's `reportdata` is bound to the provider's live TLS certificate fingerprint. A man-in-the-middle can't reuse a valid quote against a different cert.
- **iOS Sigstore cache fix:** the last blocker for TEE on iPhone — `mkdir .sigstore: operation not permitted` — is gone. The Sigstore TUF cache now lives under the SDK's `dataDir` via `sdk.SetSigstoreCacheDir`, which the iOS sandbox allows.
- **Quick-attestation cache** per provider endpoint: once a provider is verified against golden values, subsequent sessions to the same `endpoint + version + TLS fingerprint` reconnect in sub-second. Cache survives app relaunch and invalidates automatically when the provider reports a new version.
- **Verified on Phlame** (iPhone, iOS 26.4.1): `gemma3-4b:tee`, `Mistral-Fake:TEE`, Arcee-Trinity thinking model — full attestation + session + streaming chat confirmed.

### Pre-Session Confirmation Flow
- Tapping a model now opens a **"Start chat?"** modal before any stake is posted: model name, MAX Privacy (TEE) badge, duration dropdown, and the exact MOR that will be staked for the chosen duration
- Duration presets surface the **live hourly stake** calibrated from the home list so the number in the modal matches the number on the tile (no more drift between list price and actual stake)
- Default session length is **10 minutes** (was 1 hour) — cheaper to try a model, easier to discard
- Cancel returns to the home screen with no chain interaction; confirm opens the chat with the chosen duration

### In-Place Model Affordability
- Unaffordable models are greyed out **in place** (no re-sorting). The list stays visually stable as balances update
- Header counter now reads `X of Y affordable` and respects the Privacy / Show All filters
- "Show All" reveals unaffordable models (still greyed); off by default, so only what you can actually chat with is shown
- Affordability refreshes on wallet balance change, session open/close, return from Send MOR, and a 60s idle tick

### Wallet Card Redesign
- Collapsed card: address on a single line, right-aligned MOR / ETH numbers with compact `(+staked)` suffix in purple that visually recedes below the liquid balances
- Expanded card: **"Where's My MOR?"** pill deep-links to the on-chain scanner with auto-scan, "Stake for inference" / "Pays on-chain gas" helper text now spans the full chip width, staked MOR shown in purple beneath the liquid balance
- Balance numbers use `FittedBox(scaleDown)` so 5-decimal values stay honest on narrow iPhone widths instead of ellipsizing
- Live RPC connectivity pill + "Send Max" button on the MOR send sheet

### Chain Correction: Base (not Arbitrum)
- Scrubbed every user-facing "Arbitrum" reference in UI strings, tooltips, and code comments to correctly read **Base**
- `chain_config.dart` default RPCs, chainID (8453), and Blockscout links verified

### Provider Endpoint Redaction
- New `lib/utils/error_redaction.dart` strips `http(s)://`, `host:port`, and bare IPv4 addresses from error messages before they hit the chat UI
- Users see a neutral `<provider endpoint>` placeholder; full detail still lands in the app log for debugging
- Protects provider infrastructure from being shouted on screen-share / bug reports

### "Fund Your Wallet" Overlay Scoped
- Overlay now appears **only** when both MOR and ETH are 0 — no more covering active chats or re-appearing after a successful top-up
- Continue Chatting strip sits above Privacy / Show All toggles with proper vertical padding

### RPC Failover Resilience
- Expanded the fork's `shouldRetryRPCError` to cover all common public-RPC rate-limit signals (JSON-RPC `-32005`, "usage limit", "rate limit exceeded", "over quota", "too many requests", "plan limit", etc.)
- Wallet balance fetch now preserves the last-known-good number on transient errors instead of flashing `0.00000`
- Result: public round-robin of 6 Base RPCs rides through per-node daily caps transparently; no more 45-second cold-start stall

### Flutter 3.41.7 Upgrade
- Local toolchain bumped from 3.41.5 → 3.41.7 after a debugger-attach edge case left iOS releases suspended on splash
- macOS CI Flutter version pinned to 3.41.7 to match

---

## What's New in v2.7.0

### iOS Support (iPhone)
- Node Neo now runs on iPhone — full onboarding, wallet, chat, and settings
- Go SDK compiled as static library for iOS (device + simulator)
- Platform-aware feature gating: Developer API and AI Gateway hidden on mobile (desktop-only features requiring persistent servers)
- Touch-optimized: pull-to-refresh, safe area handling, compact layouts
- App icon regenerated as full-bleed for clean iOS superellipse clipping
- Simulator workflow: `make run-ios-sim` for fast iteration without a physical device

### Thinking / Reasoning Model Support
- Two-zone streaming display: chain-of-thought reasoning renders in a purple "Thinking..." zone above the answer
- Live spinner during thinking with scrolling reasoning text
- Collapses to "Thought for Xs" after completion — tap to expand and review full reasoning
- Supports both `reasoning_content` field (Venice, DeepSeek, OpenAI o-series) and `<think>` tag fallback (vLLM, ollama)
- Reasoning tokens excluded from conversation history (per best practice — not fed back as context)

### Stop / Cancel Generation
- Send button transforms to amber stop icon during streaming
- Tap to cancel: partial response is kept with "Generation stopped" indicator
- Cancellation propagates through the full stack (Dart → FFI → Go → proxy-router context cancellation)

### MOR Scanner Fix
- Fixed off-by-one ABI decoding error in `getSession` — active session stakes were always showing 0
- Removed 20-session scan cap: all sessions now scanned in batches
- Scan runs on background isolate (non-blocking UI with spinner)
- Lazy scan on card expand instead of screen load
- Auto-scan when "Where's My MOR" card is expanded (no extra tap)

### Home Screen UX
- Collapsible wallet card: compact row with address + MOR/ETH balances (collapsed by default)
- Slimmed privacy toggle: single-line "Full Privacy Models" with TEE explainer link
- Pull-to-refresh on all platforms (replaces manual refresh button on mobile)
- Hidden overlay scrollbar for cleaner appearance

### Factory Reset Improvements
- Factory reset now uses "DELETE ALL" phrase confirmation instead of private key
- Works when private key is lost (the whole point of a factory reset)
- Consistent confirmation flow from both Settings and lock screen entry points

### Additional Fixes
- Backup export works on iOS (handles `bytes` parameter requirement)
- Lock screen recovery sheet defaults to Private Key tab (matches onboarding)
- Onboarding backup screen spacing tightened for small screens
- App bar tagline overflow handling
- Deployment target aligned to iOS 16.0 across all build configurations
- Info.plist: ATS local networking, export encryption compliance
