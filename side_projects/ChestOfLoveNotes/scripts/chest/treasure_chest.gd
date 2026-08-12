extends Control
class_name LoveNotesChest
## Fantasy sheet chest animation — deterministic cropped frames from the
## authoritative sprite sheets (not the old hinged bronze lid path).
## Empty opens use glowing_treasure_chest_opening_sprite_sheet frames.
## Unread opens use magical_treasure_chest_animation_sheet frames (scroll baked in).

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
const FRAME_CANVAS := Vector2(384, 384)
## Total empty open timing (~1.05s of frame advance + settle).
const OPEN_DURATION_SEC := 1.00
const OPEN_DURATION_RM := 0.36
const ANTICIPATION_SEC := 0.10
const SETTLE_SEC := 0.12
const MAGICAL_SWELL_SEC := 0.14
## Scroll emerge portion after chest is open enough (frame path).
const SCROLL_EMERGE_SEC := 0.68
const EMPHASIS_SCALE := 1.008
## First scroll-peek frame index in the scroll sequence.
const SCROLL_REVEAL_START_INDEX := 5

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _input_locked: bool = false
var _label: Label
var _root_visual: Control
var _frame_view: TextureRect
var _glow_pulse: ColorRect
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _motes: CPUParticles2D
var _button: Button
var _ready_visuals: bool = false
var _badge: Label
var _unread_count: int = 0
var _open_amount: float = 0.0
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
	_empty_cache = _load_sequence(EMPTY_DIR, "empty_", 10)
	_scroll_cache = _load_sequence(SCROLL_DIR, "scroll_", 13)
	_sprite_frames_empty = _build_sprite_frames("empty_open", _empty_cache, 10.0)
	_sprite_frames_scroll = _build_sprite_frames("scroll_open", _scroll_cache, 11.0)
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
	custom_minimum_size = Vector2(220, 220)
	modulate.a = 1.0
	visible = true
	preload_assets()
	_empty_frames.clear()
	_scroll_frames.clear()
	for t in _empty_cache:
		_empty_frames.append(t as Texture2D)
	for t in _scroll_cache:
		_scroll_frames.append(t as Texture2D)
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


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.name = "ChestAnimationRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_visual)

	_frame_view = TextureRect.new()
	_frame_view.name = "ChestFrame"
	_frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_view.z_index = 2
	_root_visual.add_child(_frame_view)

	## Soft warm pulse overlay for empty retap — does not redraw the chest.
	_glow_pulse = ColorRect.new()
	_glow_pulse.name = "GlowPulse"
	_glow_pulse.color = Color(1.0, 0.78, 0.42, 0.0)
	_glow_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_pulse.z_index = 3
	_root_visual.add_child(_glow_pulse)

	_dust = _make_particles(Color(0.90, 0.78, 0.48, 0.38), 4, Vector2(0, -1), 14.0, 0.70)
	_dust.z_index = 4
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.84, 0.48, 0.46), 2, Vector2(0, -1), 20.0, 0.55)
	_sparks.z_index = 4
	_root_visual.add_child(_sparks)
	_motes = _make_particles(Color(1.0, 0.86, 0.55, 0.32), 5, Vector2(0, -1), 10.0, 1.1)
	_motes.one_shot = false
	_motes.explosiveness = 0.0
	_motes.z_index = 4
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


func _layout_frames() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(220, 220)
	_root_visual.pivot_offset = area * 0.5
	var side: float = minf(area.x, area.y) * 1.08
	var top: float = (area.y - side) * 0.38
	var left: float = (area.x - side) * 0.5
	_anchor_rect = Rect2(left, top, side, side)
	_place_rect(_frame_view, _anchor_rect)
	## Soft radial-ish pulse sits over the cavity region only.
	_place_rect(_glow_pulse, Rect2(
		_anchor_rect.position.x + side * 0.22,
		_anchor_rect.position.y + side * 0.28,
		side * 0.56,
		side * 0.36
	))
	var cavity_center := Vector2(area.x * 0.5, _anchor_rect.position.y + side * 0.42)
	_dust.position = cavity_center
	_sparks.position = cavity_center
	_motes.position = cavity_center
	_apply_root_transform()
	if _badge:
		_badge.position = Vector2(area.x * 0.72, top + side * 0.08)
		_badge.size = Vector2(40, 40)


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
	if _badge == null:
		return
	if count <= 0:
		_badge.visible = false
		_badge.text = ""
		return
	_badge.visible = true
	_badge.text = str(mini(count, 99))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.98, 0.78, 0.42, 1.0)
	bg.set_corner_radius_all(20)
	_badge.add_theme_stylebox_override("normal", bg)


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_input_locked = false
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_scroll_emerged_emitted = false
	_stop_motes()
	_reset_pose()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			self_modulate = Color(0.55, 0.55, 0.75, 0.9)
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


func _ease_open_curve(t: float) -> float:
	## Small resistance → smooth acceleration → gentle ease-out (no elastic bounce).
	t = clampf(t, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var early := t * t * t
	return lerpf(early, s, 0.70)


func _select_sequence(emerge_scroll: bool) -> void:
	if emerge_scroll and _scroll_frames.size() > 0:
		_active_frames = _scroll_frames
	else:
		_active_frames = _empty_frames


func _show_frame_index(index: int) -> void:
	if _active_frames.is_empty():
		return
	_frame_index = clampi(index, 0, _active_frames.size() - 1)
	var tex: Texture2D = _active_frames[_frame_index]
	if _frame_view and tex:
		_frame_view.texture = tex


func _set_frame_progress(raw_amount: float, emerge_scroll: bool) -> void:
	var linear := clampf(raw_amount, 0.0, 1.0)
	_open_amount = linear
	_select_sequence(emerge_scroll)
	if _active_frames.is_empty():
		return
	var eased := _ease_open_curve(linear)
	var max_i := _active_frames.size() - 1
	var idx: int
	if emerge_scroll and max_i >= SCROLL_REVEAL_START_INDEX:
		## Hold opening poses until the chest is substantially open, then reveal scroll.
		## First ~62% of eased time → frames before scroll peek; remainder → scroll rise.
		var open_end := SCROLL_REVEAL_START_INDEX - 1
		if eased < 0.62:
			var t_open := eased / 0.62
			idx = int(round(t_open * float(open_end)))
		else:
			var t_scroll := (eased - 0.62) / 0.38
			idx = open_end + int(round(t_scroll * float(max_i - open_end)))
	else:
		idx = int(round(eased * float(max_i)))
	_show_frame_index(idx)

	## Particles after interior is visibly open.
	if not reduced_motion and linear >= 0.28 and not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()

	## Scroll emerge signal once peek frames are reached.
	if emerge_scroll and not _scroll_emerged_emitted and idx >= SCROLL_REVEAL_START_INDEX:
		_scroll_emerged_emitted = true
		chest_state = ChestState.OPEN_SCROLL_EMERGING
		sfx_scroll_emerge.emit()
		scroll_emerged.emit(get_scroll_global_center())


func _apply_open_amount(raw_amount: float) -> void:
	## Compat path used by close tween — empty sequence, no scroll.
	_set_frame_progress(raw_amount, _show_scroll_on_finish)


func _reset_pose() -> void:
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_frame_index = 0
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
		_root_visual.modulate = Color.WHITE
	if _glow_pulse:
		_glow_pulse.color.a = 0.0
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
		pulse.tween_property(_glow_pulse, "color:a", 0.22, 0.14).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_glow_pulse, "color:a", 0.0, 0.30).set_trans(Tween.TRANS_SINE)
	if _frame_view:
		var shimmer := create_tween()
		shimmer.tween_property(_frame_view, "modulate", Color(1.08, 1.04, 0.95, 1.0), 0.12)
		shimmer.tween_property(_frame_view, "modulate", Color.WHITE, 0.26)
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
		chest_state = ChestState.OPENED
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
	chest_state = ChestState.OPENED if not _show_scroll_on_finish else ChestState.TRANSITIONING
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
	_set_frame_progress(0.0, _show_scroll_on_finish)
	_layout_frames()
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _set_frame_progress(v, _show_scroll_on_finish),
		0.0,
		1.0,
		OPEN_DURATION_RM
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
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

	## Hold closed briefly, then advance frames with hold-longer on key poses.
	var dur := OPEN_DURATION_SEC
	if _show_scroll_on_finish:
		## Extra time so scroll does not start rising until chest is open enough.
		dur = OPEN_DURATION_SEC + SCROLL_EMERGE_SEC * 0.35

	var lid := create_tween()
	lid.tween_method(
		func(v: float) -> void: _set_frame_progress(v, _show_scroll_on_finish),
		0.0,
		1.0,
		dur
	).set_trans(Tween.TRANS_LINEAR)
	await lid.finished
	if _skip:
		_apply_finished_state()
		return

	if _show_scroll_on_finish:
		chest_state = ChestState.OPEN_SCROLL_EMERGING
		## Ensure we land on the final scroll-complete frame.
		_show_frame_index(_active_frames.size() - 1)
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
		settle.tween_property(_glow_pulse, "color:a", 0.10, SETTLE_SEC).set_trans(Tween.TRANS_SINE)
	await settle.finished

	sfx_magical_swell.emit()
	var swell := create_tween()
	swell.set_parallel(true)
	swell.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, EMPHASIS_SCALE, 1.0, MAGICAL_SWELL_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _glow_pulse:
		swell.tween_property(_glow_pulse, "color:a", 0.0, MAGICAL_SWELL_SEC)
	await swell.finished
	_emphasis_scale = 1.0
	_apply_root_transform()

	if _show_scroll_on_finish and not _skip:
		chest_state = ChestState.OPEN_WAITING_FOR_SCROLL
		await get_tree().create_timer(0.08).timeout
	else:
		await get_tree().create_timer(0.06).timeout
		_stop_motes()
	_anticipation_y = 0.0
	_apply_root_transform()


func get_scroll_global_center() -> Vector2:
	## Scroll is baked into sheet frames — approximate cavity center.
	if _anchor_rect.size != Vector2.ZERO:
		return global_position + _anchor_rect.position + Vector2(
			_anchor_rect.size.x * 0.5,
			_anchor_rect.size.y * 0.38
		)
	return global_position + size * 0.5


func hide_rolled_scroll() -> void:
	## Scroll is part of sheet frames; closing returns to closed empty frame.
	pass


func _apply_finished_state() -> void:
	_set_frame_progress(1.0, _show_scroll_on_finish)
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	if _glow_pulse:
		_glow_pulse.color.a = 0.0


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
