#!/usr/bin/env python3
"""Prepare aligned transparent chest animation frames from authoring sprite sheets.

Source sheets (do not delete):
  assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png
  assets/chest/animation/magical_treasure_chest_animation_sheet.png

Outputs:
  assets/art/chest/frames/empty/*.png
  assets/art/chest/frames/scroll/*.png

v40 polish:
  - exclude source poses whose cell top already shears the lid/scroll tip
  - denser clean intermediate opening poses
  - synthesize progressive scroll-rise stages (separate scroll layer + front rim)
    inside the production canvas headroom so tops stay unclipped
  - keep absolute foot lock (BASE_Y) so on-screen chest plant does not drift
  - taller transparent headroom above the plant without moving BASE_Y
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "chest" / "frames"
GLOW_SHEET = ROOT / "assets" / "chest" / "animation" / "glowing_treasure_chest_opening_sprite_sheet.png"
MAGIC_SHEET = ROOT / "assets" / "chest" / "animation" / "magical_treasure_chest_animation_sheet.png"

## Extra transparent rows above the planted chest; foot Y stays absolute so the
## chest does not drift when headroom grows.
CANVAS_W = 384
CANVAS_H = 496
BASE_X = CANVAS_W // 2
BASE_Y = 367  ## absolute plant row — unchanged from v39 so centering holds


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


def to_rgba(arr: np.ndarray) -> np.ndarray:
	is_bg = bg_mask(arr)
	rgba = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.uint8)
	rgba[:, :, :3] = arr
	alpha = np.where(is_bg, 0, 255).astype(np.uint8)
	lum = arr.astype(np.float32).mean(axis=2)
	corners = np.stack([arr[1, 1], arr[1, -2], arr[-2, 1], arr[-2, -2]]).astype(np.float32)
	bg = corners.mean(axis=0)
	diff = np.abs(arr.astype(np.float32) - bg).sum(axis=2)
	soft = (~is_bg) & (diff < 70) & (lum < 55)
	alpha = alpha.copy()
	alpha[soft] = 140
	near_black = (lum < 22) & (alpha > 0) & (diff < 55)
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
	return rgba


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


def progressive_scroll_reveal(
	open_placed: np.ndarray, scroll_placed: np.ndarray, keep_below_y: int
) -> np.ndarray:
	"""Reveal scroll content only at y >= keep_below_y so it rises from the cavity.

	Uses pixel differences vs the open chest, restricted to the cavity band, then
	re-applies a front-rim occlusion so the roll stays behind the front lip early on.
	"""
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
	## Feather the reveal cut line.
	edge_y = int(keep_below_y)
	if 0 <= edge_y < h:
		edge = reveal[edge_y]
		if edge.any():
			scroll_layer[edge_y, edge, 3] = (
				scroll_layer[edge_y, edge, 3].astype(np.float32) * 0.55
			).astype(np.uint8)

	cavity_y = int(chest_top + (chest_bot - chest_top) * 0.48)
	band = np.zeros(h, dtype=bool)
	band[cavity_y:] = True
	lum_c = open_c[:, :, :3].astype(np.float32).mean(axis=2)
	front_mask = (open_c[:, :, 3] > 40) & band[:, None] & (~reveal)
	lip = (np.abs(np.arange(h) - cavity_y) <= 10)[:, None] & (open_c[:, :, 3] > 80) & (lum_c < 150)
	front_mask = front_mask | lip
	front_mask[: int(chest_top + (chest_bot - chest_top) * 0.38), :] = False
	front = np.zeros_like(open_c)
	front[front_mask] = open_c[front_mask]

	out = open_placed.copy()
	patch = np.zeros_like(open_placed)
	patch[:h, :w] = scroll_layer
	out = _alpha_over(out, patch)
	front_full = np.zeros_like(open_placed)
	front_full[:h, :w] = front
	out = _alpha_over(out, front_full)
	return out


def synthesize_scroll_rise(
	open_placed: np.ndarray, scroll_src_placed: np.ndarray, rise_dy: int
) -> np.ndarray:
	"""rise_dy>0 hides more of the scroll (higher keep_below); <=0 reveals more."""
	ys, _ = np.where(open_placed[:, :, 3] > 40)
	if len(ys) == 0:
		return open_placed.copy()
	chest_top, chest_bot = int(ys.min()), int(ys.max())
	cavity_mid = int(chest_top + (chest_bot - chest_top) * 0.50)
	keep_below = int(np.clip(cavity_mid + rise_dy, chest_top + 4, chest_bot - 8))
	return progressive_scroll_reveal(open_placed, scroll_src_placed, keep_below)

def finalize_locked(
	placed: np.ndarray, target_cx: float, target_y: float, target_visual_cx: float
) -> np.ndarray:
	locked = lock_to_anchor(placed, target_cx, target_y, target_visual_cx)
	m2 = base_metrics(locked)
	if m2 is not None and abs(m2[1] - target_y) >= 1:
		locked = lock_to_anchor(locked, m2[0], target_y, None)
		locked = lock_to_anchor(locked, target_cx, target_y, target_visual_cx)
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
	vc0 = visual_center(placed_list[0][0])
	target_visual_cx = float(CANVAS_W) * 0.5
	print(
		f"{sub} lock foot=({target_cx:.1f},{target_y:.1f}) "
		f"visual0={None if vc0 is None else (round(vc0[0],1), round(vc0[1],1))} "
		f"→ visual_cx={target_visual_cx:.1f} canvas={CANVAS_W}x{CANVAS_H}"
	)
	meta: list[dict] = []
	for seq, (placed, crop_h, src) in enumerate(placed_list):
		locked = finalize_locked(placed, target_cx, target_y, target_visual_cx)
		fname = f"{prefix}_{seq:02d}.png"
		Image.fromarray(locked, "RGBA").save(out_dir / fname)
		label = labels[seq] if seq < len(labels) else ""
		m = base_metrics(locked)
		vc = visual_center(locked)
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
				"canvas": [CANVAS_W, CANVAS_H],
				"canvas_top_hits": top_hit,
			}
		)
		print(
			f"{sub}/{fname} src={src:02d} crop_h={crop_h} "
			f"vis_cx={None if vc is None else round(vc[0],1)} top0={top_hit} [{label}]"
		)
	(out_dir / "manifest.json").write_text(json.dumps(meta, indent=2))
	return meta


def process_scroll_with_rise(path: Path) -> list[dict]:
	"""Opening poses from the sheet, then synthesized scroll-rise stages."""
	rgb = load_rgb(path)
	out_dir = OUT / "scroll"
	out_dir.mkdir(parents=True, exist_ok=True)
	for p in out_dir.glob("*.png"):
		p.unlink()

	## Clean opening / pre-scroll poses only (skip top-sheared 16–23 and bleedy 10).
	open_picks = [0, 3, 5, 7, 8, 9, 11, 12]
	open_labels = [
		"closed",
		"pre_crack",
		"crack",
		"early_glow",
		"early_open",
		"opening",
		"opening_more",
		"open_ready",
	]
	## Early peeks synthesized from clean natural src 13 (smaller roll), then natural 13–15.
	## keep_below_y on production canvas; higher = more hidden behind the front rim.
	## Exclude magical src 16–23 — cell tops shear the scroll/seal.
	peek_stages = [
		(300, "scroll_peek"),
		(285, "scroll_partial"),
	]
	natural_scroll = [
		(13, "scroll_rising"),
		(14, "scroll_halfway"),
		(15, "scroll_fully"),
	]

	placed_open: list[tuple[np.ndarray, int, int, str]] = []
	for src, label in zip(open_picks, open_labels):
		cell = cell_at(rgb, src)
		if cell_top_clipped(cell, threshold=48):
			raise RuntimeError(f"Damaged scroll open cell src={src}")
		placed, _a, crop_h = place_aligned(cell)
		placed_open.append((placed, crop_h, src, label))

	anchor_m = base_metrics(placed_open[0][0])
	if anchor_m is None:
		raise RuntimeError("Could not find scroll closed-frame base")
	target_cx, target_y = anchor_m
	target_visual_cx = float(CANVAS_W) * 0.5
	print(
		f"scroll lock foot=({target_cx:.1f},{target_y:.1f}) "
		f"→ visual_cx={target_visual_cx:.1f} canvas={CANVAS_W}x{CANVAS_H}"
	)

	open_ready_placed = placed_open[-1][0]
	## Donor for early peeks: clean src 13 (scroll still low / partial).
	peek_donor_cell = cell_at(rgb, 13)
	if cell_top_clipped(peek_donor_cell, threshold=48):
		raise RuntimeError("Scroll peek donor src=13 is top-clipped")
	peek_donor_placed, _a, _ch = place_aligned(peek_donor_cell)
	## Full reveal donor kept for documentation / future stages.
	scroll_donor_placed = peek_donor_placed

	frames: list[tuple[np.ndarray, int, int | str, str]] = []
	for placed, crop_h, src, label in placed_open:
		frames.append((placed, crop_h, src, label))
	for keep_y, label in peek_stages:
		synth = progressive_scroll_reveal(open_ready_placed, peek_donor_placed, keep_y)
		frames.append((synth, 0, f"peek13_y{keep_y}", label))
	for src, label in natural_scroll:
		cell = cell_at(rgb, src)
		if cell_top_clipped(cell, threshold=48):
			raise RuntimeError(f"Damaged natural scroll cell src={src}")
		placed, _a, crop_h = place_aligned(cell)
		frames.append((placed, crop_h, src, label))

	meta: list[dict] = []
	for seq, (placed, crop_h, src, label) in enumerate(frames):
		locked = finalize_locked(placed, target_cx, target_y, target_visual_cx)
		## Guard: nothing opaque on the top canvas edge.
		top_hit = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		if top_hit > 0:
			## Nudge content down 2px if a synth rise grazed the top (keep foot after).
			locked = _shift_layer(locked, 2)
			locked = finalize_locked(locked, target_cx, target_y, target_visual_cx)
			top_hit = int((locked[0, :, 3] > 40).sum() + (locked[1, :, 3] > 40).sum())
		fname = f"scroll_{seq:02d}.png"
		Image.fromarray(locked, "RGBA").save(out_dir / fname)
		m = base_metrics(locked)
		vc = visual_center(locked)
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
				"canvas": [CANVAS_W, CANVAS_H],
				"canvas_top_hits": top_hit,
			}
		)
		print(
			f"scroll/{fname} src={src} crop_h={crop_h} "
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
	print("SCROLL")
	process_scroll_with_rise(MAGIC_SHEET)


if __name__ == "__main__":
	main()
