#!/usr/bin/env bash
# Poka-yoke dev run: clean → deps → brand pipeline → Go dylib → flutter run (macOS).
# Requires: Flutter SDK, Go, Python 3 + cairosvg (`pip install cairosvg`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_CLEAN="${SKIP_CLEAN:-0}"

step() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

step "Checking brand PNGs"
python3 tools/branding/render_launcher_icons.py

if [[ "$SKIP_CLEAN" != "1" ]]; then
  step "flutter clean"
  flutter clean
else
  step "Skipping flutter clean (SKIP_CLEAN=1)"
fi

step "flutter pub get"
flutter pub get

step "dart run flutter_launcher_icons"
dart run flutter_launcher_icons

step "dart run flutter_native_splash:create"
dart run flutter_native_splash:create

step "Go shared library (libnodeneo.dylib)"
make go-macos

step "Copy dylib into Debug app bundle (ok if folder missing until first build)"
make _copy-dylib-macos || true

DART_DEFINES=""
if [[ -n "${ETH_RPC_URL:-}" ]]; then
  DART_DEFINES="--dart-define=ETH_RPC_URL=${ETH_RPC_URL}"
  step "flutter run -d macos (with premium RPC)"
else
  step "flutter run -d macos (public RPCs only)"
fi
exec flutter run -d macos $DART_DEFINES
