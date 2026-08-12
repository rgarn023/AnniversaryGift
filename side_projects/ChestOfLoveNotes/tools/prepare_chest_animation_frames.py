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

v44 polish:
  - empty + unread share glowing-sheet opening geometry (one chest family)
  - scroll rise uses high-res scroll_rolled parchment donor — never magical-sheet chest pixels
  - runtime prefers separate scroll + rim layers over baked late frames
  - normalize body exposure across opening poses
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
	near_body = _dilate(opaque, 2) & present & (out[:, :, 3] < 250) & (lum >= 18)
	out[near_body, 3] = 255
	## Any mid-alpha pixel with warm wood/gold hue must be fully opaque.
	warmish = present & (out[:, :, 3] < 250) & (r > 30) & (g > 20) & (lum < 210) & (
		(r > b) | ((r - b) > 10)
	)
	out[warmish, 3] = 255
	## Dense cavity fill near opaque neighbors (prevents beach bleed through panels).
	opaque = out[:, :, 3] >= 250
	fill = _dilate(opaque, 1) & present & (out[:, :, 3] >= 40) & (out[:, :, 3] < 250) & (lum >= 16)
	out[fill, 3] = 255
	return out




def fill_internal_holes(rgba: np.ndarray) -> np.ndarray:
	"""Fill tiny transparent holes in the planted BODY only (never the open cavity)."""
	a = rgba[:, :, 3]
	present = a > 40
	ys, xs = np.where(present)
	if len(ys) == 0:
		return rgba
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	## Only consider the lower planted body band — lid cavity stays open/glowing.
	body_cut = int(chest_top + (chest_bot - chest_top) * 0.52)
	h, w = a.shape
	exterior = np.zeros_like(present, dtype=bool)
	from collections import deque
	q = deque()
	for x in range(w):
		if not present[0, x]:
			exterior[0, x] = True
			q.append((0, x))
		if not present[h - 1, x]:
			exterior[h - 1, x] = True
			q.append((h - 1, x))
	for y in range(h):
		if not present[y, 0]:
			exterior[y, 0] = True
			q.append((y, 0))
		if not present[y, w - 1]:
			exterior[y, w - 1] = True
			q.append((y, w - 1))
	while q:
		y, x = q.popleft()
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			ny, nx = y + dy, x + dx
			if 0 <= ny < h and 0 <= nx < w and (not exterior[ny, nx]) and (not present[ny, nx]):
				exterior[ny, nx] = True
				q.append((ny, nx))
	holes = (~present) & (~exterior)
	## Restrict to lower body + small components only.
	yy = np.arange(h)[:, None]
	holes = holes & (yy >= body_cut)
	if not holes.any():
		return rgba
	## Drop large hole components (open cavities) — keep speckles/cracks.
	from numpy.lib.stride_tricks import as_strided  # noqa: keep import light
	visited = np.zeros_like(holes, dtype=bool)
	out = rgba.copy()
	opaque = a >= 200
	hys, hxs = np.where(holes)
	# component sizes via flood
	for y0, x0 in zip(hys, hxs):
		if visited[y0, x0]:
			continue
		comp = []
		stack = [(y0, x0)]
		visited[y0, x0] = True
		while stack:
			y, x = stack.pop()
			comp.append((y, x))
			for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				ny, nx = y + dy, x + dx
				if 0 <= ny < h and 0 <= nx < w and holes[ny, nx] and not visited[ny, nx]:
					visited[ny, nx] = True
					stack.append((ny, nx))
		if len(comp) > 120:
			continue  ## likely cavity / intentional void
		for y, x in comp:
			filled = False
			for rad in range(1, 6):
				ya, yb = max(0, y - rad), min(h, y + rad + 1)
				xa, xb = max(0, x - rad), min(w, x + rad + 1)
				region = opaque[ya:yb, xa:xb]
				if region.any():
					cols = rgba[ya:yb, xa:xb][region]
					out[y, x, :3] = np.median(cols[:, :3], axis=0).astype(np.uint8)
					out[y, x, 3] = 255
					filled = True
					break
			if not filled:
				out[y, x] = (70, 45, 28, 255)
	return out


def normalize_body_exposure(rgba: np.ndarray, target_lum: float) -> np.ndarray:
	"""Match opaque wood/gold body luminance to the closed reference pose."""
	out = rgba.copy()
	a = out[:, :, 3].astype(np.float32)
	rgb = out[:, :, :3].astype(np.float32)
	lum = rgb.mean(axis=2)
	present = a > 40
	r = rgb[:, :, 0]
	g = rgb[:, :, 1]
	b = rgb[:, :, 2]
	wood = present & (lum < 175) & (r > 35) & (r > b) & (g > b * 0.55)
	gold = present & (lum >= 55) & (lum < 235) & (r > 100) & (g > 65) & ((r - b) > 28)
	body = wood | gold
	if body.sum() < 80 or target_lum <= 1:
		return harden_chest_opacity(out)
	cur = float(lum[body].mean())
	if cur <= 1:
		return harden_chest_opacity(out)
	scale = float(np.clip(target_lum / cur, 0.92, 1.08))
	if abs(scale - 1.0) < 0.008:
		return harden_chest_opacity(out)
	rgb[body] = np.clip(rgb[body] * scale, 0, 255)
	out[:, :, :3] = rgb.astype(np.uint8)
	return harden_chest_opacity(out)


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
	"""Load the clean project scroll (no chest pixels). Prefer high-res rolled art."""
	candidates = [
		## Prefer native high-res rolled parchment — never upscale tiny mini as primary.
		ROOT / "assets" / "art" / "scroll" / "scroll_rolled.png",
		ROOT / "assets" / "art" / "scroll" / "scroll_mini_unread.png",
		ROOT / "assets" / "art" / "scroll" / "scroll_mini.png",
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

	Builds a thicker rolled reward scroll from high-res top/bottom rollers +
	rolled parchment — never magical-sheet chest pixels. Guarantees one chest.
	"""
	ys, xs = np.where(open_placed[:, :, 3] > 40)
	if len(ys) == 0:
		return np.zeros_like(open_placed)
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cx = float(np.median(xs))
	chest_h = max(1, chest_bot - chest_top)
	rim_y = int(chest_top + chest_h * 0.50)
	body_w = lower_body_width(open_placed) or 180.0
	target_w = max(96, int(round(body_w * 0.66)))

	rolled_path = ROOT / "assets" / "art" / "scroll" / "scroll_rolled.png"
	top_path = ROOT / "assets" / "art" / "scroll" / "scroll_top_roller.png"
	bot_path = ROOT / "assets" / "art" / "scroll" / "scroll_bottom_roller.png"
	if not rolled_path.exists():
		return _build_scroll_from_donor_fallback(open_placed, cx, rim_y, target_w)

	rolled = np.array(Image.open(rolled_path).convert("RGBA"))
	## Strip near-black matte.
	for arr in (rolled,):
		lum = arr[:, :, :3].astype(np.float32).mean(axis=2)
		a = arr[:, :, 3].astype(np.float32)
		a[lum < 14] = 0
		arr[:, :, 3] = a.astype(np.uint8)

	scale = target_w / float(max(rolled.shape[1], 1))
	rw = target_w
	rh = max(28, int(round(rolled.shape[0] * scale)))
	filt = Image.Resampling.LANCZOS if scale >= 1.0 else Image.Resampling.BICUBIC
	rolled_r = np.array(Image.fromarray(rolled, "RGBA").resize((rw, rh), filt))

	parts = [rolled_r]
	extra_h = rh
	if top_path.exists() and bot_path.exists():
		top = np.array(Image.open(top_path).convert("RGBA"))
		bot = np.array(Image.open(bot_path).convert("RGBA"))
		for arr in (top, bot):
			lum = arr[:, :, :3].astype(np.float32).mean(axis=2)
			a = arr[:, :, 3].astype(np.float32)
			a[lum < 14] = 0
			arr[:, :, 3] = a.astype(np.uint8)
		th = max(10, int(round(top.shape[0] * scale * 0.85)))
		bh = max(12, int(round(bot.shape[0] * scale * 0.85)))
		top_r = np.array(Image.fromarray(top, "RGBA").resize((rw, th), filt))
		bot_r = np.array(Image.fromarray(bot, "RGBA").resize((rw, bh), filt))
		## Stack rollers + body into one tall rolled bundle (still parchment-only).
		bundle_h = th + rh + bh - 8
		bundle = np.zeros((bundle_h, rw, 4), dtype=np.uint8)
		def _paste(dst, src, y0):
			y1 = min(dst.shape[0], y0 + src.shape[0])
			h = y1 - y0
			if h <= 0:
				return
			patch = src[:h]
			a = patch[:, :, 3:4].astype(np.float32) / 255.0
			region = dst[y0:y1].astype(np.float32)
			region[:, :, :3] = patch[:, :, :3].astype(np.float32) * a + region[:, :, :3] * (1 - a)
			region[:, :, 3] = np.maximum(region[:, :, 3], patch[:, :, 3].astype(np.float32))
			dst[y0:y1] = region.astype(np.uint8)
		_paste(bundle, top_r, 0)
		_paste(bundle, rolled_r, max(0, th - 4))
		_paste(bundle, bot_r, max(0, th + rh - 8))
		scroll = bundle
		target_h = bundle.shape[0]
	else:
		scroll = rolled_r
		target_h = rh

	## Warm parchment lift — keep paper readable.
	warm = scroll.copy()
	rgb = warm[:, :, :3].astype(np.float32)
	rgb[:, :, 0] = np.clip(rgb[:, :, 0] * 1.02 + 2, 0, 255)
	rgb[:, :, 1] = np.clip(rgb[:, :, 1] * 1.01 + 1, 0, 255)
	warm[:, :, :3] = rgb.astype(np.uint8)
	scroll = warm

	dst_x = int(round(cx - target_w * 0.5))
	## Rest: majority below rim so front lip occludes the lower scroll.
	dst_y = int(round(rim_y - target_h * 0.30))
	layer = np.zeros_like(open_placed)
	h, w = layer.shape[:2]
	src_x0 = src_y0 = 0
	src_x1, src_y1 = scroll.shape[1], scroll.shape[0]
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
		layer[dst_y : dst_y + patch.shape[0], dst_x : dst_x + patch.shape[1]] = patch
	return layer


def _build_scroll_from_donor_fallback(
	open_placed: np.ndarray, cx: float, rim_y: int, target_w: int
) -> np.ndarray:
	donor = _clean_scroll_donor_rgba()
	scale = target_w / float(max(donor.shape[1], 1))
	target_h = max(28, int(round(donor.shape[0] * scale)))
	filt = Image.Resampling.LANCZOS if scale >= 1.0 else Image.Resampling.BICUBIC
	scroll = np.array(Image.fromarray(donor, "RGBA").resize((target_w, target_h), filt))
	dst_x = int(round(cx - target_w * 0.5))
	dst_y = int(round(rim_y - target_h * 0.28))
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
		layer[dst_y : dst_y + patch.shape[0], dst_x : dst_x + patch.shape[1]] = patch
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
	placed: np.ndarray,
	target_cx: float,
	target_y: float,
	target_visual_cx: float,
	target_body_lum: float | None = None,
) -> np.ndarray:
	locked = lock_to_anchor(placed, target_cx, target_y, target_visual_cx)
	m2 = base_metrics(locked)
	if m2 is not None and abs(m2[1] - target_y) >= 1:
		locked = lock_to_anchor(locked, m2[0], target_y, None)
		locked = lock_to_anchor(locked, target_cx, target_y, target_visual_cx)
	if target_body_lum is not None:
		locked = normalize_body_exposure(locked, target_body_lum)
	locked = harden_chest_opacity(locked)
	## Final pass: no mid-alpha wood/gold anywhere on the planted chest.
	a = locked[:, :, 3]
	r = locked[:, :, 0].astype(np.float32)
	g = locked[:, :, 1].astype(np.float32)
	b = locked[:, :, 2].astype(np.float32)
	lum = (r + g + b) / 3.0
	mid = (a > 24) & (a < 250)
	warm = mid & (r > 28) & (lum < 220) & ((r > b * 0.9) | ((r - b) > 8))
	locked[warm, 3] = 255
	## Promote near-opaque fringe beside solid mass (kills beach bleed-through).
	opaque = locked[:, :, 3] >= 250
	present = locked[:, :, 3] > 30
	near = _dilate(opaque, 2) & present & (locked[:, :, 3] < 250)
	locked[near, 3] = 255
	locked = fill_internal_holes(locked)
	return locked


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
	ref0 = placed_list[0][0]
	a0 = ref0[:, :, 3] > 40
	lum0 = ref0[:, :, :3].astype(np.float32).mean(axis=2)
	target_body_lum = float(lum0[a0].mean()) if a0.any() else 70.0
	print(
		f"{sub} lock foot=({target_cx:.1f},{target_y:.1f}) "
		f"body_w0={target_body_w:.1f} lum0={target_body_lum:.1f} → visual_cx={target_visual_cx:.1f} "
		f"canvas={CANVAS_W}x{CANVAS_H}"
	)
	meta: list[dict] = []
	for seq, (placed, crop_h, src) in enumerate(placed_list):
		## Normalize planted body scale before final lock — prevents subtle growth.
		scaled = normalize_body_scale(placed, target_body_w, target_cx, target_y)
		locked = finalize_locked(scaled, target_cx, target_y, target_visual_cx, target_body_lum)
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
		(10, "scroll_peek"),  ## tiny crest just above / at the rim
		(-6, "scroll_partial"),  ## ~25%
		(-28, "scroll_rising"),  ## ~50%
		(-48, "scroll_halfway"),  ## ~60–70%
		(-78, "scroll_fully"),  ## clear reward pose — rises farther than v43
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
	ref0 = placed_open[0][0]
	a0 = ref0[:, :, 3] > 40
	lum0 = ref0[:, :, :3].astype(np.float32).mean(axis=2)
	target_body_lum = float(lum0[a0].mean()) if a0.any() else 70.0
	print(
		f"scroll lock foot=({target_cx:.1f},{target_y:.1f}) "
		f"body_w0={target_body_w:.1f} lum0={target_body_lum:.1f} → visual_cx={target_visual_cx:.1f} "
		f"canvas={CANVAS_W}x{CANVAS_H} (shared empty sheet)"
	)

	norm_open: list[tuple[np.ndarray, int, int | str, str]] = []
	for placed, crop_h, src, label in placed_open:
		scaled = normalize_body_scale(placed, target_body_w, target_cx, target_y)
		norm_open.append((scaled, crop_h, src, label))

	open_ready_placed = finalize_locked(
		norm_open[-1][0], target_cx, target_y, target_visual_cx, target_body_lum
	)
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
	## A true chest rim ghost spans wider than the parchment itself as a flat bar.
	## Roller gold tips are legitimate and must not trip this guard.
	scroll_w = int(xs.max() - xs.min() + 1)
	rim_rows = int((rimish.sum(axis=1) > int(max(scroll_w * 1.15, target_body_w * 0.42))).sum())
	if rim_rows >= 4 and int(rimish.sum()) > 600:
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
		locked = finalize_locked(placed, target_cx, target_y, target_visual_cx, target_body_lum)
		top_hit = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		if top_hit > 0:
			locked = _shift_layer(locked, 2)
			locked = finalize_locked(locked, target_cx, target_y, target_visual_cx, target_body_lum)
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
