# RedPill — Architecture

> A mobile-first, privacy-maximizing client for the MorpheusAIs decentralized AI network.
> "The Signal of decentralized AI inference."

---

## Vision

Replace the bloated Electron desktop app and the Swagger-driven developer experience with a **single, tightly integrated binary** that embeds the proxy-router, an orchestration layer, and a beautiful UI — running on phones, tablets, and desktops from a single codebase.

A user installs RedPill, creates (or imports) a wallet secured by their device biometrics, stakes MOR, picks a model, and chats. That's it. No IPFS. No Docker. No localhost ports. No Swagger. The proxy-router is embedded, not a separate process.

---

## Design Principles

1. **Embedded, not orchestrated** — The Go proxy-router code compiles into the app binary via gomobile/FFI. No separate process, no HTTP localhost, no port conflicts.
2. **Consumer-only** — This is NOT a provider tool. Strip all provider-side code, IPFS, Docker, local LLM hosting.
3. **Mobile-first** — iOS and Android are first-class. Desktop (macOS first) is a bonus, not an afterthought.
4. **Platform-native security** — Private keys live in the platform's secure enclave (iOS Keychain, Android Keystore). Auth via Face ID / Touch ID / fingerprint. Never roll our own crypto storage.
5. **Smart orchestration** — Don't just expose raw proxy-router endpoints. Add an orchestration layer that provides consumer-friendly operations (active models, provider health, one-tap session creation).
6. **Upstream dependency, not fork** — Reference `github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router` as a Go module dependency. Don't copy code. When upstream ships TEE improvements, we inherit them.

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                       │
│                                                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │
│  │  Onboarding │  │   Models   │  │   Chat + History   │  │
│  │  Wallet     │  │ Marketplace│  │   Streaming        │  │
│  │  Biometric  │  │  TEE Badge │  │   Local persist    │  │
│  └────────────┘  └────────────┘  └────────────────────┘  │
│                         │                                 │
│              dart:ffi (direct function calls)             │
│                         │                                 │
├─────────────────────────────────────────────────────────┤
│                 Orchestrator (Go)                         │
│                                                           │
│  Smarter API surface for consumers:                      │
│  • ActiveModels() — filtered, enriched, cached           │
│  • QuickSession(modelID) — approve + initiate in one op  │
│  • ProviderHealth(addr) — ping + TEE status + latency    │
│  • ChatStream(sessionID, prompt) — SSE with auto-recheck │
│  • WalletSummary() — MOR + ETH balances, staking info   │
│                                                           │
│  Borrows patterns from the API Gateway's consolidated    │
│  endpoints, minus multi-user/billing/auth overhead.      │
├─────────────────────────────────────────────────────────┤
│               Core (Go — proxy-router)                   │
│                                                           │
│  Imported as a Go module dependency:                     │
│  github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router│
│                                                           │
│  ┌────────┐ ┌───────────┐ ┌──────────┐ ┌─────────────┐  │
│  │ Wallet │ │ Blockchain│ │ Sessions │ │ Attestation │  │
│  │  mgmt  │ │  + MOR    │ │ + MOR-RPC│ │  Verifier   │  │
│  └────────┘ └───────────┘ └──────────┘ └─────────────┘  │
│                                                           │
│  EXCLUDED: IPFS, Docker, local LLM, provider-side code   │
├─────────────────────────────────────────────────────────┤
│                   Store (Go — SQLite)                    │
│                                                           │
│  Embedded SQLite via go-sqlite3 (CGo) or modernc-sqlite  │
│  • Chat history (conversations, messages, timestamps)    │
│  • Model cache (avoid re-fetching every launch)          │
│  • Session cache (active sessions, provider mappings)    │
│  • User preferences (theme, default model, etc.)         │
│  Compiled into the same binary — no external DB process. │
├─────────────────────────────────────────────────────────┤
│                   Platform Layer                         │
│                                                           │
│  iOS:    Keychain Services, Secure Enclave, Face ID      │
│  Android: Keystore, BiometricPrompt, StrongBox           │
│  macOS:  Keychain, Touch ID                              │
│                                                           │
│  Private keys stored encrypted in platform secure store. │
│  Biometric required to sign transactions.                │
│  App-level PIN as fallback.                              │
└─────────────────────────────────────────────────────────┘
```

---

## Tight Integration — Why Not HTTP Localhost

The current `ui-desktop` runs the proxy-router as a separate process on `localhost:8082` and talks to it over HTTP + IPC. This causes real-world problems:

| Problem | HTTP localhost | Embedded (gomobile FFI) |
|---------|---------------|------------------------|
| Port conflicts | Another app on :8082 → broken | No ports. Direct function calls. |
| Process management | "Is the service running?" race conditions | Single process. Always available. |
| Mobile background | iOS kills background HTTP servers | Library call — lives with the app. |
| Startup latency | Wait for HTTP server to bind | Instant. Init() on app launch. |
| Error handling | HTTP status codes, JSON parsing | Go error returns, type-safe. |
| Security | localhost still attackable on some OSes | In-process. No network surface. |

**gomobile compiles Go to:**
- iOS: `.xcframework` (static library)
- Android: `.aar` (native library)
- macOS: `.dylib` or static archive

Flutter calls these via `dart:ffi` (direct memory/function calls, no serialization overhead).

---

## Orchestrator Layer — Smarts from the API Gateway

The raw proxy-router endpoints are "dumb" — `/blockchain/models` returns ALL models (active, inactive, delisted). The API Gateway has smarter consolidated endpoints. We want that intelligence WITHOUT the multi-user, billing, Cognito overhead.

### Key orchestrator functions

**ActiveModels()**
- Calls proxy-router's blockchain model listing
- Filters to active models with available bids
- Enriches with provider TEE status (tag-based)
- Caches for 60s (models don't change per-block)
- Returns sorted by: TEE-attested first, then by stake/reputation

**QuickSession(modelID)**
- Checks MOR balance and allowance
- Auto-approves if needed (with biometric confirmation)
- Finds best provider (TEE-preferred, lowest latency)
- Initiates session
- Returns ready-to-chat session handle
- One function call instead of 4-5 HTTP calls

**ChatStream(sessionID, prompt)**
- Sends prompt via proxy-router's MOR-RPC
- Handles SSE streaming response
- Auto-runs VerifyProviderQuick (per-prompt TEE re-check)
- Persists to local SQLite on completion
- Returns streaming channel to UI

**ProviderHealth(providerAddr)**
- Pings provider
- Checks TEE attestation status
- Returns latency + TEE badge + model availability

**WalletSummary()**
- MOR balance + staked amount
- ETH balance (for gas)
- Active sessions count
- Recent transactions

---

## Data Model — Local SQLite

```sql
-- Conversations (one per model session)
CREATE TABLE conversations (
    id          TEXT PRIMARY KEY,
    model_id    TEXT NOT NULL,
    model_name  TEXT,
    provider    TEXT,
    is_tee      INTEGER DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    title       TEXT  -- auto-generated from first prompt
);

-- Messages within a conversation
CREATE TABLE messages (
    id              TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL REFERENCES conversations(id),
    role            TEXT NOT NULL,  -- 'user' | 'assistant' | 'system'
    content         TEXT NOT NULL,
    tokens_used     INTEGER,
    latency_ms      INTEGER,
    tee_verified    INTEGER DEFAULT 0,
    created_at      INTEGER NOT NULL
);

-- Cached model listing
CREATE TABLE model_cache (
    id          TEXT PRIMARY KEY,
    name        TEXT,
    provider    TEXT,
    is_tee      INTEGER DEFAULT 0,
    tags        TEXT,  -- JSON array
    stake       TEXT,
    updated_at  INTEGER NOT NULL
);

-- User preferences
CREATE TABLE preferences (
    key   TEXT PRIMARY KEY,
    value TEXT
);
```

---

## Security Model

### Key Storage
- **Platform secure enclave** for private key material
- BIP-39 mnemonic generated on first launch or imported
- Private key derived and stored in iOS Keychain / Android Keystore / macOS Keychain
- Key never leaves secure hardware — signing happens inside the enclave

### Authentication
- **Biometric first**: Face ID, Touch ID, fingerprint
- **PIN fallback**: 6-digit PIN encrypted and stored in platform keychain
- **Auto-lock**: After configurable timeout (default 5 min)
- **Transaction signing**: Always requires biometric re-auth

### Network Privacy
- No analytics, no telemetry, no crash reporting to external services
- All traffic is direct: RedPill → Blockchain RPC + MorpheusAIs P2P network
- TEE attestation verified locally by the embedded proxy-router code
- No centralized intermediary ever sees prompts

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | Flutter 3.x (Dart) | Single codebase: iOS, Android, macOS. Native compilation. |
| Go bridge | gomobile + dart:ffi | Compile Go to native library. Direct function calls. |
| Core engine | Go (proxy-router module) | Upstream dependency. Blockchain, sessions, attestation. |
| Orchestrator | Go | Smart consumer API on top of raw proxy-router calls. |
| Local DB | SQLite (modernc.org/sqlite) | Pure-Go SQLite. No CGo. Embedded in binary. |
| Keychain | flutter_secure_storage | Platform-native keychain abstraction. |
| Biometrics | local_auth | Face ID / Touch ID / fingerprint. |
| Crypto | web3dart + Go crypto | Signing, key derivation, Ethereum interaction. |

### Why Pure-Go SQLite (modernc.org/sqlite)
- No CGo dependency → simpler cross-compilation for mobile
- Compiles cleanly with gomobile for iOS and Android
- Same behavior as C sqlite3, transpiled to Go

---

## Build Pipeline

```
┌──────────────────────────────────────────────┐
│                 Makefile                       │
├──────────────────────────────────────────────┤
│                                               │
│  make go-ios      → .xcframework (arm64)     │
│  make go-android  → .aar (arm64 + x86_64)   │
│  make go-macos    → .dylib (arm64)           │
│  make go-test     → run Go unit tests        │
│                                               │
│  make flutter-ios    → iOS .ipa              │
│  make flutter-macos  → macOS .app            │
│  make flutter-android → .apk / .aab          │
│                                               │
│  make run-macos   → build Go + run Flutter   │
│  make run-ios     → build Go + run on sim    │
│                                               │
└──────────────────────────────────────────────┘
```

---

## What We Pull From the API Gateway

The MorpheusAIs API Gateway (app.mor.org) has useful patterns we adopt:

| Gateway Pattern | RedPill Equivalent |
|----------------|-------------------|
| Active model listing (filtered, enriched) | `orchestrator.ActiveModels()` |
| Provider selection with scoring | `orchestrator.BestProvider(modelID)` |
| Session lifecycle management | `orchestrator.QuickSession(modelID)` |
| Chat completions endpoint | `orchestrator.ChatStream()` |
| Balance + staking summary | `orchestrator.WalletSummary()` |

**What we DON'T take:**
- Multi-user auth (Cognito, email, API keys)
- Billing (Stripe, usage tracking)
- Centralized C-Node management
- Rate limiting / quota management

---

## Target Platforms (Priority Order)

1. **macOS** (arm64) — development and testing
2. **iOS** (arm64) — primary target, iPhone + iPad
3. **Android** (arm64) — secondary mobile target
4. **macOS** (x86_64) — Intel Mac support
5. **Linux** (x86_64, arm64) — future
6. **Windows** (x86_64) — future

---

## File Structure

```
RedPill/
├── .ai-docs/
│   ├── redpill_architecture.md    ← this file
│   └── redpill_plan.md
├── go/
│   ├── go.mod                     # module github.com/anthropic/redpill/go
│   ├── internal/
│   │   ├── core/                  # Proxy-router integration (thin wrapper)
│   │   │   └── core.go
│   │   ├── orchestrator/          # Smart consumer API layer
│   │   │   ├── models.go          # ActiveModels, BestProvider
│   │   │   ├── sessions.go        # QuickSession, ChatStream
│   │   │   └── wallet.go          # WalletSummary, balances
│   │   └── store/                 # SQLite persistence
│   │       ├── store.go           # DB init, migrations
│   │       ├── conversations.go
│   │       └── cache.go
│   └── mobile/
│       └── api.go                 # gomobile-exported functions (FFI surface)
├── lib/                           # Flutter/Dart
│   ├── main.dart
│   ├── app.dart
│   ├── screens/
│   │   ├── onboarding/            # Wallet create/import
│   │   ├── home/                  # Model list + active sessions
│   │   ├── chat/                  # Chat interface
│   │   └── settings/              # Preferences, wallet info
│   ├── services/
│   │   ├── bridge.dart            # dart:ffi bridge to Go library
│   │   ├── auth.dart              # Biometric + PIN
│   │   └── theme.dart             # Dark/light adaptive
│   └── models/                    # Dart data models
├── ios/                           # iOS project (Xcode)
├── macos/                         # macOS project
├── android/                       # Android project
├── Makefile
├── .gitignore
├── pubspec.yaml
└── README.md
```
