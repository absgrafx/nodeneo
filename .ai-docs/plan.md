# Node Neo — Plan & Progress

> Living document. Updated as we build.
> Part of the [absgrafx](https://github.com/absgrafx) project.

---

## Current Status: **Phase 1 — Browse + Chat** (in progress)

**Started:** 2026-03-17  
**Latest milestone (2026-03-20):** End-to-end chat on **Base mainnet**; **TEE attestation** enabled in embedded SDK (negative tests fail like web); session **reuse**, **stake estimate** UI, **friendly errors**, **active session** time remaining + reconcile.

**Target platform:** macOS arm64 (M1) → iOS simulator → iOS device

---

## Phase 0 — Foundation

Goal: Prove the architecture works. Go library compiles, Flutter talks to it, wallet works.


| #    | Task                                      | Status      | Notes                                      |
| ---- | ----------------------------------------- | ----------- | ------------------------------------------ |
| 0.1  | Create repo + architecture docs           | DONE        |                                            |
| 0.2  | Go module (go 1.26, go-ethereum, bip39)   | DONE        | `github.com/absgrafx/nodeneo`              |
| 0.3  | Native wallet — create, import, key derive| DONE        | BIP-39 + go-ethereum, all tests pass       |
| 0.4  | HTTP proxy client for proxy-router API    | DONE        | Models, sessions, chat, balance (now legacy)|
| 0.5  | Orchestrator — ActiveModels, QuickSession | DONE        | Cached model listing (now legacy)          |
| 0.6  | SQLite store — init + migrations          | DONE        | Conversations, messages, preferences       |
| 0.7  | Mobile FFI API surface (gomobile)         | DONE        | JSON-based function exports                |
| 0.8  | Install Flutter SDK                       | DONE        | Flutter 3.41.5                             |
| 0.9  | Flutter scaffold (macOS + iOS targets)    | DONE        | Dark theme, onboarding + home screens      |
| 0.10 | License + absgrafx org setup              | DONE        | MIT license                                |
| 0.13 | Fork proxy-router → absgrafx             | DONE        | `proxy-router/mobile/` SDK created         |
| 0.14 | Rewire Node Neo to use SDK (no HTTP)       | DONE        | `api.go` imports SDK directly              |
| 0.11 | dart:ffi bridge — call Go from Dart       | DONE        | c-shared .dylib + bridge.dart + Xcode phase|
| 0.12 | Onboarding screen — wire to real wallet   | DONE        | Real BIP-39 create + mnemonic backup flow  |
| 0.15 | Home screen — live balance + models       | DONE        | Real chain balance + active models HTTP    |
| 0.16 | Active models HTTP endpoint integration   | DONE        | 5-min cache, hash invalidation, chain fallback |
| 0.17 | CocoaPods + entitlements setup            | DONE        | network.client, path_provider plugin       |
| 1.0  | Model tap → session → chat (MVP)          | DONE        | CreateConversation FFI, ChatScreen, SendPrompt |


**Phase 0 success criteria:** Launch app on macOS, create a wallet, see address; embedded SDK for chain + models.
**Phase 0 STATUS: ✅ COMPLETE** — Wallet, **Base mainnet** init, live balances, active models HTTP cache, **first successful provider chat** (e.g. TEE model).

---

## Phase 1 — Browse + Chat

Goal: User can browse models, open a session, and chat with a TEE-attested provider.


| #   | Task                                      | Status | Notes                                 |
| --- | ----------------------------------------- | ------ | ------------------------------------- |
| 1.1 | ActiveModels() orchestrator               |        | Filter active, enrich with TEE status |
| 1.2 | Model marketplace screen                  |        | List, search, TEE badge               |
| 1.3 | BestProvider() scoring                    |        | TEE-first, latency-aware              |
| 1.4 | QuickSession() — one-tap session creation |        | Approve + initiate flow               |
| 1.5 | Chat screen — streaming responses         | DONE (Mac) | Provider `stream` + **`SendPromptStream`** / `NativeCallable` chunk UI when toggle on; non-streaming uses `SendPrompt` |
| 1.6 | TEE verification indicator                | Partial | Green shield in UI; **on-chain open now runs attestation** in embedded SDK (was missing) |
| 1.7 | Per-prompt re-verification integration    |        | VerifyProviderQuick / optional         |
| 1.8 | Basic error handling + retry              | Partial | Structured “why” + expandable technical; provider `reason` JSON parsed |
| 1.9 | On-chain session list + close             | DONE   | `GetUnclosedUserSessions`, `OnChainSessionsScreen`, drawer + ⋮ + Network/RPC |
| 1.10 | Reuse open session per model (chat)       | DONE   | `ReusableSessionForModel` + shared-session safe delete |


**Phase 1 success criteria (revised):** Chat with a **live model on Base** from the Mac app; TEE path exercised; user can **see and close** open on-chain sessions. (Original “Arbitrum + SSE in UI” deferred: Arbitrum not current target; UI token stream → Backlog B.1.)

---

## Next up — **MVP for alpha** (see `handoff_context.md` for detail)

| # | Theme | Notes |
|---|--------|--------|
| 1 | **Dev setup + iPhone** | Step-by-step Mac + device signing, rebuild `libnodeneo`, distribute to alpha testers |
| 2 | **Branding** | Morpheus-aligned colors/icons or one consistent design system |
| 3 | **Settings cleanup** | Remove stray notes; tidy sections |
| 4 | **Formal app name** | Replace working name in chrome/onboarding when chosen |
| 5 | **Password manager fill** | Autofill hints / platform issues for seed + app lock |
| 6 | **Splash / lock / onboarding** | Normie-friendly copy + quick links (e.g. get MOR / Coinbase) |
| 7 | **Usage + power user** | Token counts dashboard; response metadata drawer; temperature / params |
| 8 | **Gateway parity pass** | Doc gaps vs API Gateway single-user flows |
| 9 | **Token symbols** | **DONE** — `constants/network_tokens.dart`; wallet card + **Manage** send labels; **MOR · Base** / **ETH · Base** chips + gas hint |
| 10 | **History / drawer UX** | **DONE** — Drawer **~92% width (max 420px)**; **slidable** pin / close session / delete; **rename** pencil; overflow ⋮ removed |
| 11 | **Markdown replies** | **DONE** — `flutter_markdown` + shared `widgets/chat_message_body.dart` (chat + transcript) |
| 12 | **Copy / paste** | **DONE** — Copy icon per bubble; composer hint “paste supported”; transcript copy |
| 13 | **Images / multimodal** | Deferred — after text MVP |

**Recently done (no longer “next”):** session reuse per model, `session_ends_at` + minutes left + reconcile, stake estimate FFI, structured session errors, TEE verifier in `proxy-router/mobile`.

---

## Phase 2 — Polish + Persist

Goal: It feels like a real app. Chat history, settings, smooth UX.


| #   | Task                                 | Status | Notes                              |
| --- | ------------------------------------ | ------ | ---------------------------------- |
| 2.1 | Chat persistence to SQLite           | Partial | **On send:** `CreateConversation` + `SaveMessage` for user/assistant; **no history list UI yet** |
| 2.2 | Chat history browser                 |        | **Next:** List, open, delete — see “Next up” above              |
| 2.3 | Conversation titles (auto-generated) |        | From first prompt                  |
| 2.4 | Settings screen                      | Partial | **Network / RPC** + link to on-chain sessions; expand for theme / default model |
| 2.5 | Dark / light theme                   |        | Adaptive to platform               |
| 2.6 | Staking management screen            |        | Stake, unstake, view rewards       |
| 2.7 | Transaction history                  |        | Recent sends, stakes, sessions     |
| 2.8 | Auto-lock + biometric unlock         | Partial | App password + optional biometrics; lock on **paused**; **Autofill** for PW managers — see `app_security_plan.md` |
| 2.9 | Onboarding polish                    |        | Smooth wallet setup flow           |


---

## Phase 3 — iOS

Goal: Running on a real iPhone. Same app, native feel.


| #   | Task                           | Status | Notes                                  |
| --- | ------------------------------ | ------ | -------------------------------------- |
| 3.1 | gomobile build for iOS (arm64) |        | .xcframework                           |
| 3.2 | Flutter iOS build + simulator  |        | Xcode integration                      |
| 3.3 | Face ID integration            |        |                                        |
| 3.4 | iOS Keychain for key storage   |        |                                        |
| 3.5 | Background task handling       |        | Suspend proxy-router when backgrounded |
| 3.6 | Push notification hooks        |        | Session events                         |
| 3.7 | iOS-specific UI polish         |        | Cupertino widgets where appropriate    |
| 3.8 | TestFlight build               |        | Internal testing                       |


---

## Phase 4 — Android


| #   | Task                         | Status | Notes           |
| --- | ---------------------------- | ------ | --------------- |
| 4.1 | gomobile build for Android   |        | .aar            |
| 4.2 | Flutter Android build        |        |                 |
| 4.3 | Fingerprint / face unlock    |        | BiometricPrompt |
| 4.4 | Android Keystore integration |        |                 |
| 4.5 | Play Store prep              |        |                 |


---

## Phase 5 — Advanced Features


| #   | Task                            | Status | Notes                      |
| --- | ------------------------------- | ------ | -------------------------- |
| 5.1 | Multi-conversation management   |        | Tabs or sidebar            |
| 5.2 | Export/backup conversations     |        | Encrypted local backup     |
| 5.3 | Model favorites + pinning       |        |                            |
| 5.4 | Provider reputation scoring     |        | Historical uptime, latency |
| 5.5 | Notification for session expiry |        |                            |
| 5.6 | Widget / quick-action           |        | iOS widget, Android widget |
| 5.7 | Sharing responses               |        | Share card generation      |
| 5.8 | Voice input                     |        | Speech-to-text for prompts |


---

## Dependencies & References


| Dependency             | Source                                                      | Purpose                                |
| ---------------------- | ----------------------------------------------------------- | -------------------------------------- |
| go-ethereum            | `github.com/ethereum/go-ethereum`                           | Key derivation, Ethereum addresses     |
| go-bip39               | `github.com/tyler-smith/go-bip39`                           | BIP-39 mnemonic generation             |
| btcsuite               | `github.com/btcsuite/btcd`, `btcutil`                       | HD key derivation (BIP-32)             |
| proxy-router SDK       | `github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile` | Embedded blockchain, sessions, chat (direct, no HTTP). Go **import path** stays upstream; `go.mod` **`replace`** → local **absgrafx** fork. |
| modernc.org/sqlite     | Pure-Go SQLite                                              | Embedded DB, no CGo                    |
| Flutter SDK            | flutter.dev                                                 | Cross-platform UI                      |
| gomobile               | `golang.org/x/mobile/cmd/gomobile`                          | Compile Go → native libraries          |
| flutter_secure_storage | pub.dev                                                     | Platform keychain abstraction          |
| local_auth             | pub.dev                                                     | Biometric authentication               |


---

## Backlog (intentionally not built yet)

| # | Item | Notes |
|---|------|--------|
| B.1 | **Token-by-token UI streaming** | **Addressed (chunk UI):** `SendPromptStream` + C callback → `NativeCallable.listener`; assistant bubble updates per SDK delta. Optional follow-ups: cancellation, throttle/`SchedulerBinding`, finer token cadence if provider batches. |
| B.2 | **Chat footer — background activity status** | At the **very bottom** of the chat screen (above/beside composer), show **what’s happening** while work runs: e.g. **Setting up session** → **Session secured** (or **Attestation passed** when TEE provider) → **Sending prompt** → **Waiting for response**, with a **clear active / progress** treatment (spinner, pulsing dot, or linear stepper) so the user knows the app isn’t frozen. Wire labels to real phases (open session, attestation outcome, FFI send, stream wait). *Not implemented yet.* |

---

## Architecture Decisions Log


| Date       | Decision                                     | Rationale                                                                                                      |
| ---------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| 2026-03-17 | Flutter over React Native                    | True native compilation, first-class desktop + mobile, better Go interop via dart:ffi                          |
| 2026-03-17 | Orchestrator layer between UI and core       | Smart consumer API (active models, quick sessions) — patterns from API Gateway without multi-user overhead     |
| 2026-03-17 | Pure-Go SQLite (modernc)                     | Avoids CGo for clean cross-compilation with gomobile                                                           |
| 2026-03-17 | Consumer-only, strip provider code           | Smaller binary, simpler UX, focused scope                                                                      |
| 2026-03-17 | Native wallet, HTTP for blockchain ops       | go-ethereum/bip39 for wallet (no deps), proxy-router REST API for blockchain (pragmatic)                       |
| 2026-03-17 | Planned fork into absgrafx org               | Will add `mobile/` SDK package so Node Neo can import proxy-router directly — eliminates HTTP intermediary      |
| 2026-03-17 | absgrafx org, MIT license                    | Personal project (absgrafx) on the open Morpheus stack; upstream repos under MorpheusAIs; compatible MIT license |
| 2026-03-19 | Embedded SDK replaces HTTP proxy client      | `proxy-router/mobile/` created, Node Neo imports it directly. No external process, no REST API, no network hop  |
| 2026-03-19 | BadgerDB skipped for mobile                  | BadgerDB is provider-only (sessions, auth, capacity). SDK uses in-memory storage. SQLite at app layer for chat |
| 2026-03-19 | c-shared over gomobile for FFI               | `//export` C functions via dart:ffi gives more control than gomobile bind. Works across .dylib/.xcframework/.so |
| 2026-03-19 | Active models via HTTP, not blockchain       | Marketplace API's `active_models.json` is pre-built, cached, fast. Blockchain Multicall as fallback only. Pattern from `DirectModelService` |
| 2026-03-20 | Base mainnet consumer path                   | Production inference + staking on Base; docs and plan criteria updated from Sepolia/Arbitrum wording where obsolete |
| 2026-03-20 | On-chain session UX                          | Unclosed session list + close in app; stake recovery without relying on session timeout alone |
| 2026-03-20 | Mobile SDK TEE attestation                   | `attestation.NewVerifier` in `mobile/sdk.go` — Secure models must pass golden register check (aligned with daemon / web) |


