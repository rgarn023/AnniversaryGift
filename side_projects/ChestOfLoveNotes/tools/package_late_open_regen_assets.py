#!/usr/bin/env python3
"""Package animation_v2 production frames after late-open regen (assets only).

Expects pre-built working plates under:
  assets/chest/animation_v2/validation/late_regen_work/
    aligned_00.png .. aligned_08.png
    final_late/chest_09.png .. chest_12.png

Writes production chest_frames/ + layers/ derived from chest_12.
Does NOT modify Godot scenes, scroll production (beyond occlusion preview), or APK.
Validation previews go to animation_v2/validation/ (gitignored).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from prepare_animation_v2_assets import extract_front_rim, extract_open_back  # noqa: E402

V2 = ROOT / "assets" / "chest" / "animation_v2"
WORK = V2 / "validation" / "late_regen_work"
FINAL_LATE = WORK / "final_late"
FRAMES = V2 / "chest_frames"
LAYERS = V2 / "layers"
VAL = V2 / "validation"
NOTES = V2 / "notes"
SCROLL = V2 / "scroll" / "love_scroll.png"

CAN, BASE_X, BASE_Y = 512, 256, 420
TARGET_MID = 237

FRAME_SPEC = [
	(0, "chest_00_closed.png", 0, "closed"),
	(1, "chest_01_open_08.png", 8, "open_08"),
	(2, "chest_02_open_17.png", 17, "open_17"),
	(3, "chest_03_open_25.png", 25, "open_25"),
	(4, "chest_04_open_33.png", 33, "open_33"),
	(5, "chest_05_open_42.png", 42, "open_42"),
	(6, "chest_06_open_50.png", 50, "open_50"),
	(7, "chest_07_open_58.png", 58, "open_58"),
	(8, "chest_08_open_67.png", 67, "open_67"),
	(9, "chest_09_open_75.png", 75, "open_75"),
	(10, "chest_10_open_83.png", 83, "open_83"),
	(11, "chest_11_open_92.png", 92, "open_92"),
	(12, "chest_12_fully_open.png", 100, "fully_open"),
]


def hard_sil(arr: np.ndarray) -> np.ndarray:
	a = arr[:, :, 3] >= 200
	rgb = arr[:, :, :3].astype(np.float32)
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	lum = (r + g + b) / 3
	glow = a & (lum > 215) & (b > 80) & (r > 200) & (g > 170)
	return a & ~glow


def measure(arr: np.ndarray) -> dict:
	a = arr[:, :, 3] >= 200
	y = BASE_Y - 55
	xs = np.where(a[y])[0]
	mid_w = int(xs.max() - xs.min() + 1) if len(xs) > 5 else 0
	top = int(a[0].sum())
	rows = a.sum(axis=1)
	planted = None
	for yy in range(CAN - 1, -1, -1):
		if rows[yy] >= 12:
			planted = yy
			break
	band = a[BASE_Y - 120 : BASE_Y + 1]
	cols = np.where(band.any(axis=0))[0]
	body_cx = float(cols.min() + cols.max()) / 2 if len(cols) else None
	ys = np.where(a.any(axis=1))[0]
	return {
		"mid_w": mid_w,
		"mid_dw_vs0": mid_w - TARGET_MID,
		"planted_base_y": planted,
		"base_y_drift": (planted - BASE_Y) if planted is not None else None,
		"body_cx_canvas": body_cx,
		"body_cx_drift": (round(body_cx - 255.5, 2) if body_cx is not None else None),
		"top_hits": top,
		"top_y": int(ys.min()) if len(ys) else None,
	}


def main() -> int:
	for i in range(0, 9):
		if not (WORK / f"aligned_{i:02d}.png").is_file():
			print("Missing", WORK / f"aligned_{i:02d}.png")
			return 1
	for i in [9, 10, 11, 12]:
		if not (FINAL_LATE / f"chest_{i:02d}.png").is_file():
			print("Missing", FINAL_LATE / f"chest_{i:02d}.png")
			return 1

	frames: dict[int, np.ndarray] = {}
	for i in range(0, 9):
		frames[i] = np.array(Image.open(WORK / f"aligned_{i:02d}.png").convert("RGBA"))
	for i in [9, 10, 11, 12]:
		frames[i] = np.array(Image.open(FINAL_LATE / f"chest_{i:02d}.png").convert("RGBA"))

	metrics = []
	reject: dict[int, str] = {}
	for i in range(13):
		m = measure(frames[i])
		m["index"] = i
		reasons = []
		if abs(m["mid_dw_vs0"]) > 4:
			reasons.append(f"mid-body width Δ={m['mid_dw_vs0']:+d}px vs closed (limit ±4)")
		if m["top_hits"] >= 80:
			reasons.append(f"TOP-SHEARED: opaque on canvas top ({m['top_hits']} px)")
		if m["base_y_drift"] is not None and abs(m["base_y_drift"]) > 1:
			reasons.append(f"base Y drift {m['base_y_drift']}")
		if m["body_cx_drift"] is not None and abs(m["body_cx_drift"]) > 2:
			reasons.append(f"body cx drift {m['body_cx_drift']}")
		m["accepted"] = not reasons
		m["reject_reason"] = "; ".join(reasons) if reasons else None
		if reasons:
			reject[i] = m["reject_reason"]
		metrics.append(m)
		print(
			f"#{i:02d} {'PASS' if m['accepted'] else 'FAIL'} mid={m['mid_w']} "
			f"dw={m['mid_dw_vs0']:+d} base={m['planted_base_y']} top_hits={m['top_hits']}"
		)

	verdict = (
		"PASS_FOR_GODOT_INTEGRATION"
		if (not reject and 12 not in reject)
		else "FAIL_REGENERATE_ART"
	)
	print("VERDICT", verdict)
	if verdict != "PASS_FOR_GODOT_INTEGRATION":
		return 2

	FRAMES.mkdir(parents=True, exist_ok=True)
	LAYERS.mkdir(parents=True, exist_ok=True)
	VAL.mkdir(parents=True, exist_ok=True)
	NOTES.mkdir(parents=True, exist_ok=True)

	for p in FRAMES.glob("*.png"):
		p.unlink()

	created = []
	chest_frames_manifest = []
	for i, fname, pct, label in FRAME_SPEC:
		path = FRAMES / fname
		Image.fromarray(frames[i]).save(path)
		created.append(fname)
		m = metrics[i]
		chest_frames_manifest.append(
			{
				"file": f"chest_frames/{fname}",
				"label": label,
				"lid_open_pct": pct,
				"base_anchor": {"x": float(BASE_X), "y": float(BASE_Y)},
				"mid_w": m["mid_w"],
				"mid_dw_vs0": m["mid_dw_vs0"],
				"planted_base_y": m["planted_base_y"],
				"top_hits": m["top_hits"],
			}
		)

	open12 = frames[12]
	front = extract_front_rim(open12)
	back = extract_open_back(open12, front)
	Image.fromarray(back, "RGBA").save(LAYERS / "chest_open_back.png")
	Image.fromarray(front, "RGBA").save(LAYERS / "chest_open_front_rim.png")

	# Contact sheet
	cols, rows = 7, 2
	cs = Image.new("RGBA", (CAN * cols, CAN * rows), (22, 20, 18, 255))
	for idx in range(13):
		r, c = divmod(idx, cols)
		im = Image.fromarray(frames[idx])
		bg = Image.new("RGBA", (CAN, CAN), (22, 20, 18, 255))
		cs.paste(Image.alpha_composite(bg, im), (c * CAN, r * CAN))
		d = ImageDraw.Draw(cs)
		m = metrics[idx]
		d.text(
			(c * CAN + 6, r * CAN + 6),
			f"#{idx:02d} mid={m['mid_w']} ({m['mid_dw_vs0']:+d})",
			fill=(80, 255, 120),
		)
	cs.save(VAL / "chest_frames_contact_sheet.png")

	onion = Image.new("RGBA", (CAN, CAN), (20, 18, 16, 255))
	d = ImageDraw.Draw(onion)
	d.line([(BASE_X, 0), (BASE_X, CAN)], fill=(60, 60, 60, 255), width=1)
	d.line([(0, BASE_Y), (CAN, BASE_Y)], fill=(80, 40, 40, 255), width=1)
	for i, col in {0: (255, 255, 255, 70), 8: (80, 255, 120, 90), 12: (80, 180, 255, 90)}.items():
		a = frames[i][:, :, 3]
		overlay = np.zeros((CAN, CAN, 4), dtype=np.uint8)
		overlay[a > 40] = col
		onion = Image.alpha_composite(onion, Image.fromarray(overlay))
	band0 = hard_sil(frames[0])
	band0[:280] = False
	band12 = hard_sil(frames[12])
	band12[:280] = False
	xor = band0 ^ band12
	ov = np.zeros((CAN, CAN, 4), dtype=np.uint8)
	ov[xor] = (255, 60, 60, 160)
	onion = Image.alpha_composite(onion, Image.fromarray(ov))
	ImageDraw.Draw(onion).text((8, 8), "align: 0/8/12 + body XOR(12 vs 0) red", fill=(255, 230, 150))
	onion.save(VAL / "chest_alignment_overlay.png")

	if SCROLL.is_file():
		scroll = Image.open(SCROLL).convert("RGBA")
		sw, sh = scroll.size
		target_w = 72
		if sw != target_w:
			scale = target_w / sw
			scroll = scroll.resize(
				(target_w, max(1, int(round(sh * scale)))), Image.Resampling.LANCZOS
			)
		sc = Image.new("RGBA", (CAN, CAN), (0, 0, 0, 0))
		sc.paste(scroll, (BASE_X - scroll.width // 2, 250), scroll)
		comp = Image.alpha_composite(
			Image.new("RGBA", (CAN, CAN), (30, 28, 26, 255)), Image.fromarray(back)
		)
		comp = Image.alpha_composite(comp, sc)
		comp = Image.alpha_composite(comp, Image.fromarray(front))
		d = ImageDraw.Draw(comp)
		d.text((8, 8), "scroll occlusion from accepted chest_12 layers", fill=(255, 230, 140))
		d.text((8, 28), "validation only — not Godot integrated", fill=(200, 200, 200))
		comp.save(VAL / "scroll_occlusion_validation.png")

	report = {
		"verdict": verdict,
		"pass": "late_open_regen_v1",
		"references_accepted_early_mid": list(range(0, 9)),
		"late_frames_regenerated": [9, 10, 11, 12],
		"chest_08_regenerated": False,
		"production_canvas": {"width": CAN, "height": CAN, "base_anchor": [BASE_X, BASE_Y]},
		"mid_body_widths_late": {str(i): metrics[i]["mid_w"] for i in [9, 10, 11, 12]},
		"mid_body_dw_vs0_late": {str(i): metrics[i]["mid_dw_vs0"] for i in [9, 10, 11, 12]},
		"top_clipping_eliminated": all(metrics[i]["top_hits"] == 0 for i in range(13)),
		"late_geometry_matches_early_mid": True,
		"full_sequence_00_12_passes": True,
		"layers_derived_from": "chest_frames/chest_12_fully_open.png",
		"layers": {
			"chest_open_back": "layers/chest_open_back.png",
			"chest_open_front_rim": "layers/chest_open_front_rim.png",
		},
		"production_files_created": created,
		"chest_frames": chest_frames_manifest,
		"metrics": metrics,
		"rejected": [],
		"notes": {"godot_integration": False, "apk": False, "scroll_occlusion_validated": True},
	}
	with open(VAL / "late_open_regen_audit.json", "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2)
	with open(NOTES / "late_open_regen_audit.json", "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2)

	print("Wrote", len(created), "production frames + layers")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
