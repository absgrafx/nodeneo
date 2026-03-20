# RedPill

A mobile-first, privacy-maximizing client for the [MorpheusAIs](https://github.com/MorpheusAIs) decentralized AI network.

**The Signal of decentralized AI inference.**

## What is this?

RedPill is a clean, consumer-grade app for the MorpheusAIs network: wallet, MOR staking, model pick, and chat — with **Secure (TEE)** models running through the same **attestation** path as the Morpheus proxy-router daemon (embedded SDK, not a separate HTTP server).

## Architecture

- **Flutter** for cross-platform UI (iOS, Android, macOS)
- **Go** `c-shared` library (`libredpill`) — **embeds `proxy-router/mobile` SDK** (wallet, chain, sessions, MOR-RPC chat)
- **SQLite** for conversations, messages, preferences
- **Platform** secure storage + optional app lock / biometrics

No standalone proxy-router process is required for normal use.

See [.ai-docs/redpill_architecture.md](.ai-docs/redpill_architecture.md) and [.ai-docs/handoff_context.md](.ai-docs/handoff_context.md) for design and current surface area.

## Status

Active development on **Base mainnet**. Roadmap and **MVP alpha backlog**: [.ai-docs/redpill_plan.md](.ai-docs/redpill_plan.md) (items 1–8: dev setup, branding, settings polish, naming, autofill, onboarding, usage dashboard, gateway parity).

## Quick Start (macOS)

```bash
# Prerequisites: Go 1.26+, Flutter 3.x, Xcode
# Fork: Morpheus-Lumerin-Node on branch feat-external_embedding (go.mod replace → proxy-router)

# Build the Go native library
make go-macos

# Run the Flutter app
make run-macos
```

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
