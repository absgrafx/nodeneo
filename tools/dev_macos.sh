#!/usr/bin/env bash
# Poka-yoke dev run: clean → deps → brand pipeline → Go dylib → flutter run (macOS).
# Requires: Flutter SDK, Go, Python 3 + cairosvg (`pip install cairosvg`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_CLEAN="${SKIP_CLEAN:-0}"

step() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

step "Checking Python cairosvg (brand PNGs)"
python3 -c "import cairosvg" 2>/dev/null || {
  echo "Missing cairosvg. Install:  pip install cairosvg" >&2
  exit 1
}

if [[ "$SKIP_CLEAN" != "1" ]]; then
  step "flutter clean"
  flutter clean
else
  step "Skipping flutter clean (SKIP_CLEAN=1)"
fi

step "flutter pub get"
flutter pub get

step "Rasterize SVG → PNG + copy splash to macOS xcassets"
python3 tools/branding/render_launcher_icons.py

step "dart run flutter_launcher_icons"
dart run flutter_launcher_icons

step "dart run flutter_native_splash:create"
dart run flutter_native_splash:create

step "Go shared library (libredpill.dylib)"
make go-macos

step "Copy dylib into Debug app bundle (ok if folder missing until first build)"
make _copy-dylib-macos || true

step "flutter run -d macos"
exec flutter run -d macos
