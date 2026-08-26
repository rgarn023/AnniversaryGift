#!/usr/bin/env python3
"""Derive love_scroll_horizontal.png from the approved vertical love_scroll.png.

Exact 90° clockwise rotation only — no repaint, no AI, transparency preserved.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/chest/animation_v2/scroll/love_scroll.png"
DST = ROOT / "assets/chest/animation_v2/scroll/love_scroll_horizontal.png"


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    if im.size != (56, 132):
        raise SystemExit(f"unexpected source size {im.size}; expected (56, 132)")
    # ROTATE_270 == 90° clockwise
    out = im.transpose(Image.Transpose.ROTATE_270)
    if out.size != (132, 56):
        raise SystemExit(f"unexpected output size {out.size}; expected (132, 56)")
    DST.parent.mkdir(parents=True, exist_ok=True)
    out.save(DST, "PNG")
    # Round-trip pixel check
    back = out.transpose(Image.Transpose.ROTATE_90)
    if list(back.getdata()) != list(im.getdata()):
        raise SystemExit("round-trip pixel mismatch — aborting")
    print(f"OK wrote {DST} size={out.size}")


if __name__ == "__main__":
    main()
