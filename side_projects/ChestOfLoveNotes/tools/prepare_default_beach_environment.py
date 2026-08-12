#!/usr/bin/env python3
"""Generate the default twilight beach/ocean Chest environment raster.

Output:
  assets/art/background/environments/default_beach.png

v46: polish-only pass on the v45 twilight beach — finer foam edge, wet-sand
transition, low-amplitude water variation/reflection, restrained sand grounding
under the chest. Do NOT redesign sky/composition.
Mobile-friendly baked raster (no expensive runtime shaders).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "background" / "environments" / "default_beach.png"
W, H = 720, 1280


def lerp(a, b, t):
	return a + (b - a) * t


def lerp_color(c0, c1, t):
	t = min(max(float(t), 0.0), 1.0)
	return tuple(int(round(lerp(float(c0[i]), float(c1[i]), t))) for i in range(3))


def smoothstep(t):
	t = min(max(float(t), 0.0), 1.0)
	return t * t * (3.0 - 2.0 * t)


def value_noise(h, w, scale, rng, octaves=4):
	"""Multi-octave value noise in [-1, 1] — organic, not geometric stripes."""
	out = np.zeros((h, w), dtype=np.float32)
	amp = 1.0
	total = 0.0
	for o in range(octaves):
		gh = max(2, int(h / (scale * (0.5 ** o))))
		gw = max(2, int(w / (scale * (0.5 ** o))))
		grid = rng.uniform(-1, 1, size=(gh, gw)).astype(np.float32)
		layer = np.array(
			Image.fromarray(((grid + 1) * 127.5).astype(np.uint8), "L").resize((w, h), Image.Resampling.BICUBIC),
			dtype=np.float32,
		)
		layer = layer / 127.5 - 1.0
		out += layer * amp
		total += amp
		amp *= 0.55
	return out / max(total, 1e-6)


def shoreline_y(x, base, amp):
	n1 = np.sin(x * 0.009 + 0.5) * amp
	n2 = np.sin(x * 0.021 + 2.3) * (amp * 0.55)
	n3 = np.sin(x * 0.047 + 4.1) * (amp * 0.28)
	n4 = np.sin(x * 0.093 + 1.1) * (amp * 0.12)
	return base + n1 + n2 + n3 + n4


def paint_sky(rng):
	h, w = H, W
	ys = np.linspace(0, 1, h)[:, None]
	xs = np.linspace(0, 1, w)[None, :]
	sky = np.zeros((h, w, 3), dtype=np.float32)
	stops = [
		(0.00, (8, 14, 36)),
		(0.18, (20, 30, 64)),
		(0.34, (58, 42, 82)),
		(0.42, (150, 78, 70)),
		(0.47, (235, 140, 85)),
		(0.52, (255, 185, 120)),
	]
	for y in range(h):
		yf = y / max(h - 1, 1)
		for i in range(len(stops) - 1):
			y0, c0 = stops[i]
			y1, c1 = stops[i + 1]
			if y0 <= yf <= y1 or i == len(stops) - 2:
				t = smoothstep((yf - y0) / max(y1 - y0, 1e-6))
				sky[y, :] = lerp_color(c0, c1, t)
				break
	sun_x = 0.64
	warm = np.exp(-((xs - sun_x) ** 2) / (2 * 0.22**2)) * np.clip(1.0 - (ys - 0.38) * 4.0, 0, 1)
	sky += warm[:, :, None] * np.array([36, 16, 4], dtype=np.float32)
	# subtle sky noise
	n = value_noise(h, w, 90, rng, 3)
	sky += ((1.0 - ys) * n * 0.5)[:, :, None] * np.array([4, 3, 5], dtype=np.float32)
	base = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
	cloud = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	cd = ImageDraw.Draw(cloud)
	for cx, cy, rw, rh, a in [
		(0.20, 0.13, 110, 32, 42),
		(0.40, 0.10, 80, 24, 34),
		(0.58, 0.16, 130, 34, 40),
		(0.78, 0.11, 90, 26, 30),
		(0.30, 0.21, 70, 18, 22),
	]:
		cd.ellipse([cx*w-rw, cy*h-rh, cx*w+rw, cy*h+rh], fill=(255, 210, 190, a))
	cloud = cloud.filter(ImageFilter.GaussianBlur(12))
	base = Image.alpha_composite(base, cloud)
	sun = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	sd = ImageDraw.Draw(sun)
	sx, sy = int(w * sun_x), int(h * 0.445)
	for r, a in [(160, 22), (100, 40), (55, 70), (26, 110)]:
		sd.ellipse([sx-r, sy-int(r*0.55), sx+r, sy+int(r*0.55)], fill=(255, 175, 105, a))
	sun = sun.filter(ImageFilter.GaussianBlur(16))
	base = Image.alpha_composite(base, sun)
	d = ImageDraw.Draw(base, "RGBA")
	for _ in range(40):
		x = int(rng.integers(0, w)); y = int(rng.integers(0, int(h*0.28)))
		b = int(rng.integers(150, 230)); s = int(rng.integers(1, 3))
		d.ellipse([x, y, x+s, y+s], fill=(b, b, 255, int(rng.integers(40, 110))))
	mx, my = int(w*0.15), int(h*0.11)
	d.ellipse([mx-13, my-13, mx+13, my+13], fill=(230, 232, 245, 95))
	d.ellipse([mx-5, my-15, mx+15, my+9], fill=(10, 16, 38, 210))
	return np.array(base.convert("RGB"))


def paint_ocean(base, shore_ys, rng):
	h, w, _ = base.shape
	horizon = int(h * 0.465)
	img = base.copy().astype(np.float32)
	n = value_noise(h, w, 70, rng, 5)
	n2 = value_noise(h, w, 140, rng, 3)
	deep = np.array([18, 40, 78], dtype=np.float32)
	mid = np.array([34, 68, 105], dtype=np.float32)
	near = np.array([52, 88, 118], dtype=np.float32)
	shallow = np.array([86, 118, 132], dtype=np.float32)
	reflect = np.array([222, 152, 112], dtype=np.float32)
	for x in range(w):
		shore = int(shore_ys[x])
		span = max(shore - horizon, 1)
		for y in range(horizon, shore):
			t = smoothstep((y - horizon) / span)
			if t < 0.28:
				col = np.array(lerp_color(deep, mid, t/0.28), np.float32)
			elif t < 0.70:
				col = np.array(lerp_color(mid, near, (t-0.28)/0.42), np.float32)
			else:
				col = np.array(lerp_color(near, shallow, (t-0.70)/0.30), np.float32)
			# organic tonal variation from value noise (no periodic grid)
			col += n[y, x] * 7.0 + n2[y, x] * 4.0
			rx = abs(x/w - 0.64)
			refl = max(0.0, 1.0 - rx*2.4) * max(0.0, 1.0 - (y-horizon)/max(h*0.12,1))
			col = col*(1-refl*0.26) + reflect*(refl*0.26)
			img[y, x] = np.clip(col, 0, 255)
	# soft glints + low-amplitude wave crests (natural, not striped)
	gl = Image.new("RGBA", (w, h), (0,0,0,0))
	gd = ImageDraw.Draw(gl)
	for _ in range(56):
		x = int(np.clip(rng.normal(w*0.64, w*0.12), 6, w-6))
		y = int(rng.integers(horizon+8, int(np.mean(shore_ys))-10))
		gd.ellipse([x,y,x+2,y+1], fill=(255,220,180,int(rng.integers(12,32))))
	for _ in range(18):
		y0 = int(rng.integers(horizon + 14, int(np.mean(shore_ys)) - 18))
		phase = float(rng.uniform(0, 6.28))
		amp = float(rng.uniform(1.2, 2.8))
		pts = []
		for x in range(0, w, 6):
			yy = y0 + int(amp * np.sin(x * 0.018 + phase) + 0.7 * np.sin(x * 0.041 + phase * 1.3))
			pts.append((x, yy))
		if len(pts) > 2:
			gd.line(pts, fill=(210, 230, 245, int(rng.integers(10, 22))), width=1)
	gl = gl.filter(ImageFilter.GaussianBlur(1.35))
	out = Image.alpha_composite(Image.fromarray(np.clip(img,0,255).astype(np.uint8),"RGB").convert("RGBA"), gl)
	# atmospheric haze
	haze = Image.new("RGBA", (w,h), (0,0,0,0))
	hd = ImageDraw.Draw(haze)
	for k in range(34):
		y = horizon + k
		hd.line([(0,y),(w,y)], fill=(255,168,118,int(max(0,28-k*0.7))), width=1)
	haze = haze.filter(ImageFilter.GaussianBlur(5.5))
	out = Image.alpha_composite(out, haze)
	arr = np.array(out.convert("RGB")).astype(np.float32)
	## Break residual horizontal banding with strong lateral noise + soft blur.
	n_lat = value_noise(h, w, 40, rng, 4)
	for x in range(w):
		shore = int(shore_ys[x])
		for y in range(horizon, shore):
			arr[y, x] += n_lat[y, x] * 9.0
	arr = np.clip(arr, 0, 255)
	# Soft blur across whole ocean band so depth reads continuous, not striped.
	blur = np.array(Image.fromarray(arr.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.8)), dtype=np.float32)
	for x in range(w):
		shore = int(shore_ys[x])
		for y in range(horizon, shore):
			t = (y - horizon) / max(shore - horizon, 1)
			# more blur far, less near shore
			wt = 0.55 * (1.0 - t) + 0.20
			arr[y, x] = blur[y, x] * wt + arr[y, x] * (1.0 - wt)
	return np.clip(arr, 0, 255).astype(np.uint8)


def paint_sand(base, shore_ys, rng):
	h, w, _ = base.shape
	img = base.copy().astype(np.float32)
	n = value_noise(h, w, 55, rng, 5)
	n_big = value_noise(h, w, 160, rng, 3)
	wet = np.array([68, 80, 88], np.float32)
	damp = np.array([118, 94, 70], np.float32)
	dry = np.array([170, 130, 88], np.float32)
	warm = np.array([188, 144, 98], np.float32)
	deep = np.array([132, 98, 64], np.float32)
	for x in range(w):
		shore = int(shore_ys[x])
		for y in range(shore, h):
			t = (y - shore) / max(h - shore, 1)
			if t < 0.08:
				col = np.array(lerp_color(wet, damp, t/0.08), np.float32)
			elif t < 0.24:
				col = np.array(lerp_color(damp, dry, (t-0.08)/0.16), np.float32)
			elif t < 0.55:
				col = np.array(lerp_color(dry, warm, (t-0.24)/0.31), np.float32)
			else:
				col = np.array(lerp_color(warm, deep, (t-0.55)/0.45), np.float32)
			# multi-scale depth: large dunes + fine grain
			col += n_big[y,x] * (12 + 10*((y/h)**1.2)) + n[y,x] * (6 + 9*(y/h))
			# fine speck grain
			col += rng.normal(0, 1.8 + 2.5*(y/h), size=3)
			img[y,x] = np.clip(col, 0, 255)
	# soft dune patches
	for _ in range(14):
		cx = int(rng.integers(20, w-20))
		cy = int(rng.integers(int(h*0.62), int(h*0.95)))
		rw = int(rng.integers(55, 170)); rh = int(rng.integers(10, 28))
		yy, xx = np.ogrid[:h, :w]
		mask = ((xx-cx)/rw)**2 + ((yy-cy)/rh)**2 <= 1.0
		delta = np.array([rng.uniform(-8,10), rng.uniform(-6,7), rng.uniform(-8,3)], np.float32)
		img[mask] = np.clip(img[mask] + delta, 0, 255)
	rgba = Image.fromarray(np.clip(img,0,255).astype(np.uint8), "RGB").convert("RGBA")
	# wet-sand transition — softer, less artificial hard boundary
	wetb = Image.new("RGBA", (w,h), (0,0,0,0))
	wd = ImageDraw.Draw(wetb)
	pts_hi = [(x, int(shore_ys[x]-2+1.8*np.sin(x*0.05))) for x in range(w)]
	pts_lo = [(x, int(shore_ys[x]+28+2.6*np.sin(x*0.033+0.7))) for x in range(w-1,-1,-1)]
	wd.polygon(pts_hi+pts_lo, fill=(62,76,84,68))
	pts_mid = [(x, int(shore_ys[x]+8+1.8*np.sin(x*0.04+1.2))) for x in range(w)]
	pts_mid_lo = [(x, int(shore_ys[x]+18+2.0*np.sin(x*0.038+0.4))) for x in range(w-1,-1,-1)]
	wd.polygon(pts_mid+pts_mid_lo, fill=(90,88,78,36))
	wetb = wetb.filter(ImageFilter.GaussianBlur(5.0))
	rgba = Image.alpha_composite(rgba, wetb)
	# natural foam edge — thin broken lace, not a hard white stroke
	foam = Image.new("RGBA", (w,h), (0,0,0,0))
	fd = ImageDraw.Draw(foam)
	pts_hi2 = [(x, int(shore_ys[x]-3+2.1*np.sin(x*0.055)+0.9*np.sin(x*0.13))) for x in range(w)]
	pts_lo2 = [(x, int(shore_ys[x]+4+1.4*np.sin(x*0.048+1.0))) for x in range(w-1,-1,-1)]
	fd.polygon(pts_hi2+pts_lo2, fill=(238,232,222,42))
	for x in range(0, w, 3):
		y = int(shore_ys[x] + 0.8 * np.sin(x * 0.09))
		if rng.random() < 0.72:
			fd.ellipse(
				[x - 2, y - 1, x + int(rng.integers(2, 5)), y + int(rng.integers(1, 3))],
				fill=(248, 244, 234, int(rng.integers(18, 56))),
			)
		if rng.random() < 0.22:
			fd.ellipse(
				[x - 1, y + 2, x + 2, y + 4],
				fill=(220, 214, 200, int(rng.integers(10, 28))),
			)
	foam = foam.filter(ImageFilter.GaussianBlur(1.6))
	rgba = Image.alpha_composite(rgba, foam)
	# restrained warm spill + ambient darkening under chest plant point
	glow = Image.new("RGBA", (w,h), (0,0,0,0))
	gd = ImageDraw.Draw(glow)
	cx, cy = int(w*0.50), int(h*0.76)
	for r,a in [(150,12),(96,18),(52,24)]:
		gd.ellipse([cx-int(r*1.55), cy-int(r*0.42), cx+int(r*1.55), cy+int(r*0.42)], fill=(255,168,88,a))
	for r,a in [(120,16),(70,22)]:
		gd.ellipse([cx-int(r*1.35), cy-int(r*0.30), cx+int(r*1.35), cy+int(r*0.34)], fill=(28,18,10,a))
	glow = glow.filter(ImageFilter.GaussianBlur(16))
	rgba = Image.alpha_composite(rgba, glow)
	return np.array(rgba.convert("RGB"))


def main():
	OUT.parent.mkdir(parents=True, exist_ok=True)
	rng = np.random.default_rng(46)
	horizon_frac = 0.455
	shore_base = 0.565
	shore_amp = 26.0
	sky = paint_sky(rng)
	shore_ys = np.array([shoreline_y(float(x), H*shore_base, shore_amp) for x in range(W)], np.float32)
	# soft horizon glow band with slight undulation
	hy = int(H*horizon_frac)
	band = Image.new("RGBA", (W,H), (0,0,0,0))
	bd = ImageDraw.Draw(band)
	for k in range(28):
		a = int(max(0, 32 - abs(k-13)*2.4))
		pts = [(x, hy-12+k + int(2.0*np.sin(x*0.008+k*0.08))) for x in range(0,W,5)]
		if len(pts)>1:
			bd.line(pts, fill=(255,168,108,a), width=2)
	band = band.filter(ImageFilter.GaussianBlur(5.0))
	sky = np.array(Image.alpha_composite(Image.fromarray(sky,"RGB").convert("RGBA"), band).convert("RGB"))
	ocean = paint_ocean(sky, shore_ys, rng)
	beach = paint_sand(ocean, shore_ys, rng)
	img = Image.fromarray(beach, "RGB").convert("RGBA")
	# top readability shade
	shade = Image.new("RGBA", (W,H), (0,0,0,0))
	sd = ImageDraw.Draw(shade)
	for y in range(0, int(H*0.22)):
		t = 1.0 - y/(H*0.22)
		sd.line([(0,y),(W,y)], fill=(8,12,28,int(58*t*t)), width=1)
	img = Image.alpha_composite(img, shade)
	# Soften horizon only — keep sand/water sharper so beach matches chest quality.
	hy = int(H*horizon_frac)
	hyb = img.crop((0, hy-28, W, hy+36)).filter(ImageFilter.GaussianBlur(5.5))
	img.paste(hyb, (0, hy-28))
	## Extra sand micro-grain (no whole-image blur washout).
	sand = np.array(img)
	grain = rng.normal(0, 3.2, size=sand.shape).astype(np.float32)
	y0 = int(H * 0.58)
	sand[y0:, :, :3] = np.clip(sand[y0:, :, :3].astype(np.float32) + grain[y0:, :, :3], 0, 255)
	img = Image.fromarray(sand.astype(np.uint8), "RGBA")
	img = ImageEnhance.Contrast(img).enhance(1.10)
	img = ImageEnhance.Color(img).enhance(1.06)
	img = ImageEnhance.Sharpness(img).enhance(1.12)
	img.save(OUT, "PNG", optimize=True)
	print(f"wrote {OUT} ({OUT.stat().st_size} bytes) size={img.size}")


if __name__ == "__main__":
	main()
