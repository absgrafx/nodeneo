#!/usr/bin/env python3
"""Prepare Node Neo brand PNGs for flutter_launcher_icons / flutter_native_splash.

The source PNGs live in assets/branding/ (glasses on black = app icon + splash).
This script copies the splash logo into the macOS xcassets imageset so the native
overlay in MainFlutterWindow stays in sync.

Usage (from repo root):
  python3 tools/branding/render_launcher_icons.py
"""

from __future__ import annotations

import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BRAND = os.path.join(ROOT, "assets", "branding")


def _copy_splash_to_macos_imageset() -> None:
    """Keep macOS Runner asset in sync with splash_logo.png (native overlay in MainFlutterWindow)."""
    src = os.path.join(BRAND, "splash_logo.png")
    if not os.path.isfile(src):
        print(f"WARNING: {src} not found — skipping macOS imageset copy", file=sys.stderr)
        return
    dst_dir = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets", "SplashLogo.imageset")
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, "splash_logo.png")
    shutil.copy2(src, dst)
    print(f"Copied splash to {dst}")


def main() -> None:
    os.chdir(ROOT)
    for name in ("app_icon_full.png", "app_icon_foreground.png", "splash_logo.png"):
        path = os.path.join(BRAND, name)
        if os.path.isfile(path):
            print(f"OK  {path}")
        else:
            print(f"MISSING  {path}", file=sys.stderr)
    _copy_splash_to_macos_imageset()
    print("Done.")


if __name__ == "__main__":
    main()
