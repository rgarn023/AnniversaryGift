extends Control
class_name ChestEnvironment
## Modular Chest-screen environment / background.
## Default: romantic twilight beach ("default_beach").
## Chest animation stays a separate layer above this node.
## Future cosmetic swaps can change `environment_id` / texture without
## rewriting the chest frame animation. No store/IAP in this pass.
## v51: stronger water-only horizontal glints (beach art otherwise frozen).

const ENV_DEFAULT_BEACH := "default_beach"
const ENV_DIR := "res://assets/art/background/environments/"
const OCEAN_GLISTEN := ENV_DIR + "ocean_glisten.png"
## Authored beach water band (fraction of environment height).
## Must stay off sky (~above 0.47) and off sand (~below 0.56).
const WATER_TOP_FRAC := 0.470
const WATER_BOTTOM_FRAC := 0.560
## Soft elongated horizontal glints (water-only, staggered).
const GLINT_COUNT := 4

static var _tex_cache: Dictionary = {}
static var _preloaded: bool = false

var environment_id: String = ENV_DEFAULT_BEACH
var _base_fill: ColorRect
var _bg: TextureRect
var _top_shade: ColorRect
var _horizon_sheen: ColorRect
var _water_clip: Control
var _water_glisten: TextureRect
var _water_glisten_b: TextureRect
var _glints: Array[TextureRect] = []
var _glint_phase: PackedFloat32Array = PackedFloat32Array()
var _glint_base_x: PackedFloat32Array = PackedFloat32Array()
var _glint_base_y: PackedFloat32Array = PackedFloat32Array()
var _glint_w: PackedFloat32Array = PackedFloat32Array()
var _ready_visuals: bool = false
var _idle: float = 0.0
const SOFT_GLINT := "res://assets/art/chest/soft_glow_pulse.png"


static func preload_assets() -> void:
	if _preloaded:
		return
	_load_cached(_path_for(ENV_DEFAULT_BEACH))
	_load_cached(OCEAN_GLISTEN)
	_load_cached(SOFT_GLINT)
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


func _build() -> void:
	## Opaque twilight fill so the global starfield never peeks through.
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

	## Soft upper shade for title readability — low alpha so sky has no hard seam.
	_top_shade = ColorRect.new()
	_top_shade.name = "TopReadabilityShade"
	_top_shade.color = Color(0.04, 0.06, 0.12, 0.14)
	_top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_shade)

	## Very subtle horizon sheen (optional depth; cheap ColorRect).
	_horizon_sheen = ColorRect.new()
	_horizon_sheen.name = "HorizonSheen"
	_horizon_sheen.color = Color(1.0, 0.72, 0.45, 0.05)
	_horizon_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_horizon_sheen)

	## Water-only romantic shimmer — clipped so sand/sky/chest stay untouched.
	_water_clip = Control.new()
	_water_clip.name = "OceanGlistenClip"
	_water_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_clip.clip_contents = true
	_water_clip.z_index = 1
	add_child(_water_clip)

	var glisten_tex := _load_cached(OCEAN_GLISTEN)
	_water_glisten = TextureRect.new()
	_water_glisten.name = "OceanGlisten"
	_water_glisten.texture = glisten_tex
	_water_glisten.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_water_glisten.stretch_mode = TextureRect.STRETCH_SCALE
	_water_glisten.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_water_glisten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Noticeable soft sheen — still tasteful, never glitter spam.
	_water_glisten.modulate = Color(1.0, 0.97, 0.88, 0.72)
	_water_clip.add_child(_water_glisten)

	## Second offset glint band — different phase/opacity so shimmer feels alive.
	_water_glisten_b = TextureRect.new()
	_water_glisten_b.name = "OceanGlistenB"
	_water_glisten_b.texture = glisten_tex
	_water_glisten_b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_water_glisten_b.stretch_mode = TextureRect.STRETCH_SCALE
	_water_glisten_b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_water_glisten_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_glisten_b.modulate = Color(1.0, 0.95, 0.84, 0.48)
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
	var widths := [0.20, 0.13, 0.24, 0.16]
	var x_fracs := [0.10, 0.36, 0.56, 0.76]
	var y_fracs := [0.20, 0.46, 0.32, 0.60]
	var phases := [0.0, 1.3, 2.6, 3.9]
	var soft_tex := _load_cached(SOFT_GLINT)
	for i in range(GLINT_COUNT):
		var g := TextureRect.new()
		g.name = "OceanGlint_%d" % i
		g.texture = soft_tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		## Soft warm moonlight streak — elongated soft glow; opacity in _process.
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


func _process(delta: float) -> void:
	if not visible:
		return
	_idle += delta
	## Almost imperceptible horizon pulse — prefer stable beauty over motion noise.
	if _horizon_sheen:
		var pulse := 0.045 + 0.015 * sin(_idle * 0.55)
		_horizon_sheen.color.a = pulse
	## Soft water-only shimmer: slow sheen drift + gentle breathe (two phases).
	if _water_glisten and _water_clip and size.x > 8.0:
		var breathe_a := 0.52 + 0.20 * sin(_idle * 0.34)
		_water_glisten.modulate.a = breathe_a
		var drift_a := sin(_idle * 0.14) * size.x * 0.040
		_water_glisten.position.x = -size.x * 0.11 + drift_a
		if _water_glisten_b:
			var breathe_b := 0.32 + 0.16 * sin(_idle * 0.25 + 1.7)
			_water_glisten_b.modulate.a = breathe_b
			var drift_b := sin(_idle * 0.18 + 2.4) * size.x * 0.030
			_water_glisten_b.position.x = -size.x * 0.16 + drift_b
		## Staggered horizontal glints: slow fade in/out + tiny drift.
		var water_h := _water_clip.size.y
		for i in range(_glints.size()):
			var t := _idle * 0.55 + _glint_phase[i]
			## Period ~2.2s; soft pulse peaks so 2–4 glints are noticeable over time.
			var wave := 0.5 + 0.5 * sin(t)
			var a := lerpf(0.10, 0.55, wave * wave)
			_glints[i].modulate.a = a
			var drift := sin(_idle * 0.22 + _glint_phase[i]) * size.x * 0.012
			_glints[i].position.x = size.x * _glint_base_x[i] + drift
			_glints[i].position.y = water_h * _glint_base_y[i]


## Sand contact / ground plane as a fraction of this control's height.
## Main chest host aligns LoveNotesChest foot to this constant (CHEST_GROUND_Y).
## v51: entire assembly nudged slightly down so feet kiss the sand (no bury).
## Delta from v50 0.828 → +0.024 of viewport height (~20px @844).
const CHEST_GROUND_Y := 0.852


func sand_contact_y_frac() -> float:
	## Chest plant target: lower sand plane with room below for ground + nav.
	return CHEST_GROUND_Y
