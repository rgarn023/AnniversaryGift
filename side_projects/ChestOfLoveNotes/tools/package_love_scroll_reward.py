#!/usr/bin/env python3
"""Package new_love_scroll_master.png into a horizontal production reward scroll.

Pixel rotate/crop/resize only — no AI, no repaint.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/chest/animation_v2/incoming_new_art/new_love_scroll_master.png"
DST = ROOT / "assets/chest/animation_v2/scroll/love_scroll_reward.png"
# Empirically levels the rolled cylinder axis near horizontal while keeping ribbon/heart.
DESKEW_DEG = -100.0
TARGET_W = 720


def main() -> None:
    arr = np.array(Image.open(SRC).convert("RGBA"))
    lum = arr[:, :, :3].astype(np.float32).mean(axis=2)
    arr[:, :, 3] = np.where(lum < 18, 0, arr[:, :, 3]).astype(np.uint8)
    im = Image.fromarray(arr, "RGBA")
    up = im.rotate(DESKEW_DEG, expand=True, resample=Image.Resampling.BICUBIC)
    ua = np.array(up)
    lum = ua[:, :, :3].astype(np.float32).mean(axis=2)
    ua[:, :, 3] = np.where((lum < 16) | (ua[:, :, 3] < 18), 0, ua[:, :, 3]).astype(np.uint8)
    ys, xs = np.where(ua[:, :, 3] > 30)
    crop = ua[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    th = max(1, int(round(TARGET_W * crop.shape[0] / crop.shape[1])))
    prod = Image.fromarray(crop, "RGBA").resize((TARGET_W, th), Image.Resampling.LANCZOS)
    DST.parent.mkdir(parents=True, exist_ok=True)
    prod.save(DST, "PNG")
    print(f"OK wrote {DST} size={prod.size}")


if __name__ == "__main__":
    main()
