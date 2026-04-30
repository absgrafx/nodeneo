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

### 2. App Lock UX: Biometrics-First, Auto-Prompt

**Priority:** High (mobile UX — first impression on every app launch)

#### Problem
The lock screen shows a password field and an "Use biometrics" button. On iOS with Face ID enabled, the user must manually tap the biometrics button — it doesn't auto-trigger. Additionally, biometrics requires setting a password first, which feels backwards on mobile where Face ID is the primary auth method.

#### Requirements
- **Auto-prompt biometrics on lock screen appear**: If biometrics are enabled, immediately trigger Face ID/Touch ID when the lock screen mounts (in `initState` or after first frame). No user tap required.
- **Biometrics-only mode**: Allow enabling biometrics without requiring a password. Face ID becomes the sole unlock method.
- **Password as optional fallback**: If the user wants both, password is the fallback when biometrics fail (e.g. "Face not recognized — enter password"). If biometrics-only, the fallback is the recovery phrase / factory reset path already in place.
- **Lock screen layout**: When biometrics are primary, de-emphasize the password field (show it only after a failed biometric attempt or via "Use password instead" link).
- **Settings flow**: Simplify: single toggle "Lock with Face ID" (or Touch ID). Optional "Also set a backup password" toggle underneath.

#### Open Questions
- Should we support PIN (4-6 digit) as a lighter alternative to full password?
- On desktop (macOS), should Touch ID on Magic Keyboard auto-trigger too?

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
| 1 | **macOS** (desktop) | **Shipping** | Signed, notarized, DMG distribution via GitHub Releases |
| 2 | **iOS — iPhone** | **Shipping** | Running on device + simulator. PlatformCaps gating, pull-to-refresh, collapsible wallet, TEE attestation, Sigstore cache fix, provider-endpoint redaction, pre-session confirmation — all done. TestFlight + App Store submission next. |
| 3 | **iOS — iPad** | Planned | Adaptive layout (split-view chat + sidebar). Leverage iPad multitasking APIs. |
| 4 | **App Store publishing** | In progress | First-time submission. App Store Connect setup, review guidelines compliance, privacy nutrition labels, and in-app purchase considerations. |
| 5 | **Android** | Planned | Flutter side builds; Go `gomobile` target exists in the Makefile. Needs UI polish pass, Keystore integration, and CI runner. |
| 6 | **Linux** | Planned | Flutter Linux desktop runner. CI cross-compile for x86_64 (AppImage or .deb). Go CGO cross-compile or pre-built .so. |
| 7 | **Windows** | Maybe | Flutter Windows runner. MSIX or Inno Setup installer. Lowest priority — evaluate demand. |

#### Key Technical Considerations

**iPad**
- Adaptive layout: leverage the `medium`/`expanded` form factors already defined in `lib/services/form_factor.dart` for split-view conversation lists + chat pane
- Slide Over / Split View support from day one
- Same Go static library as iPhone — no separate build needed

**App Store Publishing Checklist**
- [ ] App Store Connect account linked to Apple Developer Program
- [x] App ID registered (`com.absgrafx.nodeneo`)
- [ ] Privacy policy URL required
- [ ] App privacy "nutrition labels" (data collection declarations)
- [ ] Screenshots for all required device sizes
- [ ] Review notes explaining blockchain/crypto functionality
- [ ] TestFlight beta distribution first
- [ ] Consider age rating implications

**Android**
- Keystore integration via `flutter_secure_storage` (already used by macOS/iOS)
- `make go-android` target builds the `.aar` — needs wiring into Flutter plugin registration
- Tall form factors (foldables) — ensure `FormFactor` policy holds

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

---

### 6. AI Gateway — Next Iteration (v0.2+)

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

### 7. Automated Regression Testing

**Priority:** Medium (engineering velocity)

#### Problem
Manual regression testing across macOS, iOS (iPhone + iPad), and eventually Android/Linux/Windows is unsustainable. Each platform has unique behaviors (safe areas, clipboard, keyboard, permissions) that need repeated verification after every change.

#### Requirements
- **Widget tests** for critical UI flows: onboarding, chat send/receive, wallet display, settings navigation
- **Integration tests** (`flutter test integration_test/`) that run on simulator: full onboarding → import wallet → open chat → send prompt → verify response renders
- **Golden image tests** for layout regression on key screen sizes (iPhone SE, iPhone 16 Pro, iPad Pro)
- **CI pipeline** (GitHub Actions): run widget + integration tests on macOS runner with iOS simulator
- **Go SDK mock** for tests that don't need real blockchain/network (mock FFI responses)

#### Open Questions
- Which test framework? Flutter's built-in `flutter_test` + `integration_test`, or Patrol / Maestro for more natural mobile testing?
- Should we test against a local mock provider or the real Morpheus testnet?
- How to handle Keychain/secure storage in test environments?
- Screenshot comparison tooling for golden tests across platforms?

---

### 8. iOS Release Regression Checklist

**Priority:** High (pre-release gate for every iOS build)

- [x] Onboarding: create wallet, import PK, import mnemonic
- [x] Home screen: wallet card (collapse + expand), model list, pull-to-refresh
- [x] Chat: non-TEE model send/receive/stream
- [x] Chat: TEE model (sigstore cache fix verified on device)
- [x] Chat: thinking model — thinking zone + answer zone
- [x] Chat: stop/cancel generation
- [x] Chat: provider error messages redacted (no IP/host:port/URL leakage)
- [x] Pre-session confirmation modal (model, TEE badge, duration, MOR stake)
- [x] Wallet: Where's My MOR scan, active sessions, staked MOR visible on home card
- [x] Settings: Network (Blockchain Connection only; no API/Gateway on mobile)
- [x] Settings: Preferences, Backup & Reset (export/import `.nnbak`)
- [x] App lock: password, Face ID, factory reset (DELETE ALL)
- [x] Safe areas: notch, Dynamic Island, keyboard overlap
- [x] Release build: symbols exported (`-rdynamic`), no debug dylib issues
- [ ] Background/foreground: long-idle resume (>30 min) without session loss
- [ ] Airplane mode → offline toast, no crash
- [ ] Wallet switching: import second wallet, confirm DB isolation

---

*Last updated: 2026-04-30 (v3.2.0 ship)*

---

## Recently Shipped (for the short-term memory)

### v3.2.0 — 2026-04-30
- **Cursor/Zed-class AI Gateway** — full OpenAI Chat Completions parity: `tools`/`tool_choice`/`parallel_tool_calls`, `tool_calls` deltas, `reasoning_content`, `MultiContent`, `response_format`, `seed`, `logit_bias`, `stream_options.include_usage`
- **`/v1/embeddings` and `/v1/completions`** endpoints added; both persist `source="api"` conversation rows in the local DB so gateway activity shows up in the history
- **`/v1/models`** advertises `supports_tools` / `supports_vision` / `supports_reasoning` capability flags
- **Session duration follows preferences live** — `session_duration_seconds` re-read on every `OpenSession`, no gateway restart
- **Three-layer provider endpoint redaction** — SDK (`redactError`/`redactedError`), gateway error envelope, Flutter UI; patterns kept in lockstep
- **UX polish** — affordability "Show all" hides when no models filtered (with `(N hidden)` label when active); session reuse skips stake modal in favour of "Continue / Start Fresh"; gateway "Copy" emits bare URL; Preferences screen banner clarifies UI-only scope
- **Engineering** — `X-Request-Id` correlation, OpenAI error envelope on all error paths, raised `ReadTimeout`, `.cursor/rules/proxy-router-workflow.mdc` documents the no-fork SDK workflow
- **iOS build unaffected** — gateway gated by `PlatformCaps.supportsGateway = isDesktop`; symbols compile clean for `ios/arm64` and are dead code at runtime on mobile

### v3.1.0 — 2026-04-24
- Chat reliability patch: handle reasoning-only stream completions honestly so a `finish_reason: stop` with no `content` no longer surfaces as a false error in the chat UI ([#66](https://github.com/absgrafx/nodeneo/pull/66))

### v3.0.0 — 2026-04
- **Full TEE compliance with proxy-router v7.0.0** — upstream merge, TDX attestation with cosign-verified golden values, TLS-fingerprint-bound `reportdata`, per-provider quick-attestation cache, end-to-end verified on iPhone
- iOS Sigstore TUF cache fix (`sdk.SetSigstoreCacheDir(dataDir)`) — unblocks TEE models on iPhone
- Pre-session confirmation modal with live stake preview and duration presets
- In-place affordability (greyed models, no re-sort, `X of Y affordable` counter)
- Wallet card redesign (single-line address, right-aligned balances, full-width helpers)
- Provider endpoint redaction (`lib/utils/error_redaction.dart`)
- "Fund Your Wallet" overlay scoped — no more covering active chats
- Chain correction: "Arbitrum" → "Base" across UI + docs (chainID 8453)
- RPC failover: expanded `shouldRetryRPCError` in the fork for public-node rate limits
- Flutter upgrade to 3.41.7 (local + CI)

### v2.7.0 — 2026-04
- iOS (iPhone) first light: full flows on device + simulator, TestFlight track open
- Two-zone streaming for reasoning/thinking models (`reasoning_content` + `<think>` fallback)
- Stop/Cancel generation (amber stop button, full cancellation plumbing)
- MOR scanner: ABI decode fix, full session scan, isolate-backed
- Collapsible wallet card, slimmed privacy toggle, pull-to-refresh
- Factory reset uses "DELETE ALL" confirmation phrase
