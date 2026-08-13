#!/usr/bin/env python3
"""Re-derive open-back + front-rim from approved chest_12_fully_open.png.

v53 root cause: gold front-lip pixels at y~275-282 remained in open-back, so the
horizontal scroll rose behind that lip and looked like it came from behind the
whole chest. This tool moves the mouth gold + front face into the front-rim
layer and clears them from open-back.

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


def derive_layers(open12: np.ndarray) -> tuple[np.ndarray, np.ndarray, dict]:
	assert open12.shape == (512, 512, 4)
	a = open12[:, :, 3]
	ys, xs = np.where(a > 40)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	rim_y = int(chest_top + chest_h * 0.50)

	yy = np.arange(512)[:, None]
	xx = np.arange(512)[None, :]
	r = open12[:, :, 0].astype(np.float32)
	g = open12[:, :, 1].astype(np.float32)
	b = open12[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0

	## Front rim owns the mouth gold lip (incl. upper band formerly stuck in back).
	gold_lip = (
		(a > 70)
		& (yy >= rim_y - 12)
		& (yy <= rim_y + 22)
		& (np.abs(xx - cx) < 128)
		& (r > 100)
		& (g > 65)
		& ((r - b) > 20)
		& (lum < 235)
		& (lum > 40)
	)
	front_face = (
		(a > 70)
		& (yy >= rim_y + 4)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 135)
		& (
			((r > 95) & (g > 65) & ((r - b) > 20) & (lum < 235))
			| ((lum < 160) & (r > 30) & (r > b) & (g > b * 0.4))
		)
	)
	lower_plate = (
		(a > 70)
		& (yy >= rim_y + 10)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 142)
	)
	not_lid = yy >= (rim_y - 12)
	not_cavity_glow = ~(
		(lum > 205) & (r > 200) & (g > 155) & (yy < rim_y + 4) & (np.abs(xx - cx) < 95)
	)
	not_soft_glow = ~(
		(lum > 190) & (r > 200) & (g > 140) & (a < 200) & (yy < rim_y + 8)
	)
	front_mask = (gold_lip | front_face | lower_plate) & not_lid & not_cavity_glow & not_soft_glow

	front = np.zeros_like(open12)
	front[front_mask] = open12[front_mask]
	front[:, :, 3] = np.where(front[:, :, 3] > 40, 255, 0).astype(np.uint8)

	solid = front[:, :, 3] > 40
	if solid.any():
		ys_f, xs_f = np.where(solid)
		y0, y1 = int(ys_f.min()), int(ys_f.max())
		x0, x1 = int(xs_f.min()), int(xs_f.max())
		fill_rgb = np.median(front[solid][:, :3], axis=0).astype(np.uint8)
		dil = _dilate(solid, 2)
		in_box = (
			(yy >= y0)
			& (yy <= y1)
			& (xx >= x0)
			& (xx <= x1)
			& (np.abs(xx - cx) < 135)
			& (yy >= rim_y + 2)
		)
		holes = in_box & (~solid) & dil & (a > 70)
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
	gold_leftover = (
		(ba > 40)
		& (yy >= rim_y - 14)
		& (yy <= rim_y + 6)
		& (np.abs(xx - cx) < 130)
		& (br > 100)
		& (bg > 60)
		& ((br - bb) > 18)
		& (blum < 240)
		& (blum > 35)
		& ~((blum > 210) & (br > 210) & (bg > 170) & (np.abs(xx - cx) < 90))
	)
	wood_leftover = (
		(ba > 40)
		& (yy >= rim_y - 2)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 122)
		& (blum < 175)
		& (br > 30)
		& (br > bb)
	)
	strip = gold_leftover | wood_leftover
	back[strip, 3] = 0
	need = strip & (front[:, :, 3] <= 40) & (a > 70)
	front[need] = open12[need]
	front[:, :, 3] = np.where(front[:, :, 3] > 40, 255, 0).astype(np.uint8)

	meta = {
		"source": str(OPEN12.relative_to(ROOT)),
		"rim_y": rim_y,
		"front_px": int((front[:, :, 3] > 40).sum()),
		"back_px": int((back[:, :, 3] > 40).sum()),
		"overlap": int(((front[:, :, 3] > 40) & (back[:, :, 3] > 40)).sum()),
		"front_top_y": int(np.where((front[:, :, 3] > 40).any(1))[0][0]),
		"lip_top_y": int(np.where((front[:, :, 3] > 40).any(1))[0][0]),
	}
	return back, front, meta


def main() -> None:
	open12 = np.array(Image.open(OPEN12).convert("RGBA"))
	back, front, meta = derive_layers(open12)
	LAYERS.mkdir(parents=True, exist_ok=True)
	Image.fromarray(back, "RGBA").save(OUT_BACK)
	Image.fromarray(front, "RGBA").save(OUT_RIM)
	print("WROTE", OUT_BACK)
	print("WROTE", OUT_RIM)
	print("META", meta)


if __name__ == "__main__":
	main()
