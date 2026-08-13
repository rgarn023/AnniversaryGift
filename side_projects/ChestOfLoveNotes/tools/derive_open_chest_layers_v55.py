#!/usr/bin/env python3
"""Re-derive open-back + front-rim + cavity mask from approved chest_12_fully_open.png.

v55 root causes (beyond v54):
1) Cavity mask wrote alpha=255 everywhere. CLIP_CHILDREN_ONLY uses parent alpha, so
   the scroll was not clipped to the mouth — it read against the rear wall / whole
   chest silhouette. Shader used .r (correct) but clip-children was a no-op.
2) Front lip had gaps across the mouth center at the rim row, so the lower scroll
   was not cleanly occluded by the front lip.
3) Mask top still allowed the early peek to visually associate with the deep rear
   glow band; keep final-scroll headroom but bias opacity toward the front lip.

Does NOT touch approved chest_frames/*.png. No new artwork — derive only.
Does NOT solidify / fill the cavity interior into the rim.
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
OUT_MASK = LAYERS / "chest_cavity_mask.png"
OUT_META_RIM_Y = LAYERS / "cavity_rim_y.txt"


def _dilate(mask: np.ndarray, iterations: int = 2) -> np.ndarray:
	dil = mask.copy()
	for _ in range(iterations):
		pad = np.pad(dil, 1, mode="constant")
		dil = (
			pad[0:-2, 0:-2]
			| pad[0:-2, 1:-1]
			| pad[0:-2, 2:]
			| pad[1:-1, 0:-2]
			| pad[1:-1, 1:-1]
			| pad[1:-1, 2:]
			| pad[2:, 0:-2]
			| pad[2:, 1:-1]
			| pad[2:, 2:]
		)
	return dil


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


def derive_layers(open12: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, dict]:
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

	## Thin mouth gold lip — include the band ABOVE old v53 rim (was stuck in back).
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

	## Cavity inner bounds: prefer full mouth opening width at the lip row.
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

	## Narrow side pillars ONLY (not the cavity interior). Frame the opening.
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

	front = np.zeros_like(open12)
	front[front_mask] = open12[front_mask]
	front[:, :, 3] = np.where(front[:, :, 3] > 40, 255, 0).astype(np.uint8)

	## Fill small holes ONLY in the lower front face (below lip), never in cavity.
	solid = front[:, :, 3] > 40
	if solid.any():
		fill_rgb = np.median(front[solid][:, :3], axis=0).astype(np.uint8)
		dil = _dilate(solid, 2)
		in_lower = (
			(yy >= lip_top + 8)
			& (yy <= chest_bot)
			& (np.abs(xx - cx) < 135)
		)
		holes = in_lower & (~solid) & dil & (a > 70)
		front[holes, 0] = fill_rgb[0]
		front[holes, 1] = fill_rgb[1]
		front[holes, 2] = fill_rgb[2]
		front[holes, 3] = 255

	## v55: solidify a CONTINUOUS mouth lip across the opening so the lower scroll
	## is occluded by the front rim (not only side pillars). Sample gold from the
	## lip band; never fill the bright cavity above the lip.
	lip_sample = (
		(front[:, :, 3] > 40)
		& (yy >= lip_top)
		& (yy <= lip_top + 10)
		& (np.abs(xx - cx) < 120)
	)
	if lip_sample.any():
		lip_rgb = np.median(open12[lip_sample][:, :3], axis=0).astype(np.uint8)
	else:
		gold_src = gold_lip & (a > 70)
		lip_rgb = (
			np.median(open12[gold_src][:, :3], axis=0).astype(np.uint8)
			if gold_src.any()
			else np.array([210, 150, 40], dtype=np.uint8)
		)
	inner_l = cavity_left + 4
	inner_r = cavity_right - 4
	for y in range(lip_top, min(511, lip_top + 8)):
		row_a = front[y, :, 3]
		## Fill only gaps inside the mouth span — keep existing rim pixels.
		for x in range(inner_l, inner_r + 1):
			if row_a[x] <= 40:
				front[y, x, 0] = lip_rgb[0]
				front[y, x, 1] = lip_rgb[1]
				front[y, x, 2] = lip_rgb[2]
				front[y, x, 3] = 255

	back = open12.copy()
	rim_solid = front[:, :, 3] > 40
	back[rim_solid, 3] = 0

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
	back[strip, 3] = 0
	need = strip & (front[:, :, 3] <= 40) & (a > 70) & (~cavity_interior)
	front[need] = open12[need]
	front[:, :, 3] = np.where(front[:, :, 3] > 40, 255, 0).astype(np.uint8)

	## Ensure rim does not cover bright cavity GLOW above the lip (scroll must show).
	center_cover = (
		(front[:, :, 3] > 40)
		& (yy < lip_top)
		& (xx > cavity_left + 10)
		& (xx < cavity_right - 10)
		& ~side_pillars
		& (lum > 190)
		& (r > 190)
		& (g > 150)
	)
	if center_cover.any():
		back[center_cover] = open12[center_cover]
		front[center_cover, 3] = 0

	## Final pass: any metallic gold still in back on/near the lip band → front rim.
	br = back[:, :, 0].astype(np.float32)
	bg = back[:, :, 1].astype(np.float32)
	bb = back[:, :, 2].astype(np.float32)
	ba = back[:, :, 3]
	blum = (br + bg + bb) / 3.0
	## Only move gold ON/BELOW the lip into the rim — never the open mouth above it.
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
		front[:, :, 3] = np.where(front[:, :, 3] > 40, 255, 0).astype(np.uint8)
		back[gold_final, 3] = 0

	## Re-assert continuous lip after gold moves (v55 critical).
	for y in range(lip_top, min(511, lip_top + 8)):
		for x in range(inner_l, inner_r + 1):
			if front[y, x, 3] <= 40:
				front[y, x, 0] = lip_rgb[0]
				front[y, x, 1] = lip_rgb[1]
				front[y, x, 2] = lip_rgb[2]
				front[y, x, 3] = 255
				back[y, x, 3] = 0

	## v55 CRITICAL: never let the front rim cover the open mouth ABOVE the lip.
	## Gold moves / leftovers were painting a false "rear wall" occluder across
	## the cavity center (y≈261–268), making the scroll read as behind the chest.
	## Keep side pillars; restore cavity interior above lip to open-back.
	mouth_above = (
		(front[:, :, 3] > 40)
		& (yy < lip_top)
		& (xx >= inner_l + 2)
		& (xx <= inner_r - 2)
		& ~side_pillars
	)
	if mouth_above.any():
		back[mouth_above] = open12[mouth_above]
		front[mouth_above, 3] = 0

	## Cavity mask — scroll may draw only here (between pillars, above lip).
	## Headroom covers final ~90% scroll height (~y 211) while biasing weight
	## toward the FRONT lip so early peek reads as inside-front, not rear wall.
	mask = np.zeros((512, 512), dtype=np.float32)
	mask_inner_l = cavity_left + 6
	mask_inner_r = cavity_right - 6
	## Final scroll top ≈ lip - 0.90 * (~64px height) ≈ lip - 58.
	top = max(chest_top + 40, lip_top - 62)
	for y in range(top, lip_top + 1):
		t = (y - top) / max(1.0, float(lip_top - top))
		## Wider near lip (front); slightly inset toward rear/lid.
		pad = int(10 * (1.0 - t))
		x0 = mask_inner_l + pad
		x1 = mask_inner_r - pad
		if x1 > x0:
			## Soft vertical bias: full opacity in the front half of the cavity
			## (near lip), gently reduced toward the rear so early pixels don't
			## read as glued to the rear wall glow.
			front_bias = 0.55 + 0.45 * t
			mask[y, x0 : x1 + 1] = front_bias
	## Soft horizontal feather only (keep vertical edge at lip crisp).
	ker = np.array([1, 2, 3, 2, 1], dtype=np.float32)
	ker /= ker.sum()
	padm = np.pad(mask, [(0, 0), (2, 2)], mode="edge")
	mask = (
		padm[:, 0:-4] * ker[0]
		+ padm[:, 1:-3] * ker[1]
		+ padm[:, 2:-2] * ker[2]
		+ padm[:, 3:-1] * ker[3]
		+ padm[:, 4:] * ker[4]
	)
	## Near-lip band must stay fully open for the first visible peek.
	for y in range(max(top, lip_top - 10), lip_top + 1):
		mask[y, mask_inner_l : mask_inner_r + 1] = np.maximum(
			mask[y, mask_inner_l : mask_inner_r + 1], 1.0
		)
	mask_u8 = np.clip(mask * 255.0, 0, 255).astype(np.uint8)
	## v55 CRITICAL: alpha must match the cavity silhouette for CLIP_CHILDREN_ONLY.
	mask_rgba = np.dstack([mask_u8, mask_u8, mask_u8, mask_u8])

	## Lip top for runtime CAVITY_RIM_CANVAS_Y: first row where rim spans the mouth.
	lip_rows = []
	for y in range(lip_top - 2, lip_top + 24):
		xs_r = np.where(front[y, :, 3] > 40)[0]
		if xs_r.size >= 80 and xs_r.min() < cx - 40 and xs_r.max() > cx + 40:
			## Also require continuous mid coverage (v55).
			mid = front[y, int(cx) - 40 : int(cx) + 41, 3]
			if (mid > 40).sum() >= 70:
				lip_rows.append(y)
				break
	runtime_rim_y = float(lip_rows[0] if lip_rows else lip_top)

	front_ys = np.where((front[:, :, 3] > 40).any(1))[0]
	mid_span = int(
		(front[int(runtime_rim_y), int(cx) - 40 : int(cx) + 41, 3] > 40).sum()
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
		"front_top_y": int(front_ys[0]) if front_ys.size else -1,
		"mask_px": int((mask_u8 > 20).sum()),
		"mask_alpha_matches_r": bool(np.array_equal(mask_u8, mask_rgba[:, :, 3])),
		"mask_top_y": int(top),
		"rim_mid_coverage_at_lip": mid_span,
		"rim_mid_at_lip": int(front[int(runtime_rim_y), int(cx), 3]),
		"rim_mid_above_lip": int(front[max(0, int(runtime_rim_y) - 4), int(cx), 3]),
		"back_gold_near_lip": int(
			(
				(back[:, :, 3] > 40)
				& (yy >= lip_top - 2)
				& (yy <= lip_top + 6)
				& (br > 100)
				& ((br - bb) > 16)
				& (blum < 230)
			).sum()
		),
	}
	return back, front, mask_rgba, meta


def main() -> None:
	open12 = np.array(Image.open(OPEN12).convert("RGBA"))
	back, front, mask, meta = derive_layers(open12)
	LAYERS.mkdir(parents=True, exist_ok=True)
	Image.fromarray(back, "RGBA").save(OUT_BACK)
	Image.fromarray(front, "RGBA").save(OUT_RIM)
	Image.fromarray(mask, "RGBA").save(OUT_MASK)
	OUT_META_RIM_Y.write_text(str(meta["runtime_rim_y"]) + "\n", encoding="utf-8")
	print("WROTE", OUT_BACK)
	print("WROTE", OUT_RIM)
	print("WROTE", OUT_MASK)
	print("META", meta)


if __name__ == "__main__":
	main()
