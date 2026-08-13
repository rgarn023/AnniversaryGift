#!/usr/bin/env python3
"""Re-derive open-back + front-rim + cavity mask from approved chest_12_fully_open.png.

v54 root cause (beyond v53):
- Mouth gold at y≈255–270 remained in open-back ABOVE the rim top (y≈271).
  The scroll then rose against that gold band and read as coming from behind
  the whole chest rather than out of the cavity.
- Side pillars that should frame the scroll lived only in open-back.

This tool:
1) Detects the true horizontal gold-lip top from the approved frame.
2) Puts ONLY front lip + front face + narrow opening side pillars into front-rim.
3) Clears those pixels from open-back (cavity glow stays in back).
4) Writes a cavity alpha mask for runtime shader occlusion.

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
	# Exclude super-bright cavity glow core; want the metallic lip band.
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

	## Cavity inner bounds: prefer full mouth opening width at the lip row
	## (not just the bright glow core — that was too narrow and clipped the scroll).
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
	## Inset past outer gold trim so pillars/mask sit on the inner opening.
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
		## Never steal bright cavity glow into the rim.
		& ~((lum > 190) & (r > 190) & (g > 140) & (np.abs(xx - cx) < 100))
	)

	## Keep cavity glow + soft glow in BACK (behind scroll).
	not_cavity_glow = ~(
		(lum > 200) & (r > 195) & (g > 150) & (yy <= lip_top + 8) & (np.abs(xx - cx) < 100)
	)
	not_soft_glow = ~(
		(lum > 185) & (r > 195) & (g > 135) & (a < 210) & (yy < lip_top + 10)
	)
	## Exclude open lid well above the mouth.
	not_lid = yy >= (lip_top - 30)

	front_mask = (gold_lip | front_face | lower_plate | side_pillars) & not_lid & not_cavity_glow & not_soft_glow

	## Critical: never mark bright cavity interior as front (would hide scroll).
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

	back = open12.copy()
	rim_solid = front[:, :, 3] > 40
	back[rim_solid, 3] = 0

	br = back[:, :, 0].astype(np.float32)
	bg = back[:, :, 1].astype(np.float32)
	bb = back[:, :, 2].astype(np.float32)
	ba = back[:, :, 3]
	blum = (br + bg + bb) / 3.0
	## Strip leftover mouth gold from back (the v53 miss: y just above old rim).
	gold_leftover = (
		(ba > 40)
		& (yy >= lip_top - 4)
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
	## Do NOT restore metallic gold lip pixels into back — that was the v53 miss.
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
	gold_final = (
		(ba > 40)
		& (yy >= lip_top - 8)
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

	## Cavity mask — scroll may draw only here (between pillars, above lip, below lid).
	mask = np.zeros((512, 512), dtype=np.float32)
	inner_l = cavity_left + 6
	inner_r = cavity_right - 6
	top = max(chest_top + 36, lip_top - 100)
	for y in range(top, lip_top + 1):
		t = (y - top) / max(1.0, float(lip_top - top))
		pad = int(8 * (1.0 - t))
		x0 = inner_l + pad
		x1 = inner_r - pad
		if x1 > x0:
			mask[y, x0 : x1 + 1] = 1.0
	## Soft horizontal feather only (keep vertical edge at lip crisp).
	ker = np.array([1, 2, 3, 2, 1], dtype=np.float32)
	ker /= ker.sum()
	pad = np.pad(mask, [(0, 0), (2, 2)], mode="edge")
	mask = (
		pad[:, 0:-4] * ker[0]
		+ pad[:, 1:-3] * ker[1]
		+ pad[:, 2:-2] * ker[2]
		+ pad[:, 3:-1] * ker[3]
		+ pad[:, 4:] * ker[4]
	)
	mask_u8 = np.clip(mask * 255.0, 0, 255).astype(np.uint8)
	mask_rgba = np.dstack([mask_u8, mask_u8, mask_u8, np.full_like(mask_u8, 255)])

	## Lip top for runtime CAVITY_RIM_CANVAS_Y: first row where rim spans the mouth.
	lip_rows = []
	for y in range(lip_top - 2, lip_top + 24):
		xs_r = np.where(front[y, :, 3] > 40)[0]
		if xs_r.size >= 80 and xs_r.min() < cx - 40 and xs_r.max() > cx + 40:
			lip_rows.append(y)
			break
	runtime_rim_y = float(lip_rows[0] if lip_rows else lip_top)

	front_ys = np.where((front[:, :, 3] > 40).any(1))[0]
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
