## What's New in v3.3.0

The iOS TestFlight readiness release. Every change in this cycle closes a "first 60 seconds with the app" rough edge — biometrics, app deletion, offline behaviour, wallet onboarding. Validated on a ProMotion iPhone (iPhone 17 Pro, iOS 26.4.2).

### Biometrics-First App Lock UX
The lock screen used to show a password field with a small "Use biometrics" button — the wrong default on a Face ID device. Reworked to put biometrics front-and-center while keeping the password as a deliberate fallback:

- **Auto-prompt on mount** — Face ID is requested as soon as the lock screen appears; cancel falls through silently to a manual button so the framework can't loop the prompt
- **New `LockMode` enum** (`off | biometricOnly | passwordOnly | passwordWithBiometric`) — biometric-only mode never writes a password hash, so there's nothing to forget or recover
- **Mode-aware layout** — `biometricOnly` hides the password field entirely; `passwordWithBiometric` keeps the field collapsed by default behind a "Use password instead" link
- **Setup chooser** verifies a real biometric prompt before flipping the storage flag, so a misconfigured device can't strand the user
- **Recovery path** — Always uses the wallet's private key (no separate password reset flow needed)

### Private-Key-Only Wallets
Removed the BIP-39 mnemonic / seed-phrase fork from the entire app. Node Neo is a single-account hot wallet — multiple derived addresses were never on the roadmap, so the seed-phrase path was strictly heavier than the PK path:

- **Onboarding** — single hex-PK input field; no Private Key / Recovery Phrase tab
- **App-lock recovery sheet** — single PK input; no Phrase / Private Key segmented control
- **`WalletVault` rewritten** with PK-only public API (`savePrivateKey`, `readPrivateKey`, `clearStoredSecret`, etc.)
- **One-shot legacy migration** — users who previously imported via mnemonic get auto-migrated on first launch: the mnemonic is read from the Keychain, the account-zero PK is derived via the embedded Go SDK, the PK is persisted, and the mnemonic is deleted. Crash-safe (writes the PK before deleting the mnemonic). No-op for new installs.
- All "phrase or key" / "wallet seed" copy across the security UI replaced with "private key"

### Network Reachability + Friendlier Error Screens
Airplane mode used to drop the user on "SDK Init Failed (Edit Custom RPC)" — a misleading screen that steers a network problem into a blockchain-config dead end. Replaced with a layered reachability gate that applies on all platforms:

- **DNS canary probe** — `lib/services/network_reachability.dart` runs `InternetAddress.lookup` against multiple hosts (3s timeout, zero new dependencies) before any blocking Go FFI call
- **Dedicated offline screen** at startup with a single Try Again CTA — clear "check your Wi-Fi or cellular data" copy
- **"Blockchain unreachable"** replaces "SDK Init Failed" when the device is online but the chain RPC is down — normal-language subtitle, "Edit blockchain endpoint" instead of "Edit Custom RPC", raw error tucked behind a "Show technical details" expander
- **Persistent `OfflineBanner`** pinned above the scroll view on Home and Chat — appears when the device goes offline mid-session and stays until reconnected
- **Loader and chat guards** — `_loadWallet` / `_loadModels` / `_computeAffordability` and the periodic 45 s timer early-return when offline; chat send and new-session creation gate on a fresh canary check, with an amber snackbar that preserves the user's typed message. Drops offline pull-to-refresh feedback from ~120 s of RPC fallback timeout to <1 s.

### Fresh-Install Reconciliation (iOS App-Delete)
On iOS / macOS the platform Keychain survives an app uninstall — Apple's intent is fumble-finger protection for password managers, but for a crypto wallet that's the wrong default. Users who explicitly deleted the app were surprised to see their previous wallet auto-restore on reinstall.

- New `FirstLaunchGuard` (`lib/services/first_launch_guard.dart`) writes a `.install_sentinel` file inside the app data directory on first run
- Every cold start checks for the sentinel **before** reading the wallet vault — if missing (= container was wiped or genuine first launch), the Keychain is wiped and the sentinel written
- Subsequent launches see the sentinel and skip the wipe — zero overhead after first run
- In-app *Erase Wallet* and *Full Factory Reset* keep the sentinel intact (no false-positive re-wipe)

### iOS Build Pipeline Hardening
Two long-running iOS install puzzles, both root-caused and fixed:

- **Cross-arch native_assets cache pollution** — bouncing between simulator and device on the same checkout used to fail at codesign with `0xe8008014 invalid signature` on `objective_c.framework`. Root cause: Flutter's `build/native_assets/ios/` cache is keyed by package, not target arch — the simulator slice silently shadowed the device slice. Fixed in `Makefile` via `_ios-stamp-device` / `_ios-stamp-sim` helpers that wipe the polluted cache on direction changes. Manual escape hatch: `make ios-clean`.
- **Flutter implicit-engine SIGSEGV on iOS 26 + ProMotion** — the actual root cause of "Phlame stalls at the splash screen forever" (it's not a hang, it's a hard `EXC_BAD_ACCESS` in `-[VSyncClient initWithTaskRunner:callback:]` that iOS perceives as a hang because the LaunchScreen stays up until the watchdog kills the dead process). Tracking [flutter/flutter#183900](https://github.com/flutter/flutter/issues/183900). Fixed by switching `ios/Runner/` from the implicit engine pattern to the explicit pattern: `SceneDelegate` now constructs a `FlutterEngine`, calls `run()`, registers plugins, then attaches the `FlutterViewController` to the fully-initialized engine. `Info.plist` no longer references `Main.storyboard`. Revert plan documented for when Flutter PR #184639 lands in stable.
- **`make install-ios-profile`** new target — sidesteps the iOS 26 `flutter run` VM Service attach hang by building in profile mode (AOT, no debugger needed) and installing via `xcrun devicectl`

### iOS Impact / Compatibility
- All changes are platform-neutral except where noted; `FirstLaunchGuard` and the `Makefile` iOS targets are iOS-specific
- The legacy mnemonic→PK migration runs once on cold start for upgraded users; new installs see no migration
- The explicit Flutter engine pattern is a hand-coded workaround for an upstream Flutter bug — when [PR #184639](https://github.com/flutter/flutter/issues/184639) lands in stable, four files in `ios/Runner/` can be reverted to the implicit pattern
- Gateway (desktop-only feature, gated by `PlatformCaps.supportsGateway`) is unchanged in this release

---

## Previous Releases

Full notes for each prior release are pinned to its tag page on GitHub.

| Version | Date | Headline |
|---------|------|----------|
| [v3.2.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.2.0) | 2026-04-30 | Cursor / Zed-class AI Gateway — full OpenAI Chat Completions parity (`tools`, `tool_choice`, `reasoning_content`, `MultiContent`); `/v1/embeddings` + `/v1/completions`; capability flags; three-layer endpoint redaction |
| [v3.1.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.1.0) | 2026-04-24 | Chat reliability patch — reasoning-only stream completions no longer surface as a false error ([#66](https://github.com/absgrafx/nodeneo/pull/66)) |
| [v3.0.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.0.0) | 2026-04-24 | Full TEE compliance with proxy-router v7.0.0 on macOS + iPhone, pre-session confirmation flow, in-place affordability, wallet card redesign, provider-endpoint redaction, RPC failover, Flutter 3.41.7 |
| [v2.7.0](https://github.com/absgrafx/nodeneo/releases/tag/v2.7.0) | 2026-04 | iOS (iPhone) first light, two-zone thinking/reasoning model support, stop/cancel generation, MOR scanner fix, collapsible wallet card, factory reset via "DELETE ALL" |
| [Older](https://github.com/absgrafx/nodeneo/releases) | — | Full release archive |
