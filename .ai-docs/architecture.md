# Node Neo — Architecture

> A mobile-first, privacy-maximizing client for the **Morpheus** decentralized AI network (published by **absgrafx**).
> "The Signal of decentralized AI inference."
> 
> Part of the [absgrafx](https://github.com/absgrafx) project.

---

## Vision

Node Neo is **the Signal of decentralized AI** — a clean, consumer-grade app that makes the Morpheus network accessible to everyone, not just developers.

A user installs Node Neo, creates a wallet, stakes MOR, picks a model, and chats. That's it. No IPFS. No Docker. No Swagger. No terminal.

### Audience

**Node Neo is for the general public.** The person who wants private AI inference but has no interest in running infrastructure. The same audience that uses Signal instead of self-hosting a Morpheus consumer node server.

Node Neo is **not** for:
- **Infrastructure operators** running compute nodes → [mor.org](https://mor.org) / [tech.mor.org](https://tech.mor.org) for C-node setup
- **Developers building on the Morpheus API** → [api.mor.org](https://api.mor.org) for the hosted Marketplace API
- **Protocol researchers** → [MorpheusAIs](https://github.com/MorpheusAIs) repos for smart contracts, tokenomics, and protocol specs

These are complementary projects in the Morpheus ecosystem. Node Neo is the **consumer endpoint** — the last mile between the network and a human who just wants to chat privately.

---

## Integration Strategy (current)

Node Neo embeds the **proxy-router mobile SDK** (`Morpheus-Lumerin-Node/proxy-router/mobile/`) as a Go module (`replace` to a local fork). There is **no separate proxy-router process** and **no HTTP hop** for consumer operations.

### What the embedded SDK covers
- **Wallet** — create / import mnemonic or private key, address, balances (same crypto stack as upstream: `go-ethereum`, `go-bip39`, etc.)
- **Chain** — JSON-RPC to Base (multi-endpoint round-robin in the SDK’s eth client)
- **Models** — active model list from `active_models.json` (cached) with blockchain fallback
- **Sessions** — open / close / query on-chain sessions; list **unclosed** sessions for the wallet
- **Chat** — `SendPrompt` → internal `SendPromptV2` / MOR-RPC to the provider (streaming aggregated in Go before returning over FFI)

### Flutter ↔ Go (Async FFI Bridge)
- **dart:ffi** to a **c-shared** library (`libnodeneo.dylib` / future `.xcframework` / `.so`)
- JSON in/out on the boundary; SQLite for **local** conversations/messages lives in Node Neo’s `internal/store` and is driven from `go/mobile/api.go`
- **Streaming uses a signal + fetch pattern** to avoid FFI use-after-free:
  - Go stores delta text in a thread-safe map (`deltaStoreM`) keyed by `int64` ID (atomic counter)
  - Go invokes Dart’s `NativeCallable.listener` with the ID only (not a `char*` pointer)
  - Dart synchronously calls `ReadStreamDelta(id)` to fetch the string while Go guarantees it is alive
  - Dart frees the C-allocated string after copying to a Dart `String`
- **Async wrappers** (`SendPromptWithOptionsAsync`, `SendPromptStreamAsync`) run the SDK call in a Go goroutine, signalling Dart via callbacks when deltas arrive and when the call completes
- **Chat tuning parameters** (temperature, top_p, max_tokens, frequency/presence penalty) are passed through the FFI as JSON, converted to `ChatParams` in Go, and forwarded to the SDK
- **Response metadata**: SDK returns the full provider response as `json.RawMessage`; Go mobile layer stores it in SQLite alongside the assistant message; Dart UI renders summary rows and raw JSON

### Expert Mode HTTP API (embedded Swagger)
Node Neo can optionally start the proxy-router's Swagger HTTP API for developers and debugging. The embedded version uses **selective route registration** — only routes with satisfied dependencies are exposed (blockchain, wallet, proxy chat/models/agents/audio, healthcheck). System config, IPFS, chat history, auth agent management, and Docker routes are excluded to prevent nil-pointer crashes. Authentication uses auto-generated HTTP Basic Auth credentials (16-char random password, displayed in Expert screen with masked reveal/copy).

### Reference: standalone proxy-router HTTP API
A full **proxy-router** binary exposes the same semantics over REST (e.g. `/v1/chat/completions`, `/blockchain/sessions/...`). That surface is useful for **documentation and parity** with [Morpheus-Marketplace-API](https://github.com/MorpheusAIs/Morpheus-Marketplace-API); Node Neo does **not** require it at runtime.

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
│  │ Preferences│  │  Wallet    │  │  Backup & Reset    │  │
│  │ Sys Prompt │  │  Keys      │  │  Export/Import     │  │
│  │ Tuning     │  │  MOR Scan  │  │  Erase/Factory     │  │
│  │ Duration   │  │  Sessions  │  │  Reset             │  │
│  │ Security   │  │            │  │                    │  │
│  └────────────┘  └────────────┘  └────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Expert Mode (accordion sections):                  │  │
│  │  • Blockchain Connection — RPC endpoint config      │  │
│  │  • Developer API — Swagger/REST server              │  │
│  │  • AI Gateway — OpenAI-compatible + API keys        │  │
│  └─────────────────────────────────────────────────────┘  │
│                         │                                 │
│              dart:ffi → c-shared lib (JSON strings)       │
│                         │                                 │
├─────────────────────────────────────────────────────────┤
│           Node Neo Go mobile API (`go/mobile/api.go`)      │
│                                                           │
│  • Init / Shutdown, wallet FFI wrappers                  │
│  • OpenWalletDatabase (fingerprinted), SetEncryptionKey  │
│  • SQLite: CreateConversation, SaveMessage (on SendPrompt)│
│  • ExportBackup / ImportBackup (encrypted .nnbak)        │
│  • Delegates chain/session/chat → proxy-router mobile SDK │
│  • Gateway: StartGateway, StopGateway, GatewayStatus     │
│  • API Keys: GenerateAPIKey, ListAPIKeys, RevokeAPIKey   │
│  • Expert API: auto-gen admin creds, GetCredentials, Reset│
│  • MOR Scanner: ScanWalletMOR, WithdrawUserStakes        │
├─────────────────────────────────────────────────────────┤
│          API Gateway (`go/internal/gateway/`)             │
│                                                           │
│  • OpenAI-compatible HTTP server (configurable port)     │
│  • POST /v1/chat/completions — streaming + non-streaming │
│  • GET  /v1/models — cached from active.mor.org          │
│  • GET  /health — unauthenticated health check           │
│  • Bearer token auth, CORS, request logging              │
│  • Automatic session management (resolve → reuse → open) │
│  • Conversations persisted with source:"api" for UI      │
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
│  modernc.org/sqlite — wallet-scoped: nodeneo_{fp}.db     │
│  AES-256-GCM: message content, metadata, conv titles     │
│  api_keys table — bcrypt-hashed Bearer tokens             │
│  conversations.source column — "ui" or "api" origin       │
│  backup.go — export/import encrypted zip archives         │
├─────────────────────────────────────────────────────────┤
│                   Platform Layer                          │
│                                                           │
│  Keychain / Keystore (private key or mnemonic)            │
│  Application Support (wallet-scoped DBs, RPC override,    │
│  preferences, logs, .nnbak export files)                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              MCP Server (`mcp-server/`)                   │
│                                                           │
│  TypeScript stdio process — @modelcontextprotocol/sdk    │
│  • morpheus_models tool — list available models          │
│  • morpheus_chat tool — send prompts to Morpheus models  │
│  • Calls gateway HTTP API on localhost (fully local)     │
│  • Configured via .cursor/mcp.json for Cursor/Claude     │
│                                                           │
│  Cursor Agent ←stdio→ MCP Server ←HTTP→ Gateway ←SDK→    │
│                                        Morpheus Network   │
└─────────────────────────────────────────────────────────┘
```

---

## Parity: proxy-router HTTP API (reference)

When running the **full** proxy-router binary, these routes mirror what the embedded SDK does internally (useful for Marketplace-API / ops tooling; **not** Node Neo’s runtime path):

| Endpoint | Method | Role |
|----------|--------|------|
| `/blockchain/sessions/user` | GET | List sessions (SDK: `GetUnclosedUserSessions` / related) |
| `/blockchain/sessions/:id/close` | POST | Close session |
| `/blockchain/models/:id/session` | POST | Open session by model |
| `/v1/chat/completions` | POST | Chat (OpenAI-compatible; SDK: `SendPrompt` / `SendPromptV2`) |
| … | … | See proxy-router OpenAPI / `controller_http.go` |

---

## Onboarding & Wallet

**PK-first approach**: New wallets are generated internally (BIP-39 for entropy), but only the derived private key is shown to the user — masked by default (first 4 + last 4 chars visible, rest as bullets), with Reveal and Copy buttons. Framed as "treat it like a password." The mnemonic is discarded; only the PK is saved to keychain.

**Import**: Supports both private key (default tab) and recovery phrase (secondary toggle for crypto-native users migrating from MetaMask, etc.). Mnemonic imports are saved to keychain and derive the encryption key from the mnemonic.

**Cold start**: `app.dart` tries `readMnemonic()` first (backward compat), then `readPrivateKey()`. Both paths derive the encryption key via SHA-256 and open the wallet-scoped DB.

## Settings UI Pattern

All settings screens use a consistent **accordion layout** via the shared `SectionCard` widget (`lib/widgets/section_card.dart`):

- **`SectionCard`** — Collapsible card with icon, title, optional `StatusPill`, animated expand/collapse. Supports `accentColor` (emerald default, amber for keys, red for danger zone).
- **`StatusPill`** — Compact pill with colored dot + label (e.g., "Running :8083", "Stopped", "10 min", "None").
- **`InfoBox`** — Dark container with left accent bar for URLs, paths, and config snippets.

All sections collapsed by default — each screen opens as a clean dashboard of status pills.

| Screen | Sections |
|--------|----------|
| Preferences | System Prompt · Default Tuning · Session Duration · Security (app lock, biometrics, iCloud Keychain) |
| Wallet | Key Management · Where's My MOR (on-chain balance scanner + recover) · Active Sessions |
| Expert Mode | Blockchain Connection · Developer API · AI Gateway |
| Backup & Reset | Data Backup (export/import .nnbak) · Danger Zone (erase wallet, factory reset) |
| Version & Logs | About · Logs |

---

## Consumer smarts (Flutter + `api.go`)

- **Active models** — SDK caches `active_models.json`; home screen applies **MAX Privacy** (TEE-only filter).
- **Sessions** — `OpenSession` per chat (default 1h); **OnChainSessionsScreen** lists unclosed on-chain sessions and **Close** reclaims stake; entry from ⋮ menu, drawer, Network / RPC settings.
- **Chat** — `SendPrompt(sessionID, conversationID, prompt, stream)`; user + assistant rows persisted to SQLite on each completed prompt.
- **RPC** — Optional `eth_rpc_override.txt`; multi-endpoint + backoff in SDK eth client.

**System prompts:** Configurable at two levels: a **default system prompt** (Settings → Preferences → System Prompt) applied to all new conversations, and a **per-conversation override** in the Chat Tuning panel. Stored in the `system_prompt` column on `conversations` (encrypted at rest). Prepended as an OpenAI `system` role message before the chat history when sending prompts to the provider.

**MOR balance scanner:** The Wallet screen includes a "Where's My MOR" section that performs read-only on-chain lookups showing MOR across three buckets: wallet balance, active session stake, and on-hold (early-close timelock). Makes raw JSON-RPC `eth_call` requests to the MOR token contract and Inference Contract (`0x6aBE...030a`) on Base mainnet, using the same RPC endpoint(s) the SDK uses. A "Recover claimable MOR" button sends a `withdrawUserStakes` transaction to reclaim tokens past the timelock period.

**Streaming UI:** With **Streaming reply** on (default), Dart uses **`SendPromptWithOptionsAsync`** with `stream: true` and **`NativeCallable.listener`** so provider deltas update the chat bubble in real time (~30fps UI throttle, `jumpTo` scrolling). Non-streaming mode uses **`SendPromptWithOptionsAsync`** with `stream: false`. Both paths support chat tuning parameters (temperature, top_p, max_tokens, frequency/presence penalty) and system prompts via per-conversation persistence in SQLite.

**Response metadata:** Each assistant message stores the full raw provider response JSON alongside the text. The Response Info sheet shows summary rows (latency, token counts, finish reason, model) and the complete JSON for debugging.

**Empty responses:** When a provider returns 200 with empty content, the chat shows "No response received — the provider may be busy." as a soft error with a "Tap to retry" button (re-sends the same prompt) and a "Dismiss" option.

**Inference logging:** At DEBUG level, the Go mobile layer logs request details (session, conversation, stream flag, message count, tuning params), response summary (latency, char count, metadata size), and errors. Empty responses are logged at WARN level. Enable DEBUG in Settings → Version & Logs.

**Log level persistence:** The log level setting is saved to SQLite preferences and restored on app restart (applied after the wallet-scoped DB opens). Both the nodeneo wrapper logger and the SDK's internal zap logger are updated atomically.

---

## Data Model — Local SQLite

Database file: `nodeneo_{fingerprint}.db` where fingerprint = first 8 hex chars of wallet address.

```sql
-- 🔒 = column encrypted with AES-256-GCM (enc:v1: prefix), legacy plaintext transparent

CREATE TABLE conversations (
    id          TEXT PRIMARY KEY,
    model_id    TEXT NOT NULL,
    model_name  TEXT,
    title       TEXT,               -- 🔒 encrypted
    is_tee      INTEGER DEFAULT 0,
    source      TEXT DEFAULT 'ui',  -- 'ui' or 'api' (gateway-originated)
    tuning_params TEXT,             -- JSON: per-conversation tuning params
    system_prompt TEXT,             -- 🔒 encrypted (OpenAI system role message)
    session_id  TEXT,               -- on-chain session for resume UX
    pinned      INTEGER DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

CREATE TABLE messages (
    id              TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL REFERENCES conversations(id),
    role            TEXT NOT NULL,
    content         TEXT NOT NULL,   -- 🔒 encrypted
    metadata        TEXT,            -- 🔒 encrypted (provider response JSON)
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

CREATE TABLE api_keys (
    id          TEXT PRIMARY KEY,
    name        TEXT DEFAULT '',
    key_hash    TEXT NOT NULL,       -- bcrypt hash of the full sk-... key
    key_prefix  TEXT NOT NULL,       -- first 12 chars for display
    created_at  INTEGER NOT NULL,
    last_used   INTEGER DEFAULT 0
);
```

---

## Security Model

### Key Storage
- **PK-first approach**: New wallets generate internally, show the private key (masked) for backup — treated like a password
- Private key stored in iOS Keychain / Android Keystore / macOS Keychain via `flutter_secure_storage`
- Legacy mnemonic import supported (recovery phrase toggle on import screen)
- For mnemonic imports: key derived via BIP-44 path `m/44'/60'/0'/0/0`

### Data Encryption at Rest
- **Column-level AES-256-GCM** in SQLite (not full-file SQLCipher)
- Encryption key: `SHA-256(private_key)` or `SHA-256(mnemonic)` — 32 bytes, set via `SetEncryptionKey` FFI
- **Encrypted columns**: `messages.content`, `messages.metadata`, `conversations.title`, `conversations.system_prompt`
- Encrypted blobs prefixed with `enc:v1:` — legacy plaintext passes through transparently
- **Wallet-scoped databases**: `nodeneo_{first8_of_address}.db` — each wallet isolated; legacy `nodeneo.db` auto-migrates on first use
- **Erase wallet** keeps the encrypted DB on disk (unreadable without the key); re-importing the same wallet reconnects conversations
- **Full Factory Reset** deletes ALL databases, keys, logs, and preferences

### Preferences — all in SQLite
All user preferences (default tuning, system prompt, session duration, streaming, Expert API password, log level) are stored in the SQLite `preferences` table — no more file-based settings. File-based stores (`default_tuning.json`, `session_duration_seconds.txt`, `chat_streaming_preference.txt`) auto-migrate to SQLite on first read and delete the legacy file. This means all settings are:
- Encrypted at rest (wallet-scoped DB)
- Included in backup/restore automatically
- Wiped on factory reset with the DB

### Backup & Restore
- **Export**: JSON zip (conversations + messages + preferences) → AES-256-GCM encrypted with `SHA-256(private_key)` → `.nnbak` file
- **Import**: Decrypt, validate manifest, destructive replace (DELETE + INSERT in transaction)
- Includes: conversations (with `system_prompt`, `tuning_params`), messages (with metadata), all preferences (tuning defaults, session duration, streaming, Expert API password)
- Manifest includes: version, app version, export date, wallet prefix, conversation/message counts
- API keys excluded from backup (device-scoped, bcrypt-hashed only)

### Authentication
- **Biometric first**: Face ID, Touch ID, fingerprint
- **PIN fallback**: 6-digit PIN
- **Auto-lock**: After configurable timeout (default 5 min)
- **Transaction signing**: Always requires biometric re-auth

### Network Privacy
- No analytics, no telemetry, no crash reporting
- Traffic is direct: **device → Base RPC + active models HTTP + provider (MOR-RPC)** via the embedded SDK (no separate C-node process in Node Neo)
- TEE flows use the same attestation paths as upstream proxy-router where applicable
- No Marketplace-API or central relay in the hot path for chat

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | Flutter 3.x (Dart) | Single codebase: iOS, Android, macOS. Native compilation. |
| Go bridge | **c-shared** + dart:ffi | `//export` C API; `FreeString` + JSON payloads. |
| Chain + inference | **proxy-router/mobile** SDK | Same logic as full node, in-process. |
| Wallet | SDK + secure store | Go wallet in memory; PK (or mnemonic) in Keychain / Keystore. |
| Local DB | SQLite (modernc.org/sqlite) | Wallet-scoped DBs, AES-256-GCM column encryption. |
| Backup | archive/zip + AES-GCM | Encrypted `.nnbak` export/import for conversations + settings. |
| Keychain | flutter_secure_storage | Platform-native keychain abstraction. |
| File picker | file_picker | Native save/open dialogs for backup files. |
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

| Gateway / app pattern | Node Neo equivalent |
|----------------------|---------------------|
| Curated active models | SDK `active_models.json` cache + home filters |
| Session open / close / list | SDK + `OnChainSessionsScreen` |
| OpenAI-shaped chat | `SendPrompt` → `SendPromptV2` |
| Optional dedicated RPC | `eth_rpc_override.txt` + `chain_config` defaults |
| `/v1/models` (Marketplace API) | Gateway fetches from `active.mor.org` with cache + SDK fallback |
| `/v1/chat/completions` | Gateway: auto session mgmt + OpenAI format |
| API key auth | Gateway: `sk-` Bearer tokens, bcrypt-hashed |
| MCP tool discovery | MCP server: `morpheus_models` + `morpheus_chat` tools |

**What we deliberately skip:** Cognito, billing, multi-tenant gateway. API keys are single-user, local-only (no central relay).

---

## API Gateway & MCP — Local AI Agent Integration

Node Neo doubles as a **personal Morpheus gateway** for external applications and AI agents. All traffic stays local.

### Gateway (`go/internal/gateway/`)

An OpenAI-compatible HTTP server that runs alongside the main app on a configurable port (default 8083). It reuses the same proxy-router SDK and SQLite store as the UI, so sessions and conversations are shared.

**Key design decisions:**
- **No upstream modifications** — All gateway code lives in `nodeneo/go/`, never touching `proxy-router/`
- **Shared state** — API-initiated conversations appear in the UI (marked with a robot icon via `source: "api"`)
- **Model list from active.mor.org** — Same source as the UI, with 5-min in-memory cache, ETag support, and SDK fallback (matches Marketplace API's `DirectModelService` pattern)
- **Transparent session lifecycle** — Resolves model name → blockchain ID, reuses open sessions, opens new ones automatically

### MCP Server (`mcp-server/`)

A lightweight TypeScript process using `@modelcontextprotocol/sdk` that bridges AI agents (Cursor, Claude Desktop) to the gateway via stdio.

**Why MCP instead of OpenAI base URL override?**
- Cursor proxies "Override OpenAI Base URL" requests through their own servers, which blocks localhost via SSRF protection
- MCP servers run as local processes — stdio communication never leaves the machine
- Prompts stay between the user and the Morpheus provider, preserving the privacy guarantee

**Data flow:**
```
AI Agent (Cursor/Claude) ←stdio→ MCP Server ←HTTP localhost→ Gateway ←SDK→ Morpheus Network
```

---

## Cursor Integration — Trust Model

The MCP server is the recommended path for Cursor integration. Cursor's "Override OpenAI Base URL" proxies requests through their own servers (SSRF protection blocks `127.0.0.1`), placing Cursor in the trust path for prompt content. The MCP server runs as a local stdio process — prompts never leave the machine, preserving the privacy guarantee.

A Cloudflare Tunnel (`cloudflared`) quick tunnel was validated end-to-end but is **not shipped** — it fixes reachability but does not restore confidentiality from Cursor on the hairpin path.

---

## Target Platforms (Priority Order)

1. **macOS** (arm64) — development and testing
2. **iOS** (arm64) — primary target, iPhone + iPad
3. **Android** (arm64) — secondary mobile target
4. **Linux** (x86_64, arm64) — future
5. **Windows** (x86_64) — future
