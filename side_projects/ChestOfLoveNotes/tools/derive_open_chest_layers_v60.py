#!/usr/bin/env python3
"""Re-derive open-back + front-rim from approved chest_12_fully_open.png (v60).

v60 root cause of layered handoff glitch:
- Prior derive cleared a front-depth cavity pocket / faded alphas in open_back,
  and/or solidified the lip with median gold — so open_back+rim no longer
  matched chest_12 when reward layering activated.
- Runtime also dimmed open-back modulate on handoff (fixed in treasure_chest.gd).

v60 derive rules:
- Exact pixels from chest_12 only (no AI, no repaint, no redesign).
- open_back = chest_12 with front-rim pixels cleared (alpha 0).
- front_rim = exact chest_12 pixels for lip / front face / side pillars.
- NO front-pocket cavity clear.
- NO alpha fade bands.
- NO median-gold lip solidify that recolors source pixels.
- Composite(open_back, front_rim) must pixel-match chest_12 on opaque pixels.

Does NOT touch approved chest_frames/*.png.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OPEN12 = ROOT / "assets/chest/animation_v2/chest_frames/chest_12_fully_open.png"
LAYERS = ROOT / "assets/chest/animation_v2/layers"
OUT_BACK = LAYERS / "chest_open_back.png"
OUT_RIM = LAYERS / "chest_open_front_rim.png"
OUT_META_RIM_Y = LAYERS / "cavity_rim_y.txt"


def _detect_lip_top(open12: np.ndarray, cx: float, chest_top: int, chest_bot: int) -> int:
	"""Top of the continuous horizontal gold mouth lip (front occluder)."""
	a = open12[:, :, 3]
	r = open12[:, :, 0].astype(np.float32)
	g = open12[:, :, 1].astype(np.float32)
	b = open12[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	yy = np.arange(open12.shape[0])[:, None]
	xx = np.arange(open12.shape[1])[None, :]
	gold = (
		(a > 70)
		& (np.abs(xx - cx) < 120)
		& (yy >= chest_top + int((chest_bot - chest_top) * 0.38))
		& (yy <= chest_top + int((chest_bot - chest_top) * 0.58))
		& (r > 110)
		& (g > 70)
		& ((r - b) > 22)
		& (lum < 230)
		& (lum > 50)
	)
	best_y = int(chest_top + (chest_bot - chest_top) * 0.50)
	best_span = 0
	for y in range(gold.shape[0]):
		xs = np.where(gold[y])[0]
		if xs.size < 50:
			continue
		span = int(xs.max() - xs.min())
		if span > best_span:
			best_span = span
			best_y = y
	lip_top = best_y
	for y in range(best_y, max(chest_top, best_y - 24), -1):
		xs = np.where(gold[y])[0]
		if xs.size < 40:
			break
		lip_top = y
	return int(lip_top)


def derive_layers(open12: np.ndarray) -> tuple[np.ndarray, np.ndarray, dict]:
	assert open12.shape == (512, 512, 4)
	a = open12[:, :, 3]
	ys, xs = np.where(a > 40)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	lip_top = _detect_lip_top(open12, cx, chest_top, chest_bot)

	yy = np.arange(512)[:, None]
	xx = np.arange(512)[None, :]
	r = open12[:, :, 0].astype(np.float32)
	g = open12[:, :, 1].astype(np.float32)
	b = open12[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0

	## Thin mouth gold lip — continuous band at the mouth.
	gold_lip = (
		(a > 70)
		& (yy >= lip_top - 1)
		& (yy <= lip_top + 20)
		& (np.abs(xx - cx) < 128)
		& (r > 100)
		& (g > 65)
		& ((r - b) > 18)
		& (lum < 235)
		& (lum > 40)
	)
	## Front face / lower plate below the lip (heart lock, wood, feet).
	front_face = (
		(a > 70)
		& (yy >= lip_top + 6)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 135)
		& (
			((r > 95) & (g > 65) & ((r - b) > 18) & (lum < 235))
			| ((lum < 160) & (r > 30) & (r > b) & (g > b * 0.4))
		)
	)
	lower_plate = (
		(a > 70)
		& (yy >= lip_top + 12)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 142)
	)

	probe_y = min(511, lip_top + 2)
	probe = a[probe_y] > 70
	if probe.sum() < 80:
		probe_y = max(chest_top + 20, lip_top - 4)
		probe = a[probe_y] > 70
	if probe.any():
		pxs = np.where(probe)[0]
		cavity_left, cavity_right = int(pxs.min()), int(pxs.max())
	else:
		cavity_left, cavity_right = int(cx - 100), int(cx + 100)
	cavity_left += 8
	cavity_right -= 8
	if cavity_right - cavity_left < 120:
		cavity_left, cavity_right = int(cx - 90), int(cx + 90)

	pillar_w = 16
	side_pillars = (
		(a > 70)
		& (yy >= lip_top - 28)
		& (yy <= lip_top + 14)
		& (
			((xx >= cavity_left - pillar_w) & (xx <= cavity_left + 5))
			| ((xx >= cavity_right - 5) & (xx <= cavity_right + pillar_w))
		)
		& (np.abs(xx - cx) < 148)
		& ~((lum > 190) & (r > 190) & (g > 140) & (np.abs(xx - cx) < 100))
	)

	not_cavity_glow = ~(
		(lum > 200) & (r > 195) & (g > 150) & (yy <= lip_top + 8) & (np.abs(xx - cx) < 100)
	)
	not_soft_glow = ~(
		(lum > 185) & (r > 195) & (g > 135) & (a < 210) & (yy < lip_top + 10)
	)
	not_lid = yy >= (lip_top - 30)

	front_mask = (gold_lip | front_face | lower_plate | side_pillars) & not_lid & not_cavity_glow & not_soft_glow

	cavity_interior = (
		(yy >= lip_top - 40)
		& (yy <= lip_top + 4)
		& (xx > cavity_left + 8)
		& (xx < cavity_right - 8)
		& (lum > 170)
		& (r > 180)
	)
	front_mask &= ~cavity_interior

	## Exact source pixels only — no median fill / recolor.
	front = np.zeros_like(open12)
	front[front_mask] = open12[front_mask]

	back = open12.copy()
	rim_solid = front[:, :, 3] > 40
	back[rim_solid, 3] = 0

	## Move leftover gold/wood/pillar that still sit in back on the lip band → rim.
	br = back[:, :, 0].astype(np.float32)
	bg = back[:, :, 1].astype(np.float32)
	bb = back[:, :, 2].astype(np.float32)
	ba = back[:, :, 3]
	blum = (br + bg + bb) / 3.0
	gold_leftover = (
		(ba > 40)
		& (yy >= lip_top)
		& (yy <= lip_top + 8)
		& (np.abs(xx - cx) < 130)
		& (br > 100)
		& (bg > 60)
		& ((br - bb) > 16)
		& (blum < 235)
		& (blum > 40)
		& ~((blum > 205) & (br > 205) & (bg > 160) & (np.abs(xx - cx) < 95))
	)
	wood_leftover = (
		(ba > 40)
		& (yy >= lip_top + 6)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 122)
		& (blum < 175)
		& (br > 30)
		& (br > bb)
	)
	pillar_leftover = (
		(ba > 40)
		& (yy >= lip_top - 28)
		& (yy <= lip_top + 10)
		& (
			((xx >= cavity_left - pillar_w) & (xx <= cavity_left + 6))
			| ((xx >= cavity_right - 6) & (xx <= cavity_right + pillar_w))
		)
		& (blum < 190)
		& ~((blum > 200) & (br > 200) & (np.abs(xx - cx) < 95))
	)
	strip = gold_leftover | wood_leftover | pillar_leftover
	need = strip & (front[:, :, 3] <= 40) & (a > 70) & (~cavity_interior)
	front[need] = open12[need]
	back[strip, 3] = 0

	## Never let the front rim cover the open mouth ABOVE the lip.
	inner_l = cavity_left + 4
	inner_r = cavity_right - 4
	mouth_above = (
		(front[:, :, 3] > 40)
		& (yy < lip_top)
		& (xx >= inner_l + 2)
		& (xx <= inner_r - 2)
		& ~side_pillars
	)
	if mouth_above.any():
		back[mouth_above] = open12[mouth_above]
		front[mouth_above] = 0

	## Final gold-on-lip pass — exact source pixels only.
	br = back[:, :, 0].astype(np.float32)
	bg = back[:, :, 1].astype(np.float32)
	bb = back[:, :, 2].astype(np.float32)
	ba = back[:, :, 3]
	blum = (br + bg + bb) / 3.0
	gold_final = (
		(ba > 40)
		& (yy >= lip_top)
		& (yy <= lip_top + 6)
		& (np.abs(xx - cx) < 128)
		& (br > 100)
		& (bg > 55)
		& ((br - bb) > 16)
		& (blum < 230)
		& (blum > 40)
		& ~((blum > 210) & (br > 210) & (bg > 170) & (np.abs(xx - cx) < 90))
	)
	if gold_final.any():
		front[gold_final] = open12[gold_final]
		back[gold_final, 3] = 0

	## Guarantee no overlap: rim wins, back cleared under rim.
	rim_solid = front[:, :, 3] > 40
	back[rim_solid, 3] = 0

	## Perfect reconstruction: any source-opaque pixel missing from both layers
	## must return to open_back (never invent new colors).
	missing = (a > 10) & (front[:, :, 3] <= 10) & (back[:, :, 3] <= 10)
	if missing.any():
		back[missing] = open12[missing]

	## Re-assert rim wins after restore.
	rim_solid = front[:, :, 3] > 40
	back[rim_solid, 3] = 0

	## Runtime rim Y = detected lip TOP (inner top edge of the front lip).
	## First scroll pixels must appear immediately above this row.
	runtime_rim_y = float(lip_top)

	## Pixel-diff composite vs source (opaque source pixels).
	comp = back.copy()
	comp[rim_solid] = front[rim_solid]
	src_a = a > 10
	diff = np.abs(open12.astype(np.int16) - comp.astype(np.int16)).sum(axis=2)
	diff_vals = diff[src_a]
	mean_diff = float(diff_vals.mean()) if diff_vals.size else 0.0
	pct_gt_30 = float((diff_vals > 30).mean() * 100.0) if diff_vals.size else 0.0
	missing = int((src_a & (comp[:, :, 3] < 10)).sum())
	back_near_lip = int(
		(
			(back[:, :, 3] > 40)
			& (yy >= lip_top - 18)
			& (yy < lip_top)
			& (xx >= inner_l + 6)
			& (xx <= inner_r - 6)
		).sum()
	)

	meta = {
		"source": str(OPEN12.relative_to(ROOT)),
		"lip_top": lip_top,
		"runtime_rim_y": runtime_rim_y,
		"cavity_left": cavity_left,
		"cavity_right": cavity_right,
		"front_px": int((front[:, :, 3] > 40).sum()),
		"back_px": int((back[:, :, 3] > 40).sum()),
		"overlap": int(((front[:, :, 3] > 40) & (back[:, :, 3] > 40)).sum()),
		"rim_mid_at_lip": int(front[int(runtime_rim_y), int(cx), 3]),
		"rim_mid_above_lip": int(front[max(0, int(runtime_rim_y) - 4), int(cx), 3]),
		"back_front_cavity_px": back_near_lip,
		"composite_mean_diff": mean_diff,
		"composite_pct_gt_30": pct_gt_30,
		"composite_missing": missing,
		"front_pocket_cleared": False,
	}
	return back, front, meta


def main() -> None:
	open12 = np.array(Image.open(OPEN12).convert("RGBA"))
	back, front, meta = derive_layers(open12)
	LAYERS.mkdir(parents=True, exist_ok=True)
	Image.fromarray(back, "RGBA").save(OUT_BACK)
	Image.fromarray(front, "RGBA").save(OUT_RIM)
	OUT_META_RIM_Y.write_text(str(meta["runtime_rim_y"]) + "\n", encoding="utf-8")
	print("WROTE", OUT_BACK)
	print("WROTE", OUT_RIM)
	print("META", meta)
	assert meta["overlap"] == 0, "back/rim must not overlap"
	assert meta["rim_mid_at_lip"] > 40, "continuous lip required"
	assert meta["rim_mid_above_lip"] == 0, "rim must not cover mouth above lip"
	assert meta["composite_missing"] == 0, "composite must cover all source opaque pixels"
	assert meta["composite_mean_diff"] < 1.0, "composite must nearly match chest_12"
	assert meta["back_front_cavity_px"] > 500, "cavity above lip must remain in open_back"


if __name__ == "__main__":
	main()
