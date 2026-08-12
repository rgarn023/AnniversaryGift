#!/usr/bin/env python3
"""Prepare aligned transparent chest animation frames from authoring sprite sheets.

Source sheets (do not delete):
  assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png
  assets/chest/animation/magical_treasure_chest_animation_sheet.png

Outputs:
  assets/art/chest/frames/empty/*.png
  assets/art/chest/frames/scroll/*.png
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

CANVAS = 384
BASE_X = CANVAS // 2
BASE_Y = int(CANVAS * 0.78)


def load_rgb(path: Path) -> np.ndarray:
	return np.array(Image.open(path).convert("RGB"))


def cell_at(rgb: np.ndarray, index: int, cols: int = 6, rows: int = 4) -> np.ndarray:
	h, w, _ = rgb.shape
	cw, ch = w // cols, h // rows
	r, c = divmod(index, cols)
	return rgb[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw].copy()


def bg_mask(arr: np.ndarray) -> np.ndarray:
	lum = arr.astype(np.float32).mean(axis=2)
	corners = np.stack([arr[1, 1], arr[1, -2], arr[-2, 1], arr[-2, -2]]).astype(np.float32)
	bg = corners.mean(axis=0)
	diff = np.abs(arr.astype(np.float32) - bg).sum(axis=2)
	return (lum < 28) | (diff < 38)


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
	if crop_h == h:
		for y in range(h - 16, h - 6):
			if energy[y] < 25 and energy[y + 1 :].mean() > 30 and energy[:y].sum() > 1000:
				crop_h = y
				break
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
	alpha[soft] = 150
	rgba[:, :, 3] = alpha
	return rgba


def place_aligned(arr: np.ndarray) -> tuple[np.ndarray, tuple[float, float] | None, int]:
	cropped, crop_h = crop_bleed(arr)
	anchor = find_base(cropped)
	rgba = to_rgba(cropped)
	out = np.zeros((CANVAS, CANVAS, 4), dtype=np.uint8)
	if anchor is None:
		x0 = (CANVAS - cropped.shape[1]) // 2
		y0 = (CANVAS - cropped.shape[0]) // 2
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
	if dst_x0 + (src_x1 - src_x0) > CANVAS:
		src_x1 = src_x0 + (CANVAS - dst_x0)
	if dst_y0 + (src_y1 - src_y0) > CANVAS:
		src_y1 = src_y0 + (CANVAS - dst_y0)
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


def lock_to_anchor(rgba: np.ndarray, target_cx: float, target_y: float) -> np.ndarray:
	"""Translate so the base foot center matches the sequence's closed frame."""
	m = base_metrics(rgba)
	if m is None:
		return rgba
	cx, y = m
	dx = int(round(target_cx - cx))
	dy = int(round(target_y - y))
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


def process(path: Path, prefix: str, picks: list[int], sub: str, labels: list[str]) -> list[dict]:
	rgb = load_rgb(path)
	out_dir = OUT / sub
	out_dir.mkdir(parents=True, exist_ok=True)
	for p in out_dir.glob("*.png"):
		p.unlink()
	placed_list: list[tuple[np.ndarray, int, int]] = []
	for src in picks:
		placed, _anchor, crop_h = place_aligned(cell_at(rgb, src))
		placed_list.append((placed, crop_h, src))
	anchor_m = base_metrics(placed_list[0][0])
	if anchor_m is None:
		raise RuntimeError(f"Could not find base anchor for {sub} closed frame")
	target_cx, target_y = anchor_m
	print(f"{sub} lock target cx={target_cx:.1f} y={target_y:.1f}")
	meta: list[dict] = []
	for seq, (placed, crop_h, src) in enumerate(placed_list):
		locked = lock_to_anchor(placed, target_cx, target_y)
		fname = f"{prefix}_{seq:02d}.png"
		Image.fromarray(locked, "RGBA").save(out_dir / fname)
		label = labels[seq] if seq < len(labels) else ""
		m = base_metrics(locked)
		meta.append(
			{
				"file": fname,
				"src_index": src,
				"label": label,
				"crop_h": crop_h,
				"base_cx": m[0] if m else None,
				"base_y": m[1] if m else None,
			}
		)
		print(f"{sub}/{fname} src={src:02d} crop_h={crop_h} [{label}]")
	(out_dir / "manifest.json").write_text(json.dumps(meta, indent=2))
	return meta


def main() -> None:
	empty_picks = [0, 7, 9, 11, 13, 15, 17, 19, 21, 23]
	empty_labels = [
		"closed",
		"crack",
		"early_open",
		"opening",
		"half_open",
		"more_open",
		"near_full",
		"fully_open",
		"open_glow",
		"open_peak",
	]
	scroll_picks = [0, 7, 9, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22]
	scroll_labels = [
		"closed",
		"crack",
		"early_open",
		"opening",
		"open_ready",
		"scroll_peek",
		"scroll_rising",
		"scroll_mid",
		"scroll_high",
		"scroll_higher",
		"scroll_full",
		"scroll_present",
		"scroll_complete",
	]
	print("EMPTY")
	process(GLOW_SHEET, "empty", empty_picks, "empty", empty_labels)
	print("SCROLL")
	process(MAGIC_SHEET, "scroll", scroll_picks, "scroll", scroll_labels)


if __name__ == "__main__":
	main()
