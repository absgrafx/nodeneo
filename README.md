# RedPill

A mobile-first, privacy-maximizing client for the MorpheusAIs decentralized AI network.

**The Signal of decentralized AI inference.**

## What is this?

RedPill is a clean, consumer-grade app that wraps the MorpheusAIs proxy-router into a single binary with a beautiful UI. No IPFS, no Docker, no Swagger, no separate processes. Install it, create a wallet, stake MOR, pick a model, and chat — with TEE attestation verified on every prompt.

## Architecture

- **Flutter** for cross-platform UI (iOS, Android, macOS)
- **Go** for the embedded proxy-router engine (compiled via gomobile)
- **SQLite** for local chat persistence
- **Platform-native** biometric auth and key storage

See [.ai-docs/redpill_architecture.md](.ai-docs/redpill_architecture.md) for the full design.

## Status

Early development. See [.ai-docs/redpill_plan.md](.ai-docs/redpill_plan.md) for progress.

## Quick Start (macOS)

```bash
# Prerequisites: Go 1.25+, Flutter 3.x, Xcode

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
