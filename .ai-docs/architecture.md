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

Node Neo embeds the **proxy-router mobile SDK** (`Morpheus-Lumerin-Node/proxy-router/mobile/`) as a Go module from upstream [`MorpheusAIs/Morpheus-Lumerin-Node`](https://github.com/MorpheusAIs/Morpheus-Lumerin-Node) (`dev` branch, promotes to `main`). For active SDK iteration a local `replace` directive in `go/go.mod` points at a sibling clone; for releases the dependency is pinned to a clean pseudo-version. There is **no separate proxy-router process** and **no HTTP hop** for consumer operations.

### What the embedded SDK covers
- **Wallet** — create / import / export private key, address, balances (same crypto stack as upstream: `go-ethereum`, `go-bip39`, etc.). Node Neo is a single-account hot wallet — BIP-39 mnemonic and HD-derivation paths are deliberately not exposed in the UI; see *Onboarding & Wallet* below.
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
│  Keychain / Keystore (private key only; legacy mnemonic   │
│  auto-migrates to PK on cold start, then is deleted)      │
│  Application Support (wallet-scoped DBs, RPC override,    │
│  preferences, logs, .nnbak export files,                  │
│  .install_sentinel for fresh-install Keychain wipe)       │
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

**Private-key-only wallet model.** Node Neo is a single-account hot wallet — we never expose multiple derived addresses, so BIP-39 mnemonic / seed-phrase UX would only add fork points and confusion. Every user-facing wallet operation operates on the hex private key directly.

**Create**: New wallets are generated internally via the same crypto stack as upstream (BIP-39 entropy → secp256k1), but only the derived private key is shown to the user — masked by default (first 4 + last 4 chars visible, rest as bullets), with Reveal and Copy buttons. Framed as "treat it like a password." The mnemonic is discarded; only the PK is saved to the platform Keychain.

**Import**: Single hex-PK input field with `0x`-prefix tolerance and 64-char validation. No phrase/key toggle.

**Export**: `Settings → Wallet → Export Private Key` reveals the same masked PK with copy-to-clipboard for use in MetaMask, hardware wallets, etc. The Erase Wallet and Factory Reset confirmation dialogs ask the user to type their PK back — preventing fat-finger destruction.

**App lock recovery sheet**: Always asks for the wallet's private key (no phrase fallback) to verify ownership and disable the app lock.

**Cold start (`_initSDK` in `lib/app.dart`)**:
1. `FirstLaunchGuard.reconcileFreshInstall(dataDir)` — if the `.install_sentinel` file is missing the container was wiped (or this is a genuine first run); proactively clear any orphaned Keychain entries before the vault is read.
2. `NetworkReachability.recheck()` — DNS canary; if offline, short-circuit to the dedicated offline screen.
3. `bridge.init(...)` (on a background isolate via `compute`) and, on success:
4. `WalletVault.migrateLegacyMnemonicToPrivateKey(bridge)` — one-shot migration for users upgraded from a pre-PK build. If a legacy mnemonic is present and no PK is saved, import via Go to derive the account-zero PK, persist the PK, then wipe the mnemonic. Crash-safe: writes the PK *before* deleting the mnemonic. No-op for new installs and PK-imported wallets.
5. `WalletVault.readPrivateKey()` — load the PK, import via `bridge.importWalletPrivateKey`, open the fingerprinted wallet DB, set the SHA-256(PK) encryption key.

**Vault internals (`lib/services/wallet_vault.dart`)**: public surface is `savePrivateKey` / `readPrivateKey` / `hasSavedWallet` / `clearStoredSecret` / `resyncKeychainItems`. The legacy `nodeneo_mnemonic` Keychain entry and pre-Keychain `.mnemonic_vault` file are read-only (migration path) and `clearStoredSecret` always wipes both alongside the PK.

## Responsive UI Policy

Node Neo commits to **three form factors** — `compact` (<600 px), `medium` (600-839 px), `expanded` (>=840 px) — matching Material 3 window-size classes. Layout decisions branch on form factor via `lib/services/form_factor.dart`; platform capability gating lives in `lib/services/platform_caps.dart`. The two concerns are orthogonal and must not be mixed.

Core rules:

- **Homogeneity first.** If the compact design is readable at wide widths (e.g. the two-line `_ModelTile`), ship it on every platform.
- **Cap, don't stretch.** Wrap scrollable screens in `MaxContentWidth` (default 960 px) so ultrawide monitors read proportionally.
- **Branch on form factor, not platform.** `isCompact(ctx)` decides layout; `Platform.isXxx` never does.
- **Inline first, split when painful.** Promote to `foo_screen_compact.dart` + `foo_screen_expanded.dart` only when divergence exceeds ~30 percent.

See **`.ai-docs/ui_responsive_design.md`** for the full decision guide, screen inventory, and new-screen checklist.

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

**Reasoning / thinking models:** The streaming pipeline distinguishes `choices[0].delta.content` (answer) from `choices[0].delta.reasoning_content` (chain-of-thought) and falls back to `<think>…</think>` tag extraction for providers that inline reasoning. The UI renders a compact "Thinking…" zone above the answer bubble that auto-collapses to `Thought for Xs` once the answer stream begins; reasoning tokens are **never** fed back into the prompt history on multi-turn conversations.

**Stop / Cancel:** During an in-flight prompt the send button swaps to an amber stop icon. Cancellation propagates through `CancelPrompt` FFI → Go `context.CancelFunc` → proxy-router HTTP context close; any tokens already streamed stay in the bubble marked "Generation stopped" so partial answers are never discarded.

**Pre-session confirmation:** Tapping a model tile on the home screen opens `widgets/session_confirmation_sheet.dart` before any on-chain stake is posted. The modal shows the model name, TEE badge, duration dropdown, and the exact MOR stake derived linearly from the tile's calibrated hourly stake — so the number the user agrees to is the number the list advertised. Confirm → `OpenSessionByModelId` + chat navigation; Cancel → no chain interaction.

**Provider endpoint redaction:** `lib/utils/error_redaction.dart` strips `http(s)://…`, `host:port`, and bare IPv4 addresses from every error string before it hits the chat UI. Full detail still lands in the app log for debugging, but users and screen-shares see a neutral `<provider endpoint>` placeholder.

**Response metadata:** Each assistant message stores the full raw provider response JSON alongside the text. The Response Info sheet shows summary rows (latency, token counts, finish reason, model) and the complete JSON for debugging.

**Empty responses:** When a provider returns 200 with empty content, the chat shows "No response received — the provider may be busy." as a soft error with a "Tap to retry" button (re-sends the same prompt) and a "Dismiss" option.

**Inference logging:** At DEBUG level, the Go mobile layer logs request details (session, conversation, stream flag, message count, tuning params), response summary (latency, char count, metadata size), and errors. Empty responses are logged at WARN level. Enable DEBUG in Settings → Version & Logs.

**Log level persistence:** The log level setting is saved to SQLite preferences and restored on app restart (applied after the wallet-scoped DB opens). Both the nodeneo wrapper logger and the SDK's internal zap logger are updated atomically.

**Network reachability gate:** A DNS canary (`lib/services/network_reachability.dart` — `InternetAddress.lookup` against `cloudflare.com` / `apple.com` / `google.com`, 3 s timeout, multiple hosts so a single DNS hiccup doesn't false-positive) tells the app "the device has internet" before any blocking Go FFI call. Used in three places:

1. **Startup** (`_initSDK`): if offline, skip `bridge.init` and show the dedicated `_OfflineScreen` ("No internet connection · Try Again"). When online but the chain RPC fails, show `_ErrorScreen` titled *Blockchain unreachable* with normal-language guidance and a "Show technical details" expander for the raw error.
2. **Lifecycle** (`didChangeAppLifecycleState → resumed`): re-probe so the home-screen RPC pill and the global `NetworkReachability.onlineNotifier` reflect "user toggled airplane mode in the background".
3. **In-session guards**: `HomeScreen` loaders (`_loadWallet` / `_loadModels` / `_computeAffordability`) and the periodic 45-second timer early-return when `onlineNotifier.value == false`. Pull-to-refresh runs the canary first and skips the load chain if offline. `ChatScreen._send` and `HomeScreen._openModelChat` (new-session creation) gate on `recheck()` and surface an amber "You're offline" snackbar that preserves the user's typed message — so an offline send/new-session attempt fails fast (<1 s) instead of stalling 30–120 s on Go's RPC fallback list.

A persistent `OfflineBanner` widget (`lib/widgets/offline_banner.dart`) wired to `onlineNotifier` is pinned above the scroll view on `HomeScreen` and `ChatScreen` so the offline state is always visible while it persists. When online, the widget renders `SizedBox.shrink` so it costs nothing.

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
- **Private-key-only**: The user-facing model is a single hex private key; no mnemonic UX (see *Onboarding & Wallet*)
- Stored in iOS Keychain / Android Keystore / macOS Keychain via `flutter_secure_storage` under the `nodeneo_private_key` key
- iOS / macOS Keychain entries use `accessibility: first_unlock_this_device` and an opt-in iCloud sync toggle (`KeychainSyncStore`)
- **Legacy mnemonic auto-migration**: on cold start, if a previous build's `nodeneo_mnemonic` entry (or the pre-Keychain `.mnemonic_vault` file) is present and no PK exists, `WalletVault.migrateLegacyMnemonicToPrivateKey` derives the account-zero PK via BIP-44 path `m/44'/60'/0'/0/0` (in the embedded Go SDK), persists the PK, and removes the mnemonic. One-shot, crash-safe, and a no-op for all new installs

### Fresh-Install Reconciliation (`FirstLaunchGuard`)
On iOS / macOS the platform Keychain survives an app uninstall (Apple's intent: password-manager fumble-finger protection). For a crypto wallet that's the wrong default — when a user explicitly deletes the app they expect the wallet gone. `lib/services/first_launch_guard.dart` writes a `.install_sentinel` file inside the app data directory on first run; `_initSDK` checks for it on every cold start and, if missing (= container was wiped or genuine first launch), proactively calls `WalletVault.clearStoredSecret()` and `AppLockService.clearLockCredentialsOnly()` **before** any vault read. Subsequent launches see the sentinel and skip the wipe. Android `EncryptedSharedPreferences` lives in the container so the wipe step is a harmless no-op there.

### Data Encryption at Rest
- **Column-level AES-256-GCM** in SQLite (not full-file SQLCipher)
- Encryption key: `SHA-256(private_key)` — 32 bytes, set via `SetEncryptionKey` FFI
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

### App Lock (Authentication)
Optional Face ID / Touch ID and/or password lock layered on top of the wallet. The lock secret is **not** the wallet PK — it's a separate SHA-256(salt:password) hash kept in the Keychain — but the wallet PK is the always-available recovery path if the user forgets their password or loses the biometric enrolment.

- **`LockMode` enum** (`AppLockService`): `off | biometricOnly | passwordOnly | passwordWithBiometric`
- **Biometric-only mode**: no salt/hash is ever written; recovery uses the wallet's private key via the recovery sheet
- **Auto-prompt**: `AppLockScreen` schedules a post-frame Face ID prompt on mount when biometrics are enabled; one auto-fire per mount so the framework can't loop
- **Setup chooser** (`AppLockSetupChoiceScreen`) verifies a real biometric prompt before flipping the storage flag, so a misconfigured device can't strand the user
- **Recovery sheet** (`AppLockRecoverySheet`): always asks for the wallet PK; calls `bridge.verifyRecoveryPrivateKey` and disables the lock on a match (wallet, SQLite, RPC settings stay)
- **Lock screen layout** is mode-aware: biometric-only hides the password field entirely; `passwordWithBiometric` keeps the password field collapsed by default behind a "Use password instead" link
- **Disable lock** in `biometricOnly` mode re-prompts Face ID instead of asking for a password we never stored

### Network Privacy
- No analytics, no telemetry, no crash reporting
- Traffic is direct: **device → Base RPC + active models HTTP + provider (MOR-RPC)** via the embedded SDK (no separate C-node process in Node Neo)
- TEE flows use the same attestation paths as upstream proxy-router where applicable
- No Marketplace-API or central relay in the hot path for chat
- Provider IPs / host:port / URLs are redacted from any error message surfaced in the UI (see `lib/utils/error_redaction.dart`); full detail stays in the local app log

### TEE Attestation (TDX)
- On-device attestation for every provider that serves a `:tee` model: CPU quote fetch over HTTPS → portal cryptographic verification (SecretAI) → RTMR3 compared against cosign-verified golden values for the fork's build version
- **Sigstore TUF cache** is redirected to the SDK's `dataDir` (under iOS `Library/Application Support/…`) via `sdk.SetSigstoreCacheDir(dataDir)` — iOS sandbox otherwise rejects the library's default `./.sigstore` path
- Quote + TLS fingerprint cached per provider endpoint for sub-second reconnects; cache survives app relaunch and invalidates automatically when the provider reports a new version

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | Flutter 3.x (Dart) | Single codebase: iOS, Android, macOS. Native compilation. |
| Go bridge | **c-shared** + dart:ffi | `//export` C API; `FreeString` + JSON payloads. |
| Chain + inference | **proxy-router/mobile** SDK | Same logic as full node, in-process. |
| Wallet | SDK + secure store | Go wallet in memory; private key only in Keychain / Keystore (legacy mnemonic auto-migrates on upgrade). |
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

1. **macOS** (Apple Silicon + Intel) — **shipping** — signed + notarized DMG via GitHub Releases
2. **iOS — iPhone** (arm64, iOS 16+) — **shipping** — TEE attestation working, TestFlight track open
3. **iOS — iPad** — planned, adaptive split-view on top of the existing `FormFactor` policy
4. **Android** (arm64) — planned, `gomobile` target exists
5. **Linux** (x86_64, arm64) — future
6. **Windows** (x86_64) — future

---

## Recently Shipped

This section is the long-form record of completed work. `feature_backlog.md` tracks only **open** items; once a backlog item ships it moves here so the backlog stays a clean to-do list. Each entry is grouped by release; in-flight work for the next release lives at the top under *Next release (in progress)* until the cut.

### v3.4.0 — 2026-05-08

v3.4.0 is the App Store legitimacy + CI/CD release. Two branches contributed: `feat/website-links-and-ios-ci` (legitimacy surface + iOS TestFlight CI) and `feat/asc-publishing-polish` (privacy posture cleanup + in-app helper-link reorganization to match the new `nodeneo.ai` pages).

A public Privacy / Terms / Support surface on `nodeneo.ai` that App Store review can read; in-app links from Onboarding / Settings / About / Wallet / Home out to those pages so users get the long-form copy when they need it; a `.github/workflows/build-ios.yml` workflow that uploads to TestFlight on every `dev` push and tags + releases on `main`; the `file_picker` → `file_selector` migration that drops three OS purpose strings; and a consolidation of in-app helper-links so the settings drawer no longer duplicates content that has more contextual homes elsewhere in the app.

#### App Store legitimacy surface (`nodeneo.ai` + in-app links)
- **Three new public pages** at `nodeneo.ai`:
  - `privacy.html` — App-Store-grade privacy policy. Leads with "Node Neo collects nothing" and walks through what stays on device, the two third parties (public Base RPC + Morpheus inference providers) the app necessarily talks to, the OS permissions declared (with the iOS Photos / Camera / Mic explanation for the `file_picker` quirk), GDPR / CCPA rights, and contact at `support@nodeneo.ai`. Auto-resolves the App Store reviewer's checklist for "Privacy Policy URL".
  - `terms.html` — Terms of Service / EULA. MIT for source, narrower personal-use license for the signed binaries, hard self-custody disclaimer (red `heads-up` block — "we cannot recover lost keys, no one can"), warranty disclaimer + liability cap (USD $100), South Dakota governing law, individual disputes only. The venue clause names the state generally rather than a specific county to match the publisher's mobile principal-office posture, mirroring the in-repo `TERMS.md` drafting. Entity named in the docs is `ABSGrafx LLC (South Dakota, USA)`.
  - `support.html` — Front-and-center email + GitHub-issues CTAs at the top, then 5 sections of collapsible FAQ (Getting started / Wallet & funds / Chat & models / Privacy & data / Troubleshooting). Every common error message we surface in the app has a matching FAQ entry.
- **Footer rewire across all 5 pages** (`index.html`, `why.html`, `deep-dive.html`, `start.html`, `onramp.html`): right-column section renamed `External` → `Legal`, `Support` link redirected from github-issues to `support.html`, `Privacy` link redirected from the github anchor to `privacy.html`, new `Terms` row added. Footer registry documented in `04-nodeneo.ai/README.md`.
- **`lib/constants/external_links.dart`** — single source of truth for every external URL the app opens. Reviewer-and-privacy-auditor friendly: one class to read to see every hostname the binary will ever launch. Helper `ExternalLinks.launch(url, context: ...)` wraps `url_launcher` with `LaunchMode.externalApplication` (no in-app web view) plus a snackbar fallback when the platform refuses to handle the scheme.
- **Settings drawer** (`HomeScreen`): new `Help & Resources` section after `Version & Logs`, with rows for `Why Node Neo?` / `New to crypto?` / `Quick start` / `Support` / `Privacy Policy` / `Terms of Service`. Each row uses the existing `_SettingsDrawerItem` widget extended with an `external` flag that swaps the trailing chevron for an `open_in_new` glyph so the user knows the tap will leave the app. Drawer's `_onSettingsTap` learned a `help:<url>` prefix that bridges to `ExternalLinks.launch`.
- **About screen** (`AboutScreen`): new `Legal & Resources` `SectionCard` between the version row and the log viewer, with rows for `Privacy Policy` / `Terms of Service` / `Support` / `Source code`. App Store reviewers actively look for these surfaces inside the app's Settings → About hierarchy as a sanity check that the App Store Connect URLs are honest.
- **Onboarding screen** (`OnboardingScreen`): subtle `New to crypto? See the walkthrough →` `TextButton` directly under the "Import Wallet" button, links to `onramp.html`. At the very bottom of the form, an inline `By creating or importing a wallet you agree to our Terms and Privacy Policy.` line with both phrases as tappable links — mirrors the Apple Review expectation that any account-like creation flow surface T&Cs before the user commits.

#### iOS CI to TestFlight + App Store (`.github/workflows/build-ios.yml`)
- Mirrors the structure and SemVer conventions of `build-macos.yml`: `generate-tag` → `build-ios`, branch strategy `dev` → TestFlight Internal (no review) and `main` → TestFlight + git tag + GitHub Release (notes-only, no binary asset).
- Reuses the proven local pipeline: `make go-ios` for the static archive, `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist`, and `xcrun altool --upload-app` with App Store Connect API key auth (the same key path `make upload-testflight` uses).
- Inlines the `_verify-ipa-symbols` Mach-O `nm` check against the produced IPA so a STRIP_STYLE drift to "all" is caught at build time, not after a 10-15 min upload + processing round-trip on TestFlight.
- Apple Distribution `.p12` cert is base64-decoded into an ephemeral keychain (with auto-lock + `set-key-partition-list` so codesign doesn't prompt). ASC API key is staged at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` per Apple's convention so both archive-time signing AND `altool` upload can use the same credential.
- App Store submission for review is intentionally **not** automated. The "Submit for Review" click in App Store Connect requires complete metadata (screenshots, age rating, review notes, what's-new copy); a rejection costs days. Workflow comments make this explicit so the next maintainer doesn't try to wedge it in.
- `build-macos.yml` got the same `#9` bare-hash version fix (drop `--single-branch`, fetch `main`) so the in-app About screen finally shows `v7.0.0-N-g<hash>` instead of just the 12-char commit.

#### App Store publishing polish (`feat/asc-publishing-polish`)

A second pass on the same release that consolidates the in-app surface around the published `nodeneo.ai` pages and tightens the iOS privacy posture for App Store review. Three concerns: the OS-permission disclosure surface, the in-app information architecture for helper / legal links, and the public-website CTA priority for support.

**iOS privacy strings — `file_picker` → `file_selector` migration.** The old `file_picker: ^11.0.2` package transitively pulled in `DKImagePickerController` + `DKPhotoGallery` + `SDWebImage` + `SwiftyGif` via CocoaPods even though the only call site (`lib/screens/settings/backup_reset_screen.dart` for `.nnbak` save/load) is a document-only flow. Apple's binary scanner observes the linked photo / video / audio APIs and forces a declaration of `NSPhotoLibraryUsageDescription` + `NSPhotoLibraryAddUsageDescription` + `NSCameraUsageDescription` + `NSMicrophoneUsageDescription` in `Info.plist`, which then surface as data-collection rows on the App Privacy nutrition label even though Dart never invokes them. Replaced with `file_selector: ^1.1.0` (official `flutter.dev` package, built on `UIDocumentPickerViewController` only — no Photos / Camera / Mic linkage). `BackupResetScreen` rewired to the new API: `getSaveLocation` for export (with the iOS-specific "write to temp file → read bytes → `XFile.fromData(...).saveTo(scopedPath)`" dance because the document picker returns a writeable scoped path rather than a destination directory), `openFile` for import. `XTypeGroup` declares `extensions: ['nnbak']` as a system hint, but no UTType is registered for the private extension so the picker accepts any file and we surface a decrypt-failure error if it isn't a real backup — the alternative tightening hides the user's own backup on first open. Net result: only `NSFaceIDUsageDescription` remains in `Info.plist` (FaceID is authentication, not data collection), and the App Privacy section can legitimately answer "Data Not Collected" for every category.

**Helper-link consolidation across the in-app surface.** The previous v3.4.0 work added a `Help & Resources` section in the settings drawer with seven external-link rows (`Why Node Neo?` / `New to crypto?` / `Quick start` / `Support` / `Report a bug` / `Privacy Policy` / `Terms of Service`). On smaller screens this overflowed the drawer (the drawer body was a non-scrolling `Column`, producing a "BOTTOM OVERFLOWED BY 248 PIXELS" debug banner during macOS dev-loop testing — would have been an actual user-visible clip on iPhone SE-class devices). The reorganization splits each link to its single most contextually appropriate home and rewrites the drawer body as a scrollable `ListView` so future additions can't regress this:

- *Settings drawer*: trimmed back to the five in-app navigation rows (Preferences / Wallet / Expert Mode / Backup & Reset / About & Help). The `Version & Logs` row was renamed `About & Help` with subtitle `App info · Resources · Logs` — anchors on existing Apple-platform muscle memory ("About <App>") and signals all three card types behind it without fronting the technical "Logs" framing first. The `_SettingsDrawerSectionHeader` widget and the `external` flag on `_SettingsDrawerItem` were both removed (no remaining drawer rows are external links). The `help:<url>` prefix branch was dropped from `_onSettingsTap`.
- *About screen*: now three cards, each with one purpose. The **About card** absorbed `Why Node Neo?` + `Architecture deep dive` + `Privacy Policy` + `Terms of Service` as `_ExternalLinkRow` rows below the version block (separated by a thin divider) — the rationale is that Privacy + Terms are *legal commitments*, not utilities; they belong with "who runs this app and what we promise" rather than in a generic resources bucket. The `_LegalAcknowledgement` on the onboarding screen already pairs them this way ("by creating a wallet you agree to our Terms and Privacy Policy"). The **Resources card** (renamed from `Legal & Resources`, icon now `Icons.support_outlined`) is a tight three-row utility card: `Support` / `Report a bug` / `Source code` — single purpose, "where do I get help / see the code". The **Logs card** is unchanged. The `AppBar` title was renamed `Version & Logs` → `About & Help` to match the drawer entry.
- *Wallet screen*: a compact emerald `TextButton.icon` "New to crypto? See the walkthrough" sits centred below the Active Sessions card. Same affordance as the onboarding screen's "Import Wallet" footer link — anyone landing on Wallet without crypto vocabulary has one tap to the 25-minute primer at `nodeneo.ai/onramp.html`.
- *Home front page*: a small `TextButton.icon` "Quick start guide" sits below the `START A NEW CHAT by selecting a model` hint when the wallet has funds. Discoverable for the user staring at the model list wondering which to tap; ignored by an oriented user. Sized at fontSize 11 / icon 14 / minimum height 24 to keep visual weight below the model tiles.
- *`_FundWalletOverlay`* (the empty-wallet state on Home): kept its `New to crypto?` + `Quick start` footer links, since this is the "new wallet, no funds yet" state where both onramp and quickstart are contextually correct. The original session-confirmation-sheet "How to add MOR" link added in the prior pass also stays.
- *`lib/constants/external_links.dart`* doc comments updated to reflect the new homes for `why` / `onramp` / `quickStart` / `deepDive` / `support`. The `Maintained alongside the app in absgrafx/Morpheus-Infra` comment that alluded to a private infrastructure repo was rewritten to describe only the public surface (`nodeneo.ai`) without exposing build / hosting details.

**Public-website CTA priority flip (`nodeneo.ai/support.html`).** The hero and bottom contact sections previously led with "Email support@nodeneo.ai" as the primary CTA and "GitHub Issues" as secondary. Flipped: GitHub Issues is now the primary action (public, searchable, lower friction for the next user with the same problem), email is the secondary fallback for the cases that genuinely need a private channel (lost-wallet questions, payment-processor issues). Meta description and supporting copy updated to match. `nodeneo.ai/privacy.html` and `nodeneo.ai/terms.html` had any claims of a "publicly auditable git history for the website source" removed (the website is built from a private Terraform stack — that detail was both misleading and unnecessary). The "Last updated" timestamp is now the sole revision indicator on those legal pages.

### v3.3.0 — 2026-05-03

The `feat/ios-testflight-readiness` branch focused on closing the iOS TestFlight readiness gates: every "first-impression" UX rough edge a normal user would hit during their first 60 seconds with the app, on whatever network state their phone happens to be in.

#### Biometrics-first app lock UX
- **`LockMode` enum** (`AppLockService`): `off | biometricOnly | passwordOnly | passwordWithBiometric`. `enableBiometricLockOnly()` writes the enabled+biometric flags without ever creating salt/hash, so there's no password material to lose.
- **Auto-prompt on mount** — `AppLockScreen.initState` schedules a post-frame Face ID prompt when biometrics are enabled. One auto-fire per mount; cancel falls through silently to the manual button so the framework can't loop.
- **Mode-aware lock screen** — `biometricOnly` hides the password field entirely; `passwordWithBiometric` keeps the field collapsed by default (Steve-Jobs single-CTA pattern) behind a small "Use password instead" link; `passwordOnly` shows the field immediately.
- **Setup chooser** (`AppLockSetupChoiceScreen`) — two cards (biometric primary, password secondary) with a real biometric verification before flipping the storage flag, so a misconfigured device can't strand the user.
- **Settings polish** — status pill shows the current mode (`Face ID` / `Password` / `Face ID + password` / `Off`) with promote/demote affordances. Refuses to toggle biometrics off in `biometricOnly` mode without a password fallback.
- **Disable lock** in `biometricOnly` mode re-prompts Face ID instead of asking for a password we never stored.

#### iOS app-delete should wipe all user data — `FirstLaunchGuard`
- New `lib/services/first_launch_guard.dart` writes a sentinel file (`.install_sentinel`) inside the app data directory the first time `_initSDK` runs after install.
- On every cold start, `_initSDK` checks for the sentinel **before** reading `WalletVault` or `AppLockService`. If the sentinel is missing (= container was wiped or genuine first run), proactively call `WalletVault.clearStoredSecret()` and `AppLockService.clearLockCredentialsOnly()` then write the sentinel.
- Subsequent launches see the sentinel and skip the wipe — zero overhead after first run.
- In-app *Erase Wallet* and *Full Factory Reset* clear Keychain explicitly and keep the sentinel intact (no false-positive re-wipe on the next start).
- iOS / macOS are the targets (Keychain otherwise survives delete); Android `flutter_secure_storage` lives in the container so the wipe step is a harmless no-op.

#### Network reachability gate + friendlier blockchain error screen
- New `lib/services/network_reachability.dart` — DNS canary probe (`InternetAddress.lookup` against `cloudflare.com` / `apple.com` / `google.com`, 3 s timeout). Zero new dependencies. Process-wide `ValueNotifier<bool?> onlineNotifier` plus `recheck()` wrapper.
- `_initSDK` runs the canary before `bridge.init`. Offline → dedicated `_OfflineScreen` ("No internet connection — check your Wi-Fi or cellular data"). Online but RPC fails → redesigned `_ErrorScreen` titled **"Blockchain unreachable"** with normal-language subtitle and a "Show technical details" expander for the raw error.
- `didChangeAppLifecycleState → resumed` re-probes so the home-screen pill reflects reality after a background airplane-mode toggle.
- **In-session guards** (`HomeScreen` + `ChatScreen`):
  - `_loadWallet` / `_loadModels` / `_computeAffordability` and the periodic 45 s timer early-return when offline. This is the actual fix for "app appears to hang after offline snackbar" — kills the doomed Go RPC fallback retries.
  - Pull-to-refresh runs the canary first and shows an amber snackbar if offline. Drops offline pull-to-refresh feedback from ~120 s to <1 s.
  - `ChatScreen._send` and `HomeScreen._openModelChat` (new session creation) gate on `recheck()` and surface an amber snackbar that preserves the typed message.
  - Persistent `OfflineBanner` widget (`lib/widgets/offline_banner.dart`) pinned above the scroll view on Home and Chat — `SizedBox.shrink` when online so it costs nothing.

#### Private-key-only wallets (mnemonic removal)
- **`OnboardingScreen`**: removed the *Private Key / Recovery Phrase* segmented toggle. Single PK input field with `0x`-prefix tolerance and 64-char validation.
- **`AppLockRecoverySheet`**: dropped the segmented control. Single PK input titled *"Unlock with your private key"*.
- **`WalletVault` rewrite**: public API is now PK-only (`savePrivateKey`, `readPrivateKey`, `hasSavedWallet`, `clearStoredSecret`, `resyncKeychainItems`).
- **`migrateLegacyMnemonicToPrivateKey(GoBridge)`** — one-shot crash-safe migration runs first thing after `bridge.init` succeeds. Imports any pre-existing mnemonic via Go, exports the derived PK, persists the PK, then wipes both legacy copies (Keychain entry + `.mnemonic_vault` file). Steady-state migration is a no-op single Keychain read.
- Copy cleanups across security UI: every "phrase or key", "wallet seed", "recovery phrase" reference replaced with "private key".
- Go FFI bindings (`GoBridge.importWalletMnemonic`, `verifyRecoveryMnemonic`) retained as internal API — only caller is the migration helper. Pruning from the shared library is deferred to a future v2 cut.

#### iOS build pipeline hardening

**Cross-architecture native_assets cache pollution (FIXED in `Makefile`).** Bouncing between `make run-ios-sim` and `make run-ios` on the same checkout used to fail at codesign with `0xe8008014 invalid signature` on `objective_c.framework`. Root cause: Flutter's native asset hooks build third-party Dart-FFI frameworks into a shared `build/native_assets/ios/` cache keyed by package, not by target arch — the simulator-arm64 slice silently shadowed the device-arm64 slice the next device run needed. `lipo -info` showed `arm64` (correct count) but `otool -l … | grep LC_BUILD_VERSION` showed `platform 7` (Simulator) instead of `platform 2` (device). Fix: `Makefile` now stamps `build/.last-ios-arch` and `_ios-stamp-device` / `_ios-stamp-sim` helpers wipe `build/native_assets/ios` and `build/ios` on direction changes. `make ios-clean` is the manual escape hatch.

**Flutter implicit-engine SIGSEGV on iOS 26 + ProMotion devices** (the actual root cause of "Phlame stalls at the splash screen forever" — not a hang, a hard `EXC_BAD_ACCESS` crash in `-[VSyncClient initWithTaskRunner:callback:]` that iOS perceives as a hang because the LaunchScreen stays up until the watchdog kills the dead process). Tracking [flutter/flutter#183900](https://github.com/flutter/flutter/issues/183900); upstream fix [PR #184639](https://github.com/flutter/flutter/issues/184639) is not yet in stable.

Trigger: Flutter's *implicit* engine pattern (where `Main.storyboard` instantiates the `FlutterViewController` and the engine is created lazily during `viewDidLoad`) combined with iOS 26 + a ≥120 Hz ProMotion display. `createTouchRateCorrectionVSyncClientIfNeeded` passes `self.engine.platformTaskRunner` to `VSyncClient initWithTaskRunner:`, but `viewDidLoad` fires before the engine shell is initialized → empty `fml::RefPtr` → null deref segfault before Dart ever boots. Sub-60 Hz devices skip the VSyncClient creation early, so this only bites iPhone 13/14/15/16/17 Pro models on iOS 26.

Fix shipped: switched the iOS app to the **explicit** engine pattern. `ios/Runner/SceneDelegate.swift` now constructs a `FlutterEngine`, calls `run()`, registers plugins, then creates the `FlutterViewController(engine:nibName:bundle:)` bound to the fully-attached engine. `AppDelegate.swift` dropped `FlutterImplicitEngineDelegate` conformance. `Info.plist` removed `UIMainStoryboardFile=Main` and `UISceneStoryboardFile=Main` so iOS no longer instantiates the storyboard-bound `FlutterViewController`. `LaunchScreen.storyboard` is unaffected. Revert plan: when Flutter PR #184639 lands in stable, the implicit pattern can be restored — until then the explicit pattern is the right shape regardless and worth keeping.

**FrontBoard cache gotcha:** if the device experienced the implicit-engine crash before the workaround was deployed, iOS's FrontBoard records the crashed-but-not-cleaned-up process slot in its internal registry. Reinstall + tap surfaces the *cached splash snapshot* from the old failed launch instead of the new binary. `xcrun devicectl device process terminate` does NOT clear this. **Reboot the device.**

**iOS 26 debug-mode workflow change.** `flutter run --debug` against iOS 26 devices frequently hangs the VM Service attach (`The Dart VM Service was not discovered after 60 seconds`) — and `--debug` mode can't run unattached anyway because iOS forbids JIT and the Dart kernel snapshot needs the debugger to fall back to interpreted execution. For on-device UX validation we don't need a debugger; build in **profile mode** instead via `make install-ios-profile`, which AOT-compiles Dart into `App.framework/App` and sidesteps `flutter run`'s VM Service hang entirely. Use `make run-ios` only when you genuinely need the Dart debugger AND iOS 26 attach is cooperating that day.

### v3.2.0 — 2026-04-30
- **Cursor/Zed-class AI Gateway** — full OpenAI Chat Completions parity: `tools` / `tool_choice` / `parallel_tool_calls`, `tool_calls` deltas, `reasoning_content`, `MultiContent`, `response_format`, `seed`, `logit_bias`, `stream_options.include_usage`
- **`/v1/embeddings` and `/v1/completions`** endpoints added; both persist `source="api"` conversation rows in the local DB so gateway activity shows up in the history
- **`/v1/models`** advertises `supports_tools` / `supports_vision` / `supports_reasoning` capability flags
- **Session duration follows preferences live** — `session_duration_seconds` re-read on every `OpenSession`, no gateway restart
- **Three-layer provider endpoint redaction** — SDK (`redactError`/`redactedError`), gateway error envelope, Flutter UI; patterns kept in lockstep
- **UX polish** — affordability "Show all" hides when no models filtered (with `(N hidden)` label when active); session reuse skips the stake modal in favour of "Continue / Start Fresh"; gateway "Copy" emits the bare URL; Preferences screen banner clarifies UI-only scope
- **Engineering** — `X-Request-Id` correlation, OpenAI error envelope on all error paths, raised `ReadTimeout`, `.cursor/rules/proxy-router-workflow.mdc` documents the no-fork SDK workflow
- **iOS build unaffected** — gateway gated by `PlatformCaps.supportsGateway = isDesktop`; symbols compile clean for `ios/arm64` and are dead code at runtime on mobile

### v3.1.0 — 2026-04-24
- Chat reliability patch: handle reasoning-only stream completions honestly so a `finish_reason: stop` with no `content` no longer surfaces as a false error in the chat UI ([#66](https://github.com/absgrafx/nodeneo/pull/66))

### v3.0.0 — 2026-04
- **Full TEE compliance with proxy-router v7.0.0** — upstream merge, TDX attestation with cosign-verified golden values, TLS-fingerprint-bound `reportdata`, per-provider quick-attestation cache, end-to-end verified on iPhone
- iOS Sigstore TUF cache fix (`sdk.SetSigstoreCacheDir(dataDir)`) — unblocks TEE models on iPhone
- Pre-session confirmation modal with live stake preview and duration presets
- In-place affordability (greyed models, no re-sort, `X of Y affordable` counter)
- Wallet card redesign (single-line address, right-aligned balances, full-width helpers)
- Provider endpoint redaction (`lib/utils/error_redaction.dart`)
- "Fund Your Wallet" overlay scoped — no more covering active chats
- Chain correction: "Arbitrum" → "Base" across UI + docs (chainID 8453)
- RPC failover: expanded `shouldRetryRPCError` in the fork for public-node rate limits
- Flutter upgrade to 3.41.7 (local + CI)

### v2.7.0 — 2026-04
- iOS (iPhone) first light: full flows on device + simulator, TestFlight track open
- Two-zone streaming for reasoning/thinking models (`reasoning_content` + `<think>` fallback)
- Stop/Cancel generation (amber stop button, full cancellation plumbing)
- MOR scanner: ABI decode fix, full session scan, isolate-backed
- Collapsible wallet card, slimmed privacy toggle, pull-to-refresh
- Factory reset uses "DELETE ALL" confirmation phrase

Older releases live in the GitHub Release archive — see [absgrafx/nodeneo/releases](https://github.com/absgrafx/nodeneo/releases).
