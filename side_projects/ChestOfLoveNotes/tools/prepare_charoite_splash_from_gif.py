#!/usr/bin/env python3
"""Convert the APPROVED Charoite Games splash GIF into Godot SpriteFrames assets.

Source of truth (do not redraw/regenerate/recolor):
  assets/branding/154659_cursor_under4mb.gif

Outputs (derived, for runtime playback only):
  assets/branding/splash_frames/frame_XXXX.png
  assets/branding/splash_still.png          (representative first frame for native/Android)
  assets/branding/charoite_cg_splash_frames.tres metadata sidecar JSON
    (Godot SpriteFrames is built at runtime from the PNG sequence + durations)

Preserves frame order and per-frame timing. No artistic changes.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "branding" / "154659_cursor_under4mb.gif"
FRAMES_DIR = ROOT / "assets" / "branding" / "splash_frames"
STILL = ROOT / "assets" / "branding" / "splash_still.png"
META = ROOT / "assets" / "branding" / "splash_frames_meta.json"


def main() -> int:
    if not SRC.is_file():
        print(f"ERROR: approved splash GIF missing: {SRC}", file=sys.stderr)
        return 2
    try:
        from PIL import Image
    except ImportError:
        import subprocess

        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pillow"])
        from PIL import Image

    img = Image.open(SRC)
    if not getattr(img, "is_animated", False):
        print("WARNING: GIF reports not animated — exporting single frame")

    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    # Clear prior derived frames only
    for old in FRAMES_DIR.glob("frame_*.png"):
        old.unlink()

    n = getattr(img, "n_frames", 1)

    # The approved splash composites to fully opaque frames, but writing them as
    # RGBA stored a constant 255 channel for every pixel of every frame — a
    # quarter of the splash's runtime texture memory spent on nothing. Drop the
    # channel when (and only when) nothing in the animation actually uses it.
    # Pixels are still preserved exactly; this changes storage, not appearance.
    uses_alpha = False
    for i in range(n):
        img.seek(i)
        if img.convert("RGBA").getchannel("A").getextrema()[0] != 255:
            uses_alpha = True
            break
    frame_mode = "RGBA" if uses_alpha else "RGB"
    print(f"frame storage: {frame_mode} (animation {'uses' if uses_alpha else 'has no'} transparency)")

    durations_ms: list[int] = []
    for i in range(n):
        img.seek(i)
        frame = img.convert("RGBA").convert(frame_mode) if frame_mode == "RGB" else img.convert("RGBA")
        # Preserve pixels as-is (no resize/recolor). PNG is lossless either way.
        out = FRAMES_DIR / f"frame_{i:04d}.png"
        frame.save(out, format="PNG", optimize=True)
        dur = int(img.info.get("duration", 100) or 100)
        if dur <= 0:
            dur = 100
        durations_ms.append(dur)
        if i == 0:
            frame.save(STILL, format="PNG", optimize=True)

    meta = {
        "source": "154659_cursor_under4mb.gif",
        "source_redrawn": False,
        "frame_count": n,
        "durations_ms": durations_ms,
        "frame_glob": "splash_frames/frame_%04d.png",
        "still": "splash_still.png",
    }
    META.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    total = sum(durations_ms) / 1000.0
    print(
        f"OK: extracted {n} frames from {SRC.name} "
        f"(loop≈{total:.2f}s) → {FRAMES_DIR.relative_to(ROOT)} + {STILL.name}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
