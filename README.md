# Node Neo

**By [absgrafx](https://github.com/absgrafx).** A mobile-first, privacy-maximizing client for the **Morpheus** decentralized AI network (protocol and upstream repos live under [MorpheusAIs on GitHub](https://github.com/MorpheusAIs)).

**The Signal of decentralized AI inference.**

**Bundle / application id:** `com.absgrafx.nodeneo`

## What is this?

Node Neo is a clean, consumer-grade app for the Morpheus network: wallet, MOR staking, model pick, and chat — with **Secure (TEE)** models running through the same **attestation** path as the Morpheus proxy-router daemon (embedded SDK, not a separate HTTP server).

## Architecture

- **Flutter** for cross-platform UI (iOS, Android, macOS)
- **Go** `c-shared` library (`libnodeneo`) — **embeds `proxy-router/mobile` SDK** (wallet, chain, sessions, MOR-RPC chat)
- **SQLite** for conversations, messages, preferences
- **Platform** secure storage + optional app lock / biometrics

No standalone proxy-router process is required for normal use.

See [.ai-docs/architecture.md](.ai-docs/architecture.md) and [.ai-docs/handoff_context.md](.ai-docs/handoff_context.md) for design and current surface area.

## Status

Active development on **Base mainnet**. Roadmap and **MVP alpha backlog**: [.ai-docs/plan.md](.ai-docs/plan.md).

## Quick Start (macOS)

```bash
# Prerequisites: Go 1.26+, Flutter 3.x, Xcode, Python 3 + cairosvg (pip install cairosvg)
# Fork: Morpheus-Lumerin-Node on branch feat-external_embedding (go.mod replace → proxy-router)

# One-shot dev refresh (poka-yoke): clean, pub get, brand PNGs, launcher icons, native splash, Go dylib, flutter run
make dev-macos

# Fast day-to-day (no clean, no icon/splash regen)
make go-macos && make run-macos
```

### Brand / launcher / splash only (no clean, no run)

```bash
make brand-assets
```

### Dev script options

- **`SKIP_CLEAN=1 ./tools/dev_macos.sh`** — same pipeline as `make dev-macos` but skips `flutter clean` for faster iteration.

## Targets

| Platform | Status |
|----------|--------|
| macOS (arm64) | In progress |
| iOS | Planned |
| Android | Planned |
| Linux | Future |
| Windows | Future |

## License

MIT — see [LICENSE](LICENSE)
