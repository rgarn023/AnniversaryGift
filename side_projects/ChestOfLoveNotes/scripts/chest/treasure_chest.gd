extends Control
class_name LoveNotesChest
## Physical chest open/close with ONE consistent source pair (closed ↔ open).
## Intermediate AI frames and detached latch/lock overlays removed — they caused
## geometry morph and giant/detached hardware on the logical mobile viewport.

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged(global_pos: Vector2)

enum ChestState { LOCKED_SILHOUETTE, AVAILABLE, OPENING, OPENED, READY, CLOSING }

const ART := "res://assets/art/chest/"
const SCROLL_ART := "res://assets/art/scroll/"
## ~210–220 logical px wide on ~390 viewport (balanced, not oversized).
const FRAME_SIZE := Vector2(220, 150)

## Only closed + open from the same canvas family — no mid-sequence morph frames.
const FRAME_KEYS: Array = [0.0, 1.0]
const FRAME_FILES: Array = [
	"chest_closed.png",
	"chest_open.png",
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
var _show_scroll_on_finish: bool = true


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
		_frame_textures.append(_load_tex(ART + str(fname)))


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
	_rolled_scroll.size = Vector2(160, 48)
	_rolled_scroll.pivot_offset = Vector2(80, 24)
	_scroll_spawn.add_child(_rolled_scroll)

	_front_lip = _make_frame(_load_tex(ART + "chest_front_lip.png"), 4, "ForegroundLip")
	_front_lip.modulate.a = 0.0
	_root_visual.add_child(_front_lip)

	## Latch/lock are baked into the closed/open artwork. Separate overlays were
	## sized in absolute px and appeared enormous/detached after the 390 viewport.

	_highlight = _make_frame(_load_tex(ART + "chest_highlight.png"), 6, "Highlight")
	_highlight.modulate = Color(1, 1, 1, 0.28)
	_root_visual.add_child(_highlight)

	## ~70% fewer particles than prior 10+10 burst; gold dust only from interior.
	_dust = _make_particles(Color(0.90, 0.78, 0.48, 0.50), 3, Vector2(0, -1), 14.0)
	_dust.z_index = 10
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.84, 0.48, 0.70), 2, Vector2(0, -1), 28.0)
	_sparks.z_index = 11
	_root_visual.add_child(_sparks)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 15)
	_badge.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1))
	_badge.text = ""
	_badge.visible = false
	_badge.z_index = 20
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(_badge)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 17)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 12
	add_child(_label)


func _make_particles(color: Color, amount: int, dir: Vector2, speed: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.12
	p.local_coords = false
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = speed * 0.15
	p.initial_velocity_max = speed * 0.45
	p.gravity = Vector2(0, 14)
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.85
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
	var top: float = (area.y - frame_h) * 0.40
	var rect := Rect2(0, top, area.x, frame_h)
	for node in _frame_nodes:
		_place_rect(node, rect)
	_place_rect(_interior_glow, rect)
	_place_rect(_highlight, rect)
	_place_rect(_contact_shadow, Rect2(rect.position.x, rect.position.y + frame_h * 0.72, rect.size.x, frame_h * 0.35))
	_place_rect(_front_lip, Rect2(rect.position.x, rect.position.y + frame_h * 0.55, rect.size.x, frame_h * 0.45))
	var scroll_w := area.x * 0.55
	var scroll_h := scroll_w * 0.30
	_scroll_spawn.position = Vector2(area.x * 0.5 - scroll_w * 0.5, rect.position.y + frame_h * 0.48)
	_rolled_scroll.position = Vector2.ZERO
	_rolled_scroll.size = Vector2(scroll_w, scroll_h)
	_rolled_scroll.pivot_offset = Vector2(scroll_w * 0.5, scroll_h * 0.5)
	_dust.position = Vector2(area.x * 0.5, rect.position.y + frame_h * 0.42)
	_sparks.position = _dust.position
	if _badge:
		_badge.position = Vector2(area.x * 0.72, top + frame_h * 0.08)
		_badge.size = Vector2(40, 40)


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
	bg.set_corner_radius_all(20)
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
			_interior_glow.modulate.a = 0.10
			_label.visible = show_final_label
			_label.text = "Your Chest"
			_show_frame_state(0.0)
		ChestState.OPENED:
			self_modulate = Color.WHITE
			_show_frame_state(1.0)
			_label.visible = false
			_interior_glow.modulate.a = 0.65
			_front_lip.modulate.a = 0.0
		_:
			pass


func _show_frame_state(open_amount: float) -> void:
	_open_amount = clampf(open_amount, 0.0, 1.0)
	if _frame_nodes.is_empty():
		return
	for n in _frame_nodes:
		(n as TextureRect).modulate.a = 0.0
	## Two-frame blend: closed (0) ↔ open (1). Same canvas size/placement.
	var t := _open_amount
	(_frame_nodes[0] as TextureRect).modulate.a = 1.0 - t
	if _frame_nodes.size() > 1:
		(_frame_nodes[1] as TextureRect).modulate.a = t
	## Warm amber glow tied to openness.
	var glow_a := 0.0
	if _open_amount < 0.15:
		glow_a = _open_amount * 0.5
	elif _open_amount < 0.35:
		glow_a = 0.08 + (_open_amount - 0.15) * 0.9
	elif _open_amount < 0.65:
		glow_a = 0.26 + (_open_amount - 0.35) * 0.8
	else:
		glow_a = 0.50 + (_open_amount - 0.65) * 0.55
	_interior_glow.modulate = Color(1.16, 0.88, 0.52, clampf(glow_a, 0.0, 0.78))
	if _contact_shadow:
		_contact_shadow.scale = Vector2(1.0 + _open_amount * 0.04, 1.0)
		_contact_shadow.modulate.a = 0.78 + _open_amount * 0.12


func _reset_pose() -> void:
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
	_layout_frames()
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
		var breathe: float = 1.0 + sin(_idle_time * 1.0) * 0.005
		_root_visual.scale = Vector2(breathe, breathe) * _press_scale
		_root_visual.position = Vector2((1.0 - breathe) * size.x * 0.5, 0.0)
		_highlight.modulate.a = 0.16 + 0.08 * sin(_idle_time * 1.4)


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
	tween.tween_property(self, "_press_scale", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func play_open_animation(short: bool = false, emerge_scroll: bool = true) -> void:
	if animating or chest_state == ChestState.OPENING or chest_state == ChestState.CLOSING:
		return
	animating = true
	_input_locked = true
	_skip = false
	_show_scroll_on_finish = emerge_scroll
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
	if animating or chest_state == ChestState.OPENING:
		return
	animating = true
	_input_locked = true
	chest_state = ChestState.CLOSING
	hide_rolled_scroll()
	var dur := 0.40 if reduced_motion else 0.85
	var tw := create_tween()
	tw.tween_method(_show_frame_state, _open_amount, 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_show_frame_state(0.0)
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
	_show_frame_state(0.0)
	var tw := create_tween()
	tw.tween_method(_show_frame_state, 0.0, 1.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished


func _open_full() -> void:
	_layout_frames()
	## 0.00–0.12 subtle press — base stays planted (uniform scale only).
	var press := create_tween()
	press.tween_property(_root_visual, "scale", Vector2(0.985, 0.985), 0.12).set_trans(Tween.TRANS_SINE)
	await press.finished
	if _skip:
		_apply_finished_state()
		return
	var unpress := create_tween()
	unpress.tween_property(_root_visual, "scale", Vector2.ONE, 0.10)
	await unpress.finished
	if _skip:
		_apply_finished_state()
		return

	## Weighted lid: slow start → mid → soft settle. ~1.35s lid + settle.
	## Hardware stays in the artwork (no detached latch/lock nodes).
	HapticHelper.lock_release()
	_front_lip.modulate.a = 0.55
	var lid := create_tween()
	lid.tween_method(_show_frame_state, 0.0, 1.0, 1.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.55).timeout
	if not _skip and not reduced_motion:
		_emit_burst()
	await lid.finished
	if _skip:
		_apply_finished_state()
		return
	await get_tree().create_timer(0.20).timeout
	if _show_scroll_on_finish:
		await _emerge_scroll()
		scroll_emerged.emit(get_scroll_global_center())


func _emerge_scroll() -> void:
	## Rise from inside rim: fade 0→1, scale 0.92→1.0, ~0.4s.
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.scale = Vector2(0.92, 0.92)
	_rolled_scroll.position = Vector2(0, 28)
	_front_lip.modulate.a = 0.85
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rolled_scroll, "modulate:a", 1.0, 0.40).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "position:y", -36.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	var soft := create_tween()
	soft.tween_property(_front_lip, "modulate:a", 0.25, 0.16)
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
	_root_visual.scale = Vector2.ONE
	_root_visual.position = Vector2.ZERO
	_front_lip.modulate.a = 0.0
	if _show_scroll_on_finish:
		_rolled_scroll.modulate.a = 1.0
		_rolled_scroll.position = Vector2(0, -36)
		_rolled_scroll.scale = Vector2.ONE
	else:
		_rolled_scroll.modulate.a = 0.0


func _emit_burst() -> void:
	_dust.restart()
	_dust.emitting = true
	_sparks.restart()
	_sparks.emitting = true


func request_skip() -> void:
	_skip = true


func frame_count() -> int:
	return _frame_nodes.size()
