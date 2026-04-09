# Feature Backlog

Items to build once the core session/wallet/signing fundamentals are solid.

---

## Remaining Backlog & Bugs (priority order)

### 1. Wallet-Scoped Database & App Reset

**Priority:** Medium-High (data integrity)

#### Problem
The local SQLite chat database is encrypted with the wallet's private key. If a user erases their wallet and recovers a *different* wallet, the old database is inaccessible but still on disk — leaking storage and potentially confusing the app. If they recover the *same* wallet, they should regain access to their conversations.

#### Requirements
- On wallet erase: prompt whether to also delete the local chat DB, logs, and cached data
- On wallet recovery: detect if an existing DB matches the recovered key and reconnect to it
- Support multiple wallet-scoped databases (one per private key), so switching wallets doesn't destroy another wallet's data
- **"Complete App Reset"** option in Wallet settings: erase wallet/keychain, database, logs, and all cached content — full factory reset with clear warning
- Consider naming/keying databases by a deterministic wallet fingerprint (e.g. first 8 chars of address) so they can coexist

#### Open Questions
- Is the DB actually encrypted with the private key today, or just stored alongside it?
- Should we offer an "export conversations" option before reset?

---

### 2. Invitation Code / Faucet Integration

**Priority:** High (onboarding)

#### Problem
New users need MOR (5) and ETH (0.001) on Base to do anything. Currently the "Fund Your Wallet" screen is a dead end unless the user already has crypto.

#### Requirements
- On the wallet funding screen (after wallet init, before main app), add an **"Invitation Code"** button
- Modal/screen with two paths:
  1. **Have a code:** Enter the one-time-use code → tap "Go" → API call to faucet with `{ code, walletAddress }` → faucet disburses 5 MOR + 0.001 ETH → poll/confirm balances → dismiss overlay
  2. **Need a code:** Enter email → tap "Request Code" → with consent checkbox ("I agree to receive communications from mor.org") → POST email to mor.org endpoint → confirmation message ("Check your email for an invitation code")
- Faucet partner provides the API endpoint and code generation — we just consume it
- Codes are one-time use; the faucet validates and rejects duplicates
- Success: auto-refresh balances and proceed to main app
- Error: show clear message (invalid code, already used, faucet depleted, network error)

#### API Contract (to confirm with partner)
```
POST /api/faucet/redeem
{
  "code": "ABC123",
  "wallet_address": "0x..."
}
Response: { "success": true, "tx_hash_mor": "0x...", "tx_hash_eth": "0x..." }
```

```
POST /api/faucet/request-code
{
  "email": "user@example.com",
  "consent_marketing": true
}
Response: { "success": true }
```

---

### 3. File Attachments for Chat Context

**Priority:** Medium (usability)

#### Problem
Users can't attach files (documents, code, images, etc.) to provide context for a conversation. Everything must be typed or pasted into the prompt.

#### Requirements
- Attach one or more files to a chat conversation via a clip/attach icon near the prompt bar
- Attachments are **per-conversation** (stored in SQLite alongside the chat record), not per-session — they survive session close/reopen
- Supported file types (initial): `.txt`, `.md`, `.json`, `.csv`, `.pdf`, `.py`, `.js`, `.ts`, `.go`, `.dart`, `.log`, images (`.png`, `.jpg`, `.gif`)
- File contents are included as context in the prompt sent to the provider (prepended or as a system message, depending on size)
- Show attached files as chips/tags below the prompt bar with remove (×) option
- Size limits: individual file cap (e.g. 100KB text, 1MB images), total conversation context budget
- Drag-and-drop support on desktop platforms

#### Open Questions
- How does the Morpheus provider protocol handle large context? Is there a token limit per prompt?
- Should attached images be sent as base64 inline (multimodal models) or just described as text?
- Should we support attaching URLs (fetch and include page content)?
- Storage: store file contents in SQLite blob, or save to app support directory with a reference?

---

### 4. Rich Media Rendering (Images, Video from LLMs)

**Priority:** Medium (future models)

#### Problem
When multimodal/generative models become available on the Morpheus network, the app needs to render image and video outputs — not just text.

#### Requirements
- Detect when an LLM response contains image data (base64 inline, URL, or binary)
- Render images inline in the chat bubble (with tap-to-expand/fullscreen)
- Support common formats: PNG, JPEG, GIF, WebP, SVG
- Video rendering: support MP4/WebM playback inline or in a modal player
- Save/export generated media to local filesystem (share sheet on mobile)
- Loading states for media generation (progress indicator while model generates)
- Markdown image syntax (`![alt](url)`) should render as actual images

#### Open Questions
- Which Morpheus models will support image/video generation? Timeline?
- What's the response format — base64 in JSON, presigned URL, streaming binary?
- Should we support streaming image generation (progressive rendering)?
- Cache policy for generated media (keep in conversation DB, or ephemeral)?
- Accessibility: alt text for generated images

---

### 5. Platform Expansion

**Priority:** High (reach / distribution)

#### Roadmap (in order)

| # | Platform | Status | Notes |
|---|----------|--------|-------|
| 1 | **macOS** (desktop) | Done — refining | Signed, notarized, DMG distribution via GitHub Releases |
| 2 | **iOS — iPhone** | Planned | Touch-first layout; most UI already uses finger-friendly patterns. Go dylib → xcframework. Needs App Store provisioning. |
| 3 | **iOS — iPad** | Planned | Adaptive layout (split-view chat + sidebar). Leverage iPad multitasking APIs. |
| 4 | **App Store publishing** | Planned | First-time submission. Requires App Store Connect setup, review guidelines compliance, privacy nutrition labels, and in-app purchase considerations (if any). |
| 5 | **Linux** | Planned | Flutter Linux desktop runner. CI cross-compile for x86_64 (AppImage or .deb). Go CGO cross-compile or pre-built .so. |
| 6 | **Windows** | Maybe | Flutter Windows runner. MSIX or Inno Setup installer. Lowest priority — evaluate demand. |

#### Key Technical Considerations

**iOS (iPhone + iPad)**
- Go SDK needs to be compiled as an xcframework (arm64) instead of a dylib
- Keychain entitlements are already registered (`com.absgrafx.nodeneo`)
- UI is mostly Flutter — should adapt well, but needs review for safe area insets, notch/dynamic island, and smaller screens
- App Transport Security (ATS) — all HTTP calls must be HTTPS or have exceptions declared
- Background execution limits — sessions/blockchain polling may need background modes or push notifications
- App Store review: crypto wallet + blockchain interaction will likely trigger extra review scrutiny; prepare clear descriptions of what the app does and doesn't do (not an exchange, not custodial, etc.)

**App Store Publishing Checklist**
- [ ] App Store Connect account linked to Apple Developer Program
- [ ] App ID already registered (`com.absgrafx.nodeneo`)
- [ ] Privacy policy URL required
- [ ] App privacy "nutrition labels" (data collection declarations)
- [ ] Screenshots for all required device sizes
- [ ] Review notes explaining blockchain/crypto functionality
- [ ] TestFlight beta distribution first
- [ ] Consider age rating implications

**Linux**
- No Keychain equivalent — need `libsecret` or file-based encrypted storage
- No notarization; distribution via AppImage, Snap, Flatpak, or .deb
- Go CGO cross-compilation (or build in CI on a Linux runner)
- Desktop integration: .desktop file, icon registration

**Windows**
- Credential Manager for secure storage (or Windows DPAPI)
- Code signing with an EV certificate for SmartScreen trust
- MSIX (Microsoft Store) or Inno Setup / WiX (standalone installer)
- Go CGO builds fine on Windows; needs MinGW or MSVC toolchain in CI

#### Open Questions
- What's the minimum iOS version to target? (iOS 16+ covers ~95% of active devices)
- Should iPad support Split View / Slide Over from day one?
- Is the plan to distribute macOS via App Store too, or keep GitHub Releases only?
- For Linux, which distros to officially support? Ubuntu LTS + Fedora covers most users.
- Any interest in Android? Flutter supports it natively, but Go cross-compilation to ARM Android is more involved.

---

### 6. API Gateway — Next Iteration (v0.2+)

**Priority:** Medium (ecosystem)

#### API Key Enhancements
- **Permission tiers**: Chat (inference only) / Read (+ models, sessions, balances) / Admin (full access)
- **Key expiry**: never, 24h, 7d, 30d, custom
- **Rate limiting** per key (configurable)
- **Spending limits** per key (MOR budget cap)
- Show client IP on last-used

#### MCP Server Expansion
- **More tools**: `session_status`, `open_session`, `close_session`, `wallet_balance`
- **Resources**: `models://list`, `wallet://balance`, `sessions://active`
- **Streaming support**: Investigate MCP streaming for long responses
- **MCP SSE transport**: For remote/network MCP clients (not just stdio)
- **Auto-start**: Launch MCP server alongside the gateway from the NodeNeo UI
- **Dynamic config**: Generate `.cursor/mcp.json` from the UI with the correct port/key

#### Service Discovery / "Bot Primer"
- `/.well-known/ai-plugin.json` (OpenAI plugin format) — node name, auth method, API spec URL
- `/.well-known/mcp.json` — for MCP-aware agents to discover the node
- Swagger at existing `/swagger/index.html`
- Human-readable "Getting Started" page at root — "Here's how to connect a bot to this node"

#### Network Exposure
- **mDNS/Bonjour** announcement so the node is discoverable on LAN without knowing the IP
- **HTTPS** for non-localhost (self-signed cert or Let's Encrypt)
- Firewall guidance in the UI

#### Broader Ecosystem Integration
- **OpenClaw** — Determine integration protocol and wire up
- **Continue.dev** — Works out of the box with the OpenAI-compatible endpoint (direct connection, no SSRF issue)
- **LangChain / LlamaIndex** — Works via OpenAI-compatible endpoint
- **Claude Desktop** — MCP server can be configured for Claude Desktop too

#### Security Considerations
- API keys should be long, random, and never logged in plaintext
- Rate limiting per key (configurable)
- Keys scoped to permission tier — never escalate
- Admin keys should require biometric/PIN confirmation to create
- Consider IP allowlist per key (optional)
- All API traffic should be HTTPS when exposed beyond localhost (self-signed cert or Let's Encrypt)

#### Open Questions
- Should we support OAuth2 flows for more sophisticated integrations, or is API key sufficient for v1?
- Do we want to support multiple concurrent users (each with their own key) sharing one node, or is it always single-user?
- How does the MOR spending work when an external client opens sessions through the node? The node owner's wallet pays — should there be spending limits per key?
- What does the OpenClaw integration specifically need? Get their API/protocol docs.
- Should the "bot primer" page be customizable (node name, description, available models)?
- Should the MCP server be bundled inside the Go binary (Go MCP implementation) instead of a separate TypeScript process?

---

### Bug Fixes / Technical Debt

#### BUG: SDK log level not syncing with UI setting
**Severity:** Medium
- When the user changes log level to Debug in Version & Logs, the Flutter wrapper switches but the Go SDK's zap logger stays at INFO
- After an SDK restart (app relaunch), the log level resets to INFO regardless of the saved preference
- **Fix needed:** `setLogLevel` must propagate to the Go SDK's zap logger atomically, and the saved preference must be applied during SDK initialization (before first log line)

#### BUG: Empty provider responses shown as "(empty response)"
**Severity:** Medium
- When a provider returns 200 with empty content, the chat shows a blank bubble with "(empty response)" — no retry option, no explanation
- **Fix needed:** Detect empty responses and show "No response received — the provider may be busy. Tap to retry." with a retry action button, consistent with other error bubble patterns

#### Enhancement: HTTP request/response logging for inference calls
**Severity:** Low-Medium (debugging)
- At DEBUG level, the SDK logs session cache lookups and semaphore acquisition, but NOT the actual HTTP request to the provider or the response status/body
- The inference HTTP exchange goes through the proxy-router's internal client which doesn't surface in the MOBILE logger
- **Fix needed:** In the SDK's `sendPrompt`/`sendPromptWithStream` path, log the outbound request URL, headers (sanitized), response status code, content length, and first N bytes of response body at DEBUG level. Log empty responses at WARN level.

---

## Completed Features

### ~~3. Chat Tuning Parameters~~ — DONE (April 2026)

Implemented in `feat/local-api-gateway` branch.

- **Tuning drawer**: Slide-up drawer from tune icon in chat screen with sliders for Temperature, Top P, Max Tokens, Frequency Penalty, Presence Penalty
- **Streaming toggle**: Lives inside the tuning drawer, on by default
- **Per-conversation persistence**: Tuning params saved in SQLite (`conversations.tuning` column), loaded on conversation resume
- **Default tuning**: `DefaultTuningStore` (file-based) persists user-set defaults for new conversations. "Save as default" button in drawer. "Reset to defaults" returns to factory baseline.
- **Tooltips**: Each parameter has a hoverable info icon with a brief explanation
- **SDK support**: `ChatParams` struct in `proxy-router/mobile/sdk.go`, forwarded through `SendPromptWithMessagesAndParams`

### ~~4. Raw Inference Response Viewer~~ — DONE (April 2026)

Implemented in `feat/local-api-gateway` branch.

- **Response Info button**: `{ }` icon on each assistant bubble opens a bottom sheet
- **Full raw provider JSON**: SDK returns `json.RawMessage` of the last chunk's `Data()` — the complete, unfiltered provider response (usage, choices, model, system_fingerprint, created, consumer/provider usage breakdowns, etc.)
- **Summary rows**: Latency, prompt/completion/total tokens, finish reason, model, created timestamp extracted automatically from the `provider_response` blob
- **Copyable**: Full JSON copy button in the sheet
- **Backward compatible**: UI gracefully handles older metadata stored before the `provider_response` field existed

### ~~5. API Gateway Mode (v0.1)~~ — DONE (April 2026)

Implemented in `feat/local-api-gateway` branch. See the detailed "What's Built" section below.

### ~~Streaming UI~~ — DONE (April 2026)

Implemented in `feat/local-api-gateway` branch.

- **Async FFI bridge**: Go goroutines + Dart `NativeCallable.listener` + `Completer` for non-blocking UI during streaming
- **Signal + fetch pattern**: Solved FFI use-after-free — Go stores delta strings in a thread-safe map, passes `int64` IDs to Dart, Dart synchronously fetches via `ReadStreamDelta` FFI export
- **UI throttling**: ~30fps cap during streaming with `jumpTo` scrolling (no animation bounce)
- **In-place bubble update**: Streaming assistant bubble updated in place (`_messages[idx] = ...`) instead of remove/add
- **Mutex narrowing**: `mu.Lock()` scope in Go mobile API narrowed so streaming doesn't block concurrent operations (fixes "no streaming on resume")
- **Session setup UX**: Single animated status line during bootstrap (replaces verbose log list), descriptive messages without step counters, persistent "ready" banner with TEE shield icon until first prompt

---

## API Gateway — What's Built (v0.1 — April 2026)

### Go Gateway (`nodeneo/go/internal/gateway/`)
- **`POST /v1/chat/completions`** — OpenAI-compatible chat endpoint with streaming (SSE) and non-streaming support
- **`GET /v1/models`** — Fetches models directly from `active.mor.org/active_models.json` with 5-minute in-memory cache, ETag support, and SDK fallback. Response includes Morpheus-specific fields (`blockchainID`, `tags`, `modelType`) alongside standard OpenAI fields
- **`GET /health`** — Health check (unauthenticated)
- **Bearer token auth** — `sk-` prefixed API keys, bcrypt-hashed in SQLite, with `last_used` tracking
- **Session management** — Automatic model name → blockchain ID resolution, session reuse (scans unclosed sessions), and transparent session opening
- **Conversation persistence** — API-initiated conversations saved to SQLite with `source: "api"`, visible in the NodeNeo UI with a robot icon
- **Request logging** — Middleware logs all inbound requests for debugging
- **CORS** — Permissive headers for local/LAN use
- **Configurable port** — Independent from the Expert Mode API/Swagger port, configurable via UI

### Flutter UI (Expert Mode)
- **Gateway section** — Start/stop toggle, configurable port, connection info card
- **API key management** — Generate, list (with last-used timestamps), revoke keys
- **Conversation list** — API-source conversations marked with `smart_toy` icon

### MCP Server (`nodeneo/mcp-server/`)
- **TypeScript stdio server** using `@modelcontextprotocol/sdk`
- **`morpheus_models` tool** — Lists available Morpheus models via the gateway
- **`morpheus_chat` tool** — Sends chat prompts to any Morpheus model, supports multi-turn messages
- **Fully local** — Communicates with gateway on localhost via stdio, no traffic leaves the machine
- **Cursor integration** — Configured via `.cursor/mcp.json`, auto-discovered by Cursor

### Key Learnings
- **Cursor's "Override OpenAI Base URL" proxies through their servers** — SSRF protection blocks `127.0.0.1`. The OpenAI-compatible endpoint works for non-Cursor clients (LangChain, curl, custom apps) but Cursor requires MCP for local/private use.
- **MCP is the right pattern for IDE integration** — Tools run as local processes, prompts never leave the machine. This aligns with the privacy goals of Morpheus.
- **Cloudflared tunnel validated the pipeline** — End-to-end test confirmed the full flow works: Cursor → gateway → SDK → Morpheus provider → response rendered in Cursor.

---

## Cursor & OpenAI-Compatible Integration — Trust Model (Research / Unlikely Feature)

**Priority:** Documentation-first (may never ship as product)

### Context
We explored using Cursor's **custom OpenAI base URL** + API key with the NodeNeo gateway, and using **Cloudflare Tunnel (`cloudflared`)** so Cursor's infrastructure can reach a **public HTTPS** endpoint (Cursor often **cannot** call `localhost` / private IPs directly due to SSRF protections).

### Why "hairpin" matters for privacy
When Cursor's **Composer / custom API** path is used, requests are typically **assembled and sent via Cursor's backend** to the configured base URL. That means:

- **Cursor is in the trust path** for whatever they put in the outbound HTTP request: messages, model name, parameters, and usually **extra product context** (system prompts, tool definitions, codebase snippets they attach, etc.).
- **TLS on the wire** protects against **third parties** (network eavesdroppers). It does **not** mean prompts are **hidden from Cursor** if their servers **terminate, log, or forward** that plaintext — they have the **capability** to process that content under their product architecture and policies.
- **Implication for a strict privacy model:** if the bar is *"no intermediary may even have the capability to intercept or inspect traffic,"* then **any** path where a third-party service constructs or relays the full request **fails that bar**. Capability alone (even if unused) is enough to undermine the mental model some users want.

### What still "physically" helps (without overstating)
- **TLS**: confidentiality and integrity **on the network** against outsiders.
- **Cloudflare Tunnel**: encrypted tunnel from the user's machine to Cloudflare; **HTTPS** on the public hostname — solid **transport** to the gateway.
- **Gateway API keys**: protect the **public URL** from anonymous abuse if the URL leaks; they do **not** hide request bodies from Cursor if Cursor is the client.

### MCP vs custom base URL (nodeneo-morpheus MCP)
The **MCP server** talks to the gateway via **`fetch` to localhost** (or configured URL) from a **local process**. That avoids putting the **HTTP hop to the gateway** through Cursor's cloud — different trust boundary than Composer's custom API override. Tradeoff: **not** the same UX as picking a model in the chat dropdown.

### Optional built-in `cloudflared` quick tunnel (probably skip)
**Idea:** start a **quick tunnel** (`*.trycloudflare.com`) automatically when the gateway starts, print the HTTPS URL for Cursor.

**Why it's on the backlog but doubtful:**
- It's **convenient** for reachability and **TLS to the gateway**.
- It does **not** restore **confidentiality from Cursor** on the hairpin path; it only fixes "Cursor can't reach `127.0.0.1`."
- Quick tunnel URLs are **secret-by-obscurity**; treat like sensitive links; rotate API keys if exposed.
- Shipping it might **imply** a privacy story we don't actually have for Cursor users — document honestly if we ever add it.

### Homework / future
- Re-read Cursor's **current** docs and forum threads on custom OpenAI base URL (behavior changes over time).
- If we document this for users: **one paragraph** on trust boundaries — **MCP localhost** vs **Composer + public tunnel** vs **pure local tools**.

---

*Last updated: 2026-04-09 (items 3, 4, 5 completed; streaming done; backlog reordered)*
