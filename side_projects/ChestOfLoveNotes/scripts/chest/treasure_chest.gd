extends Control
class_name LoveNotesChest
## Fantasy sheet chest animation — deterministic cropped frames from the
## authoritative sprite sheets (not the old hinged bronze lid path).
## Empty + unread share glowing-sheet opening geometry (one chest family).
## Unread then reveals a SEPARATE parchment scroll layer under a front-rim
## occlusion layer (never lid-over-scroll baked composites at runtime).
## Exactly one TextureRect chest sprite is visible at all times — never a
## second chest overlay / contaminated scroll-layer chest pixels.

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

const FRAME_ART := "res://assets/art/chest/frames/"
const EMPTY_DIR := FRAME_ART + "empty/"
const SCROLL_DIR := FRAME_ART + "scroll/"
const SOFT_GLOW := "res://assets/art/chest/soft_glow_pulse.png"
const SCROLL_LAYER := "res://assets/art/chest/scroll_rolled.png"
const FRONT_RIM := "res://assets/art/chest/chest_front_rim.png"
const CONTACT_SHADOW := "res://assets/art/chest/chest_contact_shadow.png"
## Taller transparent canvas (foot locked at y=367) — extra headroom, no plant drift.
const FRAME_CANVAS := Vector2(384, 496)
## Absolute plant row in authored frames (matches prepare lock foot / BASE_Y).
const CHEST_FOOT_CANVAS_Y := 394.0
## Foot as fraction of FRAME_CANVAS height — scene grounding uses this.
const CHEST_FOOT_Y_FRAC := CHEST_FOOT_CANVAS_Y / 496.0
## Clean geometrically-compatible opening only (v46 audit): closed→crack→early→half→open.
const EMPTY_FRAME_COUNT := 5
## Scroll sheet: 5 shared open poses + 5 layered rise composites (preload only).
const SCROLL_FRAME_COUNT := 10
## Deliberate reward cadence — shorter clean arc beats longer mismatched swaps.
const OPEN_DURATION_SEC := 1.42
const OPEN_DURATION_RM := 0.32
const ANTICIPATION_SEC := 0.10
const SETTLE_SEC := 0.11
const MAGICAL_SWELL_SEC := 0.12
## Scroll emerge after fully open — peek→25%→50%→65–70%→final.
const SCROLL_EMERGE_SEC := 1.20
## Intentional hold on the completed reward pose before note handoff.
const REWARD_HOLD_SEC := 0.45
## Tiny settle pulse only — must not read as the chest growing while opening.
const EMPHASIS_SCALE := 1.003
## Progress split when sampling combined unread progress (validation / short path).
const SCROLL_REVEAL_START_PROGRESS := 0.52
## Compat index marker (legacy baked scroll frames; runtime uses layers).
const SCROLL_REVEAL_START_INDEX := 5
## Canvas-pixel rise of the separate scroll layer (matches prep final dy span).
const SCROLL_RISE_CANVAS_PX := 72.0
## Soft glow peaks — warm accent only; never washes out rim/scroll/wood.
const GLOW_OPEN_A := 0.016
const GLOW_SETTLE_A := 0.024
const GLOW_RETAP_A := 0.048
const GLOW_REWARD_HOLD_A := 0.012

## Relative dwell weights for the 5 compatible poses — anticipation dwells short;
## larger lid motion (early→half→open) gets more time. Normalized at playback.
const EMPTY_POSE_WEIGHTS := [
	0.48, ## 0 closed
	0.72, ## 1 early_crack
	1.05, ## 2 early_open
	1.28, ## 3 half_open
	0.90, ## 4 fully_open
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
var _anchor_rect: Rect2 = Rect2()
var _anticipation_y: float = 0.0
var _emphasis_scale: float = 1.0
var _particles_armed: bool = false
var _empty_frames: Array[Texture2D] = []
var _scroll_frames: Array[Texture2D] = []
var _active_frames: Array[Texture2D] = []
var _frame_index: int = 0
var _scroll_emerged_emitted: bool = false
var _scroll_layer_tex: Texture2D = null
var _rim_layer_tex: Texture2D = null
var _shadow_tex: Texture2D = null
var _fit_scale: float = 1.0

## Process-wide preload so the first tap never decompresses textures.
static var _tex_cache: Dictionary = {}
static var _empty_cache: Array = []
static var _scroll_cache: Array = []
static var _preloaded: bool = false
static var _sprite_frames_empty: SpriteFrames = null
static var _sprite_frames_scroll: SpriteFrames = null


static func preload_assets() -> void:
	if _preloaded:
		return
	_empty_cache = _load_sequence(EMPTY_DIR, "empty_", EMPTY_FRAME_COUNT)
	_scroll_cache = _load_sequence(SCROLL_DIR, "scroll_", SCROLL_FRAME_COUNT)
	_load_cached(SOFT_GLOW)
	_load_cached(SCROLL_LAYER)
	_load_cached(FRONT_RIM)
	_load_cached(CONTACT_SHADOW)
	_sprite_frames_empty = _build_sprite_frames("empty_open", _empty_cache, 8.0)
	_sprite_frames_scroll = _build_sprite_frames("scroll_open", _scroll_cache, 10.0)
	_preloaded = true


static func _load_sequence(dir: String, prefix: String, count: int) -> Array:
	var out: Array = []
	for i in range(count):
		var path := "%s%s%02d.png" % [dir, prefix, i]
		out.append(_load_cached(path))
	return out


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
	_empty_frames.clear()
	_scroll_frames.clear()
	for t in _empty_cache:
		_empty_frames.append(t as Texture2D)
	for t in _scroll_cache:
		_scroll_frames.append(t as Texture2D)
	_scroll_layer_tex = _load_cached(SCROLL_LAYER)
	_rim_layer_tex = _load_cached(FRONT_RIM)
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
	_shadow_view.modulate = Color(1, 1, 1, 0.62)
	_shadow_view.z_index = 1
	_root_visual.add_child(_shadow_view)

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

	## Cavity clip — only the portion of the scroll above the front lip is visible.
	## Lower scroll body stays hidden inside the chest (simple, deterministic occlusion).
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

	## Thin front-lip highlight/occlusion strip on top of the clipped scroll.
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

	_active_frames = _empty_frames
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
	## Fit the taller production canvas; keep a little headroom so scroll tops are not clipped.
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
		var sh_w := draw_w * 0.62
		var sh_h := draw_h * 0.048
		var sh_y := foot_y - sh_h * 0.22
		_place_rect(_shadow_view, Rect2(
			_anchor_rect.position.x + (draw_w - sh_w) * 0.5,
			sh_y,
			sh_w,
			sh_h
		))
	## Soft radial pulse over the cavity — circular texture, not a box.
	_place_rect(_glow_pulse, Rect2(
		_anchor_rect.position.x + draw_w * 0.30,
		_anchor_rect.position.y + draw_h * 0.40,
		draw_w * 0.40,
		draw_h * 0.22
	))
	var cavity_center := Vector2(area.x * 0.5, _anchor_rect.position.y + draw_h * 0.48)
	_dust.position = cavity_center
	_sparks.position = cavity_center
	_motes.position = cavity_center
	_apply_root_transform()
	if _badge:
		## Near the closed chest — slightly above/right, not on lid, not horizon.
		_badge.position = Vector2(
			_anchor_rect.position.x + draw_w * 0.74,
			_anchor_rect.position.y + draw_h * 0.28
		)
		_badge.size = Vector2(40, 40)


func _place_scroll_and_rim() -> void:
	if _anchor_rect.size == Vector2.ZERO:
		return
	var draw_w := _anchor_rect.size.x
	var draw_h := _anchor_rect.size.y
	## Cavity clip: lid top stays clear; front rim is the only occluder.
	## Narrower than the lid so the love-note proportion stays believable.
	var clip_x := _anchor_rect.position.x + draw_w * 0.30
	var clip_w := draw_w * 0.40
	var clip_y := _anchor_rect.position.y + draw_h * 0.16
	var clip_h := draw_h * 0.42
	if _scroll_clip:
		_place_rect(_scroll_clip, Rect2(clip_x, clip_y, clip_w, clip_h))
	var rise_px := -_scroll_rise * SCROLL_RISE_CANVAS_PX * _fit_scale
	if _scroll_view and _scroll_clip:
		## Place the full canvas-aligned scroll relative to the clip so rise is vertical.
		## Scroll texture is authored on FRAME_CANVAS; map into clip-local coords.
		var local_x := _anchor_rect.position.x - clip_x
		var local_y := _anchor_rect.position.y - clip_y + rise_px
		_place_rect(_scroll_view, Rect2(local_x, local_y, draw_w, draw_h))
	if _rim_view:
		## Rim stays planted with the chest — gold lip sits over the clip bottom.
		## Draw order: beach → chest → scroll (clip) → front rim → glow/particles → UI.
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
	## Small resistance → smooth acceleration → gentle ease-out (no elastic bounce).
	t = clampf(t, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var early := t * t * t
	return lerpf(early, s, 0.62)


func _select_sequence(_emerge_scroll: bool) -> void:
	## Runtime always displays the empty/open chest family on the chest sprite.
	## Scroll reward uses the separate scroll + rim layers after fully open.
	_active_frames = _empty_frames


func _show_frame_index(index: int) -> void:
	if _active_frames.is_empty():
		return
	_frame_index = clampi(index, 0, _active_frames.size() - 1)
	var tex: Texture2D = _active_frames[_frame_index]
	if _frame_view and tex:
		_frame_view.texture = tex
		## One opaque chest sprite only — never a second chest overlay.
		_enforce_chest_opaque()


func _weighted_frame_index(eased: float) -> int:
	## Map eased 0–1 onto discrete poses using non-uniform dwell weights.
	var max_i := _active_frames.size() - 1
	if max_i <= 0:
		return 0
	if eased >= 0.999:
		return max_i
	var weights: Array = EMPTY_POSE_WEIGHTS
	var n := mini(weights.size(), max_i + 1)
	var total := 0.0
	for i in range(n):
		total += float(weights[i])
	if total <= 0.0:
		return clampi(int(round(eased * float(max_i))), 0, max_i)
	var target := clampf(eased, 0.0, 1.0) * total
	var acc := 0.0
	for i in range(n):
		acc += float(weights[i])
		if target <= acc:
			return i
	return max_i


func _frame_index_from_progress(eased: float, emerge_scroll: bool) -> int:
	## Chest pose only — scroll rise is a separate layer after fully open.
	var max_i := _active_frames.size() - 1
	if max_i <= 0:
		return 0
	if emerge_scroll:
		## Combined unread progress: first portion opens chest, remainder holds open.
		if eased < SCROLL_REVEAL_START_PROGRESS:
			var t_open := eased / SCROLL_REVEAL_START_PROGRESS
			return _weighted_frame_index(_ease_open_curve(t_open))
		return max_i
	return _weighted_frame_index(eased)


func _set_scroll_layers_visible(vis: bool) -> void:
	if _scroll_clip:
		_scroll_clip.visible = vis
	if _rim_view:
		_rim_view.visible = vis


func _set_scroll_rise_amount(amount: float) -> void:
	_scroll_rise = clampf(amount, 0.0, 1.0)
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
	var eased := _ease_open_curve(linear)
	var idx := _frame_index_from_progress(eased if not emerge_scroll else linear, emerge_scroll)
	_show_frame_index(idx)

	## Particles after interior is visibly open — reinforce lid motion, don't outpace it.
	if not reduced_motion and linear >= 0.26 and not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()
		## Soft cavity glow eases in with the open — radial, not rectangular.
		if _glow_pulse:
			var g := create_tween()
			g.tween_property(_glow_pulse, "modulate:a", GLOW_OPEN_A, 0.28).set_trans(Tween.TRANS_SINE)

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
			_set_scroll_layers_visible(false)
			_place_scroll_and_rim()
	else:
		_scroll_rise = 0.0
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
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
		_root_visual.modulate = Color.WHITE
	if _glow_pulse:
		_glow_pulse.modulate.a = 0.0
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
	## Retap on open empty: glow/motes only — stay open, no reopen.
	if animating:
		return
	if chest_state != ChestState.OPENED and chest_state != ChestState.OPEN_EMPTY:
		if _open_amount < 0.95:
			return
	animating = true
	_input_locked = true
	HapticHelper.light_tap()
	## Hold last empty open frame.
	_select_sequence(false)
	_show_frame_index(_empty_frames.size() - 1)
	var pulse := create_tween()
	if _glow_pulse:
		pulse.tween_property(_glow_pulse, "modulate:a", GLOW_RETAP_A, 0.14).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_glow_pulse, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_SINE)
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
	_set_frame_progress(0.0, false)
	_layout_frames()
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _set_frame_progress(v, false),
		0.0,
		1.0,
		OPEN_DURATION_RM
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	if _show_scroll_on_finish and not _skip:
		_show_frame_index(_empty_frames.size() - 1)
		var rise := create_tween()
		rise.tween_method(_set_scroll_rise_amount, 0.0, 1.0, SCROLL_EMERGE_SEC * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await rise.finished
		await get_tree().create_timer(REWARD_HOLD_SEC * 0.6).timeout
	else:
		await get_tree().create_timer(0.06).timeout


func _open_full() -> void:
	_layout_frames()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	await get_tree().create_timer(ANTICIPATION_SEC).timeout
	if _skip:
		_apply_finished_state()
		return

	sfx_latch_release.emit()
	HapticHelper.lock_release()

	## Phase 1 — shared empty opening cadence (weighted pose dwells, hard swaps).
	var lid := create_tween()
	lid.tween_method(
		func(v: float) -> void: _set_frame_progress(v, false),
		0.0,
		1.0,
		OPEN_DURATION_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await lid.finished
	if _skip:
		_apply_finished_state()
		return

	## Ensure fully-open empty pose before any scroll reveal.
	_show_frame_index(_empty_frames.size() - 1)

	## Phase 2 — layered scroll rise (unread only).
	if _show_scroll_on_finish:
		chest_state = ChestState.OPEN_SCROLL_EMERGING
		_set_scroll_layers_visible(true)
		_set_scroll_rise_amount(0.0)
		## Smooth Y rise with easing: peek → 25% → 50% → 65–70% → final.
		var rise := create_tween()
		rise.tween_method(_set_scroll_rise_amount, 0.0, 1.0, SCROLL_EMERGE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await rise.finished
		if _skip:
			_apply_finished_state()
			return
		_set_scroll_rise_amount(1.0)
		if not _scroll_emerged_emitted:
			_scroll_emerged_emitted = true
			sfx_scroll_emerge.emit()
			scroll_emerged.emit(get_scroll_global_center())

	## Settle + magical swell (tiny emphasis only — no squash).
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, 1.0, EMPHASIS_SCALE, SETTLE_SEC * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _glow_pulse:
		settle.tween_property(_glow_pulse, "modulate:a", GLOW_SETTLE_A, SETTLE_SEC).set_trans(Tween.TRANS_SINE)
	await settle.finished

	sfx_magical_swell.emit()
	var swell := create_tween()
	swell.set_parallel(true)
	swell.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, EMPHASIS_SCALE, 1.0, MAGICAL_SWELL_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _glow_pulse:
		swell.tween_property(
			_glow_pulse,
			"modulate:a",
			GLOW_REWARD_HOLD_A if _show_scroll_on_finish else 0.0,
			MAGICAL_SWELL_SEC
		)
	await swell.finished
	_emphasis_scale = 1.0
	_apply_root_transform()

	if _show_scroll_on_finish and not _skip:
		chest_state = ChestState.OPEN_WAITING_FOR_SCROLL
		## Intentional reward hold so the completed scroll reads before note transition.
		await get_tree().create_timer(REWARD_HOLD_SEC).timeout
	else:
		await get_tree().create_timer(0.06).timeout
		_stop_motes()
	_anticipation_y = 0.0
	_apply_root_transform()


func get_scroll_global_center() -> Vector2:
	## Approximate the raised scroll center from the clipped cavity.
	if _scroll_clip and _scroll_clip.visible:
		return _scroll_clip.global_position + Vector2(
			_scroll_clip.size.x * 0.5,
			_scroll_clip.size.y * 0.55
		)
	if _scroll_view and _scroll_view.is_visible_in_tree():
		return _scroll_view.global_position + Vector2(
			_scroll_view.size.x * 0.5,
			_scroll_view.size.y * 0.38
		)
	if _anchor_rect.size != Vector2.ZERO:
		return global_position + _anchor_rect.position + Vector2(
			_anchor_rect.size.x * 0.5,
			_anchor_rect.size.y * 0.38
		)
	return global_position + size * 0.5


func hide_rolled_scroll() -> void:
	_scroll_rise = 0.0
	_set_scroll_layers_visible(false)
	_place_scroll_and_rim()


func _apply_finished_state() -> void:
	_set_frame_progress(1.0, false)
	_show_frame_index(_empty_frames.size() - 1)
	if _show_scroll_on_finish:
		_set_scroll_rise_amount(1.0)
		_set_scroll_layers_visible(true)
	else:
		hide_rolled_scroll()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	if _glow_pulse:
		_glow_pulse.modulate.a = 0.0
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
	return maxi(_empty_frames.size(), 1)
