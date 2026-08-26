extends Control
class_name ChestEnvironment
## Modular Chest-screen environment / background.
## Default: romantic beach ("default_beach") with local-time sky/ocean tint.
## Chest animation stays a separate layer above this node.
## Future cosmetic swaps can change `environment_id` / texture without
## rewriting the chest frame animation. No store/IAP in this pass.
## v56: DAY sky wash is near-opaque so baked dusk beach + moon cannot tint the
## top band twilight; EnvironmentBaseFill + clear_color track opaque sky_top.
## v59: restore continuous rectangular water-band clip (v57). The v58 shoreline
## TextureRect + CLIP_CHILDREN_ONLY mask produced vertical band / tile glitches.
## Shimmer stays one water-only region — no segmented mask panels.
## v60: hold a true DAY keyframe through mid-afternoon (15:30) so 15:34 local
## cannot 80%-blend into the 17:00 sunset palette (moon/orange horizon leak).
## Device-LOCAL via Time.get_datetime_dict_from_system(); resume + periodic TOD.

const ENV_DEFAULT_BEACH := "default_beach"
const ENV_DIR := "res://assets/art/background/environments/"
const OCEAN_GLISTEN := ENV_DIR + "ocean_glisten.png"
## Legacy shoreline mask kept on disk for tooling history only — NOT used at
## runtime (v59). CLIP_CHILDREN_ONLY + cover-stretched mask caused water bands.
const OCEAN_WATER_MASK_LEGACY := ENV_DIR + "ocean_water_mask.png"
const STARFIELD := "res://assets/art/background/starfield.png"
## Authored beach water band (fraction of environment height).
## Must stay off sky (~above 0.47) and off sand (~below 0.56).
const WATER_TOP_FRAC := 0.470
const WATER_BOTTOM_FRAC := 0.560
## Soft elongated horizontal glints (water-only, staggered).
const GLINT_COUNT := 6
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
var _sky_gradient_view: TextureRect
var _sky_gradient_tex: GradientTexture2D
var _sky_gradient: Gradient
var _stars: TextureRect
var _water_clip: Control
var _ocean_tint: ColorRect
var _water_glisten: TextureRect
var _water_glisten_b: TextureRect
var _glints: Array[TextureRect] = []
var _glint_phase: PackedFloat32Array = PackedFloat32Array()
var _glint_base_x: PackedFloat32Array = PackedFloat32Array()
var _glint_base_y: PackedFloat32Array = PackedFloat32Array()
var _glint_w: PackedFloat32Array = PackedFloat32Array()
var _glint_speed: PackedFloat32Array = PackedFloat32Array()
var _glint_drift: PackedFloat32Array = PackedFloat32Array()
var _glint_fade_in: PackedFloat32Array = PackedFloat32Array()
var _glint_fade_out: PackedFloat32Array = PackedFloat32Array()
var _glint_hold: PackedFloat32Array = PackedFloat32Array()
var _glint_wait: PackedFloat32Array = PackedFloat32Array()
var _glint_clock: PackedFloat32Array = PackedFloat32Array()
var _ready_visuals: bool = false
var _idle: float = 0.0
var _tod_refresh: float = 0.0
var _last_hour_bucket: float = -999.0
const SOFT_GLINT := "res://assets/art/chest/soft_glow_pulse.png"
## Lightweight periodic TOD refresh (seconds). Also refreshes on focus/resume.
const TOD_REFRESH_SEC := 60.0

## Time-of-day keyframes (local clock hours). Smooth lerp between neighbors.
## Phases: NIGHT 20–05, DAWN 05–08, DAY 08–17, SUNSET 17–20.
## Late-afternoon DAY hold at 15.5 prevents early sunset wash before 17:00.
const TOD_HOURS := [0.0, 5.0, 6.5, 8.0, 12.0, 15.5, 17.0, 18.5, 20.0, 24.0]


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


static func local_timezone_bias_minutes() -> int:
	## Godot bias = offset from UTC in minutes (matches compose_scroll helper).
	return int(Time.get_time_zone_from_system().get("bias", 0))


static func local_hour_frac() -> float:
	## Device LOCAL wall-clock only — no location permission, no network.
	## Do NOT treat UTC hour components as local (Samsung morning→night bug).
	if debug_hour_override >= 0.0:
		return fposmod(debug_hour_override, 24.0)
	## Primary: Godot system local datetime (same API as compose_scroll_screen.gd).
	## get_datetime_dict_from_system() defaults to local wall-clock, not UTC.
	## Bias-adjusted unix path kept as a consistency cross-check only.
	var local := Time.get_datetime_dict_from_system()
	var hour := (
		float(local.get("hour", 0))
		+ float(local.get("minute", 0)) / 60.0
		+ float(local.get("second", 0)) / 3600.0
	)
	## If system local is unavailable/empty, fall back to bias-adjusted unix.
	if local.is_empty() or not local.has("hour"):
		var bias_min := local_timezone_bias_minutes()
		var unix := int(Time.get_unix_time_from_system())
		var via_bias := Time.get_datetime_dict_from_unix_time(unix + bias_min * 60)
		hour = (
			float(via_bias.get("hour", 0))
			+ float(via_bias.get("minute", 0)) / 60.0
			+ float(via_bias.get("second", 0)) / 3600.0
		)
	return fposmod(hour, 24.0)


static func local_hour_frac_via_bias() -> float:
	## Test/helper: unix + timezone bias → local components (UTC dict + bias).
	var bias_min := local_timezone_bias_minutes()
	var unix := int(Time.get_unix_time_from_system())
	var local := Time.get_datetime_dict_from_unix_time(unix + bias_min * 60)
	return fposmod(
		float(local.get("hour", 0))
		+ float(local.get("minute", 0)) / 60.0
		+ float(local.get("second", 0)) / 3600.0,
		24.0
	)


static func tod_palette_at(hour: float) -> Dictionary:
	## Lightweight keyframe interpolation for sky / ocean / stars / shimmer.
	## Multi-stop sky colors feed ONE continuous GradientTexture2D (no hard bands).
	var h := fposmod(hour, 24.0)
	## Palette: base, sky stops (top→mid→lower→horizon), bg_mod, ocean, shimmer, star_a
	var keys := [
		{ ## 00:00 deep night
			"base": Color(0.03, 0.04, 0.12, 1.0),
			"sky_top": Color(0.04, 0.05, 0.16, 0.72),
			"sky_mid": Color(0.07, 0.07, 0.22, 0.55),
			"sky_lower": Color(0.10, 0.08, 0.26, 0.38),
			"sky_horizon": Color(0.14, 0.10, 0.28, 0.22),
			"bg_mod": Color(0.72, 0.74, 0.92, 1.0),
			"ocean": Color(0.20, 0.22, 0.48, 0.34),
			"shimmer": Color(0.78, 0.88, 1.0, 1.0),
			"star_a": 0.85,
			"glisten_a": 0.58,
		},
		{ ## 05:00 night → dawn
			"base": Color(0.05, 0.05, 0.14, 1.0),
			"sky_top": Color(0.08, 0.07, 0.22, 0.55),
			"sky_mid": Color(0.22, 0.14, 0.32, 0.42),
			"sky_lower": Color(0.48, 0.28, 0.38, 0.36),
			"sky_horizon": Color(0.72, 0.42, 0.40, 0.28),
			"bg_mod": Color(0.82, 0.78, 0.90, 1.0),
			"ocean": Color(0.35, 0.30, 0.48, 0.26),
			"shimmer": Color(1.0, 0.90, 0.82, 1.0),
			"star_a": 0.45,
			"glisten_a": 0.62,
		},
		{ ## 06:30 mid dawn
			"base": Color(0.12, 0.08, 0.16, 1.0),
			"sky_top": Color(0.18, 0.14, 0.34, 0.36),
			"sky_mid": Color(0.42, 0.28, 0.48, 0.32),
			"sky_lower": Color(0.85, 0.52, 0.50, 0.34),
			"sky_horizon": Color(0.98, 0.68, 0.52, 0.30),
			"bg_mod": Color(0.96, 0.90, 0.88, 1.0),
			"ocean": Color(0.55, 0.42, 0.52, 0.22),
			"shimmer": Color(1.0, 0.92, 0.82, 1.0),
			"star_a": 0.12,
			"glisten_a": 0.66,
		},
		{ ## 08:00 day start — near-opaque wash so baked dusk/moon cannot show.
			"base": Color(0.30, 0.48, 0.72, 1.0),
			"sky_top": Color(0.36, 0.62, 0.96, 1.0),
			"sky_mid": Color(0.50, 0.74, 0.98, 0.98),
			"sky_lower": Color(0.68, 0.86, 1.0, 0.92),
			"sky_horizon": Color(0.82, 0.92, 1.0, 0.78),
			"bg_mod": Color(1.10, 1.08, 1.04, 1.0),
			"ocean": Color(0.22, 0.55, 0.78, 0.22),
			"shimmer": Color(1.0, 0.98, 0.90, 1.0),
			"star_a": 0.0,
			"glisten_a": 0.82,
		},
		{ ## 12:00 midday — opaque top sky; continuous blue to the viewport edge.
			"base": Color(0.34, 0.55, 0.82, 1.0),
			"sky_top": Color(0.30, 0.58, 0.98, 1.0),
			"sky_mid": Color(0.46, 0.74, 1.0, 0.99),
			"sky_lower": Color(0.64, 0.86, 1.0, 0.94),
			"sky_horizon": Color(0.80, 0.92, 1.0, 0.80),
			"bg_mod": Color(1.12, 1.10, 1.06, 1.0),
			"ocean": Color(0.18, 0.58, 0.84, 0.20),
			"shimmer": Color(1.0, 0.99, 0.92, 1.0),
			"star_a": 0.0,
			"glisten_a": 0.90,
		},
		{ ## 15:30 late-afternoon DAY hold — still clearly day at ~15:34.
			## Very subtle warm horizon only; moon/stars stay fully hidden; sky
			## wash stays opaque so baked crescent in default_beach.png cannot show.
			"base": Color(0.36, 0.56, 0.84, 1.0),
			"sky_top": Color(0.32, 0.60, 0.98, 1.0),
			"sky_mid": Color(0.50, 0.76, 1.0, 1.0),
			"sky_lower": Color(0.70, 0.88, 1.0, 0.98),
			"sky_horizon": Color(0.88, 0.94, 0.98, 0.90),
			"bg_mod": Color(1.10, 1.08, 1.04, 1.0),
			"ocean": Color(0.20, 0.56, 0.80, 0.20),
			"shimmer": Color(1.0, 0.98, 0.90, 1.0),
			"star_a": 0.0,
			"glisten_a": 0.88,
		},
		{ ## 17:00 sunset start — sunset colors begin here, not during DAY.
			"base": Color(0.22, 0.28, 0.48, 1.0),
			"sky_top": Color(0.28, 0.42, 0.78, 0.96),
			"sky_mid": Color(0.48, 0.40, 0.70, 0.90),
			"sky_lower": Color(0.88, 0.52, 0.48, 0.78),
			"sky_horizon": Color(0.98, 0.62, 0.40, 0.62),
			"bg_mod": Color(1.08, 1.00, 0.96, 1.0),
			"ocean": Color(0.40, 0.42, 0.62, 0.22),
			"shimmer": Color(1.0, 0.90, 0.72, 1.0),
			"star_a": 0.0,
			"glisten_a": 0.78,
		},
		{ ## 18:30 mid sunset
			"base": Color(0.10, 0.06, 0.16, 1.0),
			"sky_top": Color(0.12, 0.08, 0.28, 0.48),
			"sky_mid": Color(0.28, 0.12, 0.36, 0.42),
			"sky_lower": Color(0.82, 0.30, 0.42, 0.38),
			"sky_horizon": Color(0.95, 0.40, 0.42, 0.32),
			"bg_mod": Color(0.92, 0.80, 0.88, 1.0),
			"ocean": Color(0.42, 0.22, 0.48, 0.28),
			"shimmer": Color(1.0, 0.75, 0.70, 1.0),
			"star_a": 0.28,
			"glisten_a": 0.66,
		},
		{ ## 20:00 night start
			"base": Color(0.04, 0.05, 0.14, 1.0),
			"sky_top": Color(0.05, 0.05, 0.18, 0.68),
			"sky_mid": Color(0.08, 0.07, 0.24, 0.52),
			"sky_lower": Color(0.14, 0.10, 0.28, 0.36),
			"sky_horizon": Color(0.20, 0.12, 0.30, 0.24),
			"bg_mod": Color(0.75, 0.76, 0.92, 1.0),
			"ocean": Color(0.22, 0.22, 0.48, 0.32),
			"shimmer": Color(0.80, 0.88, 1.0, 1.0),
			"star_a": 0.70,
			"glisten_a": 0.58,
		},
		{ ## 24:00 = 00:00
			"base": Color(0.03, 0.04, 0.12, 1.0),
			"sky_top": Color(0.04, 0.05, 0.16, 0.72),
			"sky_mid": Color(0.07, 0.07, 0.22, 0.55),
			"sky_lower": Color(0.10, 0.08, 0.26, 0.38),
			"sky_horizon": Color(0.14, 0.10, 0.28, 0.22),
			"bg_mod": Color(0.72, 0.74, 0.92, 1.0),
			"ocean": Color(0.20, 0.22, 0.48, 0.34),
			"shimmer": Color(0.78, 0.88, 1.0, 1.0),
			"star_a": 0.85,
			"glisten_a": 0.58,
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
	## Smoothstep for softer phase blends (no hard jumps / palette swaps).
	t = t * t * (3.0 - 2.0 * t)
	var a: Dictionary = keys[i0]
	var b: Dictionary = keys[i0 + 1]
	return {
		"base": (a["base"] as Color).lerp(b["base"] as Color, t),
		"sky_top": (a["sky_top"] as Color).lerp(b["sky_top"] as Color, t),
		"sky_mid": (a["sky_mid"] as Color).lerp(b["sky_mid"] as Color, t),
		"sky_lower": (a["sky_lower"] as Color).lerp(b["sky_lower"] as Color, t),
		"sky_horizon": (a["sky_horizon"] as Color).lerp(b["sky_horizon"] as Color, t),
		"bg_mod": (a["bg_mod"] as Color).lerp(b["bg_mod"] as Color, t),
		"ocean": (a["ocean"] as Color).lerp(b["ocean"] as Color, t),
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


func _notification(what: int) -> void:
	## Refresh local time when the app resumes / regains focus (not only at boot).
	if what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN \
			or what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible and is_visible_in_tree():
			_tod_refresh = 0.0
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

	## Sky-only continuous gradient + stars (clipped so sand/chest stay untouched).
	## v53: ONE GradientTexture2D replaces the prior stacked hard-edged sky
	## ColorRects that produced visible horizontal color bands.
	_sky_clip = Control.new()
	_sky_clip.name = "SkyTimeClip"
	_sky_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_clip.clip_contents = true
	_sky_clip.z_index = 0
	add_child(_sky_clip)

	_sky_gradient = Gradient.new()
	_sky_gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.68, 1.0])
	_sky_gradient.colors = PackedColorArray([
		Color(0.05, 0.06, 0.18, 0.55),
		Color(0.10, 0.10, 0.28, 0.40),
		Color(0.30, 0.20, 0.40, 0.28),
		Color(0.50, 0.35, 0.40, 0.18),
	])
	_sky_gradient_tex = GradientTexture2D.new()
	_sky_gradient_tex.gradient = _sky_gradient
	_sky_gradient_tex.fill = GradientTexture2D.FILL_LINEAR
	_sky_gradient_tex.fill_from = Vector2(0.5, 0.0)
	_sky_gradient_tex.fill_to = Vector2(0.5, 1.0)
	_sky_gradient_tex.width = 4
	_sky_gradient_tex.height = 256

	_sky_gradient_view = TextureRect.new()
	_sky_gradient_view.name = "SkyContinuousGradient"
	_sky_gradient_view.texture = _sky_gradient_tex
	_sky_gradient_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky_gradient_view.stretch_mode = TextureRect.STRETCH_SCALE
	_sky_gradient_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sky_gradient_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_clip.add_child(_sky_gradient_view)

	_stars = TextureRect.new()
	_stars.name = "SkyStars"
	_stars.texture = _load_cached(STARFIELD)
	_stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_stars.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars.modulate = Color(1, 1, 1, 0.0)
	_sky_clip.add_child(_stars)

	## Top readability ColorRect removed (was a hard band). Title readability
	## uses the label outline/shadow only; sky gradient continues to the top edge.
	## v56: day sky_top alpha=1 + base_fill/clear sync — no dark beach bleed strip.

	## Water-only romantic shimmer — one continuous rectangular water band.
	## clip_contents keeps tint/glisten/glints inside water only (no sand/sky).
	## No shoreline TextureRect mask / CLIP_CHILDREN_ONLY (v58 band glitch).
	_water_clip = Control.new()
	_water_clip.name = "OceanGlistenClip"
	_water_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_clip.clip_contents = true
	_water_clip.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
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
	## Soft sheen base — discrete glints carry the "alive" motion.
	_water_glisten.modulate = Color(1.0, 0.97, 0.88, 0.55)
	_water_clip.add_child(_water_glisten)

	## Second offset glint band — different phase/opacity so shimmer feels alive.
	_water_glisten_b = TextureRect.new()
	_water_glisten_b.name = "OceanGlistenB"
	_water_glisten_b.texture = glisten_tex
	_water_glisten_b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_water_glisten_b.stretch_mode = TextureRect.STRETCH_SCALE
	_water_glisten_b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_water_glisten_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_glisten_b.modulate = Color(1.0, 0.95, 0.84, 0.38)
	_water_clip.add_child(_water_glisten_b)

	## Discrete soft horizontal streaks — independent fade/drift cycles (not synced).
	_glints.clear()
	_glint_phase = PackedFloat32Array()
	_glint_base_x = PackedFloat32Array()
	_glint_base_y = PackedFloat32Array()
	_glint_w = PackedFloat32Array()
	_glint_speed = PackedFloat32Array()
	_glint_drift = PackedFloat32Array()
	_glint_fade_in = PackedFloat32Array()
	_glint_fade_out = PackedFloat32Array()
	_glint_hold = PackedFloat32Array()
	_glint_wait = PackedFloat32Array()
	_glint_clock = PackedFloat32Array()
	_glint_phase.resize(GLINT_COUNT)
	_glint_base_x.resize(GLINT_COUNT)
	_glint_base_y.resize(GLINT_COUNT)
	_glint_w.resize(GLINT_COUNT)
	_glint_speed.resize(GLINT_COUNT)
	_glint_drift.resize(GLINT_COUNT)
	_glint_fade_in.resize(GLINT_COUNT)
	_glint_fade_out.resize(GLINT_COUNT)
	_glint_hold.resize(GLINT_COUNT)
	_glint_wait.resize(GLINT_COUNT)
	_glint_clock.resize(GLINT_COUNT)
	var widths := [0.24, 0.14, 0.28, 0.16, 0.22, 0.18]
	var x_fracs := [0.06, 0.26, 0.44, 0.62, 0.78, 0.90]
	var y_fracs := [0.16, 0.40, 0.26, 0.52, 0.34, 0.60]
	var phases := [0.0, 1.15, 2.40, 3.55, 4.80, 5.90]
	var speeds := [0.38, 0.52, 0.44, 0.60, 0.34, 0.48]
	var drifts := [0.018, 0.012, 0.022, 0.014, 0.020, 0.010]
	## Per-glint cycle timings (seconds) — staggered so they never pulse together.
	var fade_ins := [0.85, 1.15, 0.70, 1.30, 0.95, 1.05]
	var fade_outs := [1.10, 0.85, 1.40, 0.95, 1.25, 1.00]
	var holds := [0.35, 0.20, 0.45, 0.15, 0.30, 0.25]
	var waits := [1.80, 2.40, 1.20, 2.90, 1.55, 2.10]
	var clocks := [0.0, 1.6, 3.2, 0.8, 4.1, 2.5]
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
		_glint_speed[i] = speeds[i]
		_glint_drift[i] = drifts[i]
		_glint_fade_in[i] = fade_ins[i]
		_glint_fade_out[i] = fade_outs[i]
		_glint_hold[i] = holds[i]
		_glint_wait[i] = waits[i]
		_glint_clock[i] = clocks[i]

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
		if _sky_gradient_view:
			_sky_gradient_view.position = Vector2.ZERO
			_sky_gradient_view.size = Vector2(area.x, sky_h)
		if _stars:
			_stars.position = Vector2.ZERO
			_stars.size = Vector2(area.x, sky_h)
	if _water_clip and _water_glisten:
		var water_top := area.y * WATER_TOP_FRAC
		var water_h := area.y * (WATER_BOTTOM_FRAC - WATER_TOP_FRAC)
		## Single continuous water strip — children are local to this clip.
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
			var gh := maxf(3.0, water_h * 0.16)
			_glints[i].size = Vector2(gw, gh)
			_glints[i].position = Vector2(
				area.x * _glint_base_x[i],
				water_h * _glint_base_y[i]
			)


func _apply_sky_gradient(pal: Dictionary) -> void:
	if _sky_gradient == null:
		return
	## Four smooth stops — top → mid → lower → horizon. No hard horizontal seams.
	_sky_gradient.set_color(0, pal["sky_top"] as Color)
	_sky_gradient.set_color(1, pal["sky_mid"] as Color)
	_sky_gradient.set_color(2, pal["sky_lower"] as Color)
	_sky_gradient.set_color(3, pal["sky_horizon"] as Color)
	_sky_gradient.set_offset(0, 0.0)
	_sky_gradient.set_offset(1, 0.32)
	_sky_gradient.set_offset(2, 0.68)
	_sky_gradient.set_offset(3, 1.0)


func _apply_time_of_day(force: bool = false) -> void:
	var hour := local_hour_frac()
	## Refresh when the minute bucket changes (or forced). Cheap — no allocations.
	var bucket := floorf(hour * 60.0)
	if not force and absf(bucket - _last_hour_bucket) < 0.5:
		return
	_last_hour_bucket = bucket
	var pal := tod_palette_at(hour)
	var sky_top := pal["sky_top"] as Color
	## Exact top-strip source (v55 leftover): EnvironmentBaseFill was a different
	## navy/blue than the semi-transparent sky+dusk-beach composite, so the top
	## edge (and any status-bar/clear underlap) read as a darker horizontal band.
	## Fix: opaque underfill = opaque sky_top RGB; sync engine clear color too.
	var top_fill := Color(sky_top.r, sky_top.g, sky_top.b, 1.0)
	if _base_fill:
		_base_fill.color = top_fill
	## Keep Android/status underlap matching current sky-top (not a fixed navy).
	RenderingServer.set_default_clear_color(top_fill)
	if _bg:
		_bg.modulate = pal["bg_mod"] as Color
	## DAY hard rule: keep sky wash near-opaque so baked beach moon cannot show.
	var phase := str(pal.get("phase", ""))
	if phase == "day":
		var st := pal["sky_top"] as Color
		var sm := pal["sky_mid"] as Color
		var sl := pal["sky_lower"] as Color
		var sh := pal["sky_horizon"] as Color
		pal["sky_top"] = Color(st.r, st.g, st.b, maxf(st.a, 0.98))
		pal["sky_mid"] = Color(sm.r, sm.g, sm.b, maxf(sm.a, 0.96))
		pal["sky_lower"] = Color(sl.r, sl.g, sl.b, maxf(sl.a, 0.92))
		pal["sky_horizon"] = Color(sh.r, sh.g, sh.b, maxf(sh.a, 0.85))
		pal["star_a"] = 0.0
		sky_top = pal["sky_top"] as Color
		top_fill = Color(sky_top.r, sky_top.g, sky_top.b, 1.0)
		if _base_fill:
			_base_fill.color = top_fill
		RenderingServer.set_default_clear_color(top_fill)
	_apply_sky_gradient(pal)
	if _stars:
		var sa := float(pal["star_a"])
		## HARD RULE: DAY keeps moon/stars fully off (no partial / stale residue).
		if phase == "day":
			sa = 0.0
		_stars.modulate = Color(1.0, 1.0, 1.05, sa)
		## DAY: fully hidden (no moon/starfield). Dawn/sunset interpolate via alpha.
		## Baked moon in beach art is covered by opaque day sky wash.
		_stars.visible = sa > 0.01
	if _ocean_tint:
		_ocean_tint.color = pal["ocean"] as Color
	## Cache shimmer RGB for _process intensity animation.
	_shimmer_rgb = pal["shimmer"] as Color
	_glisten_base_a = float(pal["glisten_a"])


var _shimmer_rgb: Color = Color(1.0, 0.97, 0.88, 1.0)
var _glisten_base_a: float = 0.72


func _glint_alpha_at(i: int) -> float:
	## Independent cycle: wait → fade in → brief hold → fade out → wait.
	## More motion than brightness — peak alpha stays restrained.
	var fade_in := maxf(_glint_fade_in[i], 0.05)
	var hold := maxf(_glint_hold[i], 0.01)
	var fade_out := maxf(_glint_fade_out[i], 0.05)
	var wait := maxf(_glint_wait[i], 0.05)
	var cycle := fade_in + hold + fade_out + wait
	var t := fposmod(_glint_clock[i], cycle)
	if t < wait:
		return 0.0
	t -= wait
	if t < fade_in:
		var u := t / fade_in
		u = u * u * (3.0 - 2.0 * u)
		return lerpf(0.0, 0.72, u)
	t -= fade_in
	if t < hold:
		return 0.72
	t -= hold
	if t < fade_out:
		var v := t / fade_out
		v = v * v * (3.0 - 2.0 * v)
		return lerpf(0.72, 0.0, v)
	return 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_idle += delta
	_tod_refresh += delta
	## Re-evaluate local time about once a minute (plus forced on ready/resume).
	if _tod_refresh >= TOD_REFRESH_SEC:
		_tod_refresh = 0.0
		_apply_time_of_day(false)
	## Soft water-only shimmer: slow sheen drift + independently fading glints.
	## All children are local to the single continuous water clip.
	if _water_glisten and _water_clip and size.x > 8.0:
		var breathe_a := _glisten_base_a * (0.42 + 0.18 * sin(_idle * 0.30))
		var sc := _shimmer_rgb
		_water_glisten.modulate = Color(sc.r, sc.g, sc.b, clampf(breathe_a, 0.28, 0.72))
		var drift_a := sin(_idle * 0.14) * size.x * 0.040
		_water_glisten.position.x = -size.x * 0.11 + drift_a
		_water_glisten.position.y = 0.0
		if _water_glisten_b:
			var breathe_b := _glisten_base_a * (0.28 + 0.16 * sin(_idle * 0.22 + 1.7))
			_water_glisten_b.modulate = Color(
				lerpf(sc.r, 1.0, 0.15),
				lerpf(sc.g, 0.95, 0.15),
				lerpf(sc.b, 0.85, 0.15),
				clampf(breathe_b, 0.18, 0.58)
			)
			var drift_b := sin(_idle * 0.18 + 2.4) * size.x * 0.030
			_water_glisten_b.position.x = -size.x * 0.16 + drift_b
			_water_glisten_b.position.y = _water_clip.size.y * 0.04
		## Independent fade/drift per glint — not a synced sine pulse.
		var water_h := _water_clip.size.y
		for i in range(_glints.size()):
			_glint_clock[i] = _glint_clock[i] + delta
			var a := _glint_alpha_at(i)
			_glints[i].modulate = Color(sc.r, sc.g, sc.b, a)
			## Horizontal drift only while visible — a few pixels, staggered phase.
			var drift := sin(_idle * 0.22 + _glint_phase[i]) * size.x * _glint_drift[i]
			var y_drift := sin(_idle * 0.13 + _glint_phase[i] * 0.7) * water_h * 0.035
			_glints[i].position.x = size.x * _glint_base_x[i] + drift
			_glints[i].position.y = clampf(
				water_h * _glint_base_y[i] + y_drift,
				0.0,
				maxf(0.0, water_h - _glints[i].size.y)
			)


## Sand contact / ground plane as a fraction of this control's height.
## Main chest host aligns LoveNotesChest foot to this constant (CHEST_GROUND_Y).
## v53: entire assembly nudged ~15px closer to sand (@844 → +0.018) from v52 0.870.
## Feet kiss sand with no bury / no hover gap.
const CHEST_GROUND_Y := 0.888


func sand_contact_y_frac() -> float:
	## Chest plant target: lower sand plane with room below for ground + nav.
	return CHEST_GROUND_Y
