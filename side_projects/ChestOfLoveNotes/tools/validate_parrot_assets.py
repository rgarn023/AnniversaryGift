#!/usr/bin/env python3
"""Validate FREE parrot animation assets against the Phase 1B-2A contract.

Does NOT require artwork to exist yet.
When frames are missing, exits 0 with status AWAITING_ARTWORK (not a Phase failure).

When artwork is present, verifies:
  - correct file count / filenames
  - exact canvas dimensions
  - RGBA / transparent background
  - no missing frames
  - opaque bounds roughly within visible target
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "assets" / "pets" / "parrot" / "parrot_animation_manifest.json"
PARROT_ROOT = ROOT / "assets" / "pets" / "parrot"


def load_manifest() -> dict:
    with MANIFEST_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


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


def opaque_bbox(im: "Image.Image", alpha_thresh: int = 16) -> tuple[int, int, int, int] | None:
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a >= alpha_thresh else 0).getbbox()
    return bbox


def validate() -> int:
    report: dict = {
        "tool": "validate_parrot_assets",
        "manifest": str(MANIFEST_PATH.relative_to(ROOT)),
        "status": "UNKNOWN",
        "artwork_ready": False,
        "errors": [],
        "warnings": [],
        "animations": {},
    }

    if not MANIFEST_PATH.is_file():
        report["status"] = "MANIFEST_MISSING"
        report["errors"].append(f"Missing manifest: {MANIFEST_PATH}")
        print(json.dumps(report, indent=2))
        print("STATUS: MANIFEST_MISSING")
        return 1

    manifest = load_manifest()
    cw = int(manifest.get("frame_canvas_width", 128))
    ch = int(manifest.get("frame_canvas_height", 128))
    bounds = manifest.get("visible_target_bounds", {})
    max_opaque_area_frac = 0.92

    missing: list[str] = []
    present: list[str] = []
    anims = manifest.get("animations", [])
    if not isinstance(anims, list) or not anims:
        report["errors"].append("Manifest has no animations[]")
        report["status"] = "MANIFEST_INVALID"
        print(json.dumps(report, indent=2))
        print("STATUS: MANIFEST_INVALID")
        return 1

    for anim in anims:
        name = str(anim.get("name", ""))
        folder = str(anim.get("folder", name))
        pattern = str(anim.get("filename_pattern", ""))
        count = int(anim.get("expected_frame_count", 0))
        folder_path = PARROT_ROOT / folder
        anim_info = {
            "folder": folder,
            "expected_frame_count": count,
            "present": [],
            "missing": [],
            "issues": [],
        }
        for i in range(count):
            fname = expected_filename(pattern, i, name, folder)
            fpath = folder_path / fname
            rel = str(fpath.relative_to(ROOT))
            if not fpath.is_file():
                missing.append(rel)
                anim_info["missing"].append(fname)
                continue
            present.append(rel)
            anim_info["present"].append(fname)
            if Image is None:
                anim_info["issues"].append(f"{fname}: Pillow not available; skipped pixel checks")
                continue
            with Image.open(fpath) as im:
                if im.size != (cw, ch):
                    anim_info["issues"].append(
                        f"{fname}: size {im.size} != required {(cw, ch)}"
                    )
                if im.mode != "RGBA":
                    # PNG may open as other modes; convert check via presence of alpha.
                    if "A" not in im.getbands():
                        anim_info["issues"].append(f"{fname}: not RGBA / missing alpha")
                # Transparent background: corners should be mostly clear.
                rgba = im.convert("RGBA")
                corners = [
                    rgba.getpixel((0, 0))[3],
                    rgba.getpixel((cw - 1, 0))[3],
                    rgba.getpixel((0, ch - 1))[3],
                    rgba.getpixel((cw - 1, ch - 1))[3],
                ]
                if any(a > 24 for a in corners):
                    anim_info["issues"].append(
                        f"{fname}: corner alpha suggests non-transparent background"
                    )
                bbox = opaque_bbox(rgba)
                if bbox is None:
                    anim_info["issues"].append(f"{fname}: fully transparent")
                else:
                    ow = bbox[2] - bbox[0]
                    oh = bbox[3] - bbox[1]
                    if (ow * oh) > (cw * ch * max_opaque_area_frac):
                        anim_info["issues"].append(
                            f"{fname}: opaque bbox unusually large ({ow}x{oh})"
                        )
                    if bounds:
                        # Soft warning only — art review decides final crop.
                        if bbox[0] < int(bounds.get("min_x", 0)) - 8:
                            report["warnings"].append(
                                f"{rel}: opaque extends left of soft target"
                            )
                        if bbox[2] > int(bounds.get("max_x", cw)) + 8:
                            report["warnings"].append(
                                f"{rel}: opaque extends right of soft target"
                            )
        report["animations"][name] = anim_info
        report["errors"].extend(f"{name}: {issue}" for issue in anim_info["issues"])

    report["present_count"] = len(present)
    report["missing_count"] = len(missing)
    report["missing_files"] = missing[:40]
    report["frame_canvas"] = [cw, ch]
    report["visuals_enabled"] = bool(manifest.get("visuals_enabled", False))
    report["manifest_status"] = manifest.get("status", "")

    if missing and not present:
        report["status"] = "AWAITING_ARTWORK"
        report["artwork_ready"] = False
        print(json.dumps(report, indent=2))
        print("STATUS: AWAITING_ARTWORK")
        print("Phase 1B-2A OK — contract ready; no frames required yet.")
        return 0

    if missing and present:
        report["status"] = "AWAITING_ARTWORK_PARTIAL"
        report["artwork_ready"] = False
        report["warnings"].append("Partial artwork set; treat as incomplete")
        print(json.dumps(report, indent=2))
        print("STATUS: AWAITING_ARTWORK")
        return 0

    if report["errors"]:
        report["status"] = "ARTWORK_INVALID"
        report["artwork_ready"] = False
        print(json.dumps(report, indent=2))
        print("STATUS: ARTWORK_INVALID")
        return 1

    report["status"] = "ARTWORK_READY"
    report["artwork_ready"] = True
    print(json.dumps(report, indent=2))
    print("STATUS: ARTWORK_READY")
    return 0


if __name__ == "__main__":
    sys.exit(validate())
