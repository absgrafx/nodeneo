# RedPill — Architecture

> A mobile-first, privacy-maximizing client for the MorpheusAIs decentralized AI network.
> "The Signal of decentralized AI inference."
> 
> Part of the [absgrafx](https://github.com/absgrafx) project.

---

## Vision

Replace the bloated Electron desktop app and the Swagger-driven developer experience with a **clean, consumer-grade app** that provides a beautiful UI for the MorpheusAIs network — running on phones, tablets, and desktops from a single codebase.

A user installs RedPill, creates (or imports) a wallet, stakes MOR, picks a model, and chats. That's it. No IPFS. No Docker. No Swagger.

---

## Integration Strategy

RedPill uses a **two-tier approach** to integrate with the proxy-router:

### Tier 1 — Native Go (wallet operations)
Wallet creation, mnemonic import, private key import, and key derivation are implemented natively in Go using the same upstream libraries the proxy-router uses (`go-ethereum`, `go-bip39`, `btcsuite`). This gives us:
- Zero dependency on a running proxy-router for wallet ops
- Deterministic, testable key derivation
- Same addresses and key formats as the proxy-router

### Tier 2 — HTTP Client (blockchain/session/chat)
Blockchain queries, session management, and chat completions are delegated to a running proxy-router instance via its REST API. The proxy-router's packages are all under `internal/` (Go import restriction), so we talk to it as an HTTP service.

### Future — Forked SDK (planned)
A fork of `MorpheusAIs/Morpheus-Lumerin-Node` into `absgrafx/Morpheus-Lumerin-Node` will add a `proxy-router/mobile/` public SDK package that wraps the internal packages. This will let RedPill import the proxy-router directly as a Go module dependency — eliminating the HTTP intermediary for a true embedded integration.

---

## Design Principles

1. **Consumer-only** — This is NOT a provider tool. Strip all provider-side code, IPFS, Docker, local LLM hosting.
2. **Mobile-first** — iOS and Android are first-class. Desktop (macOS first) is a bonus, not an afterthought.
3. **Platform-native security** — Private keys live in the platform's secure enclave (iOS Keychain, Android Keystore). Auth via Face ID / Touch ID / fingerprint. Never roll our own crypto storage.
4. **Smart orchestration** — Don't just expose raw proxy-router endpoints. Add an orchestration layer that provides consumer-friendly operations (active models, provider health, one-tap session creation).
5. **Incremental integration** — Start with HTTP client → evolve to embedded once the fork SDK is ready.

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
│  • ChatStream(sessionID, prompt) — with auto-persist     │
│  • WalletSummary() — MOR + ETH balances, staking info   │
│  • ProxyReachable() — is the proxy-router running?       │
│                                                           │
│  Borrows patterns from the API Gateway's consolidated    │
│  endpoints, minus multi-user/billing/auth overhead.      │
├─────────────────────────────────────────────────────────┤
│               Core (Go)                                   │
│                                                           │
│  NATIVE (no proxy-router needed):                        │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Wallet: BIP-39 create, mnemonic import, key import │  │
│  │ Uses: go-ethereum, go-bip39, btcsuite              │  │
│  └────────────────────────────────────────────────────┘  │
│                                                           │
│  VIA HTTP CLIENT (talks to proxy-router REST API):       │
│  ┌────────┐ ┌───────────┐ ┌──────────┐ ┌────────────┐  │
│  │ Models │ │ Blockchain│ │ Sessions │ │    Chat    │  │
│  │  list  │ │  balance  │ │ open/cls │ │ completions│  │
│  └────────┘ └───────────┘ └──────────┘ └────────────┘  │
│                                                           │
│  EXCLUDED: IPFS, Docker, local LLM, provider-side code   │
├─────────────────────────────────────────────────────────┤
│                   Store (Go — SQLite)                    │
│                                                           │
│  Embedded SQLite via modernc.org/sqlite (pure Go)        │
│  • Chat history (conversations, messages, timestamps)    │
│  • Model cache (avoid re-fetching every launch)          │
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
└─────────────────────────────────────────────────────────┘
```

---

## Proxy-Router HTTP API Surface

The proxy-router runs on a configurable port (default `:8082`) and exposes these endpoints that RedPill consumes:

| Endpoint | Method | RedPill Use |
|----------|--------|-------------|
| `/blockchain/balance` | GET | Wallet ETH+MOR balance |
| `/blockchain/models` | GET | List all models |
| `/blockchain/models/:id/bids/rated` | GET | Best providers for a model |
| `/blockchain/models/:id/session` | POST | Open session by model |
| `/blockchain/sessions/:id/close` | POST | Close session |
| `/blockchain/sessions/user` | GET | Active user sessions |
| `/v1/chat/completions` | POST | Chat (OpenAI-compatible) |
| `/healthcheck` | GET | Liveness probe |

---

## Orchestrator Layer — Smarts from the API Gateway

The raw proxy-router endpoints are "dumb" — `/blockchain/models` returns ALL models (active, inactive, delisted). The API Gateway has smarter consolidated endpoints. We want that intelligence WITHOUT the multi-user, billing, Cognito overhead.

### Key orchestrator functions

**ActiveModels()**
- Calls proxy-router's blockchain model listing
- Filters to non-deleted models
- Sorts by: LLM first, then alphabetically
- Caches for 60s

**QuickSession(modelID, duration)**
- Delegates to proxy-router's `OpenSessionByModelId`
- Proxy-router handles MOR approval, bid selection, provider handshake
- One function call instead of multiple HTTP roundtrips

**ChatStream(sessionID, modelID, prompt)**
- Sends prompt via proxy-router's chat completions endpoint
- Persists exchange to local SQLite
- Returns full response (streaming in later phase)

**WalletSummary()**
- MOR + ETH balances from proxy-router
- Address from native wallet

---

## Data Model — Local SQLite

```sql
CREATE TABLE conversations (
    id          TEXT PRIMARY KEY,
    model_id    TEXT NOT NULL,
    model_name  TEXT,
    title       TEXT,
    is_tee      INTEGER DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

CREATE TABLE messages (
    id              TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL REFERENCES conversations(id),
    role            TEXT NOT NULL,
    content         TEXT NOT NULL,
    created_at      INTEGER NOT NULL
);

CREATE TABLE model_cache (
    id          TEXT PRIMARY KEY,
    name        TEXT,
    tags        TEXT,
    stake       TEXT,
    updated_at  INTEGER NOT NULL
);

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
- Private key derived using the same path as proxy-router (`m/44'/60'/0'/0/0`)
- Key stored in iOS Keychain / Android Keystore / macOS Keychain

### Authentication
- **Biometric first**: Face ID, Touch ID, fingerprint
- **PIN fallback**: 6-digit PIN
- **Auto-lock**: After configurable timeout (default 5 min)
- **Transaction signing**: Always requires biometric re-auth

### Network Privacy
- No analytics, no telemetry, no crash reporting
- All traffic is direct: RedPill → proxy-router → Blockchain + P2P
- TEE attestation verified by the proxy-router
- No centralized intermediary ever sees prompts

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | Flutter 3.x (Dart) | Single codebase: iOS, Android, macOS. Native compilation. |
| Go bridge | gomobile + dart:ffi | Compile Go to native library. Direct function calls. |
| Core wallet | Go (go-ethereum, go-bip39) | Native key derivation, same as proxy-router. |
| Core blockchain | HTTP client → proxy-router | Access internal packages via REST API (for now). |
| Orchestrator | Go | Smart consumer API on top of raw proxy-router calls. |
| Local DB | SQLite (modernc.org/sqlite) | Pure-Go SQLite. No CGo. Embedded in binary. |
| Keychain | flutter_secure_storage | Platform-native keychain abstraction. |
| Biometrics | local_auth | Face ID / Touch ID / fingerprint. |

---

## Build Pipeline

```
┌──────────────────────────────────────────────┐
│                 Makefile                       │
├──────────────────────────────────────────────┤
│                                               │
│  make go-test     → run Go unit tests        │
│  make go-macos    → .dylib (arm64)           │
│  make go-ios      → .xcframework (arm64)     │
│  make go-android  → .aar (arm64 + x86_64)   │
│                                               │
│  make flutter-macos  → macOS .app            │
│  make flutter-ios    → iOS .ipa              │
│  make flutter-android → .apk / .aab          │
│                                               │
│  make run-macos   → build Go + run Flutter   │
│  make run-ios     → build Go + run on sim    │
│                                               │
└──────────────────────────────────────────────┘
```

---

## What We Pull From the API Gateway

| Gateway Pattern | RedPill Equivalent |
|----------------|-------------------|
| Active model listing (filtered, enriched) | `orchestrator.ActiveModels()` |
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
4. **Linux** (x86_64, arm64) — future
5. **Windows** (x86_64) — future
