#!/usr/bin/env python3
"""Rasterize SVG branding to PNGs for flutter_launcher_icons / flutter_native_splash.

Requires: pip install cairosvg  (already used in dev environments)

Usage (from repo root):
  python3 tools/branding/render_launcher_icons.py
"""

from __future__ import annotations

import os
import shutil
import sys

try:
    import cairosvg
except ImportError as e:
    print("Install cairosvg: pip install cairosvg", file=sys.stderr)
    raise SystemExit(1) from e

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BRAND = os.path.join(ROOT, "assets", "branding")


def svg_to_png(name: str, out_name: str, size: int) -> None:
    src = os.path.join(BRAND, name)
    dst = os.path.join(BRAND, out_name)
    with open(src, "rb") as f:
        svg_bytes = f.read()
    cairosvg.svg2png(bytestring=svg_bytes, write_to=dst, output_width=size, output_height=size)
    print(f"Wrote {dst} ({size}x{size})")


def main() -> None:
    os.chdir(ROOT)
    # Launcher icons (flutter_launcher_icons expects PNG paths in pubspec)
    svg_to_png("app_icon_foreground.svg", "app_icon_foreground.png", 1024)
    svg_to_png("app_icon_full.svg", "app_icon_full.png", 1024)
    # Native splash: white mark on #0C0C0C is configured in pubspec; image is logo only
    svg_to_png("morpheus_logo_white.svg", "splash_logo.png", 512)
    _copy_splash_to_macos_imageset()
    print("Done.")


def _copy_splash_to_macos_imageset() -> None:
    """Keep macOS Runner asset in sync with splash_logo.png (native overlay in MainFlutterWindow)."""
    src = os.path.join(BRAND, "splash_logo.png")
    dst_dir = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets", "SplashLogo.imageset")
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, "splash_logo.png")
    shutil.copy2(src, dst)
    print(f"Copied splash to {dst}")


if __name__ == "__main__":
    main()
