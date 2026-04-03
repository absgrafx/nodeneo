# Feature Backlog

Items to build once the core session/wallet/signing fundamentals are solid.

---

## 1. Wallet-Scoped Database & App Reset

**Priority:** Medium-High (data integrity)

### Problem
The local SQLite chat database is encrypted with the wallet's private key. If a user erases their wallet and recovers a *different* wallet, the old database is inaccessible but still on disk — leaking storage and potentially confusing the app. If they recover the *same* wallet, they should regain access to their conversations.

### Requirements
- On wallet erase: prompt whether to also delete the local chat DB, logs, and cached data
- On wallet recovery: detect if an existing DB matches the recovered key and reconnect to it
- Support multiple wallet-scoped databases (one per private key), so switching wallets doesn't destroy another wallet's data
- **"Complete App Reset"** option in Wallet settings: erase wallet/keychain, database, logs, and all cached content — full factory reset with clear warning
- Consider naming/keying databases by a deterministic wallet fingerprint (e.g. first 8 chars of address) so they can coexist

### Open Questions
- Is the DB actually encrypted with the private key today, or just stored alongside it?
- Should we offer an "export conversations" option before reset?

---

## 2. Invitation Code / Faucet Integration

**Priority:** High (onboarding)

### Problem
New users need MOR (5) and ETH (0.001) on Base to do anything. Currently the "Fund Your Wallet" screen is a dead end unless the user already has crypto.

### Requirements
- On the wallet funding screen (after wallet init, before main app), add an **"Invitation Code"** button
- Modal/screen with two paths:
  1. **Have a code:** Enter the one-time-use code → tap "Go" → API call to faucet with `{ code, walletAddress }` → faucet disburses 5 MOR + 0.001 ETH → poll/confirm balances → dismiss overlay
  2. **Need a code:** Enter email → tap "Request Code" → with consent checkbox ("I agree to receive communications from mor.org") → POST email to mor.org endpoint → confirmation message ("Check your email for an invitation code")
- Faucet partner provides the API endpoint and code generation — we just consume it
- Codes are one-time use; the faucet validates and rejects duplicates
- Success: auto-refresh balances and proceed to main app
- Error: show clear message (invalid code, already used, faucet depleted, network error)

### API Contract (to confirm with partner)
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

## 3. Chat Tuning Parameters (Temperature, etc.)

**Priority:** Medium (power users)

### Problem
Users can't adjust inference parameters like temperature, top-p, max tokens, etc. Every conversation uses provider defaults.

### Requirements
- Gate behind an **Expert Mode** toggle (existing Expert Mode screen)
- In the chat screen, below the prompt bar, add a subtle "tune" icon that opens a **slide-up drawer**
- Drawer contents (initial set — expand later):
  - **Temperature** (0.0–2.0, slider, default 1.0) — controls randomness
  - **Top-P** (0.0–1.0, slider, default 1.0) — nucleus sampling
  - **Max Tokens** (64–4096, stepper/slider, default: model max) — response length cap
  - **Frequency Penalty** (0.0–2.0, slider, default 0.0) — penalize repeated tokens
  - **Presence Penalty** (0.0–2.0, slider, default 0.0) — penalize already-used topics
- Parameters are **per-conversation** — saved in SQLite alongside the conversation record
- New conversations inherit the global defaults (which the user can set in Expert Mode)
- Parameters are passed through the prompt/inference API call to the provider

### Open Questions
- Which parameters does the Morpheus provider protocol actually support passing through?
- Do all providers honor these, or is it model-dependent?
- Should there be a "Reset to defaults" button in the drawer?

---

## 4. Raw Inference Response Viewer

**Priority:** Low-Medium (debugging / transparency)

### Problem
Users (especially developers and power users) can't see the full JSON response from the LLM — only the extracted text. Metadata like token counts, latency, model version, finish reason, etc. are invisible.

### Requirements
- On each assistant response bubble, add a small "{ }" or "Raw" icon/button (similar to existing copy button)
- Tapping opens a **bottom sheet or modal** showing the full JSON response, formatted and syntax-highlighted
- Include all metadata: `model`, `usage` (prompt_tokens, completion_tokens, total_tokens), `finish_reason`, `created`, latency, provider address, session ID
- Make it copyable (full JSON copy button)
- Gate behind Expert Mode toggle (hidden by default for normal users)

### Open Questions
- Is the full response JSON currently passed back from the Go SDK, or only the text?
- If not, need to update `sendPrompt` / `sendPromptWithStream` to return the raw response alongside the parsed text
- Consider a "Session Stats" summary at the top of the chat showing cumulative token usage

---

## 5. API Gateway Mode — Keys, Discovery, and External Access

**Priority:** High (network value / ecosystem integration)

### Vision
Node Neo running on a desktop becomes a **personal Morpheus gateway** — other machines, bots, and AI agents on the local network (or beyond) can use it to access the Morpheus network on the user's behalf. The node announces what it can do, how to authenticate, and what permissions are available.

### Standards Landscape

| Standard | Purpose | Node Neo Role |
|---|---|---|
| **OpenAI-compatible API** (`/v1/chat/completions`) | LLM inference — widest client compatibility | Expose this so LangChain, Continue.dev, OpenClaw, etc. can use the node with just a base URL + API key |
| **OpenAPI / Swagger** | Full REST API discovery | Already exists on the expert mode HTTP server — extend with auth |
| **MCP (Model Context Protocol)** | AI agent tool/resource discovery | Expose an MCP endpoint so AI agents (Cursor, Claude Desktop, etc.) can auto-discover the node's capabilities |

Recommendation: implement all three, layered. OpenAI-compat for inference, OpenAPI for full surface, MCP for agent discovery. API keys gate everything.

### Requirements

#### API Key Management
- Generate API keys from Expert Mode (or a dedicated "API Access" settings screen)
- Keys are stored securely (Keychain or encrypted in the app DB)
- Each key has a **permission tier**:
  - **Chat** — inference only (`/v1/chat/completions`, prompt endpoints)
  - **Read** — chat + read-only endpoints (models list, session info, balances)
  - **Admin** — full access (open/close sessions, wallet operations, settings)
- Keys can be **revoked** individually
- Keys have optional **expiry** (never, 24h, 7d, 30d, custom)
- Show active keys with last-used timestamp and client IP

#### Service Discovery / "Bot Primer"
- When Expert Mode API is running, serve a machine-readable descriptor at a well-known path:
  - `/.well-known/ai-plugin.json` (OpenAI plugin format) — describes the node, auth method, API spec URL
  - `/v1/models` — OpenAI-compatible model list (returns available Morpheus models)
  - `/.well-known/mcp.json` or MCP SSE endpoint — for MCP-aware agents
  - Swagger at existing `/swagger/index.html`
- The descriptor includes: node name, capabilities, supported models, auth requirements, endpoint URLs
- A human-readable "Getting Started" page at the root when accessed via browser (like the Swagger UI but simpler — "Here's how to connect a bot to this node")

#### OpenAI-Compatible Inference Endpoint
- `POST /v1/chat/completions` — accepts standard OpenAI request format
- Maps to Morpheus session open + prompt internally
- Handles session lifecycle transparently (reuse active session, open new if needed)
- Supports streaming (`stream: true` → SSE)
- Returns standard OpenAI response format (including `usage`, `model`, `finish_reason`)
- `Authorization: Bearer <api-key>` header for auth

#### Network Exposure
- Already have Local/Network toggle in Expert Mode
- When "Network" is selected, bind to `0.0.0.0` (already implemented)
- Consider mDNS/Bonjour announcement so the node is discoverable on the LAN without knowing the IP
- Firewall guidance in the UI ("Make sure port 8082 is accessible on your network")

### MCP Server Implementation
- Expose as an MCP server (SSE transport or stdio for local)
- **Tools**: `chat` (send prompt), `list_models`, `session_status`, `open_session`, `close_session`
- **Resources**: `models://list`, `wallet://balance`, `sessions://active`
- MCP clients connect, discover tools, and invoke them with the API key
- This is how an AI agent running on another machine would "learn" what your node can do

### Security Considerations
- API keys should be long, random, and never logged in plaintext
- Rate limiting per key (configurable)
- Keys scoped to permission tier — never escalate
- Admin keys should require biometric/PIN confirmation to create
- Consider IP allowlist per key (optional)
- All API traffic should be HTTPS when exposed beyond localhost (self-signed cert or Let's Encrypt)

### Open Questions
- Should we support OAuth2 flows for more sophisticated integrations, or is API key sufficient for v1?
- Do we want to support multiple concurrent users (each with their own key) sharing one node, or is it always single-user?
- How does the MOR spending work when an external client opens sessions through the node? The node owner's wallet pays — should there be spending limits per key?
- What does the OpenClaw integration specifically need? Get their API/protocol docs.
- Should the "bot primer" page be customizable (node name, description, available models)?

---

## 6. Platform Expansion

**Priority:** High (reach / distribution)

### Roadmap (in order)

| # | Platform | Status | Notes |
|---|----------|--------|-------|
| 1 | **macOS** (desktop) | Done — refining | Signed, notarized, DMG distribution via GitHub Releases |
| 2 | **iOS — iPhone** | Planned | Touch-first layout; most UI already uses finger-friendly patterns. Go dylib → xcframework. Needs App Store provisioning. |
| 3 | **iOS — iPad** | Planned | Adaptive layout (split-view chat + sidebar). Leverage iPad multitasking APIs. |
| 4 | **App Store publishing** | Planned | First-time submission. Requires App Store Connect setup, review guidelines compliance, privacy nutrition labels, and in-app purchase considerations (if any). |
| 5 | **Linux** | Planned | Flutter Linux desktop runner. CI cross-compile for x86_64 (AppImage or .deb). Go CGO cross-compile or pre-built .so. |
| 6 | **Windows** | Maybe | Flutter Windows runner. MSIX or Inno Setup installer. Lowest priority — evaluate demand. |

### Key Technical Considerations

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

### Open Questions
- What's the minimum iOS version to target? (iOS 16+ covers ~95% of active devices)
- Should iPad support Split View / Slide Over from day one?
- Is the plan to distribute macOS via App Store too, or keep GitHub Releases only?
- For Linux, which distros to officially support? Ubuntu LTS + Fedora covers most users.
- Any interest in Android? Flutter supports it natively, but Go cross-compilation to ARM Android is more involved.

---

*Last updated: 2026-04-03*
