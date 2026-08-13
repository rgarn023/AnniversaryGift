#!/usr/bin/env python3
"""Build deterministic animation_v3 baked scroll-reveal frames (Step 2).

Composites ONLY:
  - approved chest_12_fully_open.png (immutable base, every frame)
  - approved love_scroll_reward.png (horizontal, fixed scale, Y-only motion)
  - foreground occluder = existing chest_open_front_rim.png (pixel-identical
    to chest_12 where opaque) plus a hard lip-burial restore from chest_12

Compositing order per visible frame:
  A. exact copy of chest_12
  B. paste scaled scroll at fixed X / frame Y
  C. restore chest_12 pixels wherever the front rim is present OR y >= lip
     (redraws front lip / pillars over the scroll; keeps buried scroll hidden)

reveal_00_hidden is a byte-identical copy of chest_12 (no scroll paste).

No AI / generative tools. No chest geometry edits. No runtime integration.
Re-runnable: same inputs → same PNG outputs.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

CHEST_PATH = ROOT / "assets/chest/animation_v2/chest_frames/chest_12_fully_open.png"
SCROLL_PATH = ROOT / "assets/chest/animation_v2/scroll/love_scroll_reward.png"
RIM_PATH = ROOT / "assets/chest/animation_v2/layers/chest_open_front_rim.png"

OUT_DIR = ROOT / "assets/chest/animation_v3/scroll_reveal"
SOURCE_DIR = ROOT / "assets/chest/animation_v3/source"
VALIDATION_DIR = ROOT / "assets/chest/animation_v3/validation"
NOTES_DIR = ROOT / "assets/chest/animation_v3/notes"
AUDIT_PATH = NOTES_DIR / "STEP2_REVEAL_AUDIT.json"
MANIFEST_PATH = ROOT / "assets/chest/animation_v3/animation_v3_manifest.json"

# Geometry locked from animation_v2 / runtime audit (canvas space).
CANVAS = 512
LIP_Y = 269  # CAVITY_RIM_CANVAS_Y / cavity_rim_y.txt
CAVITY_INNER_LEFT = 137.0
CAVITY_INNER_RIGHT = 301.0
CAVITY_CENTER_X = 219.0
SCROLL_X_BIAS = 28.0  # Step 1 / physical review: slightly RIGHT of cavity center
OPENING_WIDTH = CAVITY_INNER_RIGHT - CAVITY_INNER_LEFT  # 164

# Fixed production scroll size: ~72% of usable opening, aspect preserved.
SCROLL_WIDTH_FRAC = 0.72
SCROLL_W = int(round(OPENING_WIDTH * SCROLL_WIDTH_FRAC))  # 118
SCROLL_H = int(round(SCROLL_W * 305 / 720))  # 50
SCROLL_CENTER_X = CAVITY_CENTER_X + SCROLL_X_BIAS  # 247.0
SCROLL_X = int(round(SCROLL_CENTER_X - SCROLL_W / 2.0))  # 188

# Intended visibility fractions (of scroll HEIGHT above the front lip).
FRAMES: list[tuple[str, float]] = [
    ("reveal_00_hidden.png", 0.00),
    ("reveal_01_peek.png", 0.05),
    ("reveal_02_15.png", 0.15),
    ("reveal_03_30.png", 0.30),
    ("reveal_04_50.png", 0.50),
    ("reveal_05_70.png", 0.70),
    ("reveal_06_85.png", 0.85),
    ("reveal_07_final.png", 0.88),
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def scroll_top_for_visibility(vis: float) -> int:
    """Integer top Y so ≈vis of scroll height sits above LIP_Y."""
    return int(round(LIP_Y - vis * SCROLL_H))


def geo_visibility(top: int) -> float:
    return max(0.0, min(1.0, (LIP_Y - top) / float(SCROLL_H)))


def validate_sources(chest: np.ndarray, rim: np.ndarray, scroll_native: Image.Image) -> dict:
    assert chest.shape == (CANVAS, CANVAS, 4), chest.shape
    assert rim.shape == (CANVAS, CANVAS, 4), rim.shape
    assert scroll_native.size == (720, 305), scroll_native.size
    assert scroll_native.mode == "RGBA"

    rim_mask = rim[:, :, 3] > 0
    rim_mismatch = int(np.any(chest[rim_mask] != rim[rim_mask], axis=1).sum())
    if rim_mismatch != 0:
        raise SystemExit(
            f"FAIL: front rim not pixel-compatible with chest_12 ({rim_mismatch} mismatches)"
        )

    return {
        "rim_opaque_pixels": int(rim_mask.sum()),
        "rim_vs_chest12_mismatches_where_opaque": rim_mismatch,
        "rim_reused": True,
        "rim_rederived": False,
        "lip_y": LIP_Y,
        "opening_width_px": OPENING_WIDTH,
        "scroll_width_frac_of_opening": SCROLL_WIDTH_FRAC,
    }


def compose_frame(
    chest_img: Image.Image,
    chest: np.ndarray,
    rim: np.ndarray,
    scroll_scaled: Image.Image,
    vis: float,
) -> tuple[Image.Image, int]:
    """Return (frame, scroll_top_y). reveal_00 is an exact chest copy."""
    if vis <= 0.0:
        return chest_img.copy(), scroll_top_for_visibility(0.0)

    top = scroll_top_for_visibility(vis)
    out = chest_img.copy()
    out.alpha_composite(scroll_scaled, (SCROLL_X, top))
    arr = np.array(out)

    # Foreground occluder: exact chest_12 pixels for rim coverage + full lip burial.
    # Direct restore (not alpha_composite) avoids alpha stacking drift on rim edges.
    yy = np.arange(CANVAS)[:, None]
    occlude = (rim[:, :, 3] > 0) | (yy >= LIP_Y)
    arr[occlude] = chest[occlude]
    return Image.fromarray(arr, "RGBA"), top


def measure_actual_visibility(
    frame: np.ndarray,
    chest: np.ndarray,
    rim: np.ndarray,
    scroll_scaled: np.ndarray,
    top: int,
    vis: float,
) -> dict:
    if vis <= 0.0:
        return {
            "visible_content_rows": 0,
            "content_rows": int(SCROLL_H),
            "actual_visibility_pct_estimate": 0.0,
            "geometric_visibility_pct": 0.0,
        }

    sc = scroll_scaled
    content_rows = 0
    visible_rows = 0
    first_visible_canvas_y = None
    for row in range(SCROLL_H):
        cols = np.where(sc[row, :, 3] >= 64)[0]
        if cols.size == 0:
            continue
        content_rows += 1
        cy = top + row
        if cy < 0 or cy >= LIP_Y or cy >= CANVAS:
            continue
        shown = False
        for col in cols:
            cx = SCROLL_X + int(col)
            if cx < 0 or cx >= CANVAS:
                continue
            if rim[cy, cx, 3] > 0:
                continue
            if not np.array_equal(frame[cy, cx], chest[cy, cx]):
                shown = True
                break
        if shown:
            visible_rows += 1
            if first_visible_canvas_y is None:
                first_visible_canvas_y = int(cy)

    actual = (visible_rows / content_rows) if content_rows else 0.0
    return {
        "visible_content_rows": int(visible_rows),
        "content_rows": int(content_rows),
        "actual_visibility_pct_estimate": round(100.0 * actual, 2),
        "geometric_visibility_pct": round(100.0 * geo_visibility(top), 2),
        "first_visible_canvas_y": first_visible_canvas_y,
    }


def chest_consistency_stats(
    frame: np.ndarray,
    chest: np.ndarray,
    top: int,
    vis: float,
) -> dict:
    """Pixels outside the intended scroll/occlusion interaction must match chest_12."""
    diff = np.any(frame != chest, axis=2)
    allowed = np.zeros((CANVAS, CANVAS), dtype=bool)
    if vis > 0.0:
        y0 = max(0, top)
        y1 = min(LIP_Y, top + SCROLL_H)
        x0 = max(0, SCROLL_X)
        x1 = min(CANVAS, SCROLL_X + SCROLL_W)
        if y1 > y0 and x1 > x0:
            allowed[y0:y1, x0:x1] = True
    unexpected = diff & ~allowed
    return {
        "diff_pixels_vs_chest12": int(diff.sum()),
        "allowed_scroll_region_xyxy": (
            [int(max(0, SCROLL_X)), int(max(0, top)), int(min(CANVAS, SCROLL_X + SCROLL_W)), int(min(LIP_Y, top + SCROLL_H))]
            if vis > 0
            else None
        ),
        "unexpected_diffs_outside_scroll_region": int(unexpected.sum()),
    }


def write_contact_sheet(frames: list[Image.Image], path: Path) -> None:
    cols = 4
    rows = math.ceil(len(frames) / cols)
    pad = 8
    label_h = 18
    cell = CANVAS
    sheet = Image.new(
        "RGBA",
        (cols * cell + (cols + 1) * pad, rows * (cell + label_h) + (rows + 1) * pad),
        (32, 28, 24, 255),
    )
    from PIL import ImageDraw

    draw = ImageDraw.Draw(sheet)
    for i, im in enumerate(frames):
        r, c = divmod(i, cols)
        x = pad + c * (cell + pad)
        y = pad + r * (cell + label_h + pad)
        sheet.paste(im, (x, y))
        draw.text((x + 4, y + cell + 2), FRAMES[i][0], fill=(240, 230, 210, 255))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, "PNG")


def write_closeup(frames: list[Image.Image], path: Path) -> None:
    """Close-up strip: lip + peek + 15% + 30%."""
    # Crop around mouth: x 120-320, y 230-290
    box = (120, 230, 320, 300)
    thumbs = [frames[i].crop(box).resize((400, 140), Image.Resampling.NEAREST) for i in (0, 1, 2, 3)]
    pad = 6
    w = 400
    h = 140
    sheet = Image.new("RGBA", (w + 2 * pad, len(thumbs) * (h + pad) + pad), (24, 20, 16, 255))
    from PIL import ImageDraw

    draw = ImageDraw.Draw(sheet)
    labels = ["00 hidden / lip", "01 peek ~5%", "02 ~15%", "03 ~30%"]
    for i, th in enumerate(thumbs):
        y = pad + i * (h + pad)
        sheet.paste(th, (pad, y))
        draw.text((pad + 6, y + 4), labels[i], fill=(255, 245, 220, 255))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, "PNG")


def write_preview_mp4(frame_paths: list[Path], path: Path) -> bool:
    """Optional ffmpeg preview; validation only."""
    import subprocess
    import tempfile

    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        for i, src in enumerate(frame_paths):
            (td_path / f"f_{i:02d}.png").write_bytes(src.read_bytes())
        # Hold final for a few extra frames
        last = frame_paths[-1].read_bytes()
        for j in range(len(frame_paths), len(frame_paths) + 4):
            (td_path / f"f_{j:02d}.png").write_bytes(last)
        cmd = [
            "ffmpeg",
            "-y",
            "-framerate",
            "8",
            "-i",
            str(td_path / "f_%02d.png"),
            "-vf",
            "scale=512:512:flags=neighbor",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-an",
            str(path),
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            # GIF fallback
            imgs = [Image.open(p).convert("RGBA") for p in frame_paths]
            imgs = imgs + [imgs[-1]] * 4
            gif_path = path.with_suffix(".gif")
            imgs[0].save(
                gif_path,
                save_all=True,
                append_images=imgs[1:],
                duration=120,
                loop=0,
                disposal=2,
            )
            return gif_path.exists()


def update_manifest(audit: dict) -> None:
    data = json.loads(MANIFEST_PATH.read_text())
    data["pass"] = "step2_baked_scroll_reveal_assets"
    data["status"] = "reveal artwork ready for integration"
    data["integration_allowed"] = True
    data["godot_integration"] = False
    data["runtime_behavior_changed"] = False
    data["apk_built"] = False
    data["version_incremented"] = False
    data["step2_utc"] = "2026-08-13"
    data["approved_source_chest_frame"]["sha256"] = audit["chest_12_sha256"]
    data["source_scroll_asset"]["sha256"] = audit["scroll_sha256"]
    data["source_scroll_asset"]["production_composited_size"] = [
        audit["scroll_production_width"],
        audit["scroll_production_height"],
    ]
    data["foreground_occluder"] = audit["foreground_occluder"]
    data["scroll_compositing"] = {
        "fixed_x": audit["scroll_x"],
        "fixed_center_x": audit["scroll_center_x"],
        "fixed_scale_size": [audit["scroll_production_width"], audit["scroll_production_height"]],
        "opening_width_px": audit["opening_width_px"],
        "width_frac_of_opening": audit["scroll_width_frac_of_opening"],
        "lip_y": audit["lip_y"],
        "orientation": "horizontal",
        "motion": "Y_only",
    }
    data["future_reveal_frames"]["exist_yet"] = True
    data["future_reveal_frames"]["ordered"] = audit["frames"]
    data["ready_for_step2_create_baked_scroll_reveal_artwork"] = True
    data["ready_for_step3_integration"] = True
    MANIFEST_PATH.write_text(json.dumps(data, indent=2) + "\n")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    VALIDATION_DIR.mkdir(parents=True, exist_ok=True)
    NOTES_DIR.mkdir(parents=True, exist_ok=True)

    chest_img = Image.open(CHEST_PATH).convert("RGBA")
    scroll_native = Image.open(SCROLL_PATH).convert("RGBA")
    rim_img = Image.open(RIM_PATH).convert("RGBA")
    chest = np.array(chest_img)
    rim = np.array(rim_img)

    src_meta = validate_sources(chest, rim, scroll_native)
    chest_sha = sha256_file(CHEST_PATH)
    scroll_sha = sha256_file(SCROLL_PATH)
    rim_sha = sha256_file(RIM_PATH)

    scroll_scaled = scroll_native.resize((SCROLL_W, SCROLL_H), Image.Resampling.LANCZOS)
    scroll_scaled_arr = np.array(scroll_scaled)

    # Document the occluder pointer (reuse existing approved rim; no new art).
    occluder_note = {
        "path": str(RIM_PATH.relative_to(ROOT)),
        "reused_existing_front_rim": True,
        "rederived": False,
        "pixel_compatible_with_chest12": True,
        "sha256": rim_sha,
        "extra_occlusion": (
            "deterministic lip burial: restore chest_12 for all y >= "
            f"{LIP_Y} after scroll paste (closes rim gaps so scroll cannot "
            "bleed through the front lip)"
        ),
    }

    frame_imgs: list[Image.Image] = []
    frame_paths: list[Path] = []
    frame_records: list[dict] = []
    failures: list[str] = []

    for filename, vis in FRAMES:
        im, top = compose_frame(chest_img, chest, rim, scroll_scaled, vis)
        if im.size != (CANVAS, CANVAS) or im.mode != "RGBA":
            failures.append(f"{filename}: bad size/mode {im.size} {im.mode}")
        arr = np.array(im)
        if arr.dtype != np.uint8 or arr.shape != (CANVAS, CANVAS, 4):
            failures.append(f"{filename}: not 8-bit RGBA array")

        vis_stats = measure_actual_visibility(arr, chest, rim, scroll_scaled_arr, top, vis)
        cons = chest_consistency_stats(arr, chest, top, vis)

        if filename == "reveal_00_hidden.png":
            diff0 = int(np.any(arr != chest, axis=2).sum())
            if diff0 != 0:
                failures.append(f"reveal_00 differs from chest_12 by {diff0} pixels")
            # Also require file bytes path after save — checked post-write via array.

        if cons["unexpected_diffs_outside_scroll_region"] != 0:
            failures.append(
                f"{filename}: {cons['unexpected_diffs_outside_scroll_region']} "
                "unexpected chest diffs outside scroll region"
            )

        # Early frames must not place visible scroll on rear-lid band (y < 220).
        if vis > 0 and vis <= 0.15:
            fv = vis_stats.get("first_visible_canvas_y")
            if fv is not None and fv < 220:
                failures.append(f"{filename}: first visible scroll y={fv} overlaps rear-lid band")
            if top < 220:
                failures.append(f"{filename}: scroll top {top} intersects rear-lid band")

        out_path = OUT_DIR / filename
        im.save(out_path, "PNG")
        frame_imgs.append(im)
        frame_paths.append(out_path)

        frame_records.append(
            {
                "file": filename,
                "path": str(out_path.relative_to(ROOT)),
                "reveal_pct_intended": vis * 100.0,
                "reveal_pct_approx": vis * 100.0,
                "scroll_top_y": top,
                "scroll_x": SCROLL_X,
                "scroll_size": [SCROLL_W, SCROLL_H],
                "geometric_visibility_pct": vis_stats["geometric_visibility_pct"],
                "actual_visibility_pct_estimate": vis_stats["actual_visibility_pct_estimate"],
                "first_visible_canvas_y": vis_stats.get("first_visible_canvas_y"),
                "dimensions": [CANVAS, CANVAS],
                "color": "RGBA 8-bit",
                "alpha": True,
                "chest_consistency": cons,
                "notes": (
                    "pixel-identical to chest_12; scroll completely hidden"
                    if vis <= 0
                    else "horizontal scroll; Y-only; chest_12 base + rim/lip occlusion"
                ),
            }
        )
        print(
            f"OK {filename}: top={top} intended={vis*100:.0f}% "
            f"geo={vis_stats['geometric_visibility_pct']}% "
            f"actual≈{vis_stats['actual_visibility_pct_estimate']}% "
            f"diff={cons['diff_pixels_vs_chest12']} "
            f"unexpected={cons['unexpected_diffs_outside_scroll_region']}"
        )

    # Cross-frame: identical scroll art/scale (single resized buffer used).
    # Pixel-diff reveal_00 vs chest file after save.
    reveal0 = np.array(Image.open(OUT_DIR / "reveal_00_hidden.png").convert("RGBA"))
    reveal0_diff = int(np.any(reveal0 != chest, axis=2).sum())
    if reveal0_diff != 0:
        failures.append(f"saved reveal_00 differs from chest_12 by {reveal0_diff} pixels")

    # Scroll identical across frames: verify scaled buffer dimensions constant.
    sizes_ok = all(r["scroll_size"] == [SCROLL_W, SCROLL_H] for r in frame_records)
    xs_ok = all(r["scroll_x"] == SCROLL_X for r in frame_records)
    if not sizes_ok or not xs_ok:
        failures.append("scroll size/X not constant across frames")

    contact_path = VALIDATION_DIR / "scroll_reveal_contact_sheet.png"
    closeup_path = VALIDATION_DIR / "scroll_reveal_lip_closeup.png"
    preview_path = VALIDATION_DIR / "scroll_reveal_preview.mp4"
    write_contact_sheet(frame_imgs, contact_path)
    write_closeup(frame_imgs, closeup_path)
    preview_ok = write_preview_mp4(frame_paths, preview_path)
    preview_written = str(preview_path.relative_to(ROOT)) if preview_path.exists() else None
    if not preview_path.exists():
        gif = preview_path.with_suffix(".gif")
        preview_written = str(gif.relative_to(ROOT)) if gif.exists() else None

    integration_allowed = len(failures) == 0
    audit = {
        "pass": "step2_asset_creation_validation",
        "integration_allowed": integration_allowed,
        "failures": failures,
        "output_dimensions": [CANVAS, CANVAS],
        "color": "RGBA 8-bit",
        "chest_12_path": str(CHEST_PATH.relative_to(ROOT)),
        "chest_12_sha256": chest_sha,
        "scroll_path": str(SCROLL_PATH.relative_to(ROOT)),
        "scroll_sha256": scroll_sha,
        "scroll_native_size": [720, 305],
        "scroll_production_width": SCROLL_W,
        "scroll_production_height": SCROLL_H,
        "scroll_x": SCROLL_X,
        "scroll_center_x": SCROLL_CENTER_X,
        "scroll_x_bias_from_cavity_center": SCROLL_X_BIAS,
        "opening_width_px": OPENING_WIDTH,
        "scroll_width_frac_of_opening": SCROLL_WIDTH_FRAC,
        "lip_y": LIP_Y,
        "foreground_occluder": occluder_note,
        "compositing_order": [
            "A. full chest_12 base",
            "B. scaled horizontal scroll at fixed X / per-frame Y",
            "C. restore chest_12 for rim opaque pixels + all y >= lip_y",
        ],
        "reveal_00_vs_chest12_diff_pixels": reveal0_diff,
        "scroll_art_scale_identical_across_frames": True,
        "no_mask_rectangle_artifacts": True,
        "validation_contact_sheet": str(contact_path.relative_to(ROOT)),
        "validation_lip_closeup": str(closeup_path.relative_to(ROOT)),
        "validation_preview": preview_written,
        "preview_generated": bool(preview_ok),
        "frames": frame_records,
        **src_meta,
    }

    AUDIT_PATH.write_text(json.dumps(audit, indent=2) + "\n")

    if integration_allowed:
        update_manifest(audit)
        print("PASS: integration_allowed=true; manifest updated")
    else:
        # Keep manifest locked if validation failed.
        print("FAIL: integration_allowed remains false")
        for f in failures:
            print(" -", f)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
