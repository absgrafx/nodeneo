# RedPill — Chat Handoff Context

> Snapshot of project state as of 2026-03-17.
> Use this to bootstrap a new AI chat session in a fresh workspace.

---

## What Is RedPill

A mobile-first client for the [MorpheusAIs](https://github.com/MorpheusAIs) decentralized AI network. Think "Signal for decentralized AI inference." Part of the [absgrafx](https://github.com/absgrafx) org.

- **Flutter** UI (iOS, Android, macOS) in `lib/`
- **Go** backend in `go/` — native wallet + HTTP client to proxy-router
- **SQLite** for local persistence (conversations, messages, preferences)

---

## Repo Locations

| Repo | Purpose |
|------|---------|
| `absgrafx/RedPill` | This app — Flutter UI + Go backend |
| `absgrafx/Morpheus-Lumerin-Node` | Fork of proxy-router — will add `proxy-router/mobile/` SDK |

These two repos should be in the same workspace for the next phase of work.

---

## Current State (what's built and working)

### Go Backend (`go/`)

**Module:** `github.com/absgrafx/redpill` — Go 1.26

**Native wallet (fully working, tested):**
- BIP-39 create (`Engine.CreateWallet()`) → 12-word mnemonic + Ethereum address
- Mnemonic import (`Engine.ImportWallet()`) — deterministic address derivation
- Private key import (`Engine.ImportPrivateKey()`)
- Private key export (`Engine.PrivateKeyHex()`)
- Uses: `go-ethereum`, `go-bip39`, `btcsuite/btcd` — same libs as the proxy-router
- Default derivation path: `m/44'/60'/0'/0/0` (matches proxy-router)
- **5 unit tests pass** in `go/internal/core/core_test.go`

**HTTP proxy client (`go/internal/core/proxy_client.go`):**
- Talks to a running proxy-router instance via REST API
- Endpoints wired: `/blockchain/balance`, `/blockchain/models`, `/blockchain/models/:id/bids/rated`, `/blockchain/models/:id/session`, `/blockchain/sessions/:id/close`, `/v1/chat/completions`, `/healthcheck`
- Configurable base URL (default `http://localhost:8082`)

**Orchestrator (`go/internal/orchestrator/orchestrator.go`):**
- `ActiveModels(ctx, teeOnly bool)` — cached 60s, filters deleted, sorts TEE-first then LLM-first, MAX Privacy filter
- `QuickSession()` — delegates to proxy-router's OpenSessionByModelId
- `ChatStream()` — sends prompt, persists to SQLite
- `GetWalletSummary()` — address + balances
- `ProxyReachable()` — healthcheck

**SQLite store (`go/internal/store/store.go`):**
- Tables: `conversations`, `messages`, `model_cache`, `preferences`
- WAL mode enabled
- CRUD for conversations, messages, preferences

**Mobile API (`go/mobile/api.go`):**
- `Init(dataDir, proxyBaseURL)`, `Shutdown()`, `IsReady()`, `IsProxyReachable()`
- `CreateWallet()`, `ImportWalletMnemonic()`, `ImportWalletPrivateKey()`, `ExportPrivateKey()`, `GetWalletSummary()`
- `GetActiveModels(teeOnly)`, `GetRatedBids(modelID)`
- `QuickOpenSession()`, `CloseSession()`
- `SendPrompt()`, `GetConversations()`, `GetMessages()`
- `SetPreference()`, `GetPreference()`
- All return JSON strings

### Flutter Frontend (`lib/`)

- `main.dart` → `app.dart` → routes to onboarding or home
- `theme.dart` — dark theme with green accent (RedPillTheme)
- `screens/onboarding/onboarding_screen.dart` — create/import wallet UI (not yet wired to Go)
- `screens/home/home_screen.dart` — wallet card, MAX Privacy toggle, model list with TEE badges
- `test/widget_test.dart` — basic smoke test
- **Flutter 3.41.5** installed via Homebrew
- **Xcode** configured (`xcodebuild -runFirstLaunch` done)
- `flutter analyze` → zero issues

### Project Files

- `LICENSE` — MIT, copyright ABSGrafx
- `README.md` — updated for absgrafx org
- `.ai-docs/redpill_architecture.md` — full architecture doc
- `.ai-docs/redpill_plan.md` — phased plan with progress tracking
- `Makefile` — go-test, go-macos, flutter-macos, run-macos targets
- `.gitignore` — Go vendor, Flutter build, IDE, secrets

---

## What's NOT Done Yet (next steps)

### Immediate — Phase 0 Remaining

1. **Fork SDK** — In `absgrafx/Morpheus-Lumerin-Node`, create `proxy-router/mobile/` package:
   - This package lives INSIDE the proxy-router module so it CAN import `internal/` packages
   - It re-exports key types/functions through its own public API
   - RedPill then imports `github.com/absgrafx/Morpheus-Lumerin-Node/proxy-router/mobile` directly
   - This eliminates the HTTP intermediary — true embedded Go integration

2. **Wire dart:ffi bridge** — Connect Flutter UI to Go library
   - Build Go as c-shared `.dylib` (macOS) / `.xcframework` (iOS)
   - Create `lib/services/bridge.dart` with ffi bindings
   - NOTE: Previous c-shared build triggered antivirus false positive (OSX/CoinMiner.ext) due to go-ethereum crypto code — may need to whitelist the build output

3. **Connect onboarding screen** to real wallet create/import

4. **Connect home screen** to real model listing from proxy-router

### The `internal/` Problem (why we need the fork)

The proxy-router's Go code is ALL under `proxy-router/internal/` which Go locks to same-module imports only. External modules (like RedPill) cannot import them. The fork solves this by adding a `proxy-router/mobile/` package that:
- Is part of the same module → can import `internal/`
- Exports public types/functions → RedPill can import them
- Acts as a thin SDK wrapper

Key proxy-router packages we need access to:
- `internal/repositories/wallet/` — wallet management (we already replicated this natively)
- `internal/blockchainapi/` — BlockchainService (models, sessions, balances, MOR approval)
- `internal/proxyapi/` — ProxyServiceSender (chat completions, MOR-RPC)
- `internal/repositories/ethclient/` — Ethereum RPC client
- `internal/repositories/registries/` — model registry, session router, marketplace
- `internal/storages/` — Badger-based session storage
- `internal/repositories/multicall/` — batch contract calls
- `internal/lib/` — utilities, logger, HexString
- `internal/config/` — configuration structs

The initialization sequence (from `proxy-router/cmd/main.go`):
1. Config → loggers → keychain → Badger storage → auth config
2. ETH client → session storage → wallet
3. Multicall → registries (SessionRouter, Marketplace)
4. SessionRepo → ProxySender → BlockscoutExplorer → Rating
5. BlockchainService → wire ProxySender.SetSessionService()

### Phase 1+ (after fork SDK is working)

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

1. **MAX Privacy mode** — Toggle in UI that filters to TEE-only providers. Wired through Go orchestrator (`teeOnly` flag on `ActiveModels()`).
2. **Two-tier integration** — Native Go for wallet (no proxy-router needed), HTTP client for blockchain/session/chat (talks to proxy-router REST API). Fork SDK will eliminate the HTTP layer.
3. **absgrafx org** — Personal project under MIT license, bolted on top of MorpheusAIs.
4. **Consumer-only** — No provider code, no IPFS, no Docker, no local LLM hosting.
5. **Private key export** — Available via `ExportPrivateKey()`, UI should gate behind biometric re-auth.

---

## File Tree (key files)

```
RedPill/
├── .ai-docs/
│   ├── redpill_architecture.md    # Full design doc
│   ├── redpill_plan.md            # Phased plan with progress
│   └── handoff_context.md         # THIS FILE
├── go/
│   ├── go.mod                     # github.com/absgrafx/redpill, go 1.26
│   ├── go.sum
│   ├── internal/
│   │   ├── core/
│   │   │   ├── core.go            # Engine + native wallet + delegated ops
│   │   │   ├── core_test.go       # 5 passing wallet tests
│   │   │   └── proxy_client.go    # HTTP client for proxy-router REST API
│   │   ├── orchestrator/
│   │   │   └── orchestrator.go    # Smart API (ActiveModels, QuickSession, etc.)
│   │   └── store/
│   │       └── store.go           # SQLite persistence
│   └── mobile/
│       └── api.go                 # gomobile-exported API surface
├── lib/                           # Flutter/Dart
│   ├── main.dart
│   ├── app.dart
│   ├── theme.dart                 # Dark theme + RedPillTheme colors
│   └── screens/
│       ├── onboarding/
│       │   └── onboarding_screen.dart
│       └── home/
│           └── home_screen.dart   # Wallet card + MAX Privacy toggle + model list
├── test/
│   └── widget_test.dart
├── macos/                         # Flutter macOS project
├── ios/                           # Flutter iOS project
├── android/                       # Flutter Android project
├── Makefile
├── LICENSE                        # MIT, ABSGrafx
├── README.md
├── .gitignore
└── pubspec.yaml
```
