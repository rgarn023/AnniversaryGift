#!/usr/bin/env python3
"""Prepare animation_v2 chest asset package from authoritative sprite sheets.

ASSETS ONLY — does not touch Godot scenes, active frames, version, or APK.

Authoritative sources (1536×1024, 6×4 cells of 256×256):
  assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png
  assets/chest/animation/magical_treasure_chest_animation_sheet.png

Hard consistency rule:
  Every accepted frame must depict the same physical chest (body, camera,
  perspective, trim, lock, scale, lighting) with only lid angle changing.
  Do NOT invent mid-lid poses via warp/morph/paint.

Audit verdict (this pass):
  Of 48 cells inspected, only glowing[0] (closed) is a clean reference body.
  Opening poses remorph the planted body (~40–52% XOR vs closed). Magical-sheet
  chests are ~11% smaller and cannot mix. Fully-open row glowing[18–23] is
  top-sheared. Therefore ship PATH B endpoints only:
    chest_00_closed.png          ← glowing cell 0
    chest_10_fully_open.png      ← glowing cell 15 (bleed-cropped; most-open
                                   non-sheared usable pose)
  Missing clean matched lid intermediates: 10°,20°,30°,40°,50°,60°,70°,80°,90°.
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
GLOW_SHEET = ROOT / "assets" / "chest" / "animation" / "glowing_treasure_chest_opening_sprite_sheet.png"
MAGIC_SHEET = ROOT / "assets" / "chest" / "animation" / "magical_treasure_chest_animation_sheet.png"
V2 = ROOT / "assets" / "chest" / "animation_v2"
FRAMES = V2 / "chest_frames"
SCROLL_DIR = V2 / "scroll"
LAYERS = V2 / "layers"
VALIDATION = V2 / "validation"

## Production canvas sized from source bounds:
##   closed content ≈ 185×160; open (bleed-cropped) ≈ 195×201; cell 256×256.
##   512×512 gives native-scale placement, open-lid headroom, and pad.
CANVAS_W = 512
CANVAS_H = 512
BASE_X = CANVAS_W // 2
BASE_Y = 420  ## absolute plant row (feet)

ACCEPTED = [
	{
		"src_sheet": "glowing",
		"src_index": 0,
		"file": "chest_00_closed.png",
		"lid_open_pct": 0,
		"label": "closed",
	},
	{
		"src_sheet": "glowing",
		"src_index": 15,
		"file": "chest_10_fully_open.png",
		"lid_open_pct": 75,
		"label": "fully_open_endpoint",
		"note": (
			"Most-open non-sheared glowing-sheet pose after next-cell bleed crop. "
			"Planted body does NOT match closed geometry (audit XOR≈51%); "
			"intended as hard-cut open endpoint, not a smooth lid in-between."
		),
	},
]


def load_rgb(path: Path) -> np.ndarray:
	return np.array(Image.open(path).convert("RGB"))


def cell_at(rgb: np.ndarray, index: int, cols: int = 6, rows: int = 4) -> np.ndarray:
	h, w, _ = rgb.shape
	cw, ch = w // cols, h // rows
	r, c = divmod(index, cols)
	return rgb[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw].copy()


def bg_mask(arr: np.ndarray) -> np.ndarray:
	rgb = arr.astype(np.float32)
	lum = rgb.mean(axis=2)
	corners = np.stack([arr[1, 1], arr[1, -2], arr[-2, 1], arr[-2, -2]]).astype(np.float32)
	bg = corners.mean(axis=0)
	diff = np.abs(rgb - bg).sum(axis=2)
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	warm_wood = (r >= b) & (r > 12) & (g >= b * 0.35) & ((r - b) > 2)
	goldish = (r > 70) & (g > 40) & ((r - b) > 12)
	chestish = warm_wood | goldish
	near_bg = (diff < 22) & (~chestish)
	black_matte = (lum < 12) & (diff < 40) & (~chestish)
	return near_bg | black_matte


def body_mask(arr: np.ndarray) -> np.ndarray:
	is_bg = bg_mask(arr)
	r = arr[:, :, 0].astype(np.float32)
	g = arr[:, :, 1].astype(np.float32)
	b = arr[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	body = ~is_bg
	wood = body & (lum < 175) & (r > 40) & (r > b) & (g > b * 0.65)
	gold = body & (lum >= 70) & (lum < 215) & (r > 115) & (g > 75) & ((r - b) > 35)
	return wood | gold


def primary_mass_crop_h(arr: np.ndarray) -> int:
	solid = body_mask(arr)
	row_sum = solid.sum(axis=1).astype(np.int32)
	h = arr.shape[0]
	if int(row_sum.max()) < 20:
		return h
	thresh = max(20, int(row_sum.max() * 0.15))
	best: tuple[int, int, int] | None = None
	i = 0
	while i < h:
		if row_sum[i] >= thresh:
			j = i
			while j + 1 < h and row_sum[j + 1] >= max(8, int(thresh * 0.45)):
				j += 1
			score = int(row_sum[i : j + 1].sum())
			if best is None or score > best[2]:
				best = (i, j, score)
			i = j + 1
		else:
			i += 1
	if best is None:
		return h
	_y0, y1, _score = best
	crop_h = min(h, y1 + 3)
	lum = arr.mean(axis=2)
	energy = (lum > 30).sum(axis=1).astype(np.int32)
	for y in range(max(int(h * 0.45), y1 - 2), min(h - 6, y1 + 24)):
		if energy[y : y + 3].mean() < 22 and energy[y + 3 :].sum() > 180:
			if energy[:y].sum() > 900:
				crop_h = min(crop_h, y)
				break
	return crop_h


def crop_bleed(arr: np.ndarray) -> tuple[np.ndarray, int]:
	lum = arr.mean(axis=2)
	energy = (lum > 30).sum(axis=1).astype(np.int32)
	h = arr.shape[0]
	dark = energy < 18
	bands: list[tuple[int, int]] = []
	i = 0
	while i < h:
		if dark[i]:
			j = i
			while j + 1 < h and dark[j + 1]:
				j += 1
			bands.append((i, j))
			i = j + 1
		else:
			i += 1
	crop_h = h
	for a, b in bands:
		width = b - a + 1
		if a < int(h * 0.45) or width < 8:
			continue
		below = energy[b + 1 :].sum() if b + 1 < h else 0
		above = energy[:a].sum()
		if below > 400 and above > 800:
			crop_h = min(crop_h, a)
	mass_h = primary_mass_crop_h(arr)
	crop_h = min(crop_h, mass_h)
	if crop_h < h:
		return arr[:crop_h].copy(), crop_h
	return arr, h


def find_base(arr: np.ndarray) -> tuple[float, float] | None:
	solid = body_mask(arr)
	h = arr.shape[0]
	row_sum = solid.sum(axis=1).astype(np.int32)
	if int(row_sum.max()) >= 20:
		thresh = max(20, int(row_sum.max() * 0.15))
		best: tuple[int, int, int] | None = None
		i = 0
		while i < h:
			if row_sum[i] >= thresh:
				j = i
				while j + 1 < h and row_sum[j + 1] >= max(8, int(thresh * 0.45)):
					j += 1
				score = int(row_sum[i : j + 1].sum())
				if best is None or score > best[2]:
					best = (i, j, score)
				i = j + 1
			else:
				i += 1
		if best is not None:
			y0, y1, _s = best
			local = row_sum[y0 : y1 + 1]
			peak = int(local.max())
			base_local = len(local) - 1
			for k in range(len(local) - 1, -1, -1):
				if local[k] >= max(8, int(peak * 0.22)):
					base_local = k
					break
			y_max = y0 + base_local
			band = max(y0, y_max - 14)
			band_m = solid & (np.arange(h)[:, None] >= band) & (np.arange(h)[:, None] <= y_max)
			_bys, bxs = np.where(band_m)
			if len(bxs) >= 5:
				return float(np.median(bxs)), float(y_max)
	ys, xs = np.where(solid)
	if len(xs) == 0:
		return None
	y_max = int(ys.max())
	band = ys >= (y_max - 12)
	return float(np.median(xs[band])), float(y_max)


def _dilate(mask: np.ndarray, n: int = 1) -> np.ndarray:
	out = mask.copy()
	for _ in range(n):
		p = np.pad(out, 1, constant_values=False)
		out = (
			out
			| p[:-2, 1:-1]
			| p[2:, 1:-1]
			| p[1:-1, :-2]
			| p[1:-1, 2:]
			| p[:-2, :-2]
			| p[:-2, 2:]
			| p[2:, :-2]
			| p[2:, 2:]
		)
	return out


def harden_chest_opacity(rgba: np.ndarray) -> np.ndarray:
	out = rgba.copy()
	a = out[:, :, 3].astype(np.float32)
	r = out[:, :, 0].astype(np.float32)
	g = out[:, :, 1].astype(np.float32)
	b = out[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	present = a > 18
	wood = present & (lum < 175) & (r > 35) & (r > b) & (g > b * 0.55)
	gold = present & (lum >= 55) & (lum < 235) & (r > 100) & (g > 65) & ((r - b) > 28)
	warm = present & (r > 90) & (g > 45) & ((r - b) > 20) & (lum < 220)
	interior = present & (a >= 90) & (lum >= 28)
	solid = wood | gold | warm | interior
	out[solid, 3] = 255
	opaque = out[:, :, 3] >= 250
	near_body = _dilate(opaque, 2) & present & (out[:, :, 3] < 250) & (lum >= 18)
	out[near_body, 3] = 255
	ys, _xs = np.where(out[:, :, 3] > 18)
	if len(ys):
		chest_top, chest_bot = int(ys.min()), int(ys.max())
		body_cut = int(chest_top + (chest_bot - chest_top) * 0.48)
		yy = np.arange(out.shape[0])[:, None]
		lower = (yy >= body_cut) & (out[:, :, 3] > 24) & (lum >= 12)
		out[lower, 3] = 255
	return out


def to_rgba(arr: np.ndarray) -> np.ndarray:
	is_bg = bg_mask(arr)
	rgba = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.uint8)
	rgba[:, :, :3] = arr
	alpha = np.where(is_bg, 0, 255).astype(np.uint8)
	lum = arr.astype(np.float32).mean(axis=2)
	corners = np.stack([arr[1, 1], arr[1, -2], arr[-2, 1], arr[-2, -2]]).astype(np.float32)
	bg = corners.mean(axis=0)
	diff = np.abs(arr.astype(np.float32) - bg).sum(axis=2)
	r = arr[:, :, 0].astype(np.float32)
	g = arr[:, :, 1].astype(np.float32)
	b = arr[:, :, 2].astype(np.float32)
	bodyish = ((r > 40) & (r > b) & (g > b * 0.55) & (lum < 190)) | (
		(lum >= 55) & (r > 100) & (g > 65) & ((r - b) > 28)
	)
	soft = (~is_bg) & (~bodyish) & (diff < 70) & (lum < 40)
	alpha = alpha.copy()
	alpha[soft] = 160
	near_black = (lum < 18) & (alpha > 0) & (diff < 50) & (~bodyish)
	alpha[near_black] = 0
	rgba[:, :, 3] = alpha
	return harden_chest_opacity(rgba)


def cell_top_clipped(arr: np.ndarray, threshold: int = 48) -> bool:
	content = ~bg_mask(arr)
	return int((content[0] | content[1]).sum()) >= threshold


def place_aligned(arr: np.ndarray) -> tuple[np.ndarray, tuple[float, float] | None, int]:
	cropped, crop_h = crop_bleed(arr)
	anchor = find_base(cropped)
	rgba = to_rgba(cropped)
	out = np.zeros((CANVAS_H, CANVAS_W, 4), dtype=np.uint8)
	if anchor is None:
		x0 = (CANVAS_W - cropped.shape[1]) // 2
		y0 = (CANVAS_H - cropped.shape[0]) // 2
	else:
		ax, ay = anchor
		x0 = int(round(BASE_X - ax))
		y0 = int(round(BASE_Y - ay))
	h, w = rgba.shape[:2]
	dst_x0, dst_y0 = x0, y0
	src_x0 = src_y0 = 0
	src_x1, src_y1 = w, h
	if dst_x0 < 0:
		src_x0 = -dst_x0
		dst_x0 = 0
	if dst_y0 < 0:
		src_y0 = -dst_y0
		dst_y0 = 0
	if dst_x0 + (src_x1 - src_x0) > CANVAS_W:
		src_x1 = src_x0 + (CANVAS_W - dst_x0)
	if dst_y0 + (src_y1 - src_y0) > CANVAS_H:
		src_y1 = src_y0 + (CANVAS_H - dst_y0)
	if src_x1 > src_x0 and src_y1 > src_y0:
		patch = rgba[src_y0:src_y1, src_x0:src_x1]
		dest = out[dst_y0 : dst_y0 + patch.shape[0], dst_x0 : dst_x0 + patch.shape[1]].copy()
		a = patch[:, :, 3:4].astype(np.float32) / 255.0
		dest[:, :, :3] = (
			patch[:, :, :3].astype(np.float32) * a + dest[:, :, :3].astype(np.float32) * (1 - a)
		).astype(np.uint8)
		dest[:, :, 3] = np.maximum(dest[:, :, 3], patch[:, :, 3])
		out[dst_y0 : dst_y0 + patch.shape[0], dst_x0 : dst_x0 + patch.shape[1]] = dest
	return out, anchor, crop_h


def base_metrics(rgba: np.ndarray) -> tuple[float, float] | None:
	alpha = rgba[:, :, 3]
	ys, xs = np.where(alpha > 40)
	if len(xs) == 0:
		return None
	y_max = int(ys.max())
	band = ys >= (y_max - 8)
	return float(np.median(xs[band])), float(y_max)


def visual_center(rgba: np.ndarray) -> tuple[float, float] | None:
	a = rgba[:, :, 3].astype(np.float64)
	if a.sum() <= 0:
		return None
	yy, xx = np.indices(a.shape)
	return float((xx * a).sum() / a.sum()), float((yy * a).sum() / a.sum())


def visible_bbox(rgba: np.ndarray) -> list[int] | None:
	ys, xs = np.where(rgba[:, :, 3] > 40)
	if len(xs) == 0:
		return None
	return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]


def lock_to_anchor(
	rgba: np.ndarray, target_cx: float, target_y: float, target_visual_cx: float | None = None
) -> np.ndarray:
	m = base_metrics(rgba)
	if m is None:
		return rgba
	cx, y = m
	dx = int(round(target_cx - cx))
	dy = int(round(target_y - y))
	if target_visual_cx is not None:
		vc = visual_center(rgba)
		if vc is not None:
			dx = int(round(target_visual_cx - vc[0]))
	if dx == 0 and dy == 0:
		return rgba
	out = np.zeros_like(rgba)
	h, w = rgba.shape[:2]
	if dx >= 0:
		dst_x0, src_x0, width = dx, 0, w - dx
	else:
		dst_x0, src_x0, width = 0, -dx, w + dx
	if dy >= 0:
		dst_y0, src_y0, height = dy, 0, h - dy
	else:
		dst_y0, src_y0, height = 0, -dy, h + dy
	if width <= 0 or height <= 0:
		return rgba
	out[dst_y0 : dst_y0 + height, dst_x0 : dst_x0 + width] = rgba[
		src_y0 : src_y0 + height, src_x0 : src_x0 + width
	]
	return out


def dampen_cavity_glow(rgba: np.ndarray) -> np.ndarray:
	out = rgba.copy()
	a = out[:, :, 3]
	r = out[:, :, 0].astype(np.float32)
	g = out[:, :, 1].astype(np.float32)
	b = out[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	ys, xs = np.where(a > 40)
	if len(ys) == 0:
		return out
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	yy = np.arange(out.shape[0])[:, None]
	xx = np.arange(out.shape[1])[None, :]
	in_cavity = (
		(a > 40)
		& (yy >= chest_top + int(chest_h * 0.12))
		& (yy <= chest_top + int(chest_h * 0.58))
		& (np.abs(xx - cx) < 110)
	)
	hot = in_cavity & (lum > 160) & (r > 175) & (g > 120)
	mild = in_cavity & (lum > 130) & (r > 145) & (g > 100) & (~hot)
	if hot.any():
		out[:, :, 0] = np.where(hot, np.clip(r * 0.52 + 22, 0, 195), out[:, :, 0]).astype(np.uint8)
		out[:, :, 1] = np.where(hot, np.clip(g * 0.48 + 14, 0, 135), out[:, :, 1]).astype(np.uint8)
		out[:, :, 2] = np.where(hot, np.clip(b * 0.38 + 6, 0, 80), out[:, :, 2]).astype(np.uint8)
	if mild.any():
		r2 = out[:, :, 0].astype(np.float32)
		g2 = out[:, :, 1].astype(np.float32)
		b2 = out[:, :, 2].astype(np.float32)
		out[:, :, 0] = np.where(mild, np.clip(r2 * 0.74 + 8, 0, 205), out[:, :, 0]).astype(np.uint8)
		out[:, :, 1] = np.where(mild, np.clip(g2 * 0.70 + 5, 0, 155), out[:, :, 1]).astype(np.uint8)
		out[:, :, 2] = np.where(mild, np.clip(b2 * 0.62 + 3, 0, 100), out[:, :, 2]).astype(np.uint8)
	return out


def _alpha_over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
	out = dst.copy()
	a = src[:, :, 3:4].astype(np.float32) / 255.0
	out[:, :, :3] = (
		src[:, :, :3].astype(np.float32) * a + out[:, :, :3].astype(np.float32) * (1.0 - a)
	).astype(np.uint8)
	out[:, :, 3] = np.maximum(out[:, :, 3], src[:, :, 3])
	return out


def extract_front_rim(open_placed: np.ndarray) -> np.ndarray:
	"""Foreground rim/front structure for scroll occlusion."""
	a = open_placed[:, :, 3]
	ys, xs = np.where(a > 40)
	if len(ys) == 0:
		return np.zeros_like(open_placed)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	rim_y = int(chest_top + chest_h * 0.50)
	yy = np.arange(open_placed.shape[0])[:, None]
	xx = np.arange(open_placed.shape[1])[None, :]
	r = open_placed[:, :, 0].astype(np.float32)
	g = open_placed[:, :, 1].astype(np.float32)
	b = open_placed[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	gold_lip = (
		(a > 70)
		& (yy >= rim_y - 3)
		& (yy <= rim_y + 18)
		& (np.abs(xx - cx) < 120)
		& (r > 110)
		& (g > 75)
		& ((r - b) > 25)
		& (lum < 225)
		& (lum > 50)
	)
	front_face = (
		(a > 70)
		& (yy >= rim_y + 8)
		& (yy <= chest_bot)
		& (np.abs(xx - cx) < 128)
		& (
			((r > 100) & (g > 70) & ((r - b) > 25) & (lum < 230))
			| ((lum < 155) & (r > 35) & (r > b) & (g > b * 0.45))
		)
	)
	not_glow = ~((lum > 190) & (r > 200) & (g > 140) & (a < 200) & (yy < rim_y + 10))
	## Exclude lid / heart-lock above the cavity mouth.
	not_lid = yy >= (rim_y - 4)
	front_mask = (gold_lip | front_face) & not_glow & not_lid
	front = np.zeros_like(open_placed)
	front[front_mask] = open_placed[front_mask]
	fa = front[:, :, 3]
	front[:, :, 3] = np.where(fa > 40, 255, 0).astype(np.uint8)
	solid = front[:, :, 3] > 40
	if solid.any():
		ys_f, xs_f = np.where(solid)
		y0, y1 = int(ys_f.min()), int(ys_f.max())
		x0, x1 = int(xs_f.min()), int(xs_f.max())
		sample = front[solid]
		fill_rgb = np.median(sample[:, :3], axis=0).astype(np.uint8)
		yy = np.arange(front.shape[0])[:, None]
		xx = np.arange(front.shape[1])[None, :]
		in_box = (yy >= y0) & (yy <= y1) & (xx >= x0) & (xx <= x1) & (np.abs(xx - cx) < 128)
		holes = in_box & (front[:, :, 3] <= 40) & (yy >= rim_y - 1)
		dil = _dilate(solid, 2)
		fill_m = holes & dil
		front[fill_m, 0] = fill_rgb[0]
		front[fill_m, 1] = fill_rgb[1]
		front[fill_m, 2] = fill_rgb[2]
		front[fill_m, 3] = 255
	return front


def extract_open_back(open_placed: np.ndarray, front_rim: np.ndarray) -> np.ndarray:
	"""Open chest minus the front-rim occlusion layer (no duplicate rim overlay)."""
	back = open_placed.copy()
	rim_solid = front_rim[:, :, 3] > 40
	## Soften only the overlapping front-face pixels out of the back layer so
	## scroll can sit between back and rim. Keep lid + interior + sides.
	ys, xs = np.where(open_placed[:, :, 3] > 40)
	if len(ys) == 0:
		return back
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	rim_y = int(chest_top + chest_h * 0.50)
	yy = np.arange(back.shape[0])[:, None]
	xx = np.arange(back.shape[1])[None, :]
	## Remove front-face band that the rim layer owns; keep lid above rim_y-8.
	front_owned = rim_solid & (yy >= rim_y - 2) & (np.abs(xx - cx) < 128)
	back[front_owned, 3] = 0
	return back


def build_love_scroll() -> tuple[np.ndarray, dict]:
	"""Standalone upright rolled parchment — no chest pixels, no baked glow bloom."""
	donor = ROOT / "assets" / "art" / "scroll" / "scroll_rolled.png"
	if not donor.exists():
		raise RuntimeError(f"Missing scroll donor: {donor}")
	rolled = np.array(Image.open(donor).convert("RGBA"))
	lum = rolled[:, :, :3].astype(np.float32).mean(axis=2)
	alpha = rolled[:, :, 3].astype(np.float32)
	alpha[lum < 14] = 0
	rolled = rolled.copy()
	rolled[:, :, 3] = alpha.astype(np.uint8)
	ys, xs = np.where(rolled[:, :, 3] > 40)
	if len(ys) == 0:
		raise RuntimeError("Scroll donor empty after matte strip")
	crop = rolled[int(ys.min()) : int(ys.max()) + 1, int(xs.min()) : int(xs.max()) + 1]
	## Horizontal tube → upright cylindrical love note.
	if crop.shape[1] >= crop.shape[0]:
		upright = Image.fromarray(crop, "RGBA").transpose(Image.Transpose.ROTATE_90)
	else:
		upright = Image.fromarray(crop, "RGBA")
	upright = upright.rotate(-4, expand=True, resample=Image.Resampling.BICUBIC)
	arr = np.array(upright)
	lum = arr[:, :, :3].astype(np.float32).mean(axis=2)
	a = arr[:, :, 3].astype(np.float32)
	a[lum < 14] = 0
	arr[:, :, 3] = a.astype(np.uint8)
	ys2, xs2 = np.where(arr[:, :, 3] > 40)
	arr = arr[int(ys2.min()) : int(ys2.max()) + 1, int(xs2.min()) : int(xs2.max()) + 1]
	## Target: narrower than open cavity (~body_w*0.28). Open body ≈ 180–200 → ~52–56.
	target_w = 56
	target_h = int(round(target_w * 2.35))
	scroll = np.array(
		Image.fromarray(arr, "RGBA").resize((target_w, target_h), Image.Resampling.LANCZOS)
	)
	rgb = scroll[:, :, :3].astype(np.float32)
	mask = scroll[:, :, 3] > 40
	## Warm parchment grade — never blown-out white / huge glow.
	rgb[mask, 0] = np.clip(rgb[mask, 0] * 0.96 + 6, 0, 235)
	rgb[mask, 1] = np.clip(rgb[mask, 1] * 0.94 + 2, 0, 210)
	rgb[mask, 2] = np.clip(rgb[mask, 2] * 0.88, 0, 175)
	scroll[:, :, :3] = rgb.astype(np.uint8)
	scroll[:, :, 3] = np.where(mask, 255, 0).astype(np.uint8)
	meta = {
		"source": str(donor.relative_to(ROOT)),
		"donor_size": list(Image.open(donor).size),
		"output_size": [int(scroll.shape[1]), int(scroll.shape[0])],
		"contains_chest_pixels": False,
		"baked_glow": False,
	}
	return scroll, meta


def place_scroll_in_cavity(open_back: np.ndarray, scroll: np.ndarray, rise_frac: float = 0.35) -> np.ndarray:
	ys, xs = np.where(open_back[:, :, 3] > 40)
	if len(ys) == 0:
		return np.zeros_like(open_back)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	rim_y = int(chest_top + chest_h * 0.50)
	rw, rh = scroll.shape[1], scroll.shape[0]
	layer = np.zeros_like(open_back)
	dst_x = int(round(cx - rw * 0.5))
	## rise_frac: 0 = mostly hidden, 1 = mostly emerged
	dst_y = int(round(rim_y - rh * (0.15 + 0.70 * rise_frac)))
	h, w = layer.shape[:2]
	sx0 = sy0 = 0
	sx1, sy1 = rw, rh
	if dst_x < 0:
		sx0 = -dst_x
		dst_x = 0
	if dst_y < 0:
		sy0 = -dst_y
		dst_y = 0
	if dst_x + (sx1 - sx0) > w:
		sx1 = sx0 + (w - dst_x)
	if dst_y + (sy1 - sy0) > h:
		sy1 = sy0 + (h - dst_y)
	if sx1 > sx0 and sy1 > sy0:
		patch = scroll[sy0:sy1, sx0:sx1]
		layer[dst_y : dst_y + patch.shape[0], dst_x : dst_x + patch.shape[1]] = patch
	return layer


def audit_sheets() -> dict:
	glow = load_rgb(GLOW_SHEET)
	magic = load_rgb(MAGIC_SHEET)
	rejected = []
	## Closed-row near-dupes / glow pulse
	for i in range(1, 6):
		rejected.append(
			{
				"sheet": "glowing",
				"index": i,
				"reason": "closed near-dupe / idle glow pulse; not a lid-open pose; AI micro-drift vs cell 0",
			}
		)
	for i in range(6, 12):
		rejected.append(
			{
				"sheet": "glowing",
				"index": i,
				"reason": "crack/partial-open row — planted body remorphs vs closed (XOR≈40–46%); not same physical chest",
			}
		)
	for i in [12, 13, 14, 16, 17]:
		rejected.append(
			{
				"sheet": "glowing",
				"index": i,
				"reason": "mid-open row — body remorph + next-cell bleed; near-dupes of cell 15 cluster; rejected as mid-lid art",
			}
		)
	## 15 kept as open endpoint (documented mismatch)
	for i in range(18, 24):
		cell = cell_at(glow, i)
		rejected.append(
			{
				"sheet": "glowing",
				"index": i,
				"reason": f"fully-open row TOP-SHEARED (top-edge content px={int((~bg_mask(cell))[0:2].sum())}); unusable",
			}
		)
	for i in range(24):
		rejected.append(
			{
				"sheet": "magical",
				"index": i,
				"reason": (
					"magical-sheet body ≈11% smaller than glowing closed; different proportions; "
					"cannot mix into glowing sequence. Mid/late cells also bake scroll + shear."
				),
			}
		)
	return {
		"candidates_inspected": 48,
		"compatible_for_smooth_lid_arc": 1,
		"accepted_production_frames": 2,
		"accepted_note": (
			"Only glowing[0] passes hard same-body consistency. glowing[15] accepted solely as "
			"a hard-cut open endpoint (documented body mismatch). No clean 10–90% mid-lid poses."
		),
		"rejected": rejected,
	}


def write_validation(frames: list[np.ndarray], labels: list[str], open_back: np.ndarray, front: np.ndarray, scroll: np.ndarray) -> dict:
	VALIDATION.mkdir(parents=True, exist_ok=True)
	## Contact sheet — raw accepted frames side by side
	gap = 12
	panel_w = CANVAS_W
	panel_h = CANVAS_H
	n = len(frames)
	sheet_w = n * panel_w + (n + 1) * gap
	sheet_h = panel_h + 48
	sheet = Image.new("RGBA", (sheet_w, sheet_h), (24, 24, 28, 255))
	draw = ImageDraw.Draw(sheet)
	x = gap
	for fr, lab in zip(frames, labels):
		bg = Image.new("RGBA", (panel_w, panel_h), (24, 24, 28, 255))
		bg = Image.alpha_composite(bg, Image.fromarray(fr, "RGBA"))
		sheet.paste(bg, (x, 36))
		draw.text((x + 8, 10), lab, fill=(255, 220, 120, 255))
		x += panel_w + gap
	contact_path = VALIDATION / "chest_frames_contact_sheet.png"
	sheet.save(contact_path)

	## Alignment overlay: closed green / open red onion on shared canvas
	overlay = np.zeros((CANVAS_H, CANVAS_W, 4), dtype=np.uint8)
	if len(frames) >= 2:
		a0 = frames[0][:, :, 3] > 40
		a1 = frames[1][:, :, 3] > 40
		overlay[a0, 1] = 200
		overlay[a0, 3] = 220
		overlay[a1, 0] = 220
		overlay[a1, 3] = np.maximum(overlay[a1, 3], 180)
		both = a0 & a1
		overlay[both, 0] = 40
		overlay[both, 1] = 200
		overlay[both, 2] = 40
		overlay[both, 3] = 230
		## Base anchor crosshair
		img = Image.fromarray(overlay, "RGBA")
		d = ImageDraw.Draw(img)
		d.line([(BASE_X - 40, BASE_Y), (BASE_X + 40, BASE_Y)], fill=(255, 255, 0, 255), width=2)
		d.line([(BASE_X, BASE_Y - 40), (BASE_X, BASE_Y + 40)], fill=(255, 255, 0, 255), width=2)
		d.text((8, 8), "green=closed red=open yellow=overlap; cross=base anchor", fill=(255, 255, 255, 255))
		align_path = VALIDATION / "chest_alignment_overlay.png"
		img.save(align_path)
	else:
		align_path = VALIDATION / "chest_alignment_overlay.png"
		Image.fromarray(frames[0], "RGBA").save(align_path)

	## Scroll occlusion proof
	scroll_alone = Image.new("RGBA", (CANVAS_W, CANVAS_H), (24, 24, 28, 255))
	# center raw scroll for alone panel
	alone = np.zeros((CANVAS_H, CANVAS_W, 4), dtype=np.uint8)
	sy = (CANVAS_H - scroll.shape[0]) // 2
	sx = (CANVAS_W - scroll.shape[1]) // 2
	alone[sy : sy + scroll.shape[0], sx : sx + scroll.shape[1]] = scroll
	scroll_layer = place_scroll_in_cavity(open_back, scroll, rise_frac=0.45)
	comp = _alpha_over(open_back, scroll_layer)
	comp = _alpha_over(comp, front)
	proof_w = CANVAS_W * 4 + gap * 5
	proof = Image.new("RGBA", (proof_w, CANVAS_H + 40), (24, 24, 28, 255))
	pd = ImageDraw.Draw(proof)
	panels = [
		("scroll alone", alone),
		("open back", open_back),
		("scroll in cavity", _alpha_over(open_back, scroll_layer)),
		("front rim occludes", comp),
	]
	px = gap
	for title, arr in panels:
		bg = Image.new("RGBA", (CANVAS_W, CANVAS_H), (24, 24, 28, 255))
		bg = Image.alpha_composite(bg, Image.fromarray(arr, "RGBA"))
		proof.paste(bg, (px, 32))
		pd.text((px + 8, 8), title, fill=(255, 220, 120, 255))
		px += CANVAS_W + gap
	scroll_proof = VALIDATION / "scroll_occlusion_validation.png"
	proof.save(scroll_proof)

	## Occlusion check: lower scroll pixels covered by rim
	scroll_solid = scroll_layer[:, :, 3] > 40
	rim_solid = front[:, :, 3] > 40
	ys, xs = np.where(scroll_solid)
	occluded = False
	if len(ys):
		lower = scroll_solid & (np.arange(CANVAS_H)[:, None] >= int(np.percentile(ys, 70)))
		occluded = bool((lower & rim_solid).any()) and bool((lower & ~rim_solid).sum() < lower.sum())
	return {
		"contact_sheet": str(contact_path.relative_to(ROOT)),
		"alignment_overlay": str(align_path.relative_to(ROOT)),
		"scroll_occlusion_validation": str(scroll_proof.relative_to(ROOT)),
		"front_rim_occludes_lower_scroll": occluded,
	}


def main() -> None:
	FRAMES.mkdir(parents=True, exist_ok=True)
	SCROLL_DIR.mkdir(parents=True, exist_ok=True)
	LAYERS.mkdir(parents=True, exist_ok=True)
	VALIDATION.mkdir(parents=True, exist_ok=True)

	for p in FRAMES.glob("*.png"):
		p.unlink()
	for p in SCROLL_DIR.glob("*.png"):
		p.unlink()
	for p in LAYERS.glob("*.png"):
		p.unlink()

	glow = load_rgb(GLOW_SHEET)
	assert glow.shape[1] == 1536 and glow.shape[0] == 1024, glow.shape

	placed_raw: list[np.ndarray] = []
	crop_hs: list[int] = []
	for spec in ACCEPTED:
		cell = cell_at(glow, spec["src_index"])
		if spec["src_index"] >= 18 and cell_top_clipped(cell):
			raise RuntimeError(f"Refusing top-sheared cell {spec['src_index']}")
		placed, _anchor, crop_h = place_aligned(cell)
		placed_raw.append(placed)
		crop_hs.append(crop_h)

	## Foot-lock both axes to canvas plant X and the closed frame's foot Y.
	## Do not re-center by lid-weighted visual mass (that slides the feet).
	closed_plant = lock_to_anchor(placed_raw[0], float(BASE_X), float(BASE_Y), None)
	anchor_closed = base_metrics(closed_plant)
	if anchor_closed is None:
		raise RuntimeError("No base anchor on closed frame")
	target_cx, target_y = float(BASE_X), float(anchor_closed[1])

	frames_out: list[np.ndarray] = []
	frame_meta: list[dict] = []
	for spec, placed, crop_h in zip(ACCEPTED, placed_raw, crop_hs):
		locked = lock_to_anchor(placed, target_cx, target_y, None)
		for _ in range(3):
			m = base_metrics(locked)
			if m is None:
				break
			if abs(m[0] - target_cx) < 0.5 and abs(m[1] - target_y) < 0.5:
				break
			locked = lock_to_anchor(locked, target_cx, target_y, None)
		if spec["label"] != "closed":
			locked = dampen_cavity_glow(locked)
		locked = harden_chest_opacity(locked)
		locked = lock_to_anchor(locked, target_cx, target_y, None)
		m_final = base_metrics(locked)
		vc = visual_center(locked)
		bbox = visible_bbox(locked)
		top_hits = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		if top_hits > 0:
			raise RuntimeError(f"{spec['file']} lid clipped at canvas top ({top_hits} px)")
		path = FRAMES / spec["file"]
		Image.fromarray(locked, "RGBA").save(path)
		frames_out.append(locked)
		entry = {
			"file": f"chest_frames/{spec['file']}",
			"label": spec["label"],
			"lid_open_pct": spec["lid_open_pct"],
			"src_sheet": spec["src_sheet"],
			"src_index": spec["src_index"],
			"crop_h": crop_h,
			"base_anchor": {
				"x": m_final[0] if m_final else None,
				"y": m_final[1] if m_final else None,
			},
			"visual_center": {"x": vc[0] if vc else None, "y": vc[1] if vc else None},
			"visible_bbox_xyxy": bbox,
			"canvas_top_hits": top_hits,
		}
		if "note" in spec:
			entry["note"] = spec["note"]
		frame_meta.append(entry)
		print(
			f"wrote {path.name} src={spec['src_index']} crop_h={crop_h} "
			f"base={m_final} vis={None if vc is None else (round(vc[0],1), round(vc[1],1))} top={top_hits}"
		)

	open_frame = frames_out[-1]
	front = extract_front_rim(open_frame)
	back = extract_open_back(open_frame, front)
	Image.fromarray(back, "RGBA").save(LAYERS / "chest_open_back.png")
	Image.fromarray(front, "RGBA").save(LAYERS / "chest_open_front_rim.png")
	print(f"wrote layers back={back.shape[1]}x{back.shape[0]} front_px={(front[:,:,3]>40).sum()}")

	scroll, scroll_meta = build_love_scroll()
	Image.fromarray(scroll, "RGBA").save(SCROLL_DIR / "love_scroll.png")
	print(f"wrote love_scroll.png {scroll.shape[1]}x{scroll.shape[0]}")

	audit = audit_sheets()
	validation = write_validation(
		frames_out,
		[f"{e['file']} ({e['lid_open_pct']}%)" for e in frame_meta],
		back,
		front,
		scroll,
	)

	missing_pct = [10, 20, 30, 40, 50, 60, 70, 80, 90]
	## 75% endpoint covers "fully open" slot nominally; still missing true matched mids
	manifest = {
		"package": "animation_v2",
		"pass": "asset_preparation_only",
		"godot_integration": False,
		"source_files": [
			{
				"path": str(GLOW_SHEET.relative_to(ROOT)),
				"dimensions": [1536, 1024],
				"grid": "6x4",
				"cell": [256, 256],
			},
			{
				"path": str(MAGIC_SHEET.relative_to(ROOT)),
				"dimensions": [1536, 1024],
				"grid": "6x4",
				"cell": [256, 256],
			},
		],
		"production_canvas": {"width": CANVAS_W, "height": CANVAS_H},
		"base_anchor_target": {"x": BASE_X, "y": BASE_Y},
		"visual_center_target": {"x": BASE_X, "y": "alpha_weighted_per_frame"},
		"chest_frames": frame_meta,
		"missing_lid_open_percentages": missing_pct,
		"smooth_8_to_11_frame_sequence_possible": False,
		"scroll": {
			"path": "scroll/love_scroll.png",
			**scroll_meta,
		},
		"layers": {
			"chest_open_back": "layers/chest_open_back.png",
			"chest_open_front_rim": "layers/chest_open_front_rim.png",
			"dimensions": [CANVAS_W, CANVAS_H],
		},
		"intended_future_godot_layer_order": [
			"beach",
			"open chest/back (chest_open_back.png)",
			"scroll (love_scroll.png)",
			"front rim (chest_open_front_rim.png)",
			"glow/particles",
			"UI",
		],
		"audit": audit,
		"validation_temp": validation,
	}
	(V2 / "animation_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

	readme = f"""# animation_v2 — Chest Asset Requirements

Asset-preparation package only. **Not wired into Godot.** Do not treat this as a
shippable smooth lid animation.

## Authoritative sources

| File | Size | Grid |
|------|------|------|
| `assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png` | 1536×1024 | 6×4 cells (256×256) |
| `assets/chest/animation/magical_treasure_chest_animation_sheet.png` | 1536×1024 | 6×4 cells (256×256) |

Use only this fantasy wooden/gold heart-lock chest. Do not substitute the old bronze chest.

## Production canvas

- **{CANVAS_W}×{CANVAS_H}** RGBA PNG for every chest frame and open layer
- Chosen from source bounds: closed ≈185×160, open (bleed-cropped) ≈195×201, cell 256×256, plus lid/glow headroom
- Base anchor target: **({BASE_X}, {BASE_Y})** — post-lock foot Y drift target **0 px**
- Horizontal visual center target: **x = {BASE_X}**

## Consistency rules

Every frame in a future lid sequence must be the **exact same chest**:

- same body footprint, camera, perspective, trim, heart-lock, scale, lighting direction
- **only** the lid angle may change
- no grow/shrink/widen/narrow/warp/hinge drift
- no image warping, morphing, AI repainting, or interpolated lid geometry to fake missing poses
- no scroll baked into opening frames
- chest body pixels fully opaque where the source is opaque
- enough transparent headroom for the fully open lid (do not crop the lid)

## Final accepted files

### Chest frames (`chest_frames/`)

| File | Lid open % | Source |
|------|------------|--------|
| `chest_00_closed.png` | 0% | glowing cell 0 |
| `chest_10_fully_open.png` | ~75% (hard-cut open endpoint) | glowing cell 15 (bleed-cropped) |

Only these two production frames were created. Filenames `chest_01`…`chest_09` are **intentionally absent**.

### Scroll (`scroll/`)

- `love_scroll.png` — upright rolled parchment from `assets/art/scroll/scroll_rolled.png`
- Transparent PNG, warm parchment (not white), no chest/lid/rim/glow background
- Glow must stay out of this file (Godot will handle glow later)

### Layers (`layers/`)

Derived from the accepted open endpoint:

- `chest_open_back.png` — open chest / lid / rear interior behind the scroll
- `chest_open_front_rim.png` — foreground rim/front structure only (occlusion)

## Rejected source poses

### Glowing sheet (24 cells)

- **1–5:** closed near-dupes / idle glow pulse; AI micro-drift; not lid opens
- **6–11:** crack/partial-open — planted body remorphs vs closed (~40–46% XOR); rejected
- **12–14, 16–17:** mid-open cluster — body remorph + next-cell bleed; not matched mid-lid art
- **15:** kept only as hard-cut open endpoint (body still mismatches closed ~51% XOR)
- **18–23:** fully-open row **top-sheared** (lid cut by cell edge) — unusable

### Magical sheet (24 cells)

- Entire sheet rejected for the glowing-body sequence: body ~**11% smaller**, different proportions
- Mid/late cells bake scroll into the chest plate; late cells top-sheared
- Scroll artwork consulted only as visual reference; production scroll uses the clean project rolled parchment

## Missing intermediate poses

A genuinely smooth 8–11 frame lid arc is **not** possible from existing source art.

New matched production artwork is required for the **same camera/body/trim/lock/scale/lighting** as glowing cell 0, at approximately:

- 10° / 20° / 30° / 40° / 50° / 60° / 70° / 80° / 90° lid angles
- plus a clean **non-sheared fully-open** pose with the same body as closed

Until then, integration must not pretend mid-lid frames exist.

## Intended future Godot layer order

1. beach  
2. open chest/back (`chest_open_back.png`)  
3. scroll (`love_scroll.png`)  
4. front rim (`chest_open_front_rim.png`)  
5. glow/particles  
6. UI  

Do **not** implement this order in this pass.

## Validation (temporary — do not commit)

Under `validation/`:

- `chest_frames_contact_sheet.png` — accepted frames in order
- `chest_alignment_overlay.png` — body footprint / base / center onion
- `scroll_occlusion_validation.png` — scroll alone, back, cavity place, rim composite

## Tooling

Regenerate with:

```bash
python3 tools/prepare_animation_v2_assets.py
```
"""
	(V2 / "README_ASSET_REQUIREMENTS.md").write_text(readme)
	print("wrote animation_manifest.json + README_ASSET_REQUIREMENTS.md")
	print(json.dumps({"validation": validation, "smooth_possible": False}, indent=2))


if __name__ == "__main__":
	main()
