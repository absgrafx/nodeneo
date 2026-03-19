# RedPill — Plan & Progress

> Living document. Updated as we build.
> Part of the [absgrafx](https://github.com/absgrafx) project.

---

## Current Status: **Phase 0 — Foundation**

**Started:** 2026-03-17
**Target platform:** macOS arm64 (M1) → iOS simulator → iOS device

---

## Phase 0 — Foundation (current)

Goal: Prove the architecture works. Go library compiles, Flutter talks to it, wallet works.


| #    | Task                                      | Status      | Notes                                      |
| ---- | ----------------------------------------- | ----------- | ------------------------------------------ |
| 0.1  | Create repo + architecture docs           | DONE        |                                            |
| 0.2  | Go module (go 1.26, go-ethereum, bip39)   | DONE        | `github.com/absgrafx/redpill`              |
| 0.3  | Native wallet — create, import, key derive| DONE        | BIP-39 + go-ethereum, all tests pass       |
| 0.4  | HTTP proxy client for proxy-router API    | DONE        | Models, sessions, chat, balance            |
| 0.5  | Orchestrator — ActiveModels, QuickSession | DONE        | Cached model listing, one-tap sessions     |
| 0.6  | SQLite store — init + migrations          | DONE        | Conversations, messages, preferences       |
| 0.7  | Mobile FFI API surface (gomobile)         | DONE        | JSON-based function exports                |
| 0.8  | Install Flutter SDK                       | DONE        | Flutter 3.41.5                             |
| 0.9  | Flutter scaffold (macOS + iOS targets)    | DONE        | Dark theme, onboarding + home screens      |
| 0.10 | License + absgrafx org setup              | DONE        | MIT license                                |
| 0.11 | dart:ffi bridge — call Go from Dart       | TODO        | Next step                                  |
| 0.12 | Onboarding screen — wire to real wallet   | TODO        | Connect create/import to Go FFI            |
| 0.13 | Fork proxy-router → absgrafx             | TODO        | Add `mobile/` SDK for direct Go import     |


**Phase 0 success criteria:** Launch app on macOS, create a wallet, see address. Wire to proxy-router for balance + model listing.

---

## Phase 1 — Browse + Chat

Goal: User can browse models, open a session, and chat with a TEE-attested provider.


| #   | Task                                      | Status | Notes                                 |
| --- | ----------------------------------------- | ------ | ------------------------------------- |
| 1.1 | ActiveModels() orchestrator               |        | Filter active, enrich with TEE status |
| 1.2 | Model marketplace screen                  |        | List, search, TEE badge               |
| 1.3 | BestProvider() scoring                    |        | TEE-first, latency-aware              |
| 1.4 | QuickSession() — one-tap session creation |        | Approve + initiate flow               |
| 1.5 | Chat screen — streaming responses         |        | SSE, markdown rendering               |
| 1.6 | TEE verification indicator                |        | Green shield = attested               |
| 1.7 | Per-prompt re-verification integration    |        | VerifyProviderQuick                   |
| 1.8 | Basic error handling + retry              |        | Network failures, session expiry      |


**Phase 1 success criteria:** Chat with a live TEE-attested model on Arbitrum mainnet. See the green TEE shield. Streaming responses. All from the Mac app.

---

## Phase 2 — Polish + Persist

Goal: It feels like a real app. Chat history, settings, smooth UX.


| #   | Task                                 | Status | Notes                              |
| --- | ------------------------------------ | ------ | ---------------------------------- |
| 2.1 | Chat persistence to SQLite           |        | Conversations + messages           |
| 2.2 | Chat history browser                 |        | List, search, delete               |
| 2.3 | Conversation titles (auto-generated) |        | From first prompt                  |
| 2.4 | Settings screen                      |        | RPC endpoint, theme, default model |
| 2.5 | Dark / light theme                   |        | Adaptive to platform               |
| 2.6 | Staking management screen            |        | Stake, unstake, view rewards       |
| 2.7 | Transaction history                  |        | Recent sends, stakes, sessions     |
| 2.8 | Auto-lock + biometric unlock         |        | Configurable timeout               |
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
| proxy-router (HTTP)    | `github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router` | Blockchain, sessions, chat via REST    |
| modernc.org/sqlite     | Pure-Go SQLite                                              | Embedded DB, no CGo                    |
| Flutter SDK            | flutter.dev                                                 | Cross-platform UI                      |
| gomobile               | `golang.org/x/mobile/cmd/gomobile`                          | Compile Go → native libraries          |
| flutter_secure_storage | pub.dev                                                     | Platform keychain abstraction          |
| local_auth             | pub.dev                                                     | Biometric authentication               |


---

## Architecture Decisions Log


| Date       | Decision                                     | Rationale                                                                                                      |
| ---------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| 2026-03-17 | Flutter over React Native                    | True native compilation, first-class desktop + mobile, better Go interop via dart:ffi                          |
| 2026-03-17 | Orchestrator layer between UI and core       | Smart consumer API (active models, quick sessions) — patterns from API Gateway without multi-user overhead     |
| 2026-03-17 | Pure-Go SQLite (modernc)                     | Avoids CGo for clean cross-compilation with gomobile                                                           |
| 2026-03-17 | Consumer-only, strip provider code           | Smaller binary, simpler UX, focused scope                                                                      |
| 2026-03-17 | Native wallet, HTTP for blockchain ops       | go-ethereum/bip39 for wallet (no deps), proxy-router REST API for blockchain (pragmatic)                       |
| 2026-03-17 | Planned fork into absgrafx org               | Will add `mobile/` SDK package so RedPill can import proxy-router directly — eliminates HTTP intermediary      |
| 2026-03-17 | absgrafx org, MIT license                    | Personal project bolted on top of MorpheusAIs, compatible with upstream MIT license                            |


