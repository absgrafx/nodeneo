# RedPill — Chat Handoff Context

> Snapshot of project state as of 2026-03-19 (evening session).
> Use this to bootstrap a new AI chat session in a fresh workspace.

---

## What Is RedPill

A mobile-first client for the [MorpheusAIs](https://github.com/MorpheusAIs) decentralized AI network. Think "Signal for decentralized AI inference." Part of the [absgrafx](https://github.com/absgrafx) org.

- **Flutter** UI (iOS, Android, macOS) in `lib/`
- **Go** backend — embeds the proxy-router SDK directly, no external process needed
- **SQLite** for local persistence (conversations, messages, preferences)

**Consumer-only.** No provider code, no Docker, no IPFS, no local LLM hosting.

---

## Repo Locations

| Repo | Purpose | Branch |
|------|---------|--------|
| `absgrafx/RedPill` | This app — Flutter UI + Go backend | `main` |
| `absgrafx/Morpheus-Lumerin-Node` | Fork of proxy-router — contains `proxy-router/mobile/` SDK | `feat-external_embedding` |

These two repos should be in the same workspace. The RedPill go module uses a `replace` directive pointing to the local fork.

**Git SSH host:** `github.com-vader` (vader@rogueone.life / @morpheusrogue)
**gh CLI:** `gh auth switch -u morpheusrogue` for this project

---

## Architecture (as of 2026-03-19)

### Previous architecture (Phase 0 initial):
```
Flutter UI → dart:ffi → Go mobile API → HTTP ProxyClient → proxy-router REST API → blockchain
```

### Current architecture (Phase 0 with SDK + active models):
```
Flutter UI → dart:ffi → Go c-shared (.dylib) → proxy-router mobile SDK → blockchain (direct)
                                                                        → active models HTTP endpoint (cached)
```

The HTTP intermediary has been eliminated. RedPill now imports `proxy-router/mobile` directly, which wraps the proxy-router's internal packages (wallet, blockchain service, proxy sender, registries) behind a clean public API. Model listings are fetched from the Marketplace API's active models endpoint (`https://active.dev.mor.org/active_models.json`) with 5-minute cache + hash-based invalidation, falling back to blockchain Multicall if the endpoint is unavailable.

---

## Current State (what's built and working)

### Proxy-Router Mobile SDK (`Morpheus-Lumerin-Node/proxy-router/mobile/`)

**Three files, compiles clean, importable from RedPill:**

- `sdk.go` — Main SDK struct with full API:
  - **Lifecycle:** `NewSDK(Config)`, `Shutdown()`
  - **Wallet:** `CreateWallet()`, `ImportMnemonic()`, `ImportPrivateKey()`, `ExportPrivateKey()`, `GetAddress()`
  - **Balance:** `GetBalance()`, `GetBalanceJSON()`
  - **Models:** `GetAllModels()`, `GetAllModelsJSON()`, `GetRatedBids()`, `GetRatedBidsJSON()`, `ResolveModelID()`
  - **Sessions:** `OpenSession()`, `CloseSession()`, `GetSession()`, `GetSessionJSON()`
  - **Chat:** `SendPrompt()` with `StreamCallback` for streaming responses
  - Every method also has a `*JSON()` variant for FFI

- `types.go` — Public types: `Balance`, `Model` (now with `ModelType`, `CreatedAt`), `ScoredBid`, `Session` (JSON-serializable)

- `storage.go` — `MemoryKeyValueStorage` implementing `interfaces.KeyValueStorage` for the wallet

**Key design decisions in the SDK:**
- In-memory BadgerDB (`NewTestStorage()`) for session tracking — BadgerDB is provider-only, consumer doesn't need persistence
- `MemoryKeyValueStorage` for wallet (app persists via platform keychain at Dart layer)
- File-based chat storage (JSON files, portable, not BadgerDB)
- Config is programmatic (no env vars), includes `ActiveModelsURL`
- Consumer-only — no provider code, HTTP server, or auth config
- **Active models via HTTP** — SDK fetches from the Marketplace API's `active_models.json` endpoint with 5-min cache + SHA-256 hash invalidation. Blockchain Multicall as fallback. Pattern borrowed from [Morpheus-Marketplace-API `DirectModelService`](https://github.com/MorpheusAIs/Morpheus-Marketplace-API/blob/dev/src/core/direct_model_service.py).

**Init sequence** (simplified from proxy-router's 30-step main.go):
1. Logger → RPC dial → ethclient → chain ID verification
2. In-memory storage → session storage → wallet
3. Multicall → registries (SessionRouter, Marketplace)
4. Session repo → proxy sender → Blockscout explorer → default rating
5. BlockchainService → wire proxy sender's session service
6. Chat storage (file-based) + HTTP client for active models

### RedPill Go Mobile API (`redpill/go/mobile/api.go`)

**Rewired to use the SDK directly.** All JSON-returning functions for Flutter FFI:

- `Init(dataDir, ethNodeURL, chainID, diamondAddr, morTokenAddr, blockscoutURL)` — initializes SDK + SQLite
- `Shutdown()`, `IsReady()`
- `CreateWallet()`, `ImportWalletMnemonic()`, `ImportWalletPrivateKey()`, `ExportPrivateKey()`
- `GetWalletSummary()` — address + balances
- `GetActiveModels(teeOnly)` — with MAX Privacy TEE filter
- `GetRatedBids(modelID)`
- `OpenSession(modelID, durationSeconds, directPayment)`
- `CloseSession(sessionID)`, `GetSession(sessionID)`
- `SendPrompt(sessionID, conversationID, prompt)` — streaming aggregated, persisted to SQLite
- `GetConversations()`, `GetMessages(conversationID)`
- `SetPreference(key, value)`, `GetPreference(key)`

### RedPill Go Internal Packages (legacy, still present)

These were the original implementations before the SDK integration. They still exist but `api.go` no longer imports them:
- `internal/core/core.go` — Engine with native wallet (replaced by SDK wallet)
- `internal/core/proxy_client.go` — HTTP client for proxy-router REST API (replaced by SDK)
- `internal/orchestrator/orchestrator.go` — Caching + sorting layer (replaced by SDK + api.go filtering)
- `internal/store/store.go` — SQLite persistence (still in use, imported by api.go)

### dart:ffi Bridge (WORKING)

- `go/cmd/cshared/main.go` — C-exported wrapper (`//export` directives) for all 18 SDK functions
- Built as `build/go/libredpill.dylib` (50MB, c-shared, `-ldflags="-s -w"`)
- `lib/services/bridge.dart` — Dart FFI bindings, singleton `GoBridge` class, handles `Pointer<Utf8>` marshalling + `FreeString` cleanup
- Xcode build phase (`Copy Go Library`) auto-copies dylib into app bundle `Frameworks/`
- `@rpath` resolution for macOS, `DynamicLibrary.process()` for iOS, `.so` for Android

### Flutter Frontend (`lib/`) — WIRED TO REAL SDK

- `main.dart` → `app.dart` → initializes SDK on startup (Base Sepolia config), routes to loading/error/onboarding/home
- `theme.dart` — dark theme with green accent (RedPillTheme)
- `screens/onboarding/onboarding_screen.dart` — **wired to real Go SDK**: `createWallet()` generates real BIP-39 mnemonic, shows backup screen with numbered words, `importWalletMnemonic()` for recovery
- `screens/home/home_screen.dart` — **wired to real SDK**: live wallet address + balance from chain, live model listing from active models endpoint, MAX Privacy toggle filters to TEE-only, model tiles with TEE badges
- `lib/services/bridge.dart` — dart:ffi bridge to Go c-shared library
- **Flutter 3.41.5** installed via Homebrew
- `flutter analyze` → zero issues
- Dependencies: `ffi: ^2.1.0`, `path_provider: ^2.1.0`
- CocoaPods installed via Homebrew (required for `path_provider` macOS plugin)

### Project Files

- `LICENSE` — MIT, copyright ABSGrafx
- `README.md` — updated for absgrafx org
- `Makefile` — go-test, go-macos (c-shared build), flutter-macos, run-macos targets
- `.gitignore` — Go vendor, Flutter build, IDE, secrets
- Entitlements: `com.apple.security.network.client` added for outbound RPC

---

## What's NOT Done Yet (next steps)

### Immediate — Phase 0 Cleanup

1. **Clean up legacy packages** — Remove or deprecate `internal/core/`, `internal/orchestrator/` now that SDK handles everything

2. **Improve MAX Privacy toggle UX** — "Off" state now has TEE hint badge, but could be further improved with animation or explainer tooltip

### Phase 1 — Browse + Chat (next major phase)

1. **Model detail screen** — Tap a model to see bids, providers, pricing
2. **Open a session** — Wire `OpenSession()` to UI, MOR approval flow
3. **Chat screen** — Streaming responses via `SendPrompt()`, markdown rendering
4. **TEE verification indicator** — Green shield for attested providers
5. **iOS build** — `.xcframework` via gomobile, Face ID for key access

See `.ai-docs/redpill_plan.md` for full phase breakdown.

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
2. **Embedded SDK, no HTTP** — RedPill imports `proxy-router/mobile` directly. No separate process, no REST API, no network hop. True embedded Go integration.
3. **BadgerDB is provider-only** — SDK uses in-memory storage for session tracking. Local persistence is SQLite (conversations, preferences) at the app layer.
4. **absgrafx org** — Personal project under MIT license, bolted on top of MorpheusAIs.
5. **Consumer-only** — No provider code, no IPFS, no Docker, no local LLM hosting.
6. **Private key export** — Available via `ExportPrivateKey()`, UI should gate behind biometric re-auth.
7. **Active models via HTTP, not blockchain** — Model listings fetched from Marketplace API's `active_models.json` (same source as Morpheus-Marketplace-API `DirectModelService`). 5-min cache, SHA-256 hash invalidation, blockchain Multicall as fallback. Much faster and more reliable for mobile.
8. **c-shared over gomobile** — dart:ffi with `//export` C functions gives more control than gomobile bind. Works for macOS `.dylib`, iOS `.xcframework`, Android `.so`.

---

## File Tree (key files)

```
RedPill/
├── .ai-docs/
│   ├── redpill_architecture.md
│   ├── redpill_plan.md
│   └── handoff_context.md         # THIS FILE
├── build/
│   └── go/
│       └── libredpill.dylib       # c-shared library (built, not committed)
├── go/
│   ├── go.mod                     # github.com/absgrafx/redpill, go 1.26
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
│   │   └── bridge.dart            # dart:ffi bindings to Go c-shared lib
│   └── screens/
│       ├── onboarding/
│       │   └── onboarding_screen.dart  # Real wallet create/import
│       └── home/
│           └── home_screen.dart        # Live balance, models, TEE toggle
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
    └── mobile/
        ├── sdk.go                        # SDK + active models HTTP cache
        ├── types.go                      # Public types (Model w/ ModelType, Session, etc.)
        └── storage.go                    # In-memory KeyValueStorage
```
