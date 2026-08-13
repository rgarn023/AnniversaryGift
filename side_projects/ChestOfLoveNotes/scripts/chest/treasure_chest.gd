extends Control
class_name LoveNotesChest
## animation_v2 approved 13-frame chest opening (v48).
## Empty + unread share the same smooth multi-frame open (#00→#12).
## No chest crossfade / alpha fade / ghost duplicate — exactly ONE visible chest
## frame at any instant. Unread then switches cleanly to open-back + scroll +
## front-rim layering for a continuous Y-tweened scroll rise.
## Legacy PATH B / glowing-sheet frames are never used at runtime.

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged(global_pos: Vector2)
## Future audio hooks (no assets required this pass).
signal sfx_open_start
signal sfx_latch_release
signal sfx_fully_open
signal sfx_magical_swell
signal sfx_scroll_emerge

## Explicit state machine — prevent overlapping opens / duplicate scrolls.
enum ChestState {
	LOCKED_SILHOUETTE,
	AVAILABLE, ## CLOSED
	OPENING,
	OPEN_EMPTY,
	OPEN_WAITING_FOR_SCROLL,
	OPEN_SCROLL_EMERGING,
	OPENED, ## compat alias for empty-open
	READY,
	CLOSING,
	TRANSITIONING,
}

## Approved production package — never fall back to legacy frames/sheets.
const ANIM_V2 := "res://assets/chest/animation_v2/"
const CHEST_FRAMES_DIR := ANIM_V2 + "chest_frames/"
const OPEN_BACK := ANIM_V2 + "layers/chest_open_back.png"
const FRONT_RIM := ANIM_V2 + "layers/chest_open_front_rim.png"
const SCROLL_LAYER := ANIM_V2 + "scroll/love_scroll.png"
const SOFT_GLOW := "res://assets/art/chest/soft_glow_pulse.png"
const CONTACT_SHADOW := "res://assets/art/chest/chest_contact_shadow.png"
const WARM_SPILL := "res://assets/art/chest/chest_warm_spill.png"
## animation_v2 production canvas (base anchor 256,420).
const FRAME_CANVAS := Vector2(512, 512)
## Absolute plant row in authored frames (matches animation_manifest base_anchor.y).
const CHEST_FOOT_CANVAS_Y := 420.0
## Foot as fraction of FRAME_CANVAS height — scene grounding uses this.
const CHEST_FOOT_Y_FRAC := CHEST_FOOT_CANVAS_Y / 512.0
## Full approved opening sequence #00–#12.
const CHEST_FRAME_COUNT := 13
## Compat aliases (tests / older callers).
const EMPTY_FRAME_COUNT := CHEST_FRAME_COUNT
const SCROLL_FRAME_COUNT := 0
## Smooth premium open — restrained start, accelerate mid, ease into fully open.
const OPEN_DURATION_SEC := 1.0
const OPEN_DURATION_RM := 0.42
const ANTICIPATION_SEC := 0.06
const SETTLE_SEC := 0.10
const MAGICAL_SWELL_SEC := 0.10
## Scroll emerge after open — continuous Y: peek→25%→50%→70%→final.
const SCROLL_EMERGE_SEC := 1.20
## Intentional hold on the completed reward pose before note handoff.
const REWARD_HOLD_SEC := 0.45
## Tiny settle pulse only — must not read as the chest growing while opening.
const EMPHASIS_SCALE := 1.002
## Progress split when sampling combined unread progress (validation / short path).
const SCROLL_REVEAL_START_PROGRESS := 0.48
## Compat index marker (legacy baked scroll frames; runtime uses layers).
const SCROLL_REVEAL_START_INDEX := 2
## Native scroll art size (love_scroll.png).
const SCROLL_NATIVE := Vector2(56, 132)
## Canvas-space cavity / rim geometry (matches prepare_animation_v2_assets).
const CAVITY_RIM_CANVAS_Y := 285.0
## Final reward: ~65% of scroll body above the front rim.
const SCROLL_FINAL_ABOVE_RIM := 0.65
const SCROLL_PEEK_ABOVE_RIM := 0.12
## Soft glow peaks — restrained warm accent; never washes out rim/scroll/wood.
const GLOW_OPEN_A := 0.018
const GLOW_SETTLE_A := 0.028
const GLOW_RETAP_A := 0.036
const GLOW_REWARD_HOLD_A := 0.016
const GLOW_MID_A := 0.022
## Per-frame dwell weights — restrained start, smooth mid accel, soft finish.
## Sum-normalized against OPEN_DURATION_SEC; no pauses between frames.
const OPEN_POSE_WEIGHTS := [
	1.20, ## 00 closed
	0.95, ## 01 8%
	0.90, ## 02 17%
	0.85, ## 03 25%
	0.82, ## 04 33%
	0.80, ## 05 42%
	0.80, ## 06 50%
	0.85, ## 07 58%
	0.90, ## 08 67%
	0.95, ## 09 75%
	1.00, ## 10 83%
	1.10, ## 11 92%
	1.20, ## 12 fully open
]
## Exact approved filenames in order.
const CHEST_FRAME_FILES := [
	"chest_00_closed.png",
	"chest_01_open_08.png",
	"chest_02_open_17.png",
	"chest_03_open_25.png",
	"chest_04_open_33.png",
	"chest_05_open_42.png",
	"chest_06_open_50.png",
	"chest_07_open_58.png",
	"chest_08_open_67.png",
	"chest_09_open_75.png",
	"chest_10_open_83.png",
	"chest_11_open_92.png",
	"chest_12_fully_open.png",
]

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _input_locked: bool = false
var _label: Label
var _root_visual: Control
var _shadow_view: TextureRect
var _warm_spill: TextureRect
var _frame_view: TextureRect
var _scroll_clip: Control
var _scroll_view: TextureRect
var _rim_view: TextureRect
var _glow_pulse: TextureRect
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _motes: CPUParticles2D
var _button: Button
var _ready_visuals: bool = false
var _badge: Label
var _unread_count: int = 0
var _badge_suppressed: bool = false
var _open_amount: float = 0.0
var _scroll_rise: float = 0.0
var _show_scroll_on_finish: bool = false
var _layered_open: bool = false
var _anchor_rect: Rect2 = Rect2()
var _anticipation_y: float = 0.0
var _emphasis_scale: float = 1.0
var _particles_armed: bool = false
var _chest_frames: Array[Texture2D] = []
var _empty_frames: Array[Texture2D] = [] ## alias of _chest_frames
var _scroll_frames: Array[Texture2D] = [] ## unused at runtime (compat)
var _active_frames: Array[Texture2D] = []
var _frame_index: int = 0
var _scroll_emerged_emitted: bool = false
var _scroll_layer_tex: Texture2D = null
var _rim_layer_tex: Texture2D = null
var _open_back_tex: Texture2D = null
var _shadow_tex: Texture2D = null
var _fit_scale: float = 1.0

## Process-wide preload so the first tap never decompresses textures.
static var _tex_cache: Dictionary = {}
static var _chest_cache: Array = []
static var _empty_cache: Array = [] ## alias
static var _scroll_cache: Array = []
static var _preloaded: bool = false
static var _sprite_frames_empty: SpriteFrames = null
static var _sprite_frames_scroll: SpriteFrames = null
static var _open_weight_ends: PackedFloat32Array = PackedFloat32Array()


static func preload_assets() -> void:
	if _preloaded:
		return
	_chest_cache = _load_chest_sequence()
	_empty_cache = _chest_cache
	_scroll_cache = []
	_load_cached(SOFT_GLOW)
	_load_cached(SCROLL_LAYER)
	_load_cached(FRONT_RIM)
	_load_cached(OPEN_BACK)
	_load_cached(CONTACT_SHADOW)
	_load_cached(WARM_SPILL)
	_open_weight_ends = _build_open_weight_ends()
	_sprite_frames_empty = _build_sprite_frames("empty_open", _chest_cache, 13.0)
	_sprite_frames_scroll = null
	_preloaded = true


static func _load_chest_sequence() -> Array:
	var out: Array = []
	for fname in CHEST_FRAME_FILES:
		out.append(_load_cached(CHEST_FRAMES_DIR + String(fname)))
	return out


static func _build_open_weight_ends() -> PackedFloat32Array:
	var ends := PackedFloat32Array()
	ends.resize(OPEN_POSE_WEIGHTS.size())
	var total := 0.0
	for w in OPEN_POSE_WEIGHTS:
		total += float(w)
	var acc := 0.0
	for i in range(OPEN_POSE_WEIGHTS.size()):
		acc += float(OPEN_POSE_WEIGHTS[i]) / total
		ends[i] = acc
	if ends.size() > 0:
		ends[ends.size() - 1] = 1.0
	return ends


static func _build_sprite_frames(anim_name: String, textures: Array, fps: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, false)
	for tex in textures:
		if tex != null:
			sf.add_frame(anim_name, tex as Texture2D)
	return sf


static func _load_cached(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(220, 260)
	## Physical chest never fades — only glow/particles/shadow may be translucent.
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	visible = true
	preload_assets()
	_chest_frames.clear()
	_empty_frames.clear()
	_scroll_frames.clear()
	for t in _chest_cache:
		_chest_frames.append(t as Texture2D)
	_empty_frames = _chest_frames
	_scroll_layer_tex = _load_cached(SCROLL_LAYER)
	_rim_layer_tex = _load_cached(FRONT_RIM)
	_open_back_tex = _load_cached(OPEN_BACK)
	_shadow_tex = _load_cached(CONTACT_SHADOW)
	_build_visuals()
	_ready_visuals = true
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = "Open your chest"
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	set_process(not reduced_motion)
	resized.connect(_layout_frames)
	_layout_frames()
	_set_frame_progress(0.0, false)
	_enforce_chest_opaque()


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.name = "ChestAnimationRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_visual.clip_contents = false
	add_child(_root_visual)

	## Soft contact shadow under the planted foot — grounds the chest on sand.
	_shadow_view = TextureRect.new()
	_shadow_view.name = "ChestContactShadow"
	_shadow_view.texture = _shadow_tex
	_shadow_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow_view.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shadow_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Soft / restrained — never a hard blot that reads as a hover gap.
	_shadow_view.modulate = Color(1, 1, 1, 0.82)
	_shadow_view.z_index = 1
	_root_visual.add_child(_shadow_view)

	## Tiny warm magical spill on sand — separate from the dark contact shadow.
	_warm_spill = TextureRect.new()
	_warm_spill.name = "ChestWarmSpill"
	_warm_spill.texture = _load_cached(WARM_SPILL)
	_warm_spill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_warm_spill.stretch_mode = TextureRect.STRETCH_SCALE
	_warm_spill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_warm_spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warm_spill.modulate = Color(1, 1, 1, 0.0)
	_warm_spill.z_index = 2
	_root_visual.add_child(_warm_spill)

	## Exactly ONE opaque chest sprite — no duplicate underlay / crossfade layers.
	_frame_view = TextureRect.new()
	_frame_view.name = "ChestFrame"
	_frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## No mipmaps at draw time — keep wood/gold edges crisp while opening.
	_frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_view.modulate = Color(1, 1, 1, 1)
	_frame_view.self_modulate = Color(1, 1, 1, 1)
	_frame_view.z_index = 3
	_root_visual.add_child(_frame_view)

	## Cavity clip — scroll rises between open-back and front-rim.
	## Clip keeps sides tidy; front rim is the authoritative lower occluder.
	_scroll_clip = Control.new()
	_scroll_clip.name = "ScrollCavityClip"
	_scroll_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_clip.clip_contents = true
	_scroll_clip.z_index = 4
	_scroll_clip.visible = false
	_root_visual.add_child(_scroll_clip)

	## Separate vertical love-note scroll — rises inside the clipped cavity.
	_scroll_view = TextureRect.new()
	_scroll_view.name = "ScrollLayer"
	_scroll_view.texture = _scroll_layer_tex
	_scroll_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scroll_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_scroll_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_scroll_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_view.modulate = Color(1, 1, 1, 1)
	_scroll_view.visible = true
	_scroll_clip.add_child(_scroll_view)

	## Front-rim occlusion layer derived from approved fully-open frame #12.
	_rim_view = TextureRect.new()
	_rim_view.name = "ChestFrontRim"
	_rim_view.texture = _rim_layer_tex
	_rim_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rim_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rim_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rim_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim_view.modulate = Color(1, 1, 1, 1)
	_rim_view.z_index = 5
	_rim_view.visible = false
	_root_visual.add_child(_rim_view)

	## Soft radial pulse — never a rectangular ColorRect (that read as a white box).
	_glow_pulse = TextureRect.new()
	_glow_pulse.name = "GlowPulse"
	_glow_pulse.texture = _load_cached(SOFT_GLOW)
	_glow_pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow_pulse.stretch_mode = TextureRect.STRETCH_SCALE
	_glow_pulse.modulate = Color(1.0, 0.82, 0.48, 0.0)
	_glow_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_pulse.z_index = 6
	_root_visual.add_child(_glow_pulse)

	_dust = _make_particles(Color(0.90, 0.78, 0.48, 0.28), 3, Vector2(0, -1), 12.0, 0.65)
	_dust.z_index = 7
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.84, 0.48, 0.34), 2, Vector2(0, -1), 18.0, 0.50)
	_sparks.z_index = 7
	_root_visual.add_child(_sparks)
	_motes = _make_particles(Color(1.0, 0.86, 0.55, 0.24), 4, Vector2(0, -1), 9.0, 1.0)
	_motes.one_shot = false
	_motes.explosiveness = 0.0
	_motes.z_index = 7
	_root_visual.add_child(_motes)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 15)
	_badge.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1))
	_badge.visible = false
	_badge.z_index = 20
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 17)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 12
	add_child(_label)

	_active_frames = _chest_frames
	_show_frame_index(0)


func _make_particles(
	color: Color,
	amount: int,
	dir: Vector2,
	speed: float,
	lifetime: float = 0.55
) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.15
	p.local_coords = true
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = speed * 0.10
	p.initial_velocity_max = speed * 0.42
	p.gravity = Vector2(0, 14)
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.52
	p.color = color
	return p


func foot_y_in_control() -> float:
	## Visible base / plant Y inside this control after layout.
	if _anchor_rect.size.y <= 1.0:
		return size.y * CHEST_FOOT_Y_FRAC
	return _anchor_rect.position.y + _anchor_rect.size.y * CHEST_FOOT_Y_FRAC


func _layout_frames() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(220, 260)
	_root_visual.pivot_offset = area * 0.5
	## Fit the production canvas; keep headroom so scroll tops are not clipped.
	var fit: float = minf(area.x / FRAME_CANVAS.x, area.y / FRAME_CANVAS.y)
	_fit_scale = fit
	var draw_w: float = FRAME_CANVAS.x * fit
	var draw_h: float = FRAME_CANVAS.y * fit
	## Plant the authored foot on a fixed ground line inside this control.
	## CHEST_FOOT_Y_FRAC is the sand contact within the chest host; scene code
	## aligns that host line to ChestEnvironment.sand_contact_y_frac().
	var left: float = (area.x - draw_w) * 0.5
	var foot_y: float = area.y * CHEST_FOOT_Y_FRAC
	var top: float = foot_y - draw_h * CHEST_FOOT_Y_FRAC
	_anchor_rect = Rect2(left, top, draw_w, draw_h)
	_place_rect(_frame_view, _anchor_rect)
	_place_scroll_and_rim()
	## Contact shadow: directly under the foot, kissing the base (no hover gap).
	if _shadow_view:
		var sh_w := draw_w * 0.56
		var sh_h := draw_h * 0.038
		## Top of shadow overlaps the foot row — zero visible hover gap.
		var sh_y := foot_y - sh_h * 0.78
		_place_rect(_shadow_view, Rect2(
			_anchor_rect.position.x + (draw_w - sh_w) * 0.5,
			sh_y,
			sh_w,
			sh_h
		))
	## Warm spill sits slightly below/around the foot — never replaces the shadow.
	if _warm_spill:
		var sp_w := draw_w * 0.52
		var sp_h := draw_h * 0.055
		var sp_y := foot_y - sp_h * 0.35
		_place_rect(_warm_spill, Rect2(
			_anchor_rect.position.x + (draw_w - sp_w) * 0.5,
			sp_y,
			sp_w,
			sp_h
		))
	## Soft radial pulse over the cavity — circular texture, not a box.
	_place_rect(_glow_pulse, Rect2(
		_anchor_rect.position.x + draw_w * 0.32,
		_anchor_rect.position.y + draw_h * 0.42,
		draw_w * 0.36,
		draw_h * 0.18
	))
	var cavity_center := Vector2(area.x * 0.5, _anchor_rect.position.y + draw_h * 0.48)
	_dust.position = cavity_center
	_sparks.position = cavity_center
	_motes.position = cavity_center
	_apply_root_transform()
	if _badge:
		## Near the closed chest — slightly above/right, not on lid, not horizon.
		_badge.position = Vector2(
			_anchor_rect.position.x + draw_w * 0.76,
			_anchor_rect.position.y + draw_h * 0.30
		)
		_badge.size = Vector2(40, 40)


func _place_scroll_and_rim() -> void:
	if _anchor_rect.size == Vector2.ZERO:
		return
	var draw_w := _anchor_rect.size.x
	var draw_h := _anchor_rect.size.y
	## Cavity clip: high enough that lid never covers scroll top; rim occludes bottom.
	var clip_x := _anchor_rect.position.x + draw_w * 0.34
	var clip_w := draw_w * 0.32
	var clip_y := _anchor_rect.position.y + draw_h * 0.22
	var clip_h := draw_h * 0.40
	if _scroll_clip:
		_place_rect(_scroll_clip, Rect2(clip_x, clip_y, clip_w, clip_h))
	if _scroll_view and _scroll_clip:
		var sw := SCROLL_NATIVE.x * _fit_scale
		var sh := SCROLL_NATIVE.y * _fit_scale
		## Map canvas rim / rise into clip-local coordinates.
		var rim_y := _anchor_rect.position.y + (CAVITY_RIM_CANVAS_Y / FRAME_CANVAS.y) * draw_h
		var above := lerpf(SCROLL_PEEK_ABOVE_RIM, SCROLL_FINAL_ABOVE_RIM, _scroll_rise)
		var scroll_top := rim_y - sh * above
		var local_x := (_anchor_rect.position.x + (draw_w - sw) * 0.5) - clip_x
		var local_y := scroll_top - clip_y
		_place_rect(_scroll_view, Rect2(local_x, local_y, sw, sh))
	if _rim_view:
		## Rim stays planted with the chest — gold lip sits over lower scroll.
		## Draw order: beach → open-back → scroll (clip) → front rim → glow → UI.
		_place_rect(_rim_view, _anchor_rect)


func _place_rect(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.position = rect.position
	node.size = rect.size


func _apply_root_transform() -> void:
	if _root_visual == null:
		return
	var z := _emphasis_scale
	_root_visual.scale = Vector2(z, z)
	_root_visual.rotation = 0.0
	_root_visual.position = Vector2(
		(1.0 - z) * size.x * 0.5,
		_anticipation_y + (1.0 - z) * size.y * 0.5
	)


func set_unread_badge(count: int) -> void:
	_unread_count = count
	_refresh_badge_visibility()


func _refresh_badge_visibility() -> void:
	if _badge == null:
		return
	if _badge_suppressed or _unread_count <= 0:
		_badge.visible = false
		if _unread_count <= 0:
			_badge.text = ""
		return
	_badge.visible = true
	_badge.text = str(mini(_unread_count, 99))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.98, 0.78, 0.42, 1.0)
	bg.set_corner_radius_all(20)
	_badge.add_theme_stylebox_override("normal", bg)


func _set_badge_suppressed(suppressed: bool) -> void:
	_badge_suppressed = suppressed
	_refresh_badge_visibility()


func _enforce_chest_opaque() -> void:
	## Never fade the physical chest sprite / root — glow may still use alpha.
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	if _root_visual:
		_root_visual.modulate = Color(1, 1, 1, 1)
		_root_visual.self_modulate = Color(1, 1, 1, 1)
	if _frame_view:
		## Preserve idle RGB shimmer channel but keep alpha locked at 1.
		var c := _frame_view.modulate
		_frame_view.modulate = Color(c.r, c.g, c.b, 1.0)
		_frame_view.self_modulate = Color(1, 1, 1, 1)
	if _scroll_view:
		_scroll_view.modulate = Color(1, 1, 1, 1)
		_scroll_view.self_modulate = Color(1, 1, 1, 1)
	if _rim_view:
		_rim_view.modulate = Color(1, 1, 1, 1)
		_rim_view.self_modulate = Color(1, 1, 1, 1)


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_input_locked = false
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_scroll_emerged_emitted = false
	_set_badge_suppressed(false)
	_stop_motes()
	_reset_pose()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			## Dim RGB only — never reduce alpha (chest must stay opaque).
			self_modulate = Color(0.55, 0.55, 0.75, 1.0)
			_label.visible = false
			_set_frame_progress(0.0, false)
			set_process(false)
		ChestState.AVAILABLE, ChestState.READY:
			self_modulate = Color.WHITE
			_label.visible = show_final_label
			_label.text = "Your Chest"
			_set_frame_progress(0.0, false)
			set_process(not reduced_motion)
		ChestState.OPENED, ChestState.OPEN_EMPTY:
			self_modulate = Color.WHITE
			_set_frame_progress(1.0, false)
			_label.visible = false
			set_process(false)
		_:
			set_process(false)
	_enforce_chest_opaque()


func _ease_open_curve(t: float) -> float:
	## Slightly restrained start → smooth mid acceleration → soft ease-out.
	t = clampf(t, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var early := t * t * t
	return lerpf(early, s, 0.58)


func _select_sequence(_emerge_scroll: bool) -> void:
	## Runtime always displays animation_v2 chest frames on the chest sprite.
	## Scroll reward uses open-back + scroll + rim layers after fully open.
	_active_frames = _chest_frames


func _show_frame_index(index: int) -> void:
	if _active_frames.is_empty():
		return
	_frame_index = clampi(index, 0, _active_frames.size() - 1)
	var tex: Texture2D = _active_frames[_frame_index]
	if _frame_view and tex and not _layered_open:
		_frame_view.texture = tex
		## One opaque chest sprite only — never a second chest overlay.
		_enforce_chest_opaque()


func _enter_layered_open() -> void:
	## Clean switch from fully-open frame #12 to open-back + rim (no duplicate).
	_layered_open = true
	if _frame_view and _open_back_tex:
		_frame_view.texture = _open_back_tex
	_set_scroll_layers_visible(true)
	_enforce_chest_opaque()


func _exit_layered_open() -> void:
	_layered_open = false
	_set_scroll_layers_visible(false)
	if _active_frames.size() > 0 and _frame_view:
		_frame_view.texture = _active_frames[clampi(_frame_index, 0, _active_frames.size() - 1)]
	_enforce_chest_opaque()


func _weighted_frame_index(eased: float) -> int:
	## Map eased progress onto all 13 approved frames via pose-weight ends.
	## No blending — discrete opaque frame swaps only.
	var max_i := _active_frames.size() - 1
	if max_i <= 0:
		return 0
	eased = clampf(eased, 0.0, 1.0)
	if eased >= 0.999:
		return max_i
	var ends := _open_weight_ends
	if ends.is_empty():
		ends = _build_open_weight_ends()
	for i in range(mini(ends.size(), max_i + 1)):
		if eased <= ends[i] + 1e-6:
			return i
	return max_i


func _frame_index_from_progress(amount: float, emerge_scroll: bool) -> int:
	## Chest pose only — scroll rise is a separate layer after fully open.
	## Pose weights already encode restrained→accel→decel; do not double-ease.
	var max_i := _active_frames.size() - 1
	if max_i <= 0:
		return 0
	if emerge_scroll:
		## Combined unread progress: first portion opens chest, remainder holds open.
		if amount < SCROLL_REVEAL_START_PROGRESS:
			var t_open := amount / SCROLL_REVEAL_START_PROGRESS
			return _weighted_frame_index(t_open)
		return max_i
	return _weighted_frame_index(amount)


func _set_scroll_layers_visible(vis: bool) -> void:
	if _scroll_clip:
		_scroll_clip.visible = vis
	if _rim_view:
		_rim_view.visible = vis


func _set_scroll_rise_amount(amount: float) -> void:
	_scroll_rise = clampf(amount, 0.0, 1.0)
	if _scroll_rise > 0.001 and not _layered_open:
		_enter_layered_open()
	_place_scroll_and_rim()
	if _scroll_rise > 0.02:
		_set_scroll_layers_visible(true)
		if not _scroll_emerged_emitted:
			_scroll_emerged_emitted = true
			chest_state = ChestState.OPEN_SCROLL_EMERGING
			sfx_scroll_emerge.emit()
			scroll_emerged.emit(get_scroll_global_center())


func _set_frame_progress(raw_amount: float, emerge_scroll: bool) -> void:
	var linear := clampf(raw_amount, 0.0, 1.0)
	_open_amount = linear
	_select_sequence(emerge_scroll)
	if _active_frames.is_empty():
		return
	## Soft visual ease for glow only — frame index uses weighted linear progress.
	var glow_ease := _ease_open_curve(linear)
	var idx := _frame_index_from_progress(linear, emerge_scroll)
	## Layered scroll path: hold open-back once reveal starts — never show #12 + layers.
	if emerge_scroll and linear >= SCROLL_REVEAL_START_PROGRESS:
		_frame_index = _active_frames.size() - 1
		if not _layered_open:
			_enter_layered_open()
	else:
		if _layered_open and not emerge_scroll:
			_exit_layered_open()
		_show_frame_index(idx)

	## Progressive warm glow while the lid opens.
	if _glow_pulse and not _layered_open:
		_glow_pulse.modulate.a = lerpf(0.0, GLOW_MID_A, glow_ease)
	if _warm_spill and not _layered_open:
		_warm_spill.modulate.a = lerpf(0.0, 0.18, glow_ease)

	## Particles arm near mid-open — restrained, secondary to the chest.
	if not reduced_motion and linear >= 0.45 and not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()

	## Layered scroll rise for unread combined progress samples.
	if emerge_scroll:
		if linear >= SCROLL_REVEAL_START_PROGRESS:
			var t_scroll := (linear - SCROLL_REVEAL_START_PROGRESS) / (1.0 - SCROLL_REVEAL_START_PROGRESS)
			## Ease-out so peek→25%→50%→70%→final each read clearly.
			t_scroll = t_scroll * t_scroll * (3.0 - 2.0 * t_scroll)
			t_scroll = 1.0 - (1.0 - t_scroll) * (1.0 - t_scroll)
			_set_scroll_rise_amount(t_scroll)
		else:
			_scroll_rise = 0.0
			if _layered_open:
				_exit_layered_open()
			_set_scroll_layers_visible(false)
			_place_scroll_and_rim()
	else:
		_scroll_rise = 0.0
		if _layered_open:
			_exit_layered_open()
		_set_scroll_layers_visible(false)
		_place_scroll_and_rim()


func _apply_open_amount(raw_amount: float) -> void:
	## Compat path used by close tween — empty sequence, no scroll.
	_set_frame_progress(raw_amount, _show_scroll_on_finish)


func _reset_pose() -> void:
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_frame_index = 0
	_scroll_rise = 0.0
	_layered_open = false
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
		_root_visual.modulate = Color.WHITE
	if _glow_pulse:
		_glow_pulse.modulate.a = 0.0
	if _warm_spill:
		_warm_spill.modulate.a = 0.0
	_set_scroll_layers_visible(false)
	_layout_frames()
	_select_sequence(false)
	_show_frame_index(0)


func _process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
		return
	if animating or reduced_motion or not _ready_visuals:
		return
	if chest_state != ChestState.AVAILABLE and chest_state != ChestState.READY:
		return
	_idle_time += delta
	## Subtle idle shimmer via modulate — no lid squash.
	if _frame_view:
		var shimmer := 0.02 * sin(_idle_time * 1.35)
		_frame_view.modulate = Color(1.0 + shimmer, 1.0 + shimmer * 0.6, 1.0, 1.0)


func set_active_processing(enabled: bool) -> void:
	set_process(enabled)


func _on_pressed() -> void:
	if _input_locked or animating:
		_skip = true
		skip_requested.emit()
		return
	if chest_state == ChestState.OPENING \
			or chest_state == ChestState.OPEN_WAITING_FOR_SCROLL \
			or chest_state == ChestState.OPEN_SCROLL_EMERGING \
			or chest_state == ChestState.TRANSITIONING \
			or chest_state == ChestState.CLOSING:
		return
	tapped.emit()


func play_press_feedback() -> void:
	## Tiny planted response — not a button bounce / squash.
	HapticHelper.light_tap()
	if reduced_motion:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_anticipation_y = v
		_apply_root_transform()
	, 0.0, 2.5, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float) -> void:
		_anticipation_y = v
		_apply_root_transform()
	, 2.5, 0.0, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func play_empty_feedback() -> void:
	await play_open_empty_pulse()


func play_open_empty_pulse() -> void:
	## Retap on open empty: glow/motes only — stay open, no reopen / no 13-frame replay.
	if animating:
		return
	if chest_state != ChestState.OPENED and chest_state != ChestState.OPEN_EMPTY:
		if _open_amount < 0.95:
			return
	animating = true
	_input_locked = true
	HapticHelper.light_tap()
	## Hold last approved open frame (or layered back if already layered).
	_select_sequence(false)
	if not _layered_open:
		_show_frame_index(_chest_frames.size() - 1)
	var pulse := create_tween()
	if _glow_pulse:
		pulse.tween_property(_glow_pulse, "modulate:a", GLOW_RETAP_A, 0.14).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_glow_pulse, "modulate:a", GLOW_SETTLE_A * 0.5, 0.30).set_trans(Tween.TRANS_SINE)
	if _frame_view:
		var shimmer := create_tween()
		## Brightness shimmer only — alpha stays 1.0 (no translucent chest).
		shimmer.tween_property(_frame_view, "modulate", Color(1.06, 1.03, 0.96, 1.0), 0.12)
		shimmer.tween_property(_frame_view, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.26)
	if not reduced_motion:
		_emit_burst()
	if pulse.is_valid():
		await pulse.finished
	else:
		await get_tree().create_timer(0.28).timeout
	animating = false
	_input_locked = false


func play_open_animation(short: bool = false, emerge_scroll: bool = false) -> void:
	if animating \
			or chest_state == ChestState.OPENING \
			or chest_state == ChestState.OPEN_WAITING_FOR_SCROLL \
			or chest_state == ChestState.OPEN_SCROLL_EMERGING \
			or chest_state == ChestState.TRANSITIONING \
			or chest_state == ChestState.CLOSING:
		return
	if (chest_state == ChestState.OPENED or chest_state == ChestState.OPEN_EMPTY) and not emerge_scroll:
		await play_open_empty_pulse()
		return
	animating = true
	_input_locked = true
	_skip = false
	_particles_armed = false
	_scroll_emerged_emitted = false
	_set_badge_suppressed(true)
	set_process(false)
	_show_scroll_on_finish = emerge_scroll
	_select_sequence(emerge_scroll)
	chest_state = ChestState.OPENING
	sfx_open_start.emit()
	play_press_feedback()
	if reduced_motion or short:
		await _open_short()
	else:
		await _open_full()
	_apply_finished_state()
	if emerge_scroll:
		chest_state = ChestState.TRANSITIONING
	else:
		chest_state = ChestState.OPEN_EMPTY
		_set_badge_suppressed(false)
	animating = false
	_input_locked = false
	sfx_fully_open.emit()
	open_finished.emit()


func play_close_animation() -> void:
	if animating or chest_state == ChestState.OPENING or chest_state == ChestState.OPEN_SCROLL_EMERGING:
		return
	animating = true
	_input_locked = true
	chest_state = ChestState.CLOSING
	_stop_motes()
	hide_rolled_scroll()
	_show_scroll_on_finish = false
	var dur := 0.28 if reduced_motion else 0.55
	var tw := create_tween()
	tw.tween_method(_apply_open_amount, _open_amount, 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_set_frame_progress(0.0, false)
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	_set_badge_suppressed(false)
	chest_state = ChestState.READY
	animating = false
	_input_locked = false


func play_final_reopen_animation() -> void:
	await play_open_animation(true, false)


func set_interaction_enabled(enabled: bool) -> void:
	_input_locked = not enabled
	if _button != null and is_instance_valid(_button):
		_button.disabled = not enabled
		_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func finish_opening_safely() -> void:
	if not animating:
		return
	_skip = true
	_apply_finished_state()
	animating = false
	_input_locked = false
	chest_state = ChestState.OPEN_EMPTY if not _show_scroll_on_finish else ChestState.TRANSITIONING
	if not _show_scroll_on_finish:
		_set_badge_suppressed(false)
	open_finished.emit()


func apply_ready_idle_state() -> void:
	animating = false
	_skip = false
	_idle_time = 0.0
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_scroll_emerged_emitted = false
	_stop_motes()
	if _dust != null:
		_dust.emitting = false
	if _sparks != null:
		_sparks.emitting = false
	hide_rolled_scroll()
	_reset_pose()
	configure(ChestState.READY, true)
	set_interaction_enabled(true)
	modulate = Color(1, 1, 1, 1)
	visible = true


func _open_short() -> void:
	## Reduced-motion: quick opaque walk of key frames — never a translucent blend.
	_layout_frames()
	_show_frame_index(0)
	_open_amount = 0.0
	var steps := [0, 3, 6, 9, 12]
	var step_dur := OPEN_DURATION_RM / float(maxi(steps.size() - 1, 1))
	for i in range(steps.size()):
		if _skip:
			break
		_show_frame_index(int(steps[i]))
		_open_amount = float(i) / float(maxi(steps.size() - 1, 1))
		if _glow_pulse:
			_glow_pulse.modulate.a = lerpf(0.0, GLOW_OPEN_A, _open_amount)
		await get_tree().create_timer(step_dur).timeout
	_show_frame_index(_chest_frames.size() - 1)
	_open_amount = 1.0
	_enforce_chest_opaque()
	if _show_scroll_on_finish and not _skip:
		await _play_scroll_rise_tween(SCROLL_EMERGE_SEC * 0.55)
		await get_tree().create_timer(REWARD_HOLD_SEC * 0.6).timeout
	else:
		await get_tree().create_timer(0.06).timeout


func _play_scroll_rise_tween(duration: float) -> void:
	## Continuous Y translation with readable stages — never baked pose pops.
	chest_state = ChestState.OPEN_SCROLL_EMERGING
	_enter_layered_open()
	_set_scroll_rise_amount(0.0)
	var rise := create_tween()
	## hidden → tiny peek → 25% → 50% → 70% → final (~60–70% body above rim).
	rise.tween_method(_set_scroll_rise_amount, 0.00, 0.08, duration * 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rise.tween_method(_set_scroll_rise_amount, 0.08, 0.25, duration * 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_method(_set_scroll_rise_amount, 0.25, 0.50, duration * 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_method(_set_scroll_rise_amount, 0.50, 0.70, duration * 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rise.tween_method(_set_scroll_rise_amount, 0.70, 1.00, duration * 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await rise.finished
	_set_scroll_rise_amount(1.0)
	if not _scroll_emerged_emitted:
		_scroll_emerged_emitted = true
		sfx_scroll_emerge.emit()
		scroll_emerged.emit(get_scroll_global_center())


func _open_full() -> void:
	## Smooth 13-frame animation_v2 open — opaque discrete swaps, no crossfade.
	_layout_frames()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	_exit_layered_open()
	_show_frame_index(0)
	_open_amount = 0.0
	_enforce_chest_opaque()
	await get_tree().create_timer(ANTICIPATION_SEC).timeout
	if _skip:
		_apply_finished_state()
		return

	sfx_latch_release.emit()
	HapticHelper.lock_release()

	## Drive progress 0→1; weighted frames provide restrained→accel→decel feel.
	var open_tw := create_tween()
	open_tw.tween_method(func(v: float) -> void:
		_set_frame_progress(v, false)
		_enforce_chest_opaque()
	, 0.0, 1.0, OPEN_DURATION_SEC).set_trans(Tween.TRANS_LINEAR)
	await open_tw.finished
	if _skip:
		_apply_finished_state()
		return

	_show_frame_index(_chest_frames.size() - 1)
	_open_amount = 1.0
	_enforce_chest_opaque()
	sfx_magical_swell.emit()
	if not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()
	else:
		_emit_burst()

	## Settle glow at fully open — magical but not washed-out.
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, EMPHASIS_SCALE, 1.0, SETTLE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _glow_pulse:
		settle.tween_property(_glow_pulse, "modulate:a", GLOW_SETTLE_A, SETTLE_SEC).set_trans(Tween.TRANS_SINE)
	if _warm_spill:
		settle.tween_property(_warm_spill, "modulate:a", 0.20, SETTLE_SEC).set_trans(Tween.TRANS_SINE)
	await settle.finished
	if _skip:
		_apply_finished_state()
		return

	## Layered scroll rise (unread only), continuous Y tween after fully open.
	if _show_scroll_on_finish:
		await _play_scroll_rise_tween(SCROLL_EMERGE_SEC)
		if _skip:
			_apply_finished_state()
			return

	var swell := create_tween()
	swell.set_parallel(true)
	if _glow_pulse:
		swell.tween_property(
			_glow_pulse,
			"modulate:a",
			GLOW_REWARD_HOLD_A if _show_scroll_on_finish else GLOW_SETTLE_A * 0.55,
			MAGICAL_SWELL_SEC
		)
	if _warm_spill and not _show_scroll_on_finish:
		swell.tween_property(_warm_spill, "modulate:a", 0.10, MAGICAL_SWELL_SEC)
	await swell.finished
	_emphasis_scale = 1.0
	_apply_root_transform()

	if _show_scroll_on_finish and not _skip:
		chest_state = ChestState.OPEN_WAITING_FOR_SCROLL
		## Intentional reward hold so the completed scroll reads before note transition.
		await get_tree().create_timer(REWARD_HOLD_SEC).timeout
	else:
		await get_tree().create_timer(0.06).timeout
		## Empty remains open with restrained glow — motes stay soft.
	_anticipation_y = 0.0
	_apply_root_transform()


func get_scroll_global_center() -> Vector2:
	## Approximate the raised scroll center from the clipped cavity.
	if _scroll_view and _scroll_view.is_visible_in_tree() and _scroll_clip and _scroll_clip.visible:
		return _scroll_view.global_position + Vector2(
			_scroll_view.size.x * 0.5,
			_scroll_view.size.y * 0.45
		)
	if _scroll_clip and _scroll_clip.visible:
		return _scroll_clip.global_position + Vector2(
			_scroll_clip.size.x * 0.5,
			_scroll_clip.size.y * 0.55
		)
	if _anchor_rect.size != Vector2.ZERO:
		return global_position + _anchor_rect.position + Vector2(
			_anchor_rect.size.x * 0.5,
			_anchor_rect.size.y * 0.38
		)
	return global_position + size * 0.5


func hide_rolled_scroll() -> void:
	_scroll_rise = 0.0
	if _layered_open:
		_exit_layered_open()
	_set_scroll_layers_visible(false)
	_place_scroll_and_rim()


func _apply_finished_state() -> void:
	_select_sequence(false)
	_frame_index = _chest_frames.size() - 1
	_open_amount = 1.0
	if _show_scroll_on_finish:
		_enter_layered_open()
		_set_scroll_rise_amount(1.0)
		_set_scroll_layers_visible(true)
	else:
		_layered_open = false
		_set_scroll_layers_visible(false)
		if _frame_view and _chest_frames.size() > 0:
			_frame_view.texture = _chest_frames[_chest_frames.size() - 1]
		_place_scroll_and_rim()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	if _glow_pulse:
		_glow_pulse.modulate.a = GLOW_REWARD_HOLD_A if _show_scroll_on_finish else GLOW_SETTLE_A * 0.45
	if _warm_spill:
		_warm_spill.modulate.a = 0.16 if _show_scroll_on_finish else 0.08
	_enforce_chest_opaque()


func _emit_burst() -> void:
	if reduced_motion:
		return
	if _dust:
		_dust.restart()
		_dust.emitting = true
	if _sparks:
		_sparks.restart()
		_sparks.emitting = true


func _start_motes() -> void:
	if reduced_motion or _motes == null:
		return
	_motes.emitting = true


func _stop_motes() -> void:
	if _motes != null:
		_motes.emitting = false


func request_skip() -> void:
	_skip = true


func frame_count() -> int:
	return maxi(_chest_frames.size(), 1)
