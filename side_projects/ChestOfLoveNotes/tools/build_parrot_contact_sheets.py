#!/usr/bin/env python3
"""Build animation contact sheets for the FREE parrot once artwork exists.

Phase 1B-2A: scaffolding only. With no frames present, exits 0 and prints
AWAITING_ARTWORK without writing image output.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    Image = None  # type: ignore
    ImageDraw = None  # type: ignore
    ImageFont = None  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "assets" / "pets" / "parrot" / "parrot_animation_manifest.json"
PARROT_ROOT = ROOT / "assets" / "pets" / "parrot"
DEFAULT_OUT_DIR = ROOT / "assets" / "pets" / "parrot" / "source" / "contact_sheets"


def expected_filename(pattern: str, index: int, anim_name: str, folder: str) -> str:
    if not pattern:
        defaults = {
            "idle": "parrot_idle_{:02d}.png",
            "move": "parrot_move_{:02d}.png",
            "chest_interaction": "parrot_chest_{:02d}.png",
            "tap_reaction": "parrot_tap_{:02d}.png",
        }
        tmpl = defaults.get(anim_name, f"parrot_{folder}_{{:02d}}.png")
        return tmpl.format(index)
    if "{index:02d}" in pattern:
        return pattern.replace("{index:02d}", f"{index:02d}")
    if "{index}" in pattern:
        return pattern.replace("{index}", str(index))
    if "%" in pattern:
        return pattern % index
    return pattern


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help="Output directory for contact sheets (gitignored recommended)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Write sheets even if some frames are missing (gaps filled empty)",
    )
    args = parser.parse_args()

    if not MANIFEST_PATH.is_file():
        print("STATUS: MANIFEST_MISSING")
        return 1

    with MANIFEST_PATH.open("r", encoding="utf-8") as f:
        manifest = json.load(f)

    cw = int(manifest.get("frame_canvas_width", 128))
    ch = int(manifest.get("frame_canvas_height", 128))
    anims = manifest.get("animations", [])
    present_total = 0
    missing_total = 0
    planned: list[tuple[str, list[Path]]] = []

    for anim in anims:
        name = str(anim.get("name", ""))
        folder = str(anim.get("folder", name))
        pattern = str(anim.get("filename_pattern", ""))
        count = int(anim.get("expected_frame_count", 0))
        paths: list[Path] = []
        for i in range(count):
            fname = expected_filename(pattern, i, name, folder)
            fpath = PARROT_ROOT / folder / fname
            if fpath.is_file():
                present_total += 1
                paths.append(fpath)
            else:
                missing_total += 1
                paths.append(fpath)  # keep slot for --force
        planned.append((name, paths))

    if present_total == 0:
        print(
            json.dumps(
                {
                    "status": "AWAITING_ARTWORK",
                    "present": present_total,
                    "missing": missing_total,
                    "wrote": [],
                },
                indent=2,
            )
        )
        print("STATUS: AWAITING_ARTWORK")
        print("No contact sheets written (no parrot frames yet).")
        return 0

    if Image is None:
        print("STATUS: ERROR — Pillow required to build contact sheets")
        return 1

    if missing_total and not args.force:
        print(
            json.dumps(
                {
                    "status": "AWAITING_ARTWORK",
                    "present": present_total,
                    "missing": missing_total,
                    "note": "Partial set; pass --force to write incomplete sheets",
                },
                indent=2,
            )
        )
        print("STATUS: AWAITING_ARTWORK")
        return 0

    args.out_dir.mkdir(parents=True, exist_ok=True)
    wrote: list[str] = []
    pad = 8
    label_h = 24
    for name, paths in planned:
        n = len(paths)
        sheet_w = pad + n * (cw + pad)
        sheet_h = pad + label_h + ch + pad
        sheet = Image.new("RGBA", (sheet_w, sheet_h), (24, 28, 36, 255))
        draw = ImageDraw.Draw(sheet)
        draw.text((pad, 4), f"parrot / {name}", fill=(230, 230, 230, 255))
        for i, fpath in enumerate(paths):
            x = pad + i * (cw + pad)
            y = pad + label_h
            if fpath.is_file():
                with Image.open(fpath) as im:
                    frame = im.convert("RGBA")
                    if frame.size != (cw, ch):
                        frame = frame.resize((cw, ch), Image.Resampling.NEAREST)
                    sheet.alpha_composite(frame, (x, y))
            else:
                draw.rectangle([x, y, x + cw - 1, y + ch - 1], outline=(180, 80, 80, 255))
            # Ground-anchor crosshair for review.
            ax = x + int(manifest.get("ground_anchor_x", 64))
            ay = y + int(manifest.get("ground_anchor_y", 116))
            draw.line([(ax - 4, ay), (ax + 4, ay)], fill=(255, 200, 80, 200), width=1)
            draw.line([(ax, ay - 4), (ax, ay + 4)], fill=(255, 200, 80, 200), width=1)
        out = args.out_dir / f"parrot_{name}_contact.png"
        sheet.save(out)
        wrote.append(str(out.relative_to(ROOT)))

    print(json.dumps({"status": "WROTE", "wrote": wrote}, indent=2))
    print("STATUS: WROTE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
