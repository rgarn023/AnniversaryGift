#!/usr/bin/env python3
"""Generate the default twilight beach/ocean Chest environment raster.

Output:
  assets/art/background/environments/default_beach.png

Original in-project art (not a copy of any copyrighted game background).
Ships locally with the APK — no remote URL dependency.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "background" / "environments" / "default_beach.png"

## Logical mobile aspect (~9:19.5) at a comfortable mobile texture size.
W, H = 720, 1280


def lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


def lerp_color(c0, c1, t: float):
	return tuple(int(round(lerp(c0[i], c1[i], t))) for i in range(3))


def vertical_gradient(h: int, w: int, stops: list[tuple[float, tuple[int, int, int]]]) -> np.ndarray:
	"""stops: list of (y_frac 0..1, rgb)."""
	stops = sorted(stops, key=lambda s: s[0])
	img = np.zeros((h, w, 3), dtype=np.uint8)
	ys = np.linspace(0.0, 1.0, h)
	for yi, yf in enumerate(ys):
		for i in range(len(stops) - 1):
			y0, c0 = stops[i]
			y1, c1 = stops[i + 1]
			if y0 <= yf <= y1 or (i == len(stops) - 2 and yf >= y1):
				t = 0.0 if y1 <= y0 else (yf - y0) / (y1 - y0)
				t = min(max(t, 0.0), 1.0)
				col = lerp_color(c0, c1, t)
				img[yi, :] = col
				break
	return img


def main() -> None:
	OUT.parent.mkdir(parents=True, exist_ok=True)

	## Twilight sky → warm horizon → calm ocean → soft sand.
	## Sand band starts high enough that a mid/lower chest plant reads as grounded.
	sky_horizon = 0.47
	water_sand = 0.60

	base = vertical_gradient(
		H,
		W,
		[
			(0.00, (14, 22, 48)),  ## deep twilight (blue, not purple space)
			(0.18, (34, 42, 78)),
			(0.32, (88, 58, 92)),  ## soft dusk
			(0.42, (176, 86, 68)),  ## warm sunset
			(0.48, (230, 132, 78)),  ## bright horizon
			(0.51, (62, 98, 138)),  ## calm ocean
			(0.58, (38, 72, 112)),
			(0.62, (72, 92, 98)),  ## wet sand
			(0.68, (138, 104, 72)),  ## dry sand (larger band)
			(0.82, (164, 124, 84)),
			(1.00, (132, 98, 68)),
		],
	)

	img = Image.fromarray(base, "RGB")
	draw = ImageDraw.Draw(img, "RGBA")

	## Soft sun/glow just above the horizon (restrained — blurred later, no hard rings).
	sun_y = int(H * (sky_horizon - 0.02))
	sun_x = int(W * 0.70)
	sun_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	sdraw = ImageDraw.Draw(sun_layer)
	for r, a in [(110, 34), (70, 50), (36, 80)]:
		sdraw.ellipse(
			[sun_x - r, sun_y - r // 2, sun_x + r, sun_y + r // 2],
			fill=(255, 170, 100, a),
		)
	sun_layer = sun_layer.filter(ImageFilter.GaussianBlur(radius=16))
	img = Image.alpha_composite(img.convert("RGBA"), sun_layer).convert("RGB")
	draw = ImageDraw.Draw(img, "RGBA")

	## Subtle early stars in upper sky only.
	rng = np.random.default_rng(41)
	for _ in range(22):
		x = int(rng.integers(0, W))
		y = int(rng.integers(0, int(H * 0.32)))
		bright = int(rng.integers(140, 220))
		size = int(rng.integers(1, 3))
		draw.ellipse([x, y, x + size, y + size], fill=(bright, bright, 255, int(rng.integers(60, 140))))

	## Soft crescent moon — optional, low clutter.
	mx, my = int(W * 0.18), int(H * 0.14)
	draw.ellipse([mx - 14, my - 14, mx + 14, my + 14], fill=(230, 230, 245, 110))
	draw.ellipse([mx - 6, my - 16, mx + 16, my + 10], fill=(18, 22, 48, 180))

	## Calm water highlights — horizontal, not noisy waves.
	water_top = int(H * sky_horizon)
	water_bot = int(H * water_sand)
	for i in range(10):
		yf = i / 9.0
		y = int(lerp(water_top + 8, water_bot - 10, yf))
		alpha = int(lerp(35, 12, yf))
		wiggle = int(rng.integers(-18, 18))
		x0 = int(W * 0.08) + wiggle
		x1 = int(W * 0.92) + wiggle
		col = (210, 190, 170, alpha) if yf < 0.35 else (170, 190, 210, alpha)
		draw.line([(x0, y), (x1, y)], fill=col, width=2)

	## Horizon soft band.
	hy = int(H * sky_horizon)
	for k in range(10):
		a = int(40 - k * 3)
		draw.line([(0, hy - 4 + k), (W, hy - 4 + k)], fill=(255, 160, 100, max(a, 0)), width=1)

	## Sand texture — very soft grain, not noisy.
	sand = np.array(img)
	sand_y0 = int(H * (water_sand - 0.02))
	grain = rng.normal(0, 4.5, size=(H - sand_y0, W, 3))
	sand[sand_y0:] = np.clip(sand[sand_y0:].astype(np.float32) + grain, 0, 255).astype(np.uint8)
	img = Image.fromarray(sand, "RGB")

	## Warm chest spill suggestion near lower-center sand (where chest rests).
	glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	gd = ImageDraw.Draw(glow)
	cx, cy = int(W * 0.50), int(H * 0.74)
	for r, a in [(120, 22), (80, 30), (45, 38)]:
		gd.ellipse([cx - r * 1.4, cy - r * 0.55, cx + r * 1.4, cy + r * 0.55], fill=(255, 170, 90, a))
	glow = glow.filter(ImageFilter.GaussianBlur(radius=18))
	img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")

	## Upper readability shade — soft, not an opaque panel.
	shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	sd = ImageDraw.Draw(shade)
	for y in range(0, int(H * 0.28)):
		t = 1.0 - (y / (H * 0.28))
		a = int(70 * t * t)
		sd.line([(0, y), (W, y)], fill=(8, 10, 28, a), width=1)
	img = Image.alpha_composite(img.convert("RGBA"), shade)

	## Slight overall blur polish for mobile.
	img = img.filter(ImageFilter.GaussianBlur(radius=0.6))
	img.save(OUT, "PNG", optimize=True)
	print(f"wrote {OUT} ({OUT.stat().st_size} bytes) size={img.size}")


if __name__ == "__main__":
	main()
