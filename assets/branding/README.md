# RedPill branding assets (absgrafx)

Morpheus **network** mark and in-app visuals; published as **RedPill** / `com.absgrafx.redpill`.

- **`token_mor_base_square.png`** / **`token_eth_base_square.png`** — wallet token circles: Morpheus green gradient + `MOR_WHITE_256.png`, ETH blue gradient + `eth-diamond-(purple).png`. Regenerate with **`python3 tools/branding/compose_token_squares.py`** after changing those sources.
- **`base_chip.png`** — Base network badge for [`TokenWithBaseInlay`](../../lib/widgets/crypto_token_icons.dart) (bottom-right inlay).
- **`morpheus_logo_white.svg`** / **`morpheus_logo_green.svg`** — source vectors for in-app [`MorpheusLogo`](../../lib/widgets/morpheus_logo.dart) (`flutter_svg`).
- **`app_icon_foreground.svg`** — centered emerald wings on **transparent** square (1024×1024 design). Rasterized to **`app_icon_foreground.png`** for **Android adaptive foreground**.
- **`app_icon_full.svg`** — same mark on **midnight** `#0C0C0C` full square. Rasterized to **`app_icon_full.png`** for **iOS / macOS / default launcher** (`flutter_launcher_icons` `image_path`).
- **`splash_logo.png`** — white mark on transparent (generated from `morpheus_logo_white.svg`) for **`flutter_native_splash`** (background color `#0C0C0C` in `pubspec.yaml`).

`flutter_svg` does not support `<style>` / CSS classes; keep fills inline on paths (see `morpheus_logo_white.svg`).

## Regenerating PNGs (launcher + splash)

Requires Python **`cairosvg`** (`pip install cairosvg`).

**Recommended (full macOS dev refresh):** from repo root run **`make dev-macos`** — see [README](../../README.md).

Manual equivalent:

```bash
python3 tools/branding/render_launcher_icons.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Or **`make brand-assets`** (same three tool steps; no `flutter clean` / no `flutter run`).

### macOS desktop splash

`flutter_native_splash` **does not** patch macOS projects. This repo matches **iOS/Android/Web** by configuring the same **`color`** + **`splash_logo.png`** in `pubspec.yaml`, then:

- Copying `splash_logo.png` into **`macos/Runner/Assets.xcassets/SplashLogo.imageset/`** (done by the script above).
- Showing a native overlay in **`macos/Runner/MainFlutterWindow.swift`** until the first Flutter frame, then fading it out via **`MethodChannel`** `redpill/macos_splash` from [`lib/macos_splash_removal.dart`](../../lib/macos_splash_removal.dart) / [`lib/main.dart`](../../lib/main.dart).

## Legacy one-off raster (macOS)

```bash
qlmanage -t -s 1024 -o /tmp path/to/morpheus_logo_green.svg
# Prefer the script above — it centers the mark in a square for Dock/About icons.
```

Configuration: **`pubspec.yaml`** (`flutter_launcher_icons` / `flutter_native_splash`).
