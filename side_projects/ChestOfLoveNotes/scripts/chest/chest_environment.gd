extends Control
class_name ChestEnvironment
## Modular Chest-screen environment / background.
## Default: romantic beach ("default_beach") with local-time sky/ocean tint.
## Chest animation stays a separate layer above this node.
## Future cosmetic swaps can change `environment_id` / texture without
## rewriting the chest frame animation. No store/IAP in this pass.
## v52: stronger water-only glints + smooth device-local time-of-day coloring.

const ENV_DEFAULT_BEACH := "default_beach"
const ENV_DIR := "res://assets/art/background/environments/"
const OCEAN_GLISTEN := ENV_DIR + "ocean_glisten.png"
const STARFIELD := "res://assets/art/background/starfield.png"
## Authored beach water band (fraction of environment height).
## Must stay off sky (~above 0.47) and off sand (~below 0.56).
const WATER_TOP_FRAC := 0.470
const WATER_BOTTOM_FRAC := 0.560
## Soft elongated horizontal glints (water-only, staggered).
const GLINT_COUNT := 5
## Sky band for stars / wash (above horizon water).
const SKY_BOTTOM_FRAC := 0.470

## Dev/test only — when >= 0, forces local hour (0–24). Production stays -1.
static var debug_hour_override: float = -1.0

static var _tex_cache: Dictionary = {}
static var _preloaded: bool = false

var environment_id: String = ENV_DEFAULT_BEACH
var _base_fill: ColorRect
var _bg: TextureRect
var _sky_clip: Control
var _sky_wash_top: ColorRect
var _sky_wash_horizon: ColorRect
var _stars: TextureRect
var _top_shade: ColorRect
var _horizon_sheen: ColorRect
var _water_clip: Control
var _ocean_tint: ColorRect
var _water_glisten: TextureRect
var _water_glisten_b: TextureRect
var _glints: Array[TextureRect] = []
var _glint_phase: PackedFloat32Array = PackedFloat32Array()
var _glint_base_x: PackedFloat32Array = PackedFloat32Array()
var _glint_base_y: PackedFloat32Array = PackedFloat32Array()
var _glint_w: PackedFloat32Array = PackedFloat32Array()
var _ready_visuals: bool = false
var _idle: float = 0.0
var _tod_refresh: float = 0.0
var _last_hour_bucket: float = -999.0
const SOFT_GLINT := "res://assets/art/chest/soft_glow_pulse.png"

## Time-of-day keyframes (local clock hours). Smooth lerp between neighbors.
## Phases: NIGHT 20–05, DAWN 05–08, DAY 08–17, SUNSET 17–20.
const TOD_HOURS := [0.0, 5.0, 6.5, 8.0, 12.0, 17.0, 18.5, 20.0, 24.0]


static func preload_assets() -> void:
	if _preloaded:
		return
	_load_cached(_path_for(ENV_DEFAULT_BEACH))
	_load_cached(OCEAN_GLISTEN)
	_load_cached(SOFT_GLINT)
	_load_cached(STARFIELD)
	_preloaded = true


static func _path_for(env_id: String) -> String:
	return "%s%s.png" % [ENV_DIR, env_id]


static func _load_cached(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


static func local_hour_frac() -> float:
	## Device local clock only — no location permission, no network.
	if debug_hour_override >= 0.0:
		return fposmod(debug_hour_override, 24.0)
	var t := Time.get_time_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0 + float(t.second) / 3600.0


static func tod_palette_at(hour: float) -> Dictionary:
	## Lightweight keyframe interpolation for sky / ocean / stars / shimmer.
	var h := fposmod(hour, 24.0)
	## Palette: base, sky_top, sky_horizon, bg_mod, ocean, horizon, shimmer, star_a
	var keys := [
		{ ## 00:00 deep night
			"base": Color(0.03, 0.04, 0.12, 1.0),
			"sky_top": Color(0.05, 0.06, 0.18, 0.55),
			"sky_horizon": Color(0.10, 0.08, 0.22, 0.28),
			"bg_mod": Color(0.72, 0.74, 0.92, 1.0),
			"ocean": Color(0.20, 0.22, 0.48, 0.34),
			"horizon": Color(0.45, 0.50, 0.85, 0.06),
			"shimmer": Color(0.78, 0.88, 1.0, 1.0),
			"star_a": 0.85,
			"glisten_a": 0.55,
		},
		{ ## 05:00 night → dawn
			"base": Color(0.05, 0.05, 0.14, 1.0),
			"sky_top": Color(0.10, 0.08, 0.24, 0.42),
			"sky_horizon": Color(0.55, 0.32, 0.38, 0.30),
			"bg_mod": Color(0.82, 0.78, 0.90, 1.0),
			"ocean": Color(0.35, 0.30, 0.48, 0.26),
			"horizon": Color(0.95, 0.55, 0.48, 0.10),
			"shimmer": Color(1.0, 0.90, 0.82, 1.0),
			"star_a": 0.45,
			"glisten_a": 0.58,
		},
		{ ## 06:30 mid dawn
			"base": Color(0.12, 0.08, 0.16, 1.0),
			"sky_top": Color(0.22, 0.16, 0.36, 0.28),
			"sky_horizon": Color(0.98, 0.62, 0.55, 0.34),
			"bg_mod": Color(0.96, 0.90, 0.88, 1.0),
			"ocean": Color(0.55, 0.42, 0.52, 0.22),
			"horizon": Color(1.0, 0.68, 0.50, 0.14),
			"shimmer": Color(1.0, 0.92, 0.82, 1.0),
			"star_a": 0.12,
			"glisten_a": 0.62,
		},
		{ ## 08:00 day start
			"base": Color(0.18, 0.28, 0.42, 1.0),
			"sky_top": Color(0.35, 0.55, 0.85, 0.18),
			"sky_horizon": Color(0.70, 0.82, 0.95, 0.12),
			"bg_mod": Color(1.05, 1.02, 0.98, 1.0),
			"ocean": Color(0.25, 0.48, 0.72, 0.14),
			"horizon": Color(0.95, 0.88, 0.70, 0.07),
			"shimmer": Color(1.0, 0.98, 0.90, 1.0),
			"star_a": 0.0,
			"glisten_a": 0.78,
		},
		{ ## 12:00 midday
			"base": Color(0.22, 0.38, 0.58, 1.0),
			"sky_top": Color(0.30, 0.55, 0.92, 0.16),
			"sky_horizon": Color(0.65, 0.82, 1.0, 0.10),
			"bg_mod": Color(1.08, 1.05, 1.00, 1.0),
			"ocean": Color(0.20, 0.52, 0.78, 0.12),
			"horizon": Color(0.95, 0.92, 0.78, 0.05),
			"shimmer": Color(1.0, 0.99, 0.92, 1.0),
			"star_a": 0.0,
			"glisten_a": 0.85,
		},
		{ ## 17:00 sunset start
			"base": Color(0.16, 0.12, 0.22, 1.0),
			"sky_top": Color(0.22, 0.16, 0.38, 0.28),
			"sky_horizon": Color(0.98, 0.48, 0.32, 0.32),
			"bg_mod": Color(1.02, 0.92, 0.88, 1.0),
			"ocean": Color(0.48, 0.30, 0.42, 0.22),
			"horizon": Color(1.0, 0.55, 0.35, 0.16),
			"shimmer": Color(1.0, 0.82, 0.62, 1.0),
			"star_a": 0.05,
			"glisten_a": 0.70,
		},
		{ ## 18:30 mid sunset
			"base": Color(0.10, 0.06, 0.16, 1.0),
			"sky_top": Color(0.16, 0.08, 0.30, 0.40),
			"sky_horizon": Color(0.95, 0.35, 0.45, 0.36),
			"bg_mod": Color(0.92, 0.80, 0.88, 1.0),
			"ocean": Color(0.42, 0.22, 0.48, 0.28),
			"horizon": Color(1.0, 0.42, 0.48, 0.18),
			"shimmer": Color(1.0, 0.75, 0.70, 1.0),
			"star_a": 0.28,
			"glisten_a": 0.62,
		},
		{ ## 20:00 night start
			"base": Color(0.04, 0.05, 0.14, 1.0),
			"sky_top": Color(0.06, 0.06, 0.20, 0.52),
			"sky_horizon": Color(0.18, 0.10, 0.28, 0.30),
			"bg_mod": Color(0.75, 0.76, 0.92, 1.0),
			"ocean": Color(0.22, 0.22, 0.48, 0.32),
			"horizon": Color(0.50, 0.42, 0.75, 0.08),
			"shimmer": Color(0.80, 0.88, 1.0, 1.0),
			"star_a": 0.70,
			"glisten_a": 0.55,
		},
		{ ## 24:00 = 00:00
			"base": Color(0.03, 0.04, 0.12, 1.0),
			"sky_top": Color(0.05, 0.06, 0.18, 0.55),
			"sky_horizon": Color(0.10, 0.08, 0.22, 0.28),
			"bg_mod": Color(0.72, 0.74, 0.92, 1.0),
			"ocean": Color(0.20, 0.22, 0.48, 0.34),
			"horizon": Color(0.45, 0.50, 0.85, 0.06),
			"shimmer": Color(0.78, 0.88, 1.0, 1.0),
			"star_a": 0.85,
			"glisten_a": 0.55,
		},
	]
	var i0 := 0
	for i in range(TOD_HOURS.size() - 1):
		if h >= float(TOD_HOURS[i]) and h <= float(TOD_HOURS[i + 1]):
			i0 = i
			break
	var h0 := float(TOD_HOURS[i0])
	var h1 := float(TOD_HOURS[i0 + 1])
	var t := 0.0 if h1 <= h0 else clampf((h - h0) / (h1 - h0), 0.0, 1.0)
	## Smoothstep for softer phase blends (no hard jumps).
	t = t * t * (3.0 - 2.0 * t)
	var a: Dictionary = keys[i0]
	var b: Dictionary = keys[i0 + 1]
	return {
		"base": (a["base"] as Color).lerp(b["base"] as Color, t),
		"sky_top": (a["sky_top"] as Color).lerp(b["sky_top"] as Color, t),
		"sky_horizon": (a["sky_horizon"] as Color).lerp(b["sky_horizon"] as Color, t),
		"bg_mod": (a["bg_mod"] as Color).lerp(b["bg_mod"] as Color, t),
		"ocean": (a["ocean"] as Color).lerp(b["ocean"] as Color, t),
		"horizon": (a["horizon"] as Color).lerp(b["horizon"] as Color, t),
		"shimmer": (a["shimmer"] as Color).lerp(b["shimmer"] as Color, t),
		"star_a": lerpf(float(a["star_a"]), float(b["star_a"]), t),
		"glisten_a": lerpf(float(a["glisten_a"]), float(b["glisten_a"]), t),
		"hour": h,
		"blend": t,
		"phase": _phase_name(h),
	}


static func _phase_name(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h >= 20.0 or h < 5.0:
		return "night"
	if h < 8.0:
		return "dawn"
	if h < 17.0:
		return "day"
	return "sunset"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preload_assets()
	_build()
	_ready_visuals = true
	set_process(true)
	resized.connect(_layout)
	_layout()
	_apply_time_of_day(true)


func _build() -> void:
	## Opaque fill behind beach — tinted by local time of day.
	_base_fill = ColorRect.new()
	_base_fill.name = "EnvironmentBaseFill"
	_base_fill.color = Color(0.06, 0.09, 0.18, 1.0)
	_base_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_base_fill)

	_bg = TextureRect.new()
	_bg.name = "EnvironmentArt"
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	## Cover viewport without letterboxing; art is authored for tall mobile.
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	## Sky-only wash + stars (clipped so sand/chest stay untouched).
	_sky_clip = Control.new()
	_sky_clip.name = "SkyTimeClip"
	_sky_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_clip.clip_contents = true
	_sky_clip.z_index = 0
	add_child(_sky_clip)

	_sky_wash_top = ColorRect.new()
	_sky_wash_top.name = "SkyWashTop"
	_sky_wash_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_clip.add_child(_sky_wash_top)

	_sky_wash_horizon = ColorRect.new()
	_sky_wash_horizon.name = "SkyWashHorizon"
	_sky_wash_horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_clip.add_child(_sky_wash_horizon)

	_stars = TextureRect.new()
	_stars.name = "SkyStars"
	_stars.texture = _load_cached(STARFIELD)
	_stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_stars.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars.modulate = Color(1, 1, 1, 0.0)
	_sky_clip.add_child(_stars)

	## Soft upper shade for title readability — low alpha so sky has no hard seam.
	_top_shade = ColorRect.new()
	_top_shade.name = "TopReadabilityShade"
	_top_shade.color = Color(0.04, 0.06, 0.12, 0.14)
	_top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_shade.z_index = 1
	add_child(_top_shade)

	## Very subtle horizon sheen (optional depth; cheap ColorRect).
	_horizon_sheen = ColorRect.new()
	_horizon_sheen.name = "HorizonSheen"
	_horizon_sheen.color = Color(1.0, 0.72, 0.45, 0.05)
	_horizon_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_horizon_sheen.z_index = 1
	add_child(_horizon_sheen)

	## Water-only romantic shimmer — clipped so sand/sky/chest stay untouched.
	_water_clip = Control.new()
	_water_clip.name = "OceanGlistenClip"
	_water_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_clip.clip_contents = true
	_water_clip.z_index = 1
	add_child(_water_clip)

	_ocean_tint = ColorRect.new()
	_ocean_tint.name = "OceanTimeTint"
	_ocean_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ocean_tint.color = Color(0.2, 0.35, 0.55, 0.12)
	_water_clip.add_child(_ocean_tint)

	var glisten_tex := _load_cached(OCEAN_GLISTEN)
	_water_glisten = TextureRect.new()
	_water_glisten.name = "OceanGlisten"
	_water_glisten.texture = glisten_tex
	_water_glisten.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_water_glisten.stretch_mode = TextureRect.STRETCH_SCALE
	_water_glisten.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_water_glisten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Clearly visible soft sheen — still tasteful, never glitter spam.
	_water_glisten.modulate = Color(1.0, 0.97, 0.88, 0.88)
	_water_clip.add_child(_water_glisten)

	## Second offset glint band — different phase/opacity so shimmer feels alive.
	_water_glisten_b = TextureRect.new()
	_water_glisten_b.name = "OceanGlistenB"
	_water_glisten_b.texture = glisten_tex
	_water_glisten_b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_water_glisten_b.stretch_mode = TextureRect.STRETCH_SCALE
	_water_glisten_b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_water_glisten_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_glisten_b.modulate = Color(1.0, 0.95, 0.84, 0.62)
	_water_clip.add_child(_water_glisten_b)

	## Discrete soft horizontal streaks — phone-visible "little shimmer".
	_glints.clear()
	_glint_phase = PackedFloat32Array()
	_glint_base_x = PackedFloat32Array()
	_glint_base_y = PackedFloat32Array()
	_glint_w = PackedFloat32Array()
	_glint_phase.resize(GLINT_COUNT)
	_glint_base_x.resize(GLINT_COUNT)
	_glint_base_y.resize(GLINT_COUNT)
	_glint_w.resize(GLINT_COUNT)
	var widths := [0.22, 0.14, 0.26, 0.17, 0.20]
	var x_fracs := [0.08, 0.30, 0.48, 0.66, 0.82]
	var y_fracs := [0.18, 0.42, 0.28, 0.55, 0.38]
	var phases := [0.0, 1.1, 2.3, 3.4, 4.6]
	var soft_tex := _load_cached(SOFT_GLINT)
	for i in range(GLINT_COUNT):
		var g := TextureRect.new()
		g.name = "OceanGlint_%d" % i
		g.texture = soft_tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		## Soft elongated streak — opacity/color driven in _process by time-of-day.
		g.modulate = Color(1.0, 0.96, 0.86, 0.0)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_water_clip.add_child(g)
		_glints.append(g)
		_glint_phase[i] = phases[i]
		_glint_base_x[i] = x_fracs[i]
		_glint_base_y[i] = y_fracs[i]
		_glint_w[i] = widths[i]

	apply_environment(environment_id)


func apply_environment(env_id: String) -> void:
	environment_id = env_id if not env_id.is_empty() else ENV_DEFAULT_BEACH
	var tex := _load_cached(_path_for(environment_id))
	if tex == null and environment_id != ENV_DEFAULT_BEACH:
		environment_id = ENV_DEFAULT_BEACH
		tex = _load_cached(_path_for(environment_id))
	if _bg:
		_bg.texture = tex


func _layout() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		return
	if _base_fill:
		_base_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _bg:
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _sky_clip:
		var sky_h := area.y * SKY_BOTTOM_FRAC
		_sky_clip.position = Vector2.ZERO
		_sky_clip.size = Vector2(area.x, sky_h)
		if _sky_wash_top:
			_sky_wash_top.position = Vector2.ZERO
			_sky_wash_top.size = Vector2(area.x, sky_h * 0.62)
		if _sky_wash_horizon:
			_sky_wash_horizon.position = Vector2(0.0, sky_h * 0.48)
			_sky_wash_horizon.size = Vector2(area.x, sky_h * 0.52)
		if _stars:
			_stars.position = Vector2.ZERO
			_stars.size = Vector2(area.x, sky_h)
	if _top_shade:
		## Short soft band only — avoid a hard sky color seam near the top.
		_top_shade.position = Vector2.ZERO
		_top_shade.size = Vector2(area.x, area.y * 0.12)
	if _horizon_sheen:
		## Horizon sits ~48% down the authored beach art.
		_horizon_sheen.position = Vector2(0.0, area.y * 0.48)
		_horizon_sheen.size = Vector2(area.x, area.y * 0.035)
	if _water_clip and _water_glisten:
		var water_top := area.y * WATER_TOP_FRAC
		var water_h := area.y * (WATER_BOTTOM_FRAC - WATER_TOP_FRAC)
		_water_clip.position = Vector2(0.0, water_top)
		_water_clip.size = Vector2(area.x, water_h)
		if _ocean_tint:
			_ocean_tint.position = Vector2.ZERO
			_ocean_tint.size = Vector2(area.x, water_h)
		## Slightly oversized so slow horizontal drift never shows a hard edge.
		_water_glisten.size = Vector2(area.x * 1.22, water_h)
		_water_glisten.position = Vector2(-area.x * 0.11, 0.0)
		if _water_glisten_b:
			_water_glisten_b.size = Vector2(area.x * 1.30, water_h * 0.92)
			_water_glisten_b.position = Vector2(-area.x * 0.16, water_h * 0.04)
		## Place discrete soft streaks inside the water clip only.
		for i in range(_glints.size()):
			var gw := area.x * _glint_w[i]
			var gh := maxf(3.5, water_h * 0.18)
			_glints[i].size = Vector2(gw, gh)
			_glints[i].position = Vector2(
				area.x * _glint_base_x[i],
				water_h * _glint_base_y[i]
			)


func _apply_time_of_day(force: bool = false) -> void:
	var hour := local_hour_frac()
	## Refresh when the minute bucket changes (or forced). Cheap — no allocations.
	var bucket := floorf(hour * 60.0)
	if not force and absf(bucket - _last_hour_bucket) < 0.5:
		return
	_last_hour_bucket = bucket
	var pal := tod_palette_at(hour)
	if _base_fill:
		_base_fill.color = pal["base"] as Color
	if _bg:
		_bg.modulate = pal["bg_mod"] as Color
	if _sky_wash_top:
		_sky_wash_top.color = pal["sky_top"] as Color
	if _sky_wash_horizon:
		_sky_wash_horizon.color = pal["sky_horizon"] as Color
	if _stars:
		var sa := float(pal["star_a"])
		_stars.modulate = Color(1.0, 1.0, 1.05, sa)
		_stars.visible = sa > 0.01
	if _horizon_sheen:
		var hc := pal["horizon"] as Color
		_horizon_sheen.color = hc
	if _ocean_tint:
		_ocean_tint.color = pal["ocean"] as Color
	## Cache shimmer RGB for _process intensity animation.
	_shimmer_rgb = pal["shimmer"] as Color
	_glisten_base_a = float(pal["glisten_a"])


var _shimmer_rgb: Color = Color(1.0, 0.97, 0.88, 1.0)
var _glisten_base_a: float = 0.72


func _process(delta: float) -> void:
	if not visible:
		return
	_idle += delta
	_tod_refresh += delta
	## Re-evaluate local time about twice a minute (plus forced on ready/layout).
	if _tod_refresh >= 30.0:
		_tod_refresh = 0.0
		_apply_time_of_day(false)
	## Gentle horizon pulse on top of time-of-day base alpha.
	if _horizon_sheen:
		var base_a := _horizon_sheen.color.a
		var pulse := 0.85 + 0.15 * sin(_idle * 0.55)
		_horizon_sheen.color.a = clampf(base_a * pulse, 0.02, 0.22)
	## Soft water-only shimmer: slow sheen drift + gentle breathe (two phases).
	if _water_glisten and _water_clip and size.x > 8.0:
		var breathe_a := _glisten_base_a * (0.88 + 0.20 * sin(_idle * 0.34))
		var sc := _shimmer_rgb
		_water_glisten.modulate = Color(sc.r, sc.g, sc.b, clampf(breathe_a, 0.48, 0.98))
		var drift_a := sin(_idle * 0.14) * size.x * 0.040
		_water_glisten.position.x = -size.x * 0.11 + drift_a
		if _water_glisten_b:
			var breathe_b := _glisten_base_a * (0.58 + 0.24 * sin(_idle * 0.25 + 1.7))
			_water_glisten_b.modulate = Color(
				lerpf(sc.r, 1.0, 0.15),
				lerpf(sc.g, 0.95, 0.15),
				lerpf(sc.b, 0.85, 0.15),
				clampf(breathe_b, 0.32, 0.90)
			)
			var drift_b := sin(_idle * 0.18 + 2.4) * size.x * 0.030
			_water_glisten_b.position.x = -size.x * 0.16 + drift_b
		## Staggered horizontal glints: slow fade in/out + tiny drift.
		## Peaks high enough that 2–4 glints are clearly visible on a Galaxy screen.
		var water_h := _water_clip.size.y
		for i in range(_glints.size()):
			var t := _idle * 0.42 + _glint_phase[i]
			var wave := 0.5 + 0.5 * sin(t)
			var a := lerpf(0.22, 0.88, wave * wave)
			_glints[i].modulate = Color(sc.r, sc.g, sc.b, a)
			var drift := sin(_idle * 0.18 + _glint_phase[i]) * size.x * 0.016
			_glints[i].position.x = size.x * _glint_base_x[i] + drift
			_glints[i].position.y = water_h * _glint_base_y[i]


## Sand contact / ground plane as a fraction of this control's height.
## Main chest host aligns LoveNotesChest foot to this constant (CHEST_GROUND_Y).
## v52: entire assembly nudged one small final step down (feet kiss sand, no bury).
## Delta from v51 0.852 → +0.018 of viewport height (~15px @844).
const CHEST_GROUND_Y := 0.870


func sand_contact_y_frac() -> float:
	## Chest plant target: lower sand plane with room below for ground + nav.
	return CHEST_GROUND_Y
