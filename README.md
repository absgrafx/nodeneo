<p align="center">
  <img src="assets/branding/splash_logo.png" alt="Node Neo" width="160" />
</p>

<p align="center">
  <img src="assets/branding/nodeneo_text.png" alt="Node Neo" width="320" />
</p>

<p align="center">
  <b>The Signal of decentralized AI inference.</b><br/>
  A consumer-grade client for the <a href="https://mor.org">Morpheus</a> decentralized AI network.<br/>
  Wallet · MOR Staking · Model Pick · Private Chat — no Docker, no IPFS, no Swagger.
</p>

<p align="center">
  <a href="https://github.com/absgrafx/nodeneo/releases/latest"><img src="https://img.shields.io/github/v/release/absgrafx/nodeneo?style=flat-square&color=00ff41&label=latest%20release" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS-333?style=flat-square" alt="Platform" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License" /></a>
</p>

---

## Install

### macOS — signed releases (recommended)

Grab the latest **signed & notarized** `.dmg` from [**Releases**](https://github.com/absgrafx/nodeneo/releases/latest).

1. Download the `.dmg` (Apple Silicon / Intel universal)
2. Mount, drag **Node Neo** to Applications
3. Launch — create or import a wallet, stake MOR, pick a model, and chat

### iPhone (iOS 16+)

Currently distributed via TestFlight / enterprise provisioning while App Store submission is in progress. Ping [@absgrafx](https://github.com/absgrafx) for an invite, or build from source with Xcode (see below).

> Linux and Windows are on the backlog — not yet shipped.

## Down The Rabbit Hole?

Node Neo is **the Signal of decentralized AI** — a clean, consumer-grade app that makes the [Morpheus](https://mor.org) network accessible to everyone, not just developers. Install it, create a wallet, stake MOR, pick a model, and chat — privately, with no infrastructure to manage.

**Who this is for:** Anyone who wants private AI inference without running a node, managing Docker, or reading Swagger docs. If you use Signal for secure messaging, Node Neo is the same idea for AI.

**Not this project:** Running a compute node? See [mor.org](https://mor.org). Building on the Morpheus API? See [api.mor.org](https://api.mor.org). Node Neo is the consumer endpoint — the last mile between the network and a person who just wants to chat.

Under the hood it embeds the **proxy-router mobile SDK** directly via Go FFI. There is no standalone proxy-router process, no HTTP hop, and no central relay in the hot path.

### Key capabilities

- **Wallet** — Create a new wallet or import via private key / recovery phrase; balances on Base mainnet
- **Models** — Browse active models with MAX Privacy (TEE-only) filter
- **Sessions** — Open, reuse, and close on-chain sessions; configurable duration and stake estimation
- **Chat** — Streaming inference via MOR-RPC to providers; customizable system prompts, per-conversation tuning (temperature, top_p, max_tokens)
- **MOR Balance Scanner** — Read-only on-chain scan showing MOR across wallet, active sessions, and on-hold timelock; recover claimable tokens with one tap
- **Encryption** — Chat messages, titles, system prompts, and metadata encrypted at rest (AES-256-GCM, wallet-derived key)
- **Wallet-scoped data** — Each wallet gets its own encrypted database; re-importing a wallet restores conversations
- **Backup & restore** — Export/import encrypted backups (.nnbak) for conversations, settings, and preferences
- **AI Gateway** — Local OpenAI-compatible HTTP server for external tools (Cursor, LangChain, Claude Desktop)
- **Developer API** — Embedded Swagger with auto-generated HTTP Basic Auth credentials; selective route registration for safe embedded operation
- **MCP Server** — Stdio bridge so Cursor / Claude Desktop can chat through Morpheus without leaving the IDE

## Architecture

```
Flutter UI → dart:ffi → Go c-shared (.dylib) → proxy-router mobile SDK → Morpheus Network
                                              → active models HTTP (cached)
```

- **Flutter** for cross-platform UI (macOS + iOS shipping, Android / Linux / Windows on the backlog) — accordion-style settings screens
- **Go** `c-shared` library (`libnodeneo.dylib` on macOS, static `libnodeneo.a` on iOS device + simulator) — embeds `proxy-router/mobile` SDK
- **SQLite** for conversations, messages, preferences — wallet-scoped with column-level encryption
- **Platform** secure storage (Keychain) + optional biometrics (Face ID / Touch ID)

Full architecture docs: [.ai-docs/architecture.md](.ai-docs/architecture.md)

## Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS (Apple Silicon / Intel) | Shipping | Signed & notarized DMG via GitHub Releases |
| iOS — iPhone (iOS 16+) | Shipping | TEE attestation working, TestFlight in progress |
| iOS — iPad | Planned | Adaptive layout (split-view chat + sidebar) |
| Android | Planned | Flutter + Go `gomobile` builds fine, UI polish + secure store TBD |
| Linux | Future | Flutter Linux runner + CGO cross-compile |
| Windows | Future | Evaluate demand |

---

### Build from source

Requires **Go 1.26+**, **Flutter 3.41.7+**, **Xcode** (macOS/iOS), and **Python 3** with `cairosvg` (`pip install cairosvg`).

Node Neo pins a specific pseudo-version of the [absgrafx fork of Morpheus-Lumerin-Node](https://github.com/absgrafx/Morpheus-Lumerin-Node) via `go/go.mod` — you do **not** need a sibling clone for a release build. If you want to hack on the fork alongside Node Neo, add a local `replace` directive to `go/go.mod` pointing at your checkout.

```bash
git clone git@github.com:absgrafx/nodeneo.git
cd nodeneo

# macOS: full dev build (clean → pub get → brand assets → Go dylib → flutter run)
make dev-macos

# macOS: day-to-day fast iteration (skip clean + icon/splash regen)
make go-macos && make run-macos

# iOS Simulator (arm64 host)
make run-ios-sim

# iOS device — plug in phone, trust, then:
make go-ios && flutter run --release -d <device-udid>
```

See the [Makefile](Makefile) for all targets.

---

## License

MIT — see [LICENSE](LICENSE)

---

<sub>By <a href="https://github.com/absgrafx">absgrafx</a>. Protocol and upstream repos: <a href="https://github.com/MorpheusAIs">MorpheusAIs</a>.</sub>
