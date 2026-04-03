# Node Neo — Handoff Context

> Snapshot of project state as of **2026-03-20** (evening).
> Use this to bootstrap a new AI chat session in a fresh workspace.

**Repos:** Push targets are **`absgrafx/nodeneo`** and **`absgrafx/Morpheus-Lumerin-Node`** (fork). There is **no plan to merge the fork into MorpheusAIs upstream**; treat the fork as the long-lived SDK + mobile embedding branch (`feat-external_embedding`).

---

## What Is Node Neo

A mobile-first client for the **Morpheus** decentralized AI network. Think "Signal for decentralized AI inference." **Published by [absgrafx](https://github.com/absgrafx)** (`com.absgrafx.nodeneo`); upstream protocol/repos: [MorpheusAIs](https://github.com/MorpheusAIs) on GitHub.

- **Flutter** UI (iOS, Android, macOS) in `lib/`
- **Go** backend — embeds the proxy-router SDK directly, no external process needed
- **SQLite** for local persistence (conversations, messages, preferences)

**Consumer-only.** No provider code, no Docker, no IPFS, no local LLM hosting.

---

## Repo Locations

| Repo | Purpose | Branch |
|------|---------|--------|
| `absgrafx/Node Neo` | This app — Flutter UI + Go backend | `main` |
| `absgrafx/Morpheus-Lumerin-Node` | Fork of proxy-router — contains `proxy-router/mobile/` SDK | `feat-external_embedding` |

These two repos should be in the same workspace. The Node Neo go module uses a `replace` directive pointing to the local fork.

**Git SSH host:** `github.com-vader` (vader@rogueone.life / @morpheusrogue)
**gh CLI:** `gh auth switch -u morpheusrogue` for this project

---

## Architecture (as of 2026-03-20)

### Previous architecture (Phase 0 initial):
```
Flutter UI → dart:ffi → Go mobile API → HTTP ProxyClient → proxy-router REST API → blockchain
```

### Current architecture (Phase 0 with SDK + active models):
```
Flutter UI → dart:ffi → Go c-shared (.dylib) → proxy-router mobile SDK → blockchain (direct)
                                                                        → active models HTTP endpoint (cached)
```

The HTTP intermediary has been eliminated. Node Neo now imports `proxy-router/mobile` directly, which wraps the proxy-router's internal packages (wallet, blockchain service, proxy sender, registries) behind a clean public API. Model listings are fetched from the production active models endpoint (`https://active.mor.org/active_models.json`) — mainnet-only, does not mix testnet models — with 5-minute cache + hash-based invalidation, falling back to blockchain Multicall if the endpoint is unavailable.

---

## Current State (what's built and working)

### Proxy-Router Mobile SDK (`Morpheus-Lumerin-Node/proxy-router/mobile/`)

**Three files, compiles clean, importable from Node Neo:**

- `sdk.go` — Main SDK struct with full API:
  - **Lifecycle:** `NewSDK(Config)`, `Shutdown()`
  - **Wallet:** `CreateWallet()`, `ImportMnemonic()`, `ImportPrivateKey()`, `ExportPrivateKey()`, `GetAddress()`
  - **Balance:** `GetBalance()`, `GetBalanceJSON()`
  - **Models:** `GetAllModels()`, `GetAllModelsJSON()`, `GetRatedBids()`, `GetRatedBidsJSON()`, `ResolveModelID()`
  - **Sessions:** `OpenSession()`, `CloseSession()`, `GetSession()`, `GetSessionJSON()`, `GetUnclosedUserSessions` / `GetUnclosedUserSessionsJSON()`
  - **Chat:** `SendPrompt(ctx, sessionID, prompt, stream, StreamCallback)` — provider stream flag; chunks aggregated in Go before FFI returns
  - Every method also has a `*JSON()` variant for FFI

- `types.go` — Public types: `Balance`, `Model` (now with `ModelType`, `CreatedAt`), `ScoredBid`, `Session` (JSON-serializable)

- `storage.go` — `MemoryKeyValueStorage` implementing `interfaces.KeyValueStorage` for the wallet

**Key design decisions in the SDK:**
- In-memory BadgerDB (`NewTestStorage()`) for session tracking — BadgerDB is provider-only, consumer doesn't need persistence
- `MemoryKeyValueStorage` for wallet (app persists via platform keychain at Dart layer)
- File-based chat storage (JSON files, portable, not BadgerDB)
- Config is programmatic (no env vars), includes `ActiveModelsURL`
- Consumer-only — no provider code, HTTP server, or auth config
- **Active models via HTTP** — SDK fetches from `https://active.mor.org/active_models.json` (production; mainnet-only) with 5-min cache + SHA-256 hash invalidation. Blockchain Multicall as fallback. Pattern borrowed from [Morpheus-Marketplace-API `DirectModelService`](https://github.com/MorpheusAIs/Morpheus-Marketplace-API/blob/dev/src/core/direct_model_service.py).

**Init sequence** (simplified from proxy-router's 30-step main.go):
1. Logger → RPC dial → ethclient → chain ID verification
2. In-memory storage → session storage → wallet
3. Multicall → registries (SessionRouter, Marketplace)
4. Session repo → proxy sender → Blockscout explorer → default rating
5. BlockchainService → wire proxy sender's session service
6. Chat storage (file-based) + HTTP client for active models

### Node Neo Go Mobile API (`nodeneo/go/mobile/api.go`)

**Rewired to use the SDK directly.** All JSON-returning functions for Flutter FFI:

- `Init(dataDir, ethNodeURL, chainID, diamondAddr, morTokenAddr, blockscoutURL)` — initializes SDK + SQLite
- `Shutdown()`, `IsReady()`
- `CreateWallet()`, `ImportWalletMnemonic()`, `ImportWalletPrivateKey()`, `ExportPrivateKey()`
- `GetWalletSummary()` — address + balances
- `GetActiveModels(teeOnly)` — with MAX Privacy TEE filter
- `GetRatedBids(modelID)`
- `OpenSession(modelID, durationSeconds, directPayment)`
- `CloseSession(sessionID)`, `GetSession(sessionID)`, `GetUnclosedUserSessions()` — JSON array of open on-chain sessions for wallet
- `SendPrompt(sessionID, conversationID, prompt, stream)` — provider streaming flag; full response aggregated in Go, persisted to SQLite; prior turns from SQLite included in `messages[]` (truncated window)
- `CreateConversation(id, modelID, modelName, provider, isTEE)` — SQLite row before messages
- `GetConversations()`, `GetMessages(conversationID)`
- `SetConversationSession(conversationID, sessionID)`, `SetConversationTitle(conversationID, title)`, `SetConversationPinned(conversationID, pinned)` — correlate on-chain session; topic + pin for history UI
- `SetPreference(key, value)`, `GetPreference(key)`
- `EstimateOpenSessionStake(modelID, durationSeconds, directPayment)` — on-chain stake formula (supply/budget) for UI vs naive price×time
- `ReusableSessionForModel(modelID)` — returns active non-expired on-chain `session_id` for that model (chat reuse)
- `ClaimEmptyDraftForModel`, `SetConversationSession`, `DeleteConversation` — see `store.go` (shared-session delete only closes chain when last local thread)

### Node Neo Go Internal Packages (legacy, still present)

These were the original implementations before the SDK integration. They still exist but `api.go` no longer imports them:
- `internal/core/core.go` — Engine with native wallet (replaced by SDK wallet)
- `internal/core/proxy_client.go` — HTTP client for proxy-router REST API (replaced by SDK)
- `internal/orchestrator/orchestrator.go` — Caching + sorting layer (replaced by SDK + api.go filtering)
- `internal/store/store.go` — SQLite persistence (still in use, imported by api.go)

### dart:ffi Bridge (WORKING)

- `go/cmd/cshared/main.go` — C-exported wrappers (`//export` directives) for the mobile API surface (incl. `SendPrompt`, `stream`, `EstimateOpenSessionStake`, `ReusableSessionForModel`)
- Built as `build/go/libnodeneo.dylib` (50MB, c-shared, `-ldflags="-s -w"`)
- `lib/services/bridge.dart` — Dart FFI bindings, singleton `GoBridge` class, handles `Pointer<Utf8>` marshalling + `FreeString` cleanup
- Xcode build phase (`Copy Go Library`) auto-copies dylib into app bundle `Frameworks/`
- `@rpath` resolution for macOS, `DynamicLibrary.process()` for iOS, `.so` for Android

### Flutter Frontend (`lib/`) — WIRED TO REAL SDK

- `main.dart` → `app.dart` → initializes SDK on startup (Base mainnet config), routes to loading/error/onboarding/home
- `theme.dart` — dark theme with green accent (Node NeoTheme)
- `screens/onboarding/onboarding_screen.dart` — **wired to real Go SDK**: `createWallet()` generates real BIP-39 mnemonic, shows backup screen with numbered words, `importWalletMnemonic()` for recovery
- `screens/home/home_screen.dart` — **wired to real SDK**: live wallet + balances, active models, MAX Privacy (TEE-only); **Continue chatting** shows **~N min left** when `session_ends_at` from chain; **45s timer** refreshes conversations (reconcile closed/expired sessions). `GetConversations` runs chain snapshot: unclosed **and not past `ends_at`** clears stale `session_id`.
- `screens/chat/chat_screen.dart` — Session length presets (min **10 min**), **stake panel** (estimated MOR moved vs wallet via `EstimateOpenSessionStake`), **structured session errors** (`session_open_errors.dart`: red “why”, expandable technical JSON). **Reuses** `ReusableSessionForModel` before `OpenSession` for new/empty threads (multiple conversations, one on-chain session per model).
- `screens/chat/conversation_transcript_screen.dart` — read-only history; **Continue this thread** → chat without session until send
- `screens/sessions/on_chain_sessions_screen.dart` — lists unclosed on-chain sessions, **Close** with confirm
- `screens/settings/network_settings_screen.dart` — custom Base RPC override (**Test URLs** + **eth_chainId** check before save), default **chat session length**; **Clear** restores defaults; link to on-chain sessions
- `lib/utils/session_cost_estimate.dart`, `session_open_errors.dart` — stake math + human-first errors + JSON `reason` extraction from `no provider accepting session`
- `screens/security/*` — **App lock** (password + optional biometrics), `AutofillGroup` / `AutofillHints` for password managers; **⋮ → Security**
- `widgets/app_lock_gate.dart` — lock on cold start / **paused** lifecycle
- `screens/wallet/wallet_tools_screen.dart` — **export private key**, **send ETH/MOR**, **erase wallet**. See `testing_notes.md` for Keychain / container reset.
- `lib/services/bridge.dart` — dart:ffi bridge; `listUnclosedSessions()`, `sendPrompt(..., stream:)`
- `lib/services/wallet_vault.dart` — **persists BIP-39 mnemonic** in Keychain (macOS) / Keystore (Android) via `flutter_secure_storage`. On each launch after `Init()`, if a mnemonic exists it is re-imported into the in-memory Go wallet so the same address and funds are used across sessions.
- **Flutter 3.41.5** installed via Homebrew
- `flutter analyze` → zero issues
- Dependencies: `ffi: ^2.1.0`, `path_provider: ^2.1.0`
- CocoaPods installed via Homebrew (required for `path_provider` macOS plugin)

### Project Files

- `LICENSE` — MIT, copyright ABSGrafx
- `README.md` — updated for absgrafx org
- `Makefile` — go-test, go-macos (c-shared build), flutter-macos, run-macos targets
- `.gitignore` — Go vendor, Flutter build, IDE, secrets
- Entitlements: unsandboxed (`app-sandbox = false`), `disable-library-validation` for Go dylib, `keychain-access-groups` for Data Protection Keychain

---

## Recently shipped (2026-03-19 → 03-20)

- **TEE attestation in mobile SDK** — `proxy-router/mobile/sdk.go` now passes `attestation.NewVerifier(...)` into `BlockchainService` (same path as `cmd/main.go` daemon). Fake / misconfigured TEE models **fail session open** with register mismatch, aligned with app.mor.org.
- **On-chain stake estimate** — `EstimateOpenSessionStake` FFI + chat UI panel (supply/budget formula vs wallet MOR).
- **Session reuse per model** — `ReusableSessionForModel` + chat bootstrap; **delete conversation** only calls `CloseSession` when **last** local thread using that `session_id`.
- **Active session UX** — `session_ends_at` on conversations, minutes-left subtitle, periodic reconcile (wall-clock past `ends_at` + chain unclosed set).
- **Session duration** — UI floor **10 minutes**; `SessionTooShort` / ERC20 copy improvements.
- **Session open errors** — `explainSessionOpenError()` + red headline + expandable “Technical details”; parses provider `reason` from JSON failures.

---

## MVP backlog (do next — “kicking MVP”)

Prioritized list to capture before wider alpha:

1. **Dev setup & alpha distribution** — Step-by-step for **Mac + iPhone** (signing, TestFlight or ad-hoc, rebuilding `libnodeneo`, env). See also `.ai-docs/ios_device_signing.md` if present.
2. **Visual branding pass** — Standardize **colors/icons** to Morpheus artwork or a single consistent kit (today: `Node NeoTheme` green, ad hoc).
3. **Settings / layout cleanup** — Remove dev notes, tighten boxes, consistent section spacing.
4. **Product naming** — Replace working name **Node Neo** in headers/onboarding with a **formal app name** when decided.
5. **Password manager autofill** — Audit `TextField` / `AutofillHints` / `AutofillGroup` (import seed, app lock, wallet flows) so **1Password / Bitwarden / iCloud Keychain** reliably offer fill (platform quirks documented).
6. **Lock + splash / onboarding polish** — Marketing-friendly first run; **quick links** (e.g. Coinbase, Base bridge, “get MOR”) for normie path.
7. **Technical / power-user** — **Token usage** dashboard (input/output/total per model or session; stake vs direct pay); **response metadata drawer** (provider headers JSON); **tunable params** (temperature, etc.) where API allows.
8. **Parity pass** — Node Neo + embedded SDK vs **API Gateway** single-user/single-device flows; gap list doc.
9. **Token symbols & labels** — **Shipped:** `lib/constants/network_tokens.dart` + home wallet chips + wallet send screen.
10. **History / drawer list layout** — **Shipped:** wider drawer + `flutter_slidable` actions + pencil rename (overflow menu removed).
11. **Markdown in chat** — **Shipped:** `flutter_markdown` via `lib/widgets/chat_message_body.dart` (chat + read-only transcript).
12. **Copy / paste** — **Shipped:** copy icon on bubbles + paste hint on composer; transcript matches.
13. **Images / multimodal** — Farther out: inbound images, vision models, attachment UX (track after core text+MVP).

**Also on the radar**

- **Legacy Go cleanup** — `internal/core/`, `internal/orchestrator/` unused HTTP path.
- TEE **per-message** attestation UI (optional).
- **Backlog B.1** — Chunk-level **Flutter** streaming via `SendPromptStream` (optional polish: throttle, cancel).
- **Backlog B.2** — **Chat footer activity strip** — labels for session setup, **Session secured** / **Attestation passed** (TEE), **Sending prompt**, **Waiting for response**, plus an **active** indicator so background work feels alive (see `plan.md`).

See `.ai-docs/plan.md` for phase table + overlap with this backlog.

---

## Environment Notes

- **Go 1.26.1** via Homebrew at `/opt/homebrew/bin/go`
- **IMPORTANT:** Old Go 1.21 still lives at `/usr/local/go/bin/go` — need `export GOROOT="/opt/homebrew/Cellar/go/1.26.1/libexec"` and `export PATH="/opt/homebrew/bin:$PATH"` for builds, or remove `/usr/local/go` with sudo
- **Flutter 3.41.5** via Homebrew
- **Xcode** installed and configured
- **macOS ARM M1** target for development

---

## Key Design Decisions

1. **MAX Privacy mode** — Toggle in UI that filters to TEE-only providers.
2. **Embedded SDK, no HTTP** — Node Neo imports `proxy-router/mobile` directly. No separate process, no REST API, no network hop. True embedded Go integration.
3. **BadgerDB is provider-only** — SDK uses in-memory storage for session tracking. Local persistence is SQLite (conversations, preferences) at the app layer.
4. **absgrafx org** — Personal project under MIT license, built on the open Morpheus stack (upstream: MorpheusAIs GitHub org).
5. **Consumer-only** — No provider code, no IPFS, no Docker, no local LLM hosting.
6. **Private key export** — Available via `ExportPrivateKey()`, UI should gate behind biometric re-auth.
7. **Active models via HTTP, not blockchain** — Production URL `https://active.mor.org/active_models.json` (mainnet-only; not mixed with testnet). Same pattern as Morpheus-Marketplace-API `DirectModelService`. 5-min cache, SHA-256 hash invalidation, blockchain Multicall as fallback.
8. **c-shared over gomobile** — dart:ffi with `//export` C functions gives more control than gomobile bind. Works for macOS `.dylib`, iOS `.xcframework`, Android `.so`.

---

## File Tree (key files)

```
Node Neo/
├── .ai-docs/
│   ├── architecture.md
│   ├── plan.md
│   ├── testing_notes.md           # Persistence, export/send, Keychain nuke
│   └── handoff_context.md         # THIS FILE
├── build/
│   └── go/
│       └── libnodeneo.dylib       # c-shared library (built, not committed)
├── go/
│   ├── go.mod                     # github.com/absgrafx/nodeneo, go 1.26
│   ├── go.sum                     #   replace → ../../Morpheus-Lumerin-Node/proxy-router
│   ├── cmd/
│   │   └── cshared/
│   │       └── main.go            # //export C wrappers for dart:ffi
│   ├── internal/
│   │   ├── core/                  # (legacy — replaced by SDK)
│   │   ├── orchestrator/          # (legacy — replaced by SDK)
│   │   └── store/
│   │       └── store.go           # SQLite persistence (still in use)
│   └── mobile/
│       └── api.go                 # FFI API — uses proxy-router SDK directly
├── lib/                           # Flutter/Dart
│   ├── main.dart
│   ├── app.dart                   # SDK init on startup, routing
│   ├── theme.dart
│   ├── services/
│   │   ├── bridge.dart                     # dart:ffi → c-shared
│   │   ├── chat_streaming_preference_store.dart
│   │   ├── rpc_settings_store.dart
│   │   └── wallet_vault.dart
│   └── screens/
│       ├── onboarding/onboarding_screen.dart
│       ├── home/home_screen.dart
│       ├── chat/chat_screen.dart
│       ├── sessions/on_chain_sessions_screen.dart
│       ├── settings/network_settings_screen.dart
│       └── wallet/wallet_tools_screen.dart
├── macos/
│   └── Runner.xcodeproj/
│       └── project.pbxproj        # Includes "Copy Go Library" build phase
├── Makefile                       # go-macos builds c-shared dylib
├── LICENSE
├── README.md
├── .gitignore
└── pubspec.yaml                   # ffi, path_provider deps

Morpheus-Lumerin-Node/                    # Fork (branch: feat-external_embedding)
└── proxy-router/
    ├── mobile/
    │   ├── sdk.go                        # SDK + active models HTTP + TEE attestation.Verifier
    │   ├── types.go
    │   └── storage.go
    └── internal/blockchainapi/
        ├── service.go                    # stake estimate helper, OpenSession TEE path
        └── structs/res.go                # OpenSessionStakeEstimate
```
