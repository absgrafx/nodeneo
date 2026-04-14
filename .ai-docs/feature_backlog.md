# Feature Backlog

Remaining items to build, in priority order.

---

### 1. Invitation Code / Faucet Integration

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

### 2. File Attachments for Chat Context

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

### 3. Rich Media Rendering (Images, Video from LLMs)

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

### 4. Platform Expansion

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

### 5. AI Gateway — Next Iteration (v0.2+)

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

#### Open Questions
- Should we support OAuth2 flows for more sophisticated integrations, or is API key sufficient for v1?
- Do we want to support multiple concurrent users (each with their own key) sharing one node, or is it always single-user?
- How does the MOR spending work when an external client opens sessions through the node? The node owner's wallet pays — should there be spending limits per key?
- What does the OpenClaw integration specifically need? Get their API/protocol docs.
- Should the "bot primer" page be customizable (node name, description, available models)?
- Should the MCP server be bundled inside the Go binary (Go MCP implementation) instead of a separate TypeScript process?

---

*Last updated: 2026-04-14*
