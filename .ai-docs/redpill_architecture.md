# RedPill — Architecture

> A mobile-first, privacy-maximizing client for the **Morpheus** decentralized AI network (published by **absgrafx**).
> "The Signal of decentralized AI inference."
> 
> Part of the [absgrafx](https://github.com/absgrafx) project.

---

## Vision

Replace the bloated Electron desktop app and the Swagger-driven developer experience with a **clean, consumer-grade app** that provides a beautiful UI for the Morpheus network — running on phones, tablets, and desktops from a single codebase.

A user installs RedPill, creates (or imports) a wallet, stakes MOR, picks a model, and chats. That's it. No IPFS. No Docker. No Swagger.

---

## Integration Strategy (current)

RedPill embeds the **proxy-router mobile SDK** (`Morpheus-Lumerin-Node/proxy-router/mobile/`) as a Go module (`replace` to a local fork). There is **no separate proxy-router process** and **no HTTP hop** for consumer operations.

### What the embedded SDK covers
- **Wallet** — create / import mnemonic or private key, address, balances (same crypto stack as upstream: `go-ethereum`, `go-bip39`, etc.)
- **Chain** — JSON-RPC to Base (multi-endpoint round-robin in the SDK’s eth client)
- **Models** — active model list from `active_models.json` (cached) with blockchain fallback
- **Sessions** — open / close / query on-chain sessions; list **unclosed** sessions for the wallet
- **Chat** — `SendPrompt` → internal `SendPromptV2` / MOR-RPC to the provider (streaming aggregated in Go before returning over FFI)

### Flutter ↔ Go
- **dart:ffi** to a **c-shared** library (`libredpill.dylib` / future `.xcframework` / `.so`)
- JSON in/out on the boundary; SQLite for **local** conversations/messages lives in RedPill’s `internal/store` and is driven from `go/mobile/api.go`

### Reference: standalone proxy-router HTTP API
A full **proxy-router** binary exposes the same semantics over REST (e.g. `/v1/chat/completions`, `/blockchain/sessions/...`). That surface is useful for **documentation and parity** with [Morpheus-Marketplace-API](https://github.com/MorpheusAIs/Morpheus-Marketplace-API); RedPill does **not** require it at runtime.

---

## Design Principles

1. **Consumer-only** — This is NOT a provider tool. Strip all provider-side code, IPFS, Docker, local LLM hosting.
2. **Mobile-first** — iOS and Android are first-class. Desktop (macOS first) is a bonus, not an afterthought.
3. **Platform-native security** — Private keys live in the platform's secure enclave (iOS Keychain, Android Keystore). Auth via Face ID / Touch ID / fingerprint. Never roll our own crypto storage.
4. **Smart UX on top of the SDK** — Flutter screens filter models (e.g. MAX Privacy / TEE), surface RPC overrides, and manage on-chain session lists; the SDK still owns chain + provider I/O.
5. **Embedded first** — HTTP client code in `internal/core/proxy_client.go` is **legacy**; the live path is `go/mobile/api.go` → SDK.

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                       │
│                                                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │
│  │  Onboarding │  │   Home     │  │   Chat             │  │
│  │  Wallet     │  │   Models   │  │   SendPrompt       │  │
│  │             │  │   TEE      │  │   (provider stream │  │
│  │             │  │   toggle   │  │    toggle → Go)    │  │
│  └────────────┘  └────────────┘  └────────────────────┘  │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │
│  │  Wallet    │  │  Network   │  │  On-chain sessions │  │
│  │  send/erase│  │  / RPC     │  │  list + close      │  │
│  └────────────┘  └────────────┘  └────────────────────┘  │
│                         │                                 │
│              dart:ffi → c-shared lib (JSON strings)       │
│                         │                                 │
├─────────────────────────────────────────────────────────┤
│           RedPill Go mobile API (`go/mobile/api.go`)      │
│                                                           │
│  • Init / Shutdown, wallet FFI wrappers                  │
│  • SQLite: CreateConversation, SaveMessage (on SendPrompt)│
│  • Delegates chain/session/chat → proxy-router mobile SDK │
├─────────────────────────────────────────────────────────┤
│     Proxy-router mobile SDK (`proxy-router/mobile/`)      │
│                                                           │
│  • Wallet, balance, OpenSession, CloseSession, GetSession │
│  • GetUnclosedUserSessions (paginated, consumer wallet)   │
│  • SendPrompt (stream flag → OpenAI-compatible request)   │
│  • Active models HTTP + registries / proxy sender         │
│                                                           │
│  EXCLUDED: IPFS, Docker, local LLM, provider-node role    │
├─────────────────────────────────────────────────────────┤
│                   Store (Go — SQLite)                     │
│                                                           │
│  modernc.org/sqlite — conversations, messages, prefs      │
│  (Chat **browser** UI = next; persistence on send = yes)   │
├─────────────────────────────────────────────────────────┤
│                   Platform Layer                          │
│                                                           │
│  Keychain / Keystore (mnemonic), Application Support      │
│  (RPC override file, chat_streaming_preference.txt, DB)    │
└─────────────────────────────────────────────────────────┘
```

---

## Parity: proxy-router HTTP API (reference)

When running the **full** proxy-router binary, these routes mirror what the embedded SDK does internally (useful for Marketplace-API / ops tooling; **not** RedPill’s runtime path):

| Endpoint | Method | Role |
|----------|--------|------|
| `/blockchain/sessions/user` | GET | List sessions (SDK: `GetUnclosedUserSessions` / related) |
| `/blockchain/sessions/:id/close` | POST | Close session |
| `/blockchain/models/:id/session` | POST | Open session by model |
| `/v1/chat/completions` | POST | Chat (OpenAI-compatible; SDK: `SendPrompt` / `SendPromptV2`) |
| … | … | See proxy-router OpenAPI / `controller_http.go` |

---

## Consumer smarts (Flutter + `api.go`)

- **Active models** — SDK caches `active_models.json`; home screen applies **MAX Privacy** (TEE-only filter).
- **Sessions** — `OpenSession` per chat (default 1h); **OnChainSessionsScreen** lists unclosed on-chain sessions and **Close** reclaims stake; entry from ⋮ menu, drawer, Network / RPC settings.
- **Chat** — `SendPrompt(sessionID, conversationID, prompt, stream)`; user + assistant rows persisted to SQLite on each completed prompt.
- **RPC** — Optional `eth_rpc_override.txt`; multi-endpoint + backoff in SDK eth client.

**Streaming UI:** With **Streaming reply** on, Dart uses **`SendPromptStream`** + **`NativeCallable.listener`** so provider deltas update the chat before the final JSON returns. Non-streaming mode uses **`SendPrompt`** with `stream: false`.

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
- Traffic is direct: **device → Base RPC + active models HTTP + provider (MOR-RPC)** via the embedded SDK (no separate C-node process in RedPill)
- TEE flows use the same attestation paths as upstream proxy-router where applicable
- No Marketplace-API or central relay in the hot path for chat

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | Flutter 3.x (Dart) | Single codebase: iOS, Android, macOS. Native compilation. |
| Go bridge | **c-shared** + dart:ffi | `//export` C API; `FreeString` + JSON payloads. |
| Chain + inference | **proxy-router/mobile** SDK | Same logic as full node, in-process. |
| Wallet | SDK + secure store | Go wallet in memory; mnemonic in Keychain / Keystore. |
| Local DB | SQLite (modernc.org/sqlite) | Conversations + messages + preferences. |
| Keychain | flutter_secure_storage | Platform-native keychain abstraction. |
| Biometrics | local_auth (planned polish) | Face ID / Touch ID / fingerprint. |

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

## What We Align With (Marketplace / Gateway patterns)

| Gateway / app pattern | RedPill equivalent |
|----------------------|---------------------|
| Curated active models | SDK `active_models.json` cache + home filters |
| Session open / close / list | SDK + `OnChainSessionsScreen` |
| OpenAI-shaped chat | `SendPrompt` → `SendPromptV2` |
| Optional dedicated RPC | `eth_rpc_override.txt` + `chain_config` defaults |

**What we deliberately skip:** Cognito, API keys, billing, multi-tenant gateway as a dependency in the inference path.

---

## Target Platforms (Priority Order)

1. **macOS** (arm64) — development and testing
2. **iOS** (arm64) — primary target, iPhone + iPad
3. **Android** (arm64) — secondary mobile target
4. **Linux** (x86_64, arm64) — future
5. **Windows** (x86_64) — future
