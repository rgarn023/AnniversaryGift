#!/usr/bin/env python3
"""Audit animation_v2/incoming_new_art master sheets (assets only).

Does NOT modify Godot scenes, active production frames, version, or APK.
Writes gitignored validation previews under animation_v2/validation/ and a
JSON audit summary there. Durable verdict lives in notes/.

Hard rule: every accepted lid frame must be the same physical chest; only lid
angle / intentional interior glow may change.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
INCOMING = ROOT / "assets" / "chest" / "animation_v2" / "incoming_new_art"
V2 = ROOT / "assets" / "chest" / "animation_v2"
VAL = V2 / "validation"
NOTES = V2 / "notes"

SHEET = INCOMING / "new_chest_opening_master_sheet.png"
SCROLL = INCOMING / "new_love_scroll_master.png"

COLS, ROWS = 4, 4
CAN, BASE_X, BASE_Y = 512, 256, 420
ACCEPT_MAX_ABS_MID_DW = 4

# Indices that fail hard consistency on the current incoming sheet.
# Re-derived each run from measurements; these labels are for reporting.
REJECT_REASONS_TEMPLATE = {
	9: "mid-body width shrink vs closed after align; progressive late-sequence narrowing",
	10: "mid-body width shrink vs closed after align; progressive late-sequence narrowing",
	11: "TOP-SHEARED: opaque lid mass touches cell top edge + mid-body narrowing",
	12: "mid-body width shrink vs closed after align; planted body remorphs/narrows",
}


def hard_sil(cell: np.ndarray, athresh: int = 200) -> np.ndarray:
	a = cell[:, :, 3]
	rgb = cell[:, :, :3].astype(np.float32)
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	lum = (r + g + b) / 3
	opaque = a >= athresh
	glow_fill = opaque & (lum > 215) & (b > 80) & (r > 200) & (g > 170)
	return opaque & ~glow_fill


def base_y(sil: np.ndarray, min_w: int = 12) -> int | None:
	rows = sil.sum(axis=1)
	for y in range(len(rows) - 1, -1, -1):
		if rows[y] >= min_w:
			return int(y)
	return None


def body_cx(sil: np.ndarray, by: int, bh: int = 120) -> float:
	band = sil[max(0, by - bh) : by + 1]
	cols = np.where(band.any(axis=0))[0]
	return float(cols.min() + cols.max()) / 2


def extract_cells(sheet: np.ndarray) -> list[dict]:
	h, w = sheet.shape[:2]
	cw, ch = w // COLS, h // ROWS
	out: list[dict] = []
	for r in range(ROWS):
		for c in range(COLS):
			cell = sheet[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw].copy()
			if (cell[:, :, 3] > 20).mean() >= 0.02:
				out.append({"r": r, "c": c, "cell": cell, "cw": cw, "ch": ch})
	return out


def align_to_canvas(cell: np.ndarray, by: int, cx: float) -> tuple[Image.Image, int, int]:
	dx = int(round(BASE_X - cx))
	dy = int(round(BASE_Y - by))
	canvas = Image.new("RGBA", (CAN, CAN), (0, 0, 0, 0))
	im = Image.fromarray(cell)
	canvas.paste(im, (dx, dy), im)
	return canvas, dx, dy


def measure_planted(canvas: Image.Image) -> dict:
	arr = np.array(canvas)
	a = arr[:, :, 3] >= 200
	y = BASE_Y - 55
	xs = np.where(a[y])[0]
	mid_w = int(xs.max() - xs.min() + 1) if len(xs) > 5 else 0
	yf = BASE_Y - 3
	xs = np.where(a[yf])[0]
	feet_w = int(xs.max() - xs.min() + 1) if len(xs) > 3 else 0
	band = a[BASE_Y - 120 : BASE_Y + 1]
	cols = np.where(band.any(axis=0))[0]
	body_w = int(cols.max() - cols.min() + 1) if len(cols) else 0
	body_cx_c = float(cols.min() + cols.max()) / 2 if len(cols) else None
	rows = a.sum(axis=1)
	planted_base = None
	for y in range(CAN - 1, -1, -1):
		if rows[y] >= 12:
			planted_base = int(y)
			break
	return {
		"mid_w": mid_w,
		"feet_w": feet_w,
		"body_w": body_w,
		"body_cx_canvas": body_cx_c,
		"planted_base_y": planted_base,
	}


def audit_scroll() -> dict:
	scroll = Image.open(SCROLL).convert("RGBA")
	arr = np.array(scroll)
	a = arr[:, :, 3]
	ys, xs = np.where(a > 40)
	pts = np.stack([xs, ys], axis=1).astype(np.float64)
	pts -= pts.mean(axis=0)
	cov = np.cov(pts.T)
	_eigvals, eigvecs = np.linalg.eigh(cov)
	axis = eigvecs[:, -1]
	angle = float(np.degrees(np.arctan2(axis[1], axis[0])))
	rot = scroll.rotate(90 - angle, expand=True, resample=Image.Resampling.BICUBIC)
	bb = rot.getbbox()
	rot = rot.crop(bb)
	target_w = 72
	scale = target_w / rot.width
	prod = rot.resize((target_w, int(round(rot.height * scale))), Image.Resampling.LANCZOS)
	# Preview only
	VAL.mkdir(exist_ok=True)
	preview = Image.new("RGBA", (256, 256), (40, 35, 30, 255))
	ps = prod
	if ps.height > 240:
		s = 240 / ps.height
		ps = ps.resize((max(1, int(ps.width * s)), 240), Image.Resampling.LANCZOS)
	preview.paste(ps, ((256 - ps.width) // 2, (256 - ps.height) // 2), ps)
	preview.save(VAL / "scroll_upright_candidate_preview.png")
	return {
		"path": str(SCROLL.relative_to(ROOT)),
		"dimensions": [scroll.width, scroll.height],
		"format": "PNG RGBA",
		"content_bbox": list(scroll.getbbox()) if scroll.getbbox() else None,
		"principal_axis_angle_deg": round(angle, 2),
		"orientation": "diagonal / tilted (needs upright rotate for production)",
		"upright_candidate_wh": [prod.width, prod.height],
		"contains_chest_pixels": False,
		"production_committed": False,
		"upright_image": prod,
	}


def main() -> int:
	if not SHEET.is_file() or not SCROLL.is_file():
		print("Missing incoming master sheets under", INCOMING)
		return 1

	VAL.mkdir(exist_ok=True)
	NOTES.mkdir(exist_ok=True)

	sheet_im = Image.open(SHEET)
	sheet = np.array(sheet_im.convert("RGBA"))
	h, w = sheet.shape[:2]
	cells = extract_cells(sheet)
	cw, ch = cells[0]["cw"], cells[0]["ch"]

	meta = []
	aligned = []
	metrics = []
	for i, item in enumerate(cells):
		sil = hard_sil(item["cell"])
		by = base_y(sil)
		cx = body_cx(sil, by)
		top_opaque = int(sil[0].sum())
		canvas, dx, dy = align_to_canvas(item["cell"], by, cx)
		aligned.append(canvas)
		m = measure_planted(canvas)
		meta.append({**item, "i": i, "by": by, "cx": cx, "top_opaque": top_opaque})
		metrics.append(
			{
				"index": i,
				"grid": f"r{item['r']}c{item['c']}",
				"cell_base_y": by,
				"cell_body_cx": round(cx, 2),
				"place_dx": dx,
				"place_dy": dy,
				"top_opaque_on_cell_edge": top_opaque,
				**m,
			}
		)

	ref_mid = metrics[0]["mid_w"]
	ref_base = metrics[0]["planted_base_y"]
	ref_cx = metrics[0]["body_cx_canvas"]
	reject: dict[int, str] = {}
	for m in metrics:
		m["mid_dw_vs0"] = m["mid_w"] - ref_mid
		m["base_y_drift"] = m["planted_base_y"] - ref_base
		m["body_cx_drift"] = (
			round(m["body_cx_canvas"] - ref_cx, 2) if m["body_cx_canvas"] is not None else None
		)
		reasons = []
		if abs(m["mid_dw_vs0"]) > ACCEPT_MAX_ABS_MID_DW:
			reasons.append(
				f"mid-body width Δ={m['mid_dw_vs0']:+d}px vs closed (limit ±{ACCEPT_MAX_ABS_MID_DW})"
			)
		# Significant opaque lid on the cell top = real shear (ignore tiny glow crumbs).
		if m["top_opaque_on_cell_edge"] >= 80 and m["index"] > 0:
			reasons.append(
				f"TOP-SHEARED: opaque pixels on cell top edge ({m['top_opaque_on_cell_edge']} px)"
			)
		if reasons:
			reject[m["index"]] = "; ".join(reasons)
		m["accepted"] = m["index"] not in reject
		m["reject_reason"] = reject.get(m["index"])

	# Contact sheet
	pad, label_h = 10, 28
	cs = Image.new(
		"RGBA",
		(COLS * (cw + pad) + pad, ROWS * (ch + pad + label_h) + pad),
		(22, 20, 18, 255),
	)
	draw = ImageDraw.Draw(cs)
	for i, item in enumerate(meta):
		r, c = divmod(i, COLS)
		x = pad + c * (cw + pad)
		y = pad + r * (ch + pad + label_h)
		bg = Image.new("RGBA", (cw, ch), (22, 20, 18, 255))
		cs.paste(Image.alpha_composite(bg, Image.fromarray(item["cell"])), (x, y + label_h))
		ok = i not in reject
		draw.text((x + 4, y + 4), f"#{i:02d} {'ACCEPT' if ok else 'REJECT'}", fill=(80, 220, 120) if ok else (255, 80, 80))
	cs.save(VAL / "incoming_new_art_candidates_contact_sheet.png")

	# Accepted aligned contact
	acc_idx = [i for i in range(len(meta)) if i not in reject]
	acc_cols = min(5, max(1, len(acc_idx)))
	acc_rows = (len(acc_idx) + acc_cols - 1) // acc_cols if acc_idx else 1
	acs = Image.new(
		"RGBA",
		(acc_cols * (CAN + pad) + pad, acc_rows * (CAN + pad) + pad),
		(22, 20, 18, 255),
	)
	for j, idx in enumerate(acc_idx):
		r, c = divmod(j, acc_cols)
		x = pad + c * (CAN + pad)
		y = pad + r * (CAN + pad)
		bg = Image.new("RGBA", (CAN, CAN), (22, 20, 18, 255))
		acs.paste(Image.alpha_composite(bg, aligned[idx]), (x, y))
		ImageDraw.Draw(acs).text((x + 8, y + 8), f"aligned accept #{idx:02d}", fill=(255, 240, 120))
	acs.save(VAL / "chest_frames_contact_sheet.png")

	# Alignment overlay
	onion = Image.new("RGBA", (CAN, CAN), (20, 18, 16, 255))
	d = ImageDraw.Draw(onion)
	d.line([(BASE_X, 0), (BASE_X, CAN)], fill=(60, 60, 60, 255), width=1)
	d.line([(0, BASE_Y), (CAN, BASE_Y)], fill=(80, 40, 40, 255), width=1)
	for i, col in {0: (255, 255, 255, 70), 4: (80, 255, 120, 90), 8: (80, 180, 255, 90)}.items():
		if i < len(aligned):
			a = np.array(aligned[i])[:, :, 3]
			overlay = np.zeros((CAN, CAN, 4), dtype=np.uint8)
			overlay[a > 40] = col
			onion = Image.alpha_composite(onion, Image.fromarray(overlay))
	if len(aligned) > 12:
		xor = (np.array(aligned[12])[:, :, 3] > 40) ^ (np.array(aligned[0])[:, :, 3] > 40)
		ov = np.zeros((CAN, CAN, 4), dtype=np.uint8)
		ov[xor] = (255, 60, 60, 160)
		onion = Image.alpha_composite(onion, Image.fromarray(ov))
	ImageDraw.Draw(onion).text((8, 8), "align overlay: 0/4/8 + XOR(12 vs 0) red", fill=(255, 230, 150))
	onion.save(VAL / "chest_alignment_overlay.png")

	scroll_info = audit_scroll()
	prod = scroll_info.pop("upright_image")

	# Occlusion demo on most-open accepted frame (if any)
	if acc_idx:
		most_open = acc_idx[-1]
		back = aligned[most_open].copy()
		barr = np.array(back)
		rgb = barr[:, :, :3].astype(np.float32)
		al = barr[:, :, 3]
		lum = rgb.mean(axis=2)
		woodgold = (al >= 180) & (rgb[:, :, 0] > 50) & (rgb[:, :, 0] >= rgb[:, :, 2]) & (lum < 200)
		rim = np.zeros_like(barr)
		rim_band = np.zeros(al.shape, dtype=bool)
		rim_band[310:420, 150:350] = woodgold[310:420, 150:350]
		rim[rim_band] = barr[rim_band]
		sc = Image.new("RGBA", (CAN, CAN), (0, 0, 0, 0))
		sc.paste(prod, (BASE_X - prod.width // 2, 250), prod)
		comp = Image.alpha_composite(Image.new("RGBA", (CAN, CAN), (30, 28, 26, 255)), back)
		comp = Image.alpha_composite(comp, sc)
		comp = Image.alpha_composite(comp, Image.fromarray(rim))
		d = ImageDraw.Draw(comp)
		d.text((8, 8), f"occlusion demo using ACCEPT #{most_open:02d}", fill=(255, 230, 140))
		d.text((8, 28), "validation only — not a production commit", fill=(200, 200, 200))
		comp.save(VAL / "scroll_occlusion_validation.png")

	has_fully_open_accept = any(i == 12 and i not in reject for i in range(len(meta)))
	verdict = "PASS_FOR_GODOT_INTEGRATION" if (not reject and has_fully_open_accept) else "FAIL_REGENERATE_ART"
	# Partial early-arc accepts without fully-open still FAIL integration gate.
	if reject or not has_fully_open_accept:
		verdict = "FAIL_REGENERATE_ART"

	report = {
		"verdict": verdict,
		"branch_note": "incoming_new_art validation only; production chest_frames/scroll/layers NOT replaced on FAIL",
		"master_sheet": {
			"path": str(SHEET.relative_to(ROOT)),
			"dimensions": [w, h],
			"format": f"PNG {sheet_im.mode}",
			"grid": f"{COLS}x{ROWS}",
			"cell": [cw, ch],
			"occupied_frames": len(cells),
		},
		"scroll_master": scroll_info,
		"production_canvas_tested": {"width": CAN, "height": CAN, "base_anchor": [BASE_X, BASE_Y]},
		"inspected": len(cells),
		"accepted_candidate_indices": acc_idx,
		"rejected": [{"index": k, "reason": v} for k, v in sorted(reject.items())],
		"accepted_production_files_created": [],
		"layers_derived": False,
		"metrics": metrics,
		"notes": {
			"integration_gate": "Requires full closed→fully-open arc with same body; late rejects or missing fully-open => FAIL",
			"vs_old_sheets": "Early/mid frames much tighter than prior glowing/magical sheets, but late open poses still unsafe",
		},
	}
	with open(VAL / "incoming_new_art_audit.json", "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2)
	# Durable copy (validation/ is gitignored)
	with open(NOTES / "incoming_new_art_audit.json", "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2)

	print(json.dumps({"verdict": verdict, "accepted": acc_idx, "rejected": sorted(reject)}, indent=2))
	print("Validation images →", VAL)
	print("Durable audit JSON →", NOTES / "incoming_new_art_audit.json")
	return 0 if verdict.startswith("PASS") else 2


if __name__ == "__main__":
	raise SystemExit(main())
