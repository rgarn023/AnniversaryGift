#!/usr/bin/env python3
"""Generate the default twilight beach/ocean Chest environment raster.

Output:
  assets/art/background/environments/default_beach.png

Original in-project art (not a copy of any copyrighted game background).
Ships locally with the APK — no remote URL dependency.

v43: stylized-realistic twilight beach with textured sand, irregular shoreline,
calm ocean detail, soft horizon, and romantic sunset sky — not flat color bands.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "background" / "environments" / "default_beach.png"

## Logical mobile aspect (~9:19.5) at a comfortable mobile texture size.
W, H = 720, 1280


def lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


def lerp_color(c0, c1, t: float):
	t = min(max(t, 0.0), 1.0)
	return tuple(int(round(lerp(float(c0[i]), float(c1[i]), t))) for i in range(len(c0)))


def smoothstep(t: float) -> float:
	t = min(max(t, 0.0), 1.0)
	return t * t * (3.0 - 2.0 * t)


def shoreline_y(x: float, base: float, amp: float, rng: np.random.Generator) -> float:
	## Multi-frequency irregular water edge — never a hard straight divide.
	n1 = np.sin(x * 0.012 + 0.7) * amp
	n2 = np.sin(x * 0.031 + 2.1) * (amp * 0.45)
	n3 = np.sin(x * 0.067 + 4.4) * (amp * 0.22)
	return base + n1 + n2 + n3


def paint_sky(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
	"""Romantic sunset-to-twilight sky with soft cloud forms and early stars."""
	h, w, _ = img.shape
	ys = np.linspace(0.0, 1.0, h)[:, None]
	xs = np.linspace(0.0, 1.0, w)[None, :]

	## Deep twilight → cooler mid → warm dusk → bright warm horizon.
	c_top = np.array([12, 20, 46], dtype=np.float32)
	c_upper = np.array([28, 40, 78], dtype=np.float32)
	c_mid = np.array([72, 52, 88], dtype=np.float32)
	c_warm = np.array([188, 92, 72], dtype=np.float32)
	c_horizon = np.array([245, 148, 88], dtype=np.float32)
	c_glow = np.array([255, 188, 120], dtype=np.float32)

	sky = np.zeros((h, w, 3), dtype=np.float32)
	for y in range(h):
		yf = y / max(h - 1, 1)
		if yf < 0.22:
			t = smoothstep(yf / 0.22)
			col = lerp_color(c_top, c_upper, t)
		elif yf < 0.38:
			t = smoothstep((yf - 0.22) / 0.16)
			col = lerp_color(c_upper, c_mid, t)
		elif yf < 0.455:
			t = smoothstep((yf - 0.38) / 0.075)
			col = lerp_color(c_mid, c_warm, t)
		elif yf < 0.50:
			t = smoothstep((yf - 0.455) / 0.045)
			col = lerp_color(c_warm, c_horizon, t)
		else:
			t = smoothstep((yf - 0.50) / 0.04)
			col = lerp_color(c_horizon, c_glow, min(t, 1.0))
		sky[y, :] = col

	## Soft lateral warm spill near the sun side.
	sun_x = 0.68
	warm_spill = np.exp(-((xs - sun_x) ** 2) / (2 * 0.18**2)) * np.clip(1.0 - (ys - 0.42) * 4.5, 0, 1)
	sky += warm_spill[:, :, None] * np.array([28, 12, 0], dtype=np.float32)

	## Soft cloud forms (not hard shapes).
	cloud = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	cd = ImageDraw.Draw(cloud)
	for cx, cy, rw, rh, a in [
		(0.22, 0.16, 90, 28, 55),
		(0.38, 0.13, 70, 22, 42),
		(0.55, 0.18, 110, 30, 48),
		(0.78, 0.12, 80, 24, 38),
		(0.30, 0.24, 60, 18, 30),
	]:
		x0 = int(cx * w - rw)
		y0 = int(cy * h - rh)
		x1 = int(cx * w + rw)
		y1 = int(cy * h + rh)
		cd.ellipse([x0, y0, x1, y1], fill=(255, 210, 190, a))
		cd.ellipse([x0 + rw // 3, y0 - rh // 3, x1 - rw // 5, y1 - rh // 4], fill=(255, 220, 200, a // 2))
	cloud = cloud.filter(ImageFilter.GaussianBlur(radius=10))
	base = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
	base = Image.alpha_composite(base, cloud)

	## Sun / glow just above horizon.
	sun_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	sd = ImageDraw.Draw(sun_layer)
	sx, sy = int(w * sun_x), int(h * 0.455)
	for r, a in [(130, 28), (85, 46), (48, 78), (22, 120)]:
		sd.ellipse([sx - r, sy - int(r * 0.55), sx + r, sy + int(r * 0.55)], fill=(255, 175, 105, a))
	sun_layer = sun_layer.filter(ImageFilter.GaussianBlur(radius=14))
	base = Image.alpha_composite(base, sun_layer)

	## Restrained early stars in upper sky.
	draw = ImageDraw.Draw(base, "RGBA")
	for _ in range(28):
		x = int(rng.integers(0, w))
		y = int(rng.integers(0, int(h * 0.28)))
		bright = int(rng.integers(150, 230))
		size = int(rng.integers(1, 3))
		draw.ellipse([x, y, x + size, y + size], fill=(bright, bright, 255, int(rng.integers(50, 130))))

	## Soft crescent moon.
	mx, my = int(w * 0.16), int(h * 0.12)
	draw.ellipse([mx - 13, my - 13, mx + 13, my + 13], fill=(230, 232, 245, 100))
	draw.ellipse([mx - 5, my - 15, mx + 15, my + 9], fill=(14, 20, 44, 200))

	return np.array(base.convert("RGB"))


def paint_ocean(base: np.ndarray, shore_ys: np.ndarray, rng: np.random.Generator) -> np.ndarray:
	"""Calm ocean with depth, reflective variation, and subtle ripples."""
	h, w, _ = base.shape
	horizon = int(h * 0.48)
	img = base.copy().astype(np.float32)

	deep = np.array([28, 58, 98], dtype=np.float32)
	mid = np.array([42, 82, 122], dtype=np.float32)
	near = np.array([58, 96, 128], dtype=np.float32)
	reflect = np.array([210, 150, 110], dtype=np.float32)

	for x in range(w):
		shore = int(shore_ys[x])
		for y in range(horizon, shore):
			t = (y - horizon) / max(shore - horizon, 1)
			t = smoothstep(t)
			if t < 0.35:
				col = lerp_color(deep, mid, t / 0.35)
			else:
				col = lerp_color(mid, near, (t - 0.35) / 0.65)
			## Warm reflection near horizon under the sun.
			rx = abs(x / w - 0.68)
			refl = max(0.0, 1.0 - rx * 3.2) * max(0.0, 1.0 - (y - horizon) / max(h * 0.08, 1))
			col = lerp_color(col, reflect, refl * 0.35)
			img[y, x] = col

	## Subtle ripple / wave bands with soft undulation.
	draw_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	dd = ImageDraw.Draw(draw_layer)
	for i in range(16):
		yf = i / 15.0
		y_base = int(lerp(horizon + 10, float(np.mean(shore_ys)) - 14, yf))
		alpha = int(lerp(40, 10, yf))
		pts = []
		for x in range(0, w, 8):
			wiggle = int(6 * np.sin(x * 0.04 + i * 0.7) + 3 * np.sin(x * 0.11 + i))
			pts.append((x, y_base + wiggle))
		if len(pts) > 1:
			col = (220, 195, 170, alpha) if yf < 0.4 else (170, 200, 220, alpha)
			dd.line(pts, fill=col, width=2)
	draw_layer = draw_layer.filter(ImageFilter.GaussianBlur(radius=1.2))
	out = Image.alpha_composite(
		Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA"),
		draw_layer,
	)
	return np.array(out.convert("RGB"))


def paint_sand(base: np.ndarray, shore_ys: np.ndarray, rng: np.random.Generator) -> np.ndarray:
	"""Textured sand with wet edge, foam detail, and warm chest spill."""
	h, w, _ = base.shape
	img = base.copy().astype(np.float32)

	wet = np.array([78, 90, 96], dtype=np.float32)
	damp = np.array([128, 102, 74], dtype=np.float32)
	dry = np.array([168, 128, 88], dtype=np.float32)
	deep_sand = np.array([140, 104, 70], dtype=np.float32)

	for x in range(w):
		shore = int(shore_ys[x])
		for y in range(shore, h):
			t = (y - shore) / max(h - shore, 1)
			if t < 0.08:
				col = lerp_color(wet, damp, t / 0.08)
			elif t < 0.28:
				col = lerp_color(damp, dry, (t - 0.08) / 0.20)
			else:
				col = lerp_color(dry, deep_sand, (t - 0.28) / 0.72)
			img[y, x] = col

	## Sand grain / variation — denser near foreground.
	grain = rng.normal(0, 1.0, size=(h, w))
	yy = np.linspace(0, 1, h)[:, None]
	strength = 3.5 + 5.5 * yy
	for c in range(3):
		channel_bias = rng.normal(0, 0.35, size=(h, w))
		band = np.zeros((h, w), dtype=bool)
		for x in range(w):
			band[int(shore_ys[x]) :, x] = True
		noise = (grain + channel_bias) * strength
		img[:, :, c] = np.where(band, np.clip(img[:, :, c] + noise, 0, 255), img[:, :, c])

	## Soft dune-ish tonal streaks (very restrained).
	for _ in range(7):
		cx = int(rng.integers(40, w - 40))
		cy = int(rng.integers(int(h * 0.68), int(h * 0.92)))
		rw = int(rng.integers(60, 140))
		rh = int(rng.integers(10, 22))
		yy, xx = np.ogrid[:h, :w]
		mask = ((xx - cx) / rw) ** 2 + ((yy - cy) / rh) ** 2 <= 1.0
		img[mask] = np.clip(img[mask] + np.array([6, 3, -2], dtype=np.float32), 0, 255)

	rgba = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

	## Foam / wet-sand edge along irregular shoreline.
	foam = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	fd = ImageDraw.Draw(foam)
	pts_hi = [(x, int(shore_ys[x] - 2 + 1.5 * np.sin(x * 0.08))) for x in range(w)]
	pts_lo = [(x, int(shore_ys[x] + 5 + 1.2 * np.sin(x * 0.05 + 1.0))) for x in range(w - 1, -1, -1)]
	fd.polygon(pts_hi + pts_lo, fill=(235, 230, 220, 70))
	for x in range(0, w, 3):
		y = int(shore_ys[x])
		fd.ellipse([x - 2, y - 1, x + 3, y + 3], fill=(245, 240, 230, int(rng.integers(35, 80))))
	foam = foam.filter(ImageFilter.GaussianBlur(radius=1.8))
	rgba = Image.alpha_composite(rgba, foam)

	## Warm chest spill on lower-center sand.
	glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	gd = ImageDraw.Draw(glow)
	cx, cy = int(w * 0.50), int(h * 0.72)
	for r, a in [(140, 20), (95, 28), (55, 36)]:
		gd.ellipse(
			[cx - int(r * 1.45), cy - int(r * 0.55), cx + int(r * 1.45), cy + int(r * 0.55)],
			fill=(255, 170, 90, a),
		)
	glow = glow.filter(ImageFilter.GaussianBlur(radius=16))
	rgba = Image.alpha_composite(rgba, glow)
	return np.array(rgba.convert("RGB"))


def main() -> None:
	OUT.parent.mkdir(parents=True, exist_ok=True)
	rng = np.random.default_rng(43)

	## Authoring bands (fractions of height).
	horizon_frac = 0.47
	shore_base = 0.62
	shore_amp = 14.0

	sky = paint_sky(np.zeros((H, W, 3), dtype=np.uint8), rng)

	shore_ys = np.array(
		[shoreline_y(float(x), H * shore_base, shore_amp, rng) for x in range(W)],
		dtype=np.float32,
	)

	## Soft atmospheric horizon (not a hard geometric line).
	hy = int(H * horizon_frac)
	band = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	bd = ImageDraw.Draw(band)
	for k in range(22):
		a = int(max(0, 36 - abs(k - 10) * 3))
		bd.line([(0, hy - 10 + k), (W, hy - 10 + k)], fill=(255, 170, 110, a), width=1)
	band = band.filter(ImageFilter.GaussianBlur(radius=3.5))
	sky_img = Image.alpha_composite(Image.fromarray(sky, "RGB").convert("RGBA"), band)
	sky = np.array(sky_img.convert("RGB"))

	ocean = paint_ocean(sky, shore_ys, rng)
	beach = paint_sand(ocean, shore_ys, rng)

	img = Image.fromarray(beach, "RGB").convert("RGBA")

	## Upper readability shade for title — soft, not an opaque panel.
	shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	sd = ImageDraw.Draw(shade)
	for y in range(0, int(H * 0.26)):
		t = 1.0 - (y / (H * 0.26))
		a = int(78 * t * t)
		sd.line([(0, y), (W, y)], fill=(8, 12, 28, a), width=1)
	img = Image.alpha_composite(img, shade)

	## Soften horizon so it never reads as a hard geometric ruler line.
	hy = int(H * horizon_frac)
	hyb = img.crop((0, hy - 28, W, hy + 34)).filter(ImageFilter.GaussianBlur(radius=7))
	img.paste(hyb, (0, hy - 28))
	## Mild overall polish — keep shoreline detail, avoid plastic blur.
	img = img.filter(ImageFilter.GaussianBlur(radius=0.45))
	img = ImageEnhance.Contrast(img).enhance(1.05)
	img = ImageEnhance.Color(img).enhance(1.06)
	img.save(OUT, "PNG", optimize=True)
	print(f"wrote {OUT} ({OUT.stat().st_size} bytes) size={img.size}")


if __name__ == "__main__":
	main()
