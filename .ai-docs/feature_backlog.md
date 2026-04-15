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
| 2 | **iOS — iPhone** | **In progress** | Running on device + simulator. PlatformCaps gating, pull-to-refresh, collapsible wallet, compact privacy toggle, safe area fixes done. Needs TestFlight + App Store submission. |
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

### 6. Thinking / Reasoning Model Support

**Priority:** High (correctness — currently broken for reasoning models)

#### Problem
When chatting with reasoning models (e.g. GLM-4.7, DeepSeek-R1, Qwen-3 Thinking), the model's internal chain-of-thought "thinking" tokens stream directly into the chat bubble alongside the final answer. The result is a scrambled wall of text where reasoning artifacts (hallucinated code snippets, self-dialogue, planning notes) are indistinguishable from the actual response. Observed with Venice `venice-glm-47` — the model's reasoning about Terraform/AWS config leaked into visible output.

#### Root Cause
The entire streaming pipeline — from proxy-router SDK through Go FFI to Flutter — only reads `choices[0].delta.content`. The `reasoning_content` field on the delta (the industry-standard convention for separating thinking from answer) is silently dropped at every layer:
- `ChunkStreaming.String()` in `proxy-router` → reads `Delta.Content` only
- `ChatCompletionDelta` struct → has `Content` and `Role` fields only, no `ReasoningContent`
- Go mobile `api.go` → accumulates a single `fullResponse` string
- Flutter `chat_screen.dart` → accumulates a single `accumulated` string from all deltas

#### Conventions to Support
Two patterns exist in the wild — we need to handle both:

| Pattern | Used by | How it works |
|---------|---------|--------------|
| `delta.reasoning_content` field | Venice, DeepSeek API, OpenAI o-series, GLM-4.7, Qwen-3 | Separate field on the streaming delta; `content` is clean |
| `<think>...</think>` tags in `content` | Self-hosted models (vLLM, ollama), some proxies | Reasoning wrapped in XML-style tags inside the content string |

Venice also provides `reasoning_effort` parameter (low/medium/high) and `reasoning.enabled: false` to control/disable reasoning.

#### Requirements

**Go / proxy-router layer:**
- Extend `ChatCompletionDelta` and `ChatCompletionStreamResponseExtra` to parse `reasoning_content` from the delta JSON
- Extend `ChunkStreaming` to expose both `Content()` and `ReasoningContent()` (or a typed enum: thinking vs answer)
- Extend the mobile SDK `StreamCallback` to carry a chunk type (thinking vs content) — e.g. `StreamCallback func(text string, isThinking bool, isLast bool) error`
- Go mobile `api.go`: accumulate two separate buffers (`fullResponse` for content, `thinkingResponse` for reasoning); store both in SQLite metadata
- FFI signal: extend the delta store to include chunk type so Dart knows whether each piece is thinking or content
- Fallback: if `reasoning_content` is absent, check for `<think>...</think>` tags in `content` and split them out

**Flutter UI:**
- Two-zone streaming display:
  - **Thinking zone** — A compact (3–5 line) scrolling window above the main response bubble, with a muted/dimmed style (e.g. smaller font, italic, 60% opacity). Shows reasoning tokens scrolling by in real time. Auto-collapses when thinking is done and content begins.
  - **Answer zone** — The normal chat bubble, renders only `content` tokens (the actual answer)
- Thinking zone should have a "Thinking…" label and a subtle animation while active
- After completion, the thinking zone collapses to a single "Thought for Xs" row (tap to expand full reasoning)
- For non-streaming mode: parse the final response and split thinking from answer before rendering

**Conversation history:**
- When building message history for multi-turn conversations, strip `reasoning_content` from prior assistant messages (per DeepSeek/Venice best practice — reasoning tokens should NOT be fed back as context)
- Store reasoning separately in message metadata for review but don't include in prompt history

#### Open Questions
- Should we expose `reasoning_effort` as a tuning parameter in the Chat Tuning drawer? Venice supports low/medium/high for GLM-4.7.
- Should we add a per-model flag to `active_models.json` cache indicating `supportsReasoning` / `supportsReasoningEffort`? Venice's `/v1/models` endpoint includes these fields.
- Should the thinking zone be opt-in (hidden by default) or visible by default?
- How to handle models that sometimes reason and sometimes don't (reasoning is task-dependent)?

---

### 7. Stop / Cancel Generation Button

**Priority:** High (usability — no way to interrupt runaway responses)

#### Problem
There is no way to stop a response once it starts generating. The send button (`Icons.send_rounded`) simply disables while `_sending` is true. If a model goes off the rails (as observed with GLM-4.7's reasoning leak), produces an unexpectedly long response, or the user simply changes their mind, they must wait for the full response to complete or kill the app.

#### Current State
- Send button: `IconButton.filled` with `Icons.send_rounded`, `onPressed: _sending ? null : _send` — disabled (greyed out) during generation
- No cancel token or `context.CancelFunc` is threaded through the FFI → Go → SDK path
- The Go SDK's `SendPromptWithMessagesAndParams` accepts a `context.Context` (currently `context.Background()`) — so cancellation is architecturally possible but unwired
- The `StreamCallback` in Go can return an error to abort streaming, but the c-shared wrapper's chunk function always returns `nil`

#### Requirements

**Flutter UI:**
- While `_sending` is true, replace the send button icon from `Icons.send_rounded` (paper airplane) to `Icons.stop_rounded` (filled square) — standard "stop generation" convention
- Button color: change from green to amber/red while in stop mode
- `onPressed` while sending → calls `_stopGeneration()` instead of `_send()`
- Keep the tuning button disabled while sending (unchanged)

**Cancellation plumbing (FFI → Go → SDK):**
- Add a new FFI export: `CancelPrompt()` (or `AbortCurrentPrompt()`) that cancels the active streaming context
- In Go mobile `api.go`: store a `context.CancelFunc` for the in-flight prompt; `CancelPrompt()` calls it
- Pass the cancellable `context.Context` to `SendPromptWithMessagesAndParams` instead of `context.Background()`
- When cancelled: the SDK's HTTP streaming reader should close, the goroutine should return, and the `done` callback should fire with a result indicating cancellation
- Dart bridge: add `cancelPrompt()` method that calls the FFI `CancelPrompt` export
- Chat screen: on cancel, finalize the streaming bubble with whatever has accumulated so far (don't discard partial responses), mark as "(stopped)" or similar, set `_sending = false`

**Edge cases:**
- Cancel during session opening (blockchain tx) — should we allow cancelling during the `_reopeningSession` phase? Probably not (tx is already submitted). Disable stop button during session open, enable once streaming starts.
- Cancel with no streaming started yet (waiting for first token) — should work, just show empty/cancelled state
- Multiple rapid cancel/send — debounce or disable send for a brief period after cancel
- Non-streaming mode — cancel should also work (abort the HTTP request via context)

#### Open Questions
- Should cancelled responses be saved to conversation history? (Probably yes — the partial response is useful context)
- Should there be a "Regenerate" button after cancellation (re-send the same prompt)?
- Haptic feedback on stop tap?

---

### 8. ~~Collapsible Wallet Card on Home Screen~~ DONE

Collapsed by default on all platforms. Compact inline row with address + MOR/ETH balances. Privacy toggle slimmed to single row with TEE explainer link.

---

### 9. App Lock UX: Biometrics-First, Auto-Prompt

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

### 10. ~~Bug: MOR Scanner Doesn't Reflect Active Session Stakes~~ FIXED

**Priority:** Medium (accounting accuracy)

#### Problem
The "Where's My MOR" wallet breakdown shows 0 MOR in "Active (Staked)" even when sessions are open with staked MOR. Observed on both macOS and iOS — the scanner reports "Scanned 20 of 41 sessions (newest only)" and the staked amount for the active session is missing from the total. The gap between expected balance (e.g. 105 MOR deposited) and displayed "In Wallet" (e.g. 96.7956 MOR) is unaccounted.

#### Likely Cause
The Go SDK `MorScanner` caps scanning to the 20 newest sessions. If the active session's on-chain staking data falls outside that window, or if the scanner reads `approvedAmount` rather than actual locked stake, the active stake won't appear.

#### Requirements
- Active session stakes must always appear in the "Active (Staked)" total
- The gap between deposited and spendable MOR should be fully accounted (staked + on-hold + gas spent)
- Consider scanning all sessions with open status, not just the newest N

---

### 9. Automated Regression Testing

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

*Last updated: 2026-04-16*
