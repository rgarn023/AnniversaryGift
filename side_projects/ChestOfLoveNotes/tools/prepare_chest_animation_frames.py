#!/usr/bin/env python3
"""Prepare aligned transparent chest animation frames from authoring sprite sheets.

Source sheets (do not delete):
  assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png
  assets/chest/animation/magical_treasure_chest_animation_sheet.png

Outputs:
  assets/art/chest/frames/empty/*.png
  assets/art/chest/frames/scroll/*.png
  assets/art/chest/scroll_rolled.png   (clean parchment-only scroll layer)
  assets/art/chest/chest_front_rim.png (thin front-lip occlusion for scroll rise)

v42 polish:
  - empty + unread share glowing-sheet opening geometry (one chest family)
  - scroll rise uses a clean parchment donor — never magical-sheet chest pixels
  - stronger rim-occluded peek → rise → final reward stages
  - normalize lower-body visual scale across poses (foot-locked)
  - preserve absolute foot lock (BASE_Y) and canvas center
  - reject top-sheared source cells
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "chest" / "frames"
ART = ROOT / "assets" / "art" / "chest"
GLOW_SHEET = ROOT / "assets" / "chest" / "animation" / "glowing_treasure_chest_opening_sprite_sheet.png"
MAGIC_SHEET = ROOT / "assets" / "chest" / "animation" / "magical_treasure_chest_animation_sheet.png"

## Extra transparent rows above the planted chest; foot Y stays absolute so the
## chest does not drift when headroom grows.
CANVAS_W = 384
CANVAS_H = 496
BASE_X = CANVAS_W // 2
BASE_Y = 367  ## absolute plant row — unchanged so centering holds


def load_rgb(path: Path) -> np.ndarray:
	return np.array(Image.open(path).convert("RGB"))


def cell_at(rgb: np.ndarray, index: int, cols: int = 6, rows: int = 4) -> np.ndarray:
	h, w, _ = rgb.shape
	cw, ch = w // cols, h // rows
	r, c = divmod(index, cols)
	return rgb[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw].copy()


def bg_mask(arr: np.ndarray) -> np.ndarray:
	"""Strict sheet-background mask — removes dark cell fill without eating glow."""
	lum = arr.astype(np.float32).mean(axis=2)
	corners = np.stack([arr[1, 1], arr[1, -2], arr[-2, 1], arr[-2, -2]]).astype(np.float32)
	bg = corners.mean(axis=0)
	diff = np.abs(arr.astype(np.float32) - bg).sum(axis=2)
	return (lum < 30) | (diff < 42)


def crop_bleed(arr: np.ndarray) -> tuple[np.ndarray, int]:
	"""Remove bottom-row bleed from the next sprite-sheet cell (not top content)."""
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
	if crop_h == h:
		for y in range(h - 16, h - 6):
			if energy[y] < 25 and energy[y + 1 :].mean() > 30 and energy[:y].sum() > 1000:
				crop_h = y
				break
	## Detached lower fragment (next-cell lid/scroll peek) without a full dark band.
	if crop_h == h:
		lower = energy[int(h * 0.55) :]
		upper = energy[: int(h * 0.55)]
		if upper.sum() > 1200 and lower.sum() > 350:
			best_y = None
			best_score = 1e18
			for y in range(int(h * 0.55), h - 8):
				window = float(energy[y : y + 4].mean())
				if window < best_score and window < 28:
					best_score = window
					best_y = y
			if best_y is not None and energy[best_y:].sum() > 200:
				crop_h = best_y
	if crop_h < h:
		return arr[:crop_h].copy(), crop_h
	return arr, h


def find_base(arr: np.ndarray) -> tuple[float, float] | None:
	is_bg = bg_mask(arr)
	r = arr[:, :, 0].astype(np.float32)
	g = arr[:, :, 1].astype(np.float32)
	b = arr[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	body = ~is_bg
	wood = body & (lum < 175) & (r > 40) & (r > b) & (g > b * 0.65)
	gold = body & (lum >= 70) & (lum < 215) & (r > 115) & (g > 75) & ((r - b) > 35)
	solid = wood | gold
	h = arr.shape[0]
	lower = np.zeros_like(solid)
	lower[int(h * 0.40) :, :] = solid[int(h * 0.40) :, :]
	ys, xs = np.where(lower)
	if len(xs) < 20:
		ys, xs = np.where(solid)
	if len(xs) == 0:
		return None
	y_max = int(ys.max())
	band = y_max - 12
	band_m = lower & (np.arange(h)[:, None] >= band)
	_bys, bxs = np.where(band_m)
	if len(bxs) < 5:
		band_m = body & (np.arange(h)[:, None] >= band)
		_bys, bxs = np.where(band_m)
	cx = float(np.median(bxs)) if len(bxs) else float(np.median(xs))
	return cx, float(y_max)


def harden_chest_opacity(rgba: np.ndarray) -> np.ndarray:
	"""Force wood/gold chest body pixels fully opaque.

	Soft mid-alpha must never make the physical chest see-through over beach.
	Glow / soft fringe may stay translucent at the extreme outer edge only.
	"""
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
	body = wood | gold | warm
	## Interior fill that is clearly chest mass (not sparse glow dust).
	interior = present & (a >= 90) & (lum >= 28)
	solid = body | interior
	out[solid, 3] = 255
	## Collapse residual soft body fringe: if a mid-alpha pixel is surrounded by
	## opaque body, promote it to opaque instead of letting beach show through.
	opaque = out[:, :, 3] >= 250
	near_body = _dilate(opaque, 1) & present & (out[:, :, 3] < 250) & (lum >= 24)
	out[near_body, 3] = 255
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
	## Only true near-bg fringe may be soft — never dark wood/gold body mass.
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
	## Feather a hard cell-top cut so a sliced lid/scroll does not read as a white bar.
	if arr.shape[0] > 4 and (alpha[0] > 200).sum() > 24:
		for y in range(0, 3):
			fade = float(40 + y * 55)
			row = alpha[y].astype(np.float32)
			hit = row > 40
			row[hit] = np.minimum(row[hit], fade)
			alpha[y] = row.astype(np.uint8)
		rgba[:, :, 3] = alpha
	return harden_chest_opacity(rgba)


def cell_top_clipped(arr: np.ndarray, threshold: int = 40) -> bool:
	"""True when the source cell itself shears opaque content at its top edge."""
	is_bg = bg_mask(arr)
	content = ~is_bg
	top_hits = int((content[0] | content[1]).sum())
	return top_hits >= threshold


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
	bx = xs[band]
	cx = float(np.median(bx))
	return cx, float(y_max)


def visual_center(rgba: np.ndarray) -> tuple[float, float] | None:
	"""Alpha-weighted center of the visible chest (not the transparent canvas)."""
	a = rgba[:, :, 3].astype(np.float64)
	if a.sum() <= 0:
		return None
	yy, xx = np.indices(a.shape)
	return float((xx * a).sum() / a.sum()), float((yy * a).sum() / a.sum())


def lower_body_width(rgba: np.ndarray, frac: float = 0.45) -> float | None:
	"""Width of the planted lower body (excludes most of the opening lid)."""
	alpha = rgba[:, :, 3]
	ys, xs = np.where(alpha > 40)
	if len(xs) == 0:
		return None
	y0, y1 = int(ys.min()), int(ys.max())
	cut = y1 - int((y1 - y0 + 1) * frac)
	mask = (alpha > 40) & (np.arange(alpha.shape[0])[:, None] >= cut)
	_bys, bxs = np.where(mask)
	if len(bxs) < 20:
		return None
	return float(bxs.max() - bxs.min() + 1)


def lock_to_anchor(
	rgba: np.ndarray, target_cx: float, target_y: float, target_visual_cx: float | None = None
) -> np.ndarray:
	"""Translate so foot Y matches and visual mass X matches the closed frame."""
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


def scale_about_foot(rgba: np.ndarray, scale: float, foot_x: float, foot_y: float) -> np.ndarray:
	"""Uniform scale about the planted foot — keeps base anchor stable."""
	if abs(scale - 1.0) < 0.004:
		return rgba
	## Clamp so we never invent large resize jumps between poses.
	scale = float(np.clip(scale, 0.97, 1.045))
	img = Image.fromarray(rgba, "RGBA")
	nw = max(1, int(round(img.width * scale)))
	nh = max(1, int(round(img.height * scale)))
	resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
	## Foot in resized space
	fx = foot_x * scale
	fy = foot_y * scale
	## Place so foot lands on (foot_x, foot_y) of the original canvas.
	canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
	paste_x = int(round(foot_x - fx))
	paste_y = int(round(foot_y - fy))
	canvas.paste(resized, (paste_x, paste_y), resized)
	## LANCZOS introduces soft fringe — re-harden body so beach never shows through.
	return harden_chest_opacity(np.array(canvas))


def normalize_body_scale(rgba: np.ndarray, target_width: float, foot_x: float, foot_y: float) -> np.ndarray:
	w = lower_body_width(rgba)
	if w is None or w < 8 or target_width < 8:
		return rgba
	return scale_about_foot(rgba, target_width / w, foot_x, foot_y)


def _alpha_over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
	out = dst.copy()
	a = src[:, :, 3:4].astype(np.float32) / 255.0
	out[:, :, :3] = (
		src[:, :, :3].astype(np.float32) * a + out[:, :, :3].astype(np.float32) * (1.0 - a)
	).astype(np.uint8)
	out[:, :, 3] = np.maximum(out[:, :, 3], src[:, :, 3])
	return out


def _shift_layer(layer: np.ndarray, dy: int) -> np.ndarray:
	"""Translate a transparent layer vertically inside the same canvas."""
	if dy == 0:
		return layer.copy()
	out = np.zeros_like(layer)
	h = layer.shape[0]
	if dy > 0:
		out[dy:] = layer[: h - dy]
	else:
		out[: h + dy] = layer[-dy:]
	return out


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


def _clean_scroll_donor_rgba() -> np.ndarray:
	"""Load the clean project scroll (no chest pixels). Prefer mini, then rolled."""
	candidates = [
		ROOT / "assets" / "art" / "scroll" / "scroll_mini.png",
		ROOT / "assets" / "art" / "scroll" / "scroll_rolled.png",
		ROOT / "assets" / "art" / "scroll" / "scroll_mini_unread.png",
	]
	for path in candidates:
		if path.exists():
			rgba = np.array(Image.open(path).convert("RGBA"))
			## Treat near-black as transparent so composites stay clean.
			lum = rgba[:, :, :3].astype(np.float32).mean(axis=2)
			alpha = rgba[:, :, 3].astype(np.float32)
			alpha[lum < 18] = 0
			rgba = rgba.copy()
			rgba[:, :, 3] = alpha.astype(np.uint8)
			if (rgba[:, :, 3] > 40).sum() > 200:
				return rgba
	raise RuntimeError("No clean scroll donor found under assets/art/scroll/")


def build_clean_scroll_layer(open_placed: np.ndarray) -> np.ndarray:
	"""Place a clean parchment-only scroll into the open chest cavity.

	Never copies chest gold/wood from the magical sheet. This is the hard
	guarantee that rising reward frames contain exactly one chest.
	"""
	ys, xs = np.where(open_placed[:, :, 3] > 40)
	if len(ys) == 0:
		return np.zeros_like(open_placed)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	## Target: scroll rests mostly behind the front rim; rise stages peek then clear.
	rim_y = int(chest_top + chest_h * 0.50)
	donor = _clean_scroll_donor_rgba()
	## Fit scroll width to ~58% of lower-body width so it reads inside the cavity.
	body_w = lower_body_width(open_placed) or 180.0
	target_w = max(72, int(round(body_w * 0.58)))
	scale = target_w / float(donor.shape[1])
	target_h = max(18, int(round(donor.shape[0] * scale)))
	scaled = Image.fromarray(donor, "RGBA").resize((target_w, target_h), Image.Resampling.LANCZOS)
	scroll = np.array(scaled)
	## Rest pose: majority of scroll body below the rim (occluded by front lip).
	dst_x = int(round(cx - target_w * 0.5))
	dst_y = int(round(rim_y - target_h * 0.18))
	layer = np.zeros_like(open_placed)
	h, w = layer.shape[:2]
	src_x0 = src_y0 = 0
	src_x1, src_y1 = target_w, target_h
	if dst_x < 0:
		src_x0 = -dst_x
		dst_x = 0
	if dst_y < 0:
		src_y0 = -dst_y
		dst_y = 0
	if dst_x + (src_x1 - src_x0) > w:
		src_x1 = src_x0 + (w - dst_x)
	if dst_y + (src_y1 - src_y0) > h:
		src_y1 = src_y0 + (h - dst_y)
	if src_x1 > src_x0 and src_y1 > src_y0:
		patch = scroll[src_y0:src_y1, src_x0:src_x1]
		## Gentle warm lift only — keep parchment readable as paper, not metal.
		warm = patch.copy()
		rgb = warm[:, :, :3].astype(np.float32)
		rgb[:, :, 0] = np.clip(rgb[:, :, 0] * 1.03 + 3, 0, 255)
		rgb[:, :, 1] = np.clip(rgb[:, :, 1] * 1.01 + 1, 0, 255)
		warm[:, :, :3] = rgb.astype(np.uint8)
		layer[dst_y : dst_y + patch.shape[0], dst_x : dst_x + patch.shape[1]] = warm
	## Keep donor alpha as-is (already parchment-only). Do not reclassify by hue —
	## spindle tips are legitimately gold and must remain.
	return layer


def extract_scroll_layer(open_placed: np.ndarray, scroll_placed: np.ndarray | None = None) -> np.ndarray:
	"""Build a parchment-only scroll layer. Ignores contaminated sheet diffs."""
	_ = scroll_placed  ## retained for call-site compat; never used for chest pixels
	return build_clean_scroll_layer(open_placed)


def extract_front_rim(open_placed: np.ndarray) -> np.ndarray:
	"""Thin front-lip occlusion only — never the full chest front/body."""
	a = open_placed[:, :, 3]
	ys, xs = np.where(a > 40)
	if len(ys) == 0:
		return np.zeros_like(open_placed)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	rim_y = int(chest_top + (chest_bot - chest_top) * 0.48)
	yy = np.arange(open_placed.shape[0])[:, None]
	xx = np.arange(open_placed.shape[1])[None, :]
	r = open_placed[:, :, 0].astype(np.float32)
	g = open_placed[:, :, 1].astype(np.float32)
	b = open_placed[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	## Narrow gold lip (+ tiny wood just under it). Exclude cavity glow + body.
	gold_lip = (
		(a > 60)
		& (yy >= rim_y - 1)
		& (yy <= rim_y + 12)
		& (np.abs(xx - cx) < 92)
		& (r > 120)
		& (g > 85)
		& ((r - b) > 30)
		& (lum < 205)
	)
	wood_lip = (
		(a > 60)
		& (yy >= rim_y + 6)
		& (yy <= rim_y + 16)
		& (np.abs(xx - cx) < 88)
		& (lum < 130)
		& (r > 40)
		& (r > b)
	)
	front_mask = gold_lip | wood_lip
	front = np.zeros_like(open_placed)
	front[front_mask] = open_placed[front_mask]
	return front


def compose_scroll_rise(open_placed: np.ndarray, scroll_layer: np.ndarray, rise_dy: int) -> np.ndarray:
	"""rise_dy < 0 lifts the scroll; front rim is re-applied so it stays behind the lip."""
	shifted = _shift_layer(scroll_layer, rise_dy)
	out = _alpha_over(open_placed, shifted)
	front = extract_front_rim(open_placed)
	out = _alpha_over(out, front)
	return out


def progressive_scroll_reveal(
	open_placed: np.ndarray, scroll_placed: np.ndarray, keep_below_y: int
) -> np.ndarray:
	"""Reveal scroll content only at y >= keep_behind so it rises from the cavity."""
	h = min(open_placed.shape[0], scroll_placed.shape[0])
	w = min(open_placed.shape[1], scroll_placed.shape[1])
	open_c = open_placed[:h, :w]
	scroll_c = scroll_placed[:h, :w]
	diff = np.abs(scroll_c[:, :, :3].astype(np.float32) - open_c[:, :, :3].astype(np.float32)).sum(axis=2)
	changed = (diff > 45) & (scroll_c[:, :, 3] > 40)
	ys, xs = np.where(open_c[:, :, 3] > 40)
	if len(ys) == 0:
		return open_placed.copy()
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	cavity_top = int(chest_top + (chest_bot - chest_top) * 0.12)
	cavity_bot = int(chest_top + (chest_bot - chest_top) * 0.78)
	yy = np.arange(h)[:, None]
	xx = np.arange(w)[None, :]
	in_cavity = (yy >= cavity_top) & (yy <= cavity_bot) & (np.abs(xx - cx) < w * 0.36)
	reveal = changed & in_cavity & (yy >= int(keep_below_y))

	scroll_layer = np.zeros_like(scroll_c)
	scroll_layer[reveal] = scroll_c[reveal]
	edge_y = int(keep_below_y)
	if 0 <= edge_y < h:
		edge = reveal[edge_y]
		if edge.any():
			scroll_layer[edge_y, edge, 3] = (
				scroll_layer[edge_y, edge, 3].astype(np.float32) * 0.55
			).astype(np.uint8)

	out = open_placed.copy()
	patch = np.zeros_like(open_placed)
	patch[:h, :w] = scroll_layer
	out = _alpha_over(out, patch)
	front = extract_front_rim(open_placed)
	out = _alpha_over(out, front)
	return out


def finalize_locked(
	placed: np.ndarray, target_cx: float, target_y: float, target_visual_cx: float
) -> np.ndarray:
	locked = lock_to_anchor(placed, target_cx, target_y, target_visual_cx)
	m2 = base_metrics(locked)
	if m2 is not None and abs(m2[1] - target_y) >= 1:
		locked = lock_to_anchor(locked, m2[0], target_y, None)
		locked = lock_to_anchor(locked, target_cx, target_y, target_visual_cx)
	return harden_chest_opacity(locked)


def process(path: Path, prefix: str, picks: list[int], sub: str, labels: list[str]) -> list[dict]:
	rgb = load_rgb(path)
	out_dir = OUT / sub
	out_dir.mkdir(parents=True, exist_ok=True)
	for p in out_dir.glob("*.png"):
		p.unlink()
	placed_list: list[tuple[np.ndarray, int, int]] = []
	for src in picks:
		cell = cell_at(rgb, src)
		if cell_top_clipped(cell, threshold=48):
			raise RuntimeError(
				f"Refusing damaged top-clipped source cell {sub} src={src} — pick a cleaner pose"
			)
		placed, _anchor, crop_h = place_aligned(cell)
		placed_list.append((placed, crop_h, src))
	anchor_m = base_metrics(placed_list[0][0])
	if anchor_m is None:
		raise RuntimeError(f"Could not find base anchor for {sub} closed frame")
	target_cx, target_y = anchor_m
	target_visual_cx = float(CANVAS_W) * 0.5
	target_body_w = lower_body_width(placed_list[0][0]) or 180.0
	print(
		f"{sub} lock foot=({target_cx:.1f},{target_y:.1f}) "
		f"body_w0={target_body_w:.1f} → visual_cx={target_visual_cx:.1f} "
		f"canvas={CANVAS_W}x{CANVAS_H}"
	)
	meta: list[dict] = []
	for seq, (placed, crop_h, src) in enumerate(placed_list):
		## Normalize planted body scale before final lock — prevents subtle growth.
		scaled = normalize_body_scale(placed, target_body_w, target_cx, target_y)
		locked = finalize_locked(scaled, target_cx, target_y, target_visual_cx)
		fname = f"{prefix}_{seq:02d}.png"
		Image.fromarray(locked, "RGBA").save(out_dir / fname)
		label = labels[seq] if seq < len(labels) else ""
		m = base_metrics(locked)
		vc = visual_center(locked)
		bw = lower_body_width(locked)
		top_hit = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		meta.append(
			{
				"file": fname,
				"src_index": src,
				"label": label,
				"crop_h": crop_h,
				"base_cx": m[0] if m else None,
				"base_y": m[1] if m else None,
				"visual_cx": vc[0] if vc else None,
				"visual_cy": vc[1] if vc else None,
				"lower_body_w": bw,
				"canvas": [CANVAS_W, CANVAS_H],
				"canvas_top_hits": top_hit,
			}
		)
		print(
			f"{sub}/{fname} src={src:02d} crop_h={crop_h} "
			f"body_w={None if bw is None else round(bw,1)} "
			f"vis_cx={None if vc is None else round(vc[0],1)} top0={top_hit} [{label}]"
		)
	(out_dir / "manifest.json").write_text(json.dumps(meta, indent=2))
	return meta


def process_scroll_with_rise(_magic_path: Path | None = None) -> list[dict]:
	"""Shared empty-sheet opening poses, then clean parchment scroll-rise stages.

	Opening uses the glowing (empty) sheet so empty + unread share identical chest
	geometry. Rise stages composite a chest-pixel-free scroll onto the fully-open
	empty pose — guaranteeing exactly one visible chest at every moment.
	"""
	_ = _magic_path  ## magical sheet retained in repo; not used for contaminated scroll extract
	rgb = load_rgb(GLOW_SHEET)
	out_dir = OUT / "scroll"
	out_dir.mkdir(parents=True, exist_ok=True)
	for p in out_dir.glob("*.png"):
		p.unlink()

	## Same clean glowing-sheet opening arc as empty — subsampled to 8 poses so
	## unread opening cadence matches empty until fully open, then diverges.
	open_picks = [0, 7, 9, 11, 13, 15, 16, 17]
	open_labels = [
		"closed",
		"crack",
		"early_open",
		"opening_more",
		"half_open",
		"three_quarter",
		"nearly_open",
		"open_ready",
	]
	## Progressive scroll rise: dy>0 lowers (behind rim); dy<0 lifts.
	## Final target ~55–70% of the rolled scroll body above the front rim.
	rise_stages = [
		(8, "scroll_peek"),  ## tiny crest just above / at the rim
		(-4, "scroll_partial"),
		(-16, "scroll_rising"),
		(-30, "scroll_halfway"),
		(-48, "scroll_fully"),  ## unmistakable reward — ~55–70%+ above rim
	]

	placed_open: list[tuple[np.ndarray, int, int, str]] = []
	for src, label in zip(open_picks, open_labels):
		cell = cell_at(rgb, src)
		if cell_top_clipped(cell, threshold=48):
			raise RuntimeError(f"Damaged shared open cell src={src}")
		placed, _a, crop_h = place_aligned(cell)
		placed_open.append((placed, crop_h, src, label))

	anchor_m = base_metrics(placed_open[0][0])
	if anchor_m is None:
		raise RuntimeError("Could not find scroll closed-frame base")
	target_cx, target_y = anchor_m
	target_visual_cx = float(CANVAS_W) * 0.5
	target_body_w = lower_body_width(placed_open[0][0]) or 180.0
	print(
		f"scroll lock foot=({target_cx:.1f},{target_y:.1f}) "
		f"body_w0={target_body_w:.1f} → visual_cx={target_visual_cx:.1f} "
		f"canvas={CANVAS_W}x{CANVAS_H} (shared empty sheet)"
	)

	norm_open: list[tuple[np.ndarray, int, int | str, str]] = []
	for placed, crop_h, src, label in placed_open:
		scaled = normalize_body_scale(placed, target_body_w, target_cx, target_y)
		norm_open.append((scaled, crop_h, src, label))

	open_ready_placed = finalize_locked(norm_open[-1][0], target_cx, target_y, target_visual_cx)
	## Clean parchment-only layer — never diff-extract from magical sheet.
	scroll_layer = build_clean_scroll_layer(open_ready_placed)
	front_rim = extract_front_rim(open_ready_placed)
	Image.fromarray(scroll_layer, "RGBA").save(ART / "scroll_rolled.png")
	Image.fromarray(front_rim, "RGBA").save(ART / "chest_front_rim.png")
	scroll_px = int((scroll_layer[:, :, 3] > 40).sum())
	print(f"wrote scroll_rolled.png + chest_front_rim.png (scroll_px={scroll_px})")
	if scroll_px < 400:
		raise RuntimeError(f"Clean scroll layer too sparse ({scroll_px} px)")

	## Sanity: reject a wide horizontal gold/wood BAR below the scroll (chest rim ghost).
	a = scroll_layer[:, :, 3]
	r = scroll_layer[:, :, 0].astype(np.float32)
	g = scroll_layer[:, :, 1].astype(np.float32)
	b = scroll_layer[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	ys, xs = np.where(a > 40)
	if len(ys) == 0:
		raise RuntimeError("Clean scroll layer empty after place")
	y0, y1 = int(ys.min()), int(ys.max())
	scroll_h = max(1, y1 - y0 + 1)
	below = (np.arange(a.shape[0])[:, None] > (y0 + int(scroll_h * 0.85))) & (a > 40)
	rimish = below & (
		((r > 140) & (g > 90) & ((r - b) > 40) & (lum < 210))
		| ((lum < 100) & (r > 35) & (r > b))
	)
	## A true chest rim ghost spans most of the scroll width as a flat bar.
	rim_rows = int((rimish.sum(axis=1) > int(target_body_w * 0.35)).sum())
	if rim_rows >= 3 or int(rimish.sum()) > 280:
		raise RuntimeError(
			f"Scroll layer still has chest-rim ghost (rim_px={int(rimish.sum())} rim_rows={rim_rows})"
		)

	frames: list[tuple[np.ndarray, int, int | str, str]] = []
	for placed, crop_h, src, label in norm_open:
		frames.append((placed, crop_h, src, label))
	for rise_dy, label in rise_stages:
		synth = compose_scroll_rise(open_ready_placed, scroll_layer, rise_dy)
		frames.append((synth, 0, f"rise_dy{rise_dy}", label))

	meta: list[dict] = []
	for seq, (placed, crop_h, src, label) in enumerate(frames):
		locked = finalize_locked(placed, target_cx, target_y, target_visual_cx)
		top_hit = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		if top_hit > 0:
			locked = _shift_layer(locked, 2)
			locked = finalize_locked(locked, target_cx, target_y, target_visual_cx)
			top_hit = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		fname = f"scroll_{seq:02d}.png"
		Image.fromarray(locked, "RGBA").save(out_dir / fname)
		m = base_metrics(locked)
		vc = visual_center(locked)
		bw = lower_body_width(locked)
		meta.append(
			{
				"file": fname,
				"src_index": src,
				"label": label,
				"crop_h": crop_h,
				"base_cx": m[0] if m else None,
				"base_y": m[1] if m else None,
				"visual_cx": vc[0] if vc else None,
				"visual_cy": vc[1] if vc else None,
				"lower_body_w": bw,
				"canvas": [CANVAS_W, CANVAS_H],
				"canvas_top_hits": top_hit,
			}
		)
		print(
			f"scroll/{fname} src={src} crop_h={crop_h} "
			f"body_w={None if bw is None else round(bw,1)} "
			f"vis_cx={None if vc is None else round(vc[0],1)} top0={top_hit} [{label}]"
		)
	(out_dir / "manifest.json").write_text(json.dumps(meta, indent=2))
	return meta


def main() -> None:
	## Denser clean opening poses. Skip near-duplicate closed wobble 1–5.
	## Exclude glow src 18–23 — cell tops physically shear the lid tip.
	empty_picks = [0, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
	empty_labels = [
		"closed",
		"pre_crack",
		"crack",
		"early_glow",
		"early_open",
		"opening",
		"opening_more",
		"half_open",
		"more_open",
		"near_full",
		"three_quarter",
		"nearly_open",
		"fully_open",
	]
	print("EMPTY")
	process(GLOW_SHEET, "empty", empty_picks, "empty", empty_labels)
	print("SCROLL (shared empty opening + clean parchment rise)")
	process_scroll_with_rise(MAGIC_SHEET)


if __name__ == "__main__":
	main()
