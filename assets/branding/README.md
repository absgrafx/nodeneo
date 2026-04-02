# Node Neo branding assets

Decentralised AI inference client, published as **Node Neo** / `com.nodeneo.app`.

## Runtime assets (bundled in app)

- **`wordmark_v2.png`** — combined glasses + Matrix-font "NODE NEO" wordmark (transparent RGBA). Used in the home screen app bar.
- **`splash_logo.png`** — angled glasses on transparent background. Used for `flutter_native_splash`, onboarding screen, and lock screen via [`NeoLogo`](../../lib/widgets/morpheus_logo.dart).
- **`app_icon_full.png`** — glasses on midnight `#0C0C0C` square. Used by `flutter_launcher_icons` for iOS / macOS / default launcher.
- **`app_icon_foreground.png`** — glasses on transparent square. Used for Android adaptive foreground.
- **`base_chip.png`** — Base network badge for [`TokenWithBaseInlay`](../../lib/widgets/crypto_token_icons.dart).
- **`token_eth_base_square.png`** / **`token_mor_base_square.png`** — wallet token icons.
- **`dmg-background.png`** — macOS DMG installer background.

## Source vectors

- **`app_icon_foreground.svg`** / **`app_icon_full.svg`** — SVG source for launcher icons.

## Colour palette

| Name         | Hex       | Usage                          |
|--------------|-----------|--------------------------------|
| Midnight     | `#0C0C0C` | Scaffold / background          |
| Matrix Green | `#30D020` | Primary brand / buttons / glow |
| Neon Mint    | `#00FF85` | High-contrast accent           |
| Eclipse      | `#1C302F` | Card / surface fill            |
| Platinum     | `#EBEBEB` | Primary text on dark           |

## Regenerating PNGs (launcher + splash)

From repo root: **`make dev-macos`** (full macOS dev refresh), or manually:

```bash
python3 tools/branding/render_launcher_icons.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### macOS desktop splash

`flutter_native_splash` does not patch macOS. The repo matches iOS/Android/Web by configuring `color` + `splash_logo.png` in `pubspec.yaml`, then:

- Copying `splash_logo.png` into `macos/Runner/Assets.xcassets/SplashLogo.imageset/` (done by the render script).
- Showing a native overlay in `macos/Runner/MainFlutterWindow.swift` until the first Flutter frame, faded via `MethodChannel` from [`lib/macos_splash_removal.dart`](../../lib/macos_splash_removal.dart).

Configuration: **`pubspec.yaml`** (`flutter_launcher_icons` / `flutter_native_splash`).
