# RedPill

A mobile-first, privacy-maximizing client for the [MorpheusAIs](https://github.com/MorpheusAIs) decentralized AI network.

**The Signal of decentralized AI inference.**

## What is this?

RedPill is a clean, consumer-grade app that gives you a beautiful UI for the MorpheusAIs network. Create a wallet, stake MOR, pick a model, and chat — with TEE attestation verified on every prompt.

## Architecture

- **Flutter** for cross-platform UI (iOS, Android, macOS)
- **Go** for native wallet operations (BIP-39, go-ethereum key derivation)
- **Proxy-router** as the blockchain/session/chat backend (HTTP API)
- **SQLite** for local chat persistence
- **Platform-native** biometric auth and key storage (planned)

The Go layer handles wallet creation/import natively using the same crypto libraries as the proxy-router (go-ethereum, go-bip39). Blockchain operations, session management, and chat completions are delegated to a running proxy-router instance via its REST API.

See [.ai-docs/redpill_architecture.md](.ai-docs/redpill_architecture.md) for the full design.

## Status

Early development. See [.ai-docs/redpill_plan.md](.ai-docs/redpill_plan.md) for progress.

## Quick Start (macOS)

```bash
# Prerequisites: Go 1.26+, Flutter 3.x, Xcode
# Also need a running proxy-router instance (default: localhost:8082)

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
