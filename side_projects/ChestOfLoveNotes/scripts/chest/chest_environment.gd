extends Control
class_name ChestEnvironment
## Modular Chest-screen environment / background.
## Default: romantic twilight beach ("default_beach").
## Chest animation stays a separate layer above this node.
## Future cosmetic swaps can change `environment_id` / texture without
## rewriting the chest frame animation. No store/IAP in this pass.

const ENV_DEFAULT_BEACH := "default_beach"
const ENV_DIR := "res://assets/art/background/environments/"

static var _tex_cache: Dictionary = {}
static var _preloaded: bool = false

var environment_id: String = ENV_DEFAULT_BEACH
var _base_fill: ColorRect
var _bg: TextureRect
var _top_shade: ColorRect
var _horizon_sheen: ColorRect
var _ready_visuals: bool = false
var _idle: float = 0.0


static func preload_assets() -> void:
	if _preloaded:
		return
	_load_cached(_path_for(ENV_DEFAULT_BEACH))
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

	## Soft upper shade for title / filter readability — not an opaque panel.
	_top_shade = ColorRect.new()
	_top_shade.name = "TopReadabilityShade"
	_top_shade.color = Color(0.04, 0.06, 0.12, 0.28)
	_top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_shade)

	## Very subtle horizon sheen (optional depth; cheap ColorRect).
	_horizon_sheen = ColorRect.new()
	_horizon_sheen.name = "HorizonSheen"
	_horizon_sheen.color = Color(1.0, 0.72, 0.45, 0.05)
	_horizon_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_horizon_sheen)

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
		_top_shade.position = Vector2.ZERO
		_top_shade.size = Vector2(area.x, area.y * 0.18)
	if _horizon_sheen:
		## Horizon sits ~48% down the authored beach art.
		_horizon_sheen.position = Vector2(0.0, area.y * 0.48)
		_horizon_sheen.size = Vector2(area.x, area.y * 0.035)


func _process(delta: float) -> void:
	if not visible or _horizon_sheen == null:
		return
	_idle += delta
	## Almost imperceptible shimmer — prefer stable beauty over motion noise.
	var pulse := 0.045 + 0.015 * sin(_idle * 0.55)
	_horizon_sheen.color.a = pulse


## Sand contact / ground plane as a fraction of this control's height.
## Main chest host aligns LoveNotesChest foot to this constant (CHEST_GROUND_Y).
const CHEST_GROUND_Y := 0.76


func sand_contact_y_frac() -> float:
	## Chest plant target: lower sand plane with room below for ground + nav.
	return CHEST_GROUND_Y
