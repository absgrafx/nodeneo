#!/usr/bin/env python3
"""Build square token PNGs: Morpheus green + MOR mark, Ethereum blue + ETH diamond.

Sources (in assets/branding/):
  - MOR_WHITE_256.png
  - eth-diamond-(purple).png

Outputs:
  - token_mor_base_square.png
  - token_eth_base_square.png

Requires: pip install pillow
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as e:
    print("Install Pillow: pip install pillow", file=sys.stderr)
    raise SystemExit(1) from e

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "assets" / "branding"
SIZE = 512

# Match lib/widgets/crypto_token_icons.dart gradients (MOR / ETH token circles).
MOR_TOP = (0x20, 0xDC, 0x8E)
MOR_BOT = (0x0D, 0x9B, 0x6C)
ETH_TOP = (0x62, 0x7E, 0xEA)
ETH_BOT = (0x45, 0x48, 0xB0)


def diagonal_gradient_rgba(size: int, rgb_a: tuple[int, int, int], rgb_b: tuple[int, int, int]) -> Image.Image:
    """Top-left → bottom-right diagonal (same visual as Flutter LinearGradient TL→BR)."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    denom = max(2 * (size - 1), 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom
            r = int(rgb_a[0] + (rgb_b[0] - rgb_a[0]) * t)
            g = int(rgb_a[1] + (rgb_b[1] - rgb_a[1]) * t)
            b = int(rgb_a[2] + (rgb_b[2] - rgb_a[2]) * t)
            px[x, y] = (r, g, b, 255)
    return img


def paste_centered_cover(bg: Image.Image, fg: Image.Image, margin_ratio: float = 0.12) -> Image.Image:
    fg = fg.convert("RGBA")
    w, h = bg.size
    margin = int(w * margin_ratio)
    max_side = w - 2 * margin
    scale = min(max_side / fg.width, max_side / fg.height)
    nw = max(1, int(fg.width * scale))
    nh = max(1, int(fg.height * scale))
    fg = fg.resize((nw, nh), Image.Resampling.LANCZOS)
    x = (w - nw) // 2
    y = (h - nh) // 2
    out = bg.copy()
    out.paste(fg, (x, y), fg)
    return out


def main() -> None:
    os.chdir(ROOT)

    mor_src = BRAND / "MOR_WHITE_256.png"
    eth_src = BRAND / "eth-diamond-(purple).png"
    for p in (mor_src, eth_src):
        if not p.is_file():
            print(f"Missing: {p}", file=sys.stderr)
            raise SystemExit(1)

    mor_bg = diagonal_gradient_rgba(SIZE, MOR_TOP, MOR_BOT)
    mor_fg = Image.open(mor_src)
    mor_out = paste_centered_cover(mor_bg, mor_fg)
    mor_path = BRAND / "token_mor_base_square.png"
    mor_out.save(mor_path, "PNG", optimize=True)
    print(f"Wrote {mor_path}")

    eth_bg = diagonal_gradient_rgba(SIZE, ETH_TOP, ETH_BOT)
    eth_fg = Image.open(eth_src)
    eth_out = paste_centered_cover(eth_bg, eth_fg)
    eth_path = BRAND / "token_eth_base_square.png"
    eth_out.save(eth_path, "PNG", optimize=True)
    print(f"Wrote {eth_path}")


if __name__ == "__main__":
    main()
