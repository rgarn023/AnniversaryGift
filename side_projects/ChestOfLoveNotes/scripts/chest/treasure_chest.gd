extends Control
class_name LoveNotesChest
## Multi-frame physical chest opening (closed → … → open).
## Uses progressive photoreal frames with weighty non-linear timing.
## Does not rotate a flat PNG lid (perspective would look fake).

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged(global_pos: Vector2)

enum ChestState { LOCKED_SILHOUETTE, AVAILABLE, OPENING, OPENED, READY }

const ART := "res://assets/art/chest/"
const FRAME_ART := "res://assets/art/chest/opening_frames/"
const SCROLL_ART := "res://assets/art/scroll/"
## Logical chest footprint in ~390-wide mobile space (~60% width).
const FRAME_SIZE := Vector2(260, 178)

## Curated transparent frames only (black-bg intermediates removed from playback).
## Same camera family: closed → early open → ajar → half → open.
const FRAME_KEYS: Array = [0.0, 0.12, 0.28, 0.45, 0.70, 1.0]
const FRAME_FILES: Array = [
	"frame_00_closed.png",
	"frame_01_open10.png",
	"frame_02_open25.png",
	"frame_03_ajar.png",
	"frame_04_half.png",
	"frame_05_open.png",
]

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _input_locked: bool = false
var _label: Label
var _root_visual: Control
var _contact_shadow: TextureRect
var _frame_nodes: Array = [] # TextureRect
var _frame_textures: Array = [] # Texture2D
var _interior_glow: TextureRect
var _front_lip: TextureRect
var _latch: TextureRect
var _lock: TextureRect
var _highlight: TextureRect
var _scroll_spawn: Control
var _rolled_scroll: TextureRect
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _button: Button
var _press_scale: float = 1.0
var _ready_visuals: bool = false
var _badge: Label
var _unread_count: int = 0
var _open_amount: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(FRAME_SIZE.x, FRAME_SIZE.x)
	modulate.a = 0.0
	visible = false
	_preload_textures()
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
	set_process(true)
	resized.connect(_layout_frames)
	_layout_frames()
	_show_frame_state(0.0)
	visible = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _preload_textures() -> void:
	_frame_textures.clear()
	for fname in FRAME_FILES:
		var path := FRAME_ART + str(fname)
		if not ResourceLoader.exists(path):
			path = ART + str(fname)
		_frame_textures.append(_load_tex(path))


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("Missing chest texture: " + path)
	return null


func _make_frame(tex: Texture2D, z: int, name: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = name
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = z
	tr.modulate.a = 0.0
	return tr


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.name = "ChestRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_visual)

	_contact_shadow = _make_frame(_load_tex(ART + "chest_contact_shadow.png"), 0, "ContactShadow")
	_contact_shadow.modulate = Color(1, 1, 1, 0.88)
	_root_visual.add_child(_contact_shadow)

	_interior_glow = _make_frame(_load_tex(ART + "chest_inner_glow.png"), 1, "InteriorGlow")
	_interior_glow.modulate = Color(1.15, 0.9, 0.55, 0.0)
	_root_visual.add_child(_interior_glow)

	_frame_nodes.clear()
	for i in _frame_textures.size():
		var node := _make_frame(_frame_textures[i], 2, "Frame_%d" % i)
		_root_visual.add_child(node)
		_frame_nodes.append(node)

	_scroll_spawn = Control.new()
	_scroll_spawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_spawn.z_index = 3
	_root_visual.add_child(_scroll_spawn)

	_rolled_scroll = TextureRect.new()
	_rolled_scroll.texture = _load_tex(SCROLL_ART + "scroll_rolled.png")
	_rolled_scroll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rolled_scroll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rolled_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.size = Vector2(300, 70)
	_rolled_scroll.pivot_offset = Vector2(150, 35)
	_scroll_spawn.add_child(_rolled_scroll)

	_front_lip = _make_frame(_load_tex(ART + "chest_front_lip.png"), 4, "ForegroundLip")
	_front_lip.modulate.a = 0.0
	_root_visual.add_child(_front_lip)

	_latch = TextureRect.new()
	_latch.texture = _load_tex(ART + "chest_latch.png")
	_latch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_latch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_latch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_latch.z_index = 5
	_latch.modulate.a = 0.0
	_latch.size = Vector2(140, 36)
	_latch.pivot_offset = Vector2(70, 18)
	_root_visual.add_child(_latch)

	_lock = TextureRect.new()
	_lock.texture = _load_tex(ART + "chest_lock.png")
	_lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock.z_index = 5
	_lock.modulate.a = 0.0
	_lock.size = Vector2(72, 96)
	_lock.pivot_offset = Vector2(36, 16)
	_root_visual.add_child(_lock)

	_highlight = _make_frame(_load_tex(ART + "chest_highlight.png"), 6, "Highlight")
	_highlight.modulate = Color(1, 1, 1, 0.3)
	_root_visual.add_child(_highlight)

	_dust = _make_particles(Color(0.85, 0.75, 0.55, 0.55), 10, Vector2(0, -1), 18.0)
	_dust.z_index = 10
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.82, 0.42, 0.85), 10, Vector2(0, -1), 55.0)
	_sparks.z_index = 11
	_root_visual.add_child(_sparks)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 18)
	_badge.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1))
	_badge.text = ""
	_badge.visible = false
	_badge.z_index = 20
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_bg := ColorRect.new()
	badge_bg.color = Color(0.98, 0.78, 0.42, 1.0)
	badge_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Simple badge without nested complexity — style via modulate on label parent.
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(_badge)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 20)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 12
	add_child(_label)


func _make_particles(color: Color, amount: int, dir: Vector2, speed: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.15
	p.local_coords = false
	p.direction = dir
	p.spread = 28.0
	p.initial_velocity_min = speed * 0.2
	p.initial_velocity_max = speed * 0.55
	p.gravity = Vector2(0, 18)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.color = color
	return p


func _layout_frames() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(FRAME_SIZE.x, FRAME_SIZE.x)
	_root_visual.pivot_offset = area * 0.5
	var frame_h: float = area.x * (FRAME_SIZE.y / FRAME_SIZE.x)
	var top: float = (area.y - frame_h) * 0.38
	var rect := Rect2(0, top, area.x, frame_h)
	for node in _frame_nodes:
		_place_rect(node, rect)
	_place_rect(_interior_glow, rect)
	_place_rect(_highlight, rect)
	_place_rect(_contact_shadow, Rect2(rect.position.x, rect.position.y + frame_h * 0.72, rect.size.x, frame_h * 0.35))
	_place_rect(_front_lip, Rect2(rect.position.x, rect.position.y + frame_h * 0.55, rect.size.x, frame_h * 0.45))
	_scroll_spawn.position = Vector2(area.x * 0.5 - 150.0, rect.position.y + frame_h * 0.42)
	_rolled_scroll.position = Vector2.ZERO
	_rolled_scroll.size = Vector2(300, 70)
	_latch.position = Vector2(area.x * 0.5 - 70.0, rect.position.y + frame_h * 0.48)
	_lock.position = Vector2(area.x * 0.5 - 36.0, rect.position.y + frame_h * 0.52)
	_dust.position = Vector2(area.x * 0.5, rect.position.y + frame_h * 0.4)
	_sparks.position = _dust.position
	if _badge:
		_badge.position = Vector2(area.x * 0.72, top + frame_h * 0.08)
		_badge.size = Vector2(44, 44)


func _place_rect(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.position = rect.position
	node.size = rect.size


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
	bg.set_corner_radius_all(22)
	_badge.add_theme_stylebox_override("normal", bg)


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_input_locked = false
	_reset_pose()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			self_modulate = Color(0.55, 0.55, 0.75, 0.9)
			_interior_glow.modulate.a = 0.1
			_label.visible = false
			_show_frame_state(0.0)
		ChestState.AVAILABLE, ChestState.READY:
			self_modulate = Color.WHITE
			_interior_glow.modulate.a = 0.12
			_label.visible = show_final_label
			_label.text = "Your Chest"
			_show_frame_state(0.0)
		ChestState.OPENED:
			self_modulate = Color.WHITE
			_show_frame_state(1.0)
			_label.visible = false
			_interior_glow.modulate.a = 0.7
			_front_lip.modulate.a = 0.0
		_:
			pass


func _show_frame_state(open_amount: float) -> void:
	## Blend neighboring frames for progressive motion. Glow tracks openness.
	_open_amount = clampf(open_amount, 0.0, 1.0)
	if _frame_nodes.is_empty():
		return
	for n in _frame_nodes:
		(n as TextureRect).modulate.a = 0.0
	# Find surrounding keys.
	var lo_i := 0
	var hi_i := _frame_nodes.size() - 1
	for i in range(FRAME_KEYS.size() - 1):
		if _open_amount >= float(FRAME_KEYS[i]) and _open_amount <= float(FRAME_KEYS[i + 1]):
			lo_i = i
			hi_i = i + 1
			break
		if _open_amount > float(FRAME_KEYS[i]):
			lo_i = i
			hi_i = mini(i + 1, FRAME_KEYS.size() - 1)
	var lo_v := float(FRAME_KEYS[lo_i])
	var hi_v := float(FRAME_KEYS[hi_i])
	var t := 0.0 if hi_v <= lo_v else (_open_amount - lo_v) / (hi_v - lo_v)
	(_frame_nodes[lo_i] as TextureRect).modulate.a = 1.0 - t
	(_frame_nodes[hi_i] as TextureRect).modulate.a = t
	# Glow progresses with lid openness (seam → full).
	var glow_a := 0.0
	if _open_amount < 0.10:
		glow_a = _open_amount * 0.8
	elif _open_amount < 0.30:
		glow_a = 0.08 + (_open_amount - 0.10) * 1.1
	elif _open_amount < 0.60:
		glow_a = 0.30 + (_open_amount - 0.30) * 0.9
	else:
		glow_a = 0.57 + (_open_amount - 0.60) * 0.7
	_interior_glow.modulate = Color(1.18, 0.88, 0.52, clampf(glow_a, 0.0, 0.85))
	# Contact shadow gently widens as lid rises.
	if _contact_shadow:
		var s := 1.0 + _open_amount * 0.06
		_contact_shadow.scale = Vector2(s, 1.0)
		_contact_shadow.modulate.a = 0.75 + _open_amount * 0.15


func _reset_pose() -> void:
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
	_layout_frames()
	if _latch:
		_latch.modulate.a = 0.0
		_latch.rotation = 0.0
	if _lock:
		_lock.modulate.a = 0.0
		_lock.rotation = 0.0
	if _rolled_scroll:
		_rolled_scroll.modulate.a = 0.0
		_rolled_scroll.position = Vector2.ZERO
		_rolled_scroll.rotation = 0.0
		_rolled_scroll.scale = Vector2.ONE
	if _front_lip:
		_front_lip.modulate.a = 0.0


func _process(delta: float) -> void:
	if animating or reduced_motion or not _ready_visuals:
		return
	_idle_time += delta
	if chest_state == ChestState.AVAILABLE or chest_state == ChestState.READY:
		var breathe: float = 1.0 + sin(_idle_time * 1.1) * 0.007
		var float_y: float = sin(_idle_time * 0.8) * 1.6
		_root_visual.scale = Vector2(breathe, breathe) * _press_scale
		_root_visual.position = Vector2((1.0 - breathe) * size.x * 0.5, float_y)
		_highlight.modulate.a = 0.18 + 0.1 * sin(_idle_time * 1.6)


func _on_pressed() -> void:
	if _input_locked or animating:
		_skip = true
		skip_requested.emit()
		return
	tapped.emit()


func play_press_feedback() -> void:
	HapticHelper.light_tap()
	var tween := create_tween()
	_press_scale = 0.985
	tween.tween_property(self, "_press_scale", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func play_open_animation(short: bool = false) -> void:
	if animating:
		return
	animating = true
	_input_locked = true
	_skip = false
	chest_state = ChestState.OPENING
	play_press_feedback()
	if reduced_motion or short:
		await _open_short()
	else:
		await _open_full()
	_apply_finished_state()
	chest_state = ChestState.OPENED
	animating = false
	_input_locked = false
	open_finished.emit()


func play_close_animation() -> void:
	if animating:
		return
	animating = true
	_input_locked = true
	hide_rolled_scroll()
	var dur := 0.45 if reduced_motion else 0.7
	var tw := create_tween()
	tw.tween_method(_show_frame_state, _open_amount, 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_show_frame_state(0.0)
	chest_state = ChestState.READY
	animating = false
	_input_locked = false


func play_final_reopen_animation() -> void:
	await play_open_animation(true)


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
	chest_state = ChestState.OPENED
	open_finished.emit()


func apply_ready_idle_state() -> void:
	animating = false
	_skip = false
	_idle_time = 0.0
	_press_scale = 1.0
	if _dust != null:
		_dust.emitting = false
	if _sparks != null:
		_sparks.emitting = false
	hide_rolled_scroll()
	if _root_visual != null:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
	configure(ChestState.READY, true)
	set_interaction_enabled(true)
	modulate = Color(1, 1, 1, 1)
	visible = true


func _open_short() -> void:
	## Reduced-motion path (~0.35–0.45s): closed → brief glow → open.
	_show_frame_state(0.0)
	var tw := create_tween()
	tw.tween_method(_show_frame_state, 0.0, 1.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished


func _open_full() -> void:
	_layout_frames()
	# 0.00–0.12 tactile press (base stays planted — scale only)
	var press := create_tween()
	press.tween_property(_root_visual, "scale", Vector2(1.0, 0.978), 0.12).set_trans(Tween.TRANS_SINE)
	await press.finished
	if _skip:
		_apply_finished_state()
		return

	# 0.12–0.45 latch/lock mechanical motion
	_latch.modulate.a = 1.0
	_lock.modulate.a = 0.95
	HapticHelper.lock_release()
	var latch_tw := create_tween()
	latch_tw.tween_property(_root_visual, "scale", Vector2.ONE, 0.10)
	latch_tw.parallel().tween_property(_latch, "position:y", _latch.position.y - 4.0, 0.18)
	latch_tw.parallel().tween_property(_lock, "rotation", deg_to_rad(6.0), 0.18)
	await latch_tw.finished
	if _skip:
		_apply_finished_state()
		return
	var release := create_tween()
	release.tween_property(_latch, "modulate:a", 0.0, 0.14)
	release.parallel().tween_property(_lock, "rotation", 0.0, 0.12)
	release.parallel().tween_property(_lock, "modulate:a", 0.0, 0.14)
	await release.finished
	if _skip:
		_apply_finished_state()
		return

	# 0.45–1.55 weighted lid (~1.1s): slow start, faster mid, soft settle. No bounce.
	_front_lip.modulate.a = 0.85
	var lid := create_tween()
	lid.tween_method(_show_frame_state, 0.0, 1.0, 1.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.40).timeout
	if not _skip and not reduced_motion:
		_emit_burst()
	await lid.finished
	if _skip:
		_apply_finished_state()
		return
	await get_tree().create_timer(0.18).timeout
	await _emerge_scroll()
	scroll_emerged.emit(get_scroll_global_center())


func _emerge_scroll() -> void:
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.position = Vector2(0, 40)
	_rolled_scroll.rotation = deg_to_rad(-3.0)
	_front_lip.modulate.a = 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rolled_scroll, "modulate:a", 1.0, 0.18)
	tw.tween_property(_rolled_scroll, "position:y", -55.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "rotation", 0.0, 0.45)
	await tw.finished
	var soft := create_tween()
	soft.tween_property(_front_lip, "modulate:a", 0.3, 0.18)
	await soft.finished


func get_scroll_global_center() -> Vector2:
	if _rolled_scroll and is_instance_valid(_rolled_scroll):
		return _rolled_scroll.global_position + _rolled_scroll.size * 0.5
	return global_position + size * 0.5


func hide_rolled_scroll() -> void:
	if _rolled_scroll:
		_rolled_scroll.modulate.a = 0.0
	if _front_lip:
		_front_lip.modulate.a = 0.0


func _apply_finished_state() -> void:
	_show_frame_state(1.0)
	_latch.modulate.a = 0.0
	_lock.modulate.a = 0.0
	_lock.rotation = 0.0
	_root_visual.scale = Vector2.ONE
	_root_visual.position = Vector2.ZERO
	_front_lip.modulate.a = 0.0
	_rolled_scroll.modulate.a = 1.0
	_rolled_scroll.position = Vector2(0, -55)
	_rolled_scroll.rotation = 0.0


func _emit_burst() -> void:
	_dust.restart()
	_dust.emitting = true
	_sparks.restart()
	_sparks.emitting = true


func request_skip() -> void:
	_skip = true


func frame_count() -> int:
	return _frame_nodes.size()
