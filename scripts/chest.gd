extends Control
class_name TreasureChest

## Photoreal treasure chest using frame-based lid opening (closed→ajar→half→open).
## Front-facing rendered plates cannot hinge with 2D rotation; frames look physical.

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged(global_pos: Vector2)

enum ChestState { LOCKED_SILHOUETTE, AVAILABLE, OPENING, OPENED, FINAL_GIFT }

const ART := "res://assets/art/chest/"
const SCROLL_ART := "res://assets/art/scroll/"

## Shared canvas scale for all frame plates (matches closed art aspect).
const FRAME_SIZE := Vector2(560, 383)

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _input_locked: bool = false
var _label: Label
var _root_visual: Control
var _contact_shadow: TextureRect
var _frame_closed: TextureRect
var _frame_ajar: TextureRect
var _frame_half: TextureRect
var _frame_open: TextureRect
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
var _tex_closed: Texture2D
var _tex_ajar: Texture2D
var _tex_half: Texture2D
var _tex_open: Texture2D
var _tex_glow: Texture2D
var _tex_shadow: Texture2D
var _tex_lip: Texture2D
var _tex_latch: Texture2D
var _tex_lock: Texture2D
var _tex_highlight: Texture2D
var _tex_rolled: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(560, 560)
	# Invisible until textures are preloaded and layered.
	modulate.a = 0.0
	visible = false
	_preload_textures()
	_build_visuals()
	_ready_visuals = true
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = "Anniversary treasure chest"
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	set_process(true)
	resized.connect(_layout_frames)
	_layout_frames()
	_show_frame_state(0.0)
	# Fade in only after first layout with realistic frames.
	visible = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _preload_textures() -> void:
	_tex_closed = _load_tex(ART + "chest_closed.png")
	_tex_ajar = _load_tex(ART + "chest_ajar.png")
	_tex_half = _load_tex(ART + "chest_half.png")
	_tex_open = _load_tex(ART + "chest_open.png")
	_tex_glow = _load_tex(ART + "chest_inner_glow.png")
	_tex_shadow = _load_tex(ART + "chest_contact_shadow.png")
	_tex_lip = _load_tex(ART + "chest_front_lip.png")
	_tex_latch = _load_tex(ART + "chest_latch.png")
	_tex_lock = _load_tex(ART + "chest_lock.png")
	_tex_highlight = _load_tex(ART + "chest_highlight.png")
	_tex_rolled = _load_tex(SCROLL_ART + "scroll_rolled.png")


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
	return tr


func _build_visuals() -> void:
	## Z-order (documented):
	## 0 ContactShadow
	## 1 InteriorGlow (under frames)
	## 2 Frame plates (closed/ajar/half/open)
	## 3 RolledScroll (inside opening)
	## 4 ForegroundLip (masks scroll bottom)
	## 5 Latch / Lock overlays during open
	## 6 Highlight
	## 10+ Particles
	_root_visual = Control.new()
	_root_visual.name = "ChestRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_visual.pivot_offset = Vector2(280, 280)
	add_child(_root_visual)

	_contact_shadow = _make_frame(_tex_shadow, 0, "ContactShadow")
	_contact_shadow.modulate = Color(1, 1, 1, 0.88)
	_root_visual.add_child(_contact_shadow)

	_interior_glow = _make_frame(_tex_glow, 1, "InteriorGlow")
	_interior_glow.modulate = Color(1.15, 0.9, 0.55, 0.0)
	_root_visual.add_child(_interior_glow)

	_frame_closed = _make_frame(_tex_closed, 2, "FrameClosed")
	_root_visual.add_child(_frame_closed)
	_frame_ajar = _make_frame(_tex_ajar, 2, "FrameAjar")
	_frame_ajar.modulate.a = 0.0
	_root_visual.add_child(_frame_ajar)
	_frame_half = _make_frame(_tex_half, 2, "FrameHalf")
	_frame_half.modulate.a = 0.0
	_root_visual.add_child(_frame_half)
	_frame_open = _make_frame(_tex_open, 2, "FrameOpen")
	_frame_open.modulate.a = 0.0
	_root_visual.add_child(_frame_open)

	_scroll_spawn = Control.new()
	_scroll_spawn.name = "ScrollSpawnPoint"
	_scroll_spawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_spawn.z_index = 3
	_root_visual.add_child(_scroll_spawn)

	_rolled_scroll = TextureRect.new()
	_rolled_scroll.name = "RolledScroll"
	_rolled_scroll.texture = _tex_rolled
	_rolled_scroll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rolled_scroll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rolled_scroll.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rolled_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.size = Vector2(300, 70)
	_rolled_scroll.pivot_offset = Vector2(150, 35)
	_scroll_spawn.add_child(_rolled_scroll)

	_front_lip = _make_frame(_tex_lip, 4, "ForegroundLip")
	_front_lip.modulate.a = 0.0
	_root_visual.add_child(_front_lip)

	_latch = TextureRect.new()
	_latch.name = "Latch"
	_latch.texture = _tex_latch
	_latch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_latch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_latch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_latch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_latch.z_index = 5
	_latch.modulate.a = 0.0
	_latch.size = Vector2(140, 36)
	_latch.pivot_offset = Vector2(70, 18)
	_root_visual.add_child(_latch)

	_lock = TextureRect.new()
	_lock.name = "Lock"
	_lock.texture = _tex_lock
	_lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock.z_index = 5
	_lock.modulate.a = 0.0
	_lock.size = Vector2(72, 96)
	_lock.pivot_offset = Vector2(36, 16)
	_root_visual.add_child(_lock)

	_highlight = _make_frame(_tex_highlight, 6, "Highlight")
	_highlight.modulate = Color(1, 1, 1, 0.35)
	_root_visual.add_child(_highlight)

	_dust = _make_particles(Color(0.85, 0.75, 0.55, 0.6), 12, Vector2(0, -1), 22.0)
	_dust.name = "DustParticles"
	_dust.z_index = 10
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.82, 0.42, 0.9), 14, Vector2(0, -1), 70.0)
	_sparks.name = "SparkParticles"
	_sparks.z_index = 11
	_root_visual.add_child(_sparks)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 22)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_top = -8
	_label.offset_bottom = 28
	_label.offset_left = -160
	_label.offset_right = 160
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 12
	add_child(_label)


func _make_particles(color: Color, amount: int, dir: Vector2, speed: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.3
	p.one_shot = true
	p.explosiveness = 0.6
	p.local_coords = false
	p.direction = dir
	p.spread = 42.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 28)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color = color
	return p


func _layout_frames() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(560, 560)
	_root_visual.pivot_offset = area * 0.5
	# Frame plates share the same rect so crossfades align.
	var frame_h: float = area.x * (FRAME_SIZE.y / FRAME_SIZE.x)
	var top: float = (area.y - frame_h) * 0.42
	var rect := Rect2(0, top, area.x, frame_h)
	for node in [_contact_shadow, _interior_glow, _frame_closed, _frame_ajar, _frame_half, _frame_open, _highlight]:
		_place_rect(node, rect)
	# Shadow sits slightly lower.
	_place_rect(_contact_shadow, Rect2(rect.position.x, rect.position.y + frame_h * 0.72, rect.size.x, frame_h * 0.35))
	# Front lip covers lower third of frame (masks rising scroll).
	_place_rect(_front_lip, Rect2(rect.position.x, rect.position.y + frame_h * 0.55, rect.size.x, frame_h * 0.45))
	# Scroll spawn inside cavity.
	_scroll_spawn.position = Vector2(area.x * 0.5 - 150.0, rect.position.y + frame_h * 0.42)
	_rolled_scroll.position = Vector2.ZERO
	_rolled_scroll.size = Vector2(300, 70)
	_rolled_scroll.pivot_offset = Vector2(150, 35)
	# Latch / lock over front center of closed chest.
	_latch.position = Vector2(area.x * 0.5 - 70.0, rect.position.y + frame_h * 0.48)
	_lock.position = Vector2(area.x * 0.5 - 36.0, rect.position.y + frame_h * 0.52)
	_dust.position = Vector2(area.x * 0.5, rect.position.y + frame_h * 0.4)
	_sparks.position = _dust.position


func _place_rect(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.position = rect.position
	node.size = rect.size


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
		ChestState.AVAILABLE:
			self_modulate = Color.WHITE
			_interior_glow.modulate.a = 0.15
			_label.visible = false
			_show_frame_state(0.0)
		ChestState.OPENED:
			self_modulate = Color.WHITE
			_show_frame_state(1.0)
			_label.visible = false
			_interior_glow.modulate.a = 0.7
			_front_lip.modulate.a = 0.0
		ChestState.FINAL_GIFT:
			self_modulate = Color(1.05, 0.95, 1.05, 1.0)
			_interior_glow.modulate = Color(1.25, 0.75, 0.95, 0.45)
			_label.text = "One More Surprise"
			_label.visible = show_final_label
			_show_frame_state(0.0)
		_:
			pass


func _show_frame_state(open_amount: float) -> void:
	## open_amount 0=closed, 0.33=ajar, 0.66=half, 1=open
	open_amount = clampf(open_amount, 0.0, 1.0)
	var a_closed := 0.0
	var a_ajar := 0.0
	var a_half := 0.0
	var a_open := 0.0
	if open_amount <= 0.0:
		a_closed = 1.0
	elif open_amount < 0.33:
		var t := open_amount / 0.33
		a_closed = 1.0 - t
		a_ajar = t
	elif open_amount < 0.66:
		var t2 := (open_amount - 0.33) / 0.33
		a_ajar = 1.0 - t2
		a_half = t2
	else:
		var t3 := (open_amount - 0.66) / 0.34
		a_half = 1.0 - t3
		a_open = t3
	_frame_closed.modulate.a = a_closed
	_frame_ajar.modulate.a = a_ajar
	_frame_half.modulate.a = a_half
	_frame_open.modulate.a = a_open


func _reset_pose() -> void:
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
	_layout_frames()
	if _latch:
		_latch.modulate.a = 0.0
		_latch.rotation = 0.0
		_latch.position.x = size.x * 0.5 - 70.0 if size.x > 0 else 210.0
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
	if chest_state == ChestState.AVAILABLE or chest_state == ChestState.FINAL_GIFT:
		var breathe: float = 1.0 + sin(_idle_time * 1.15) * 0.008
		var float_y: float = sin(_idle_time * 0.85) * 2.0
		_root_visual.scale = Vector2(breathe, breathe) * _press_scale
		_root_visual.position = Vector2((1.0 - breathe) * size.x * 0.5, float_y)
		if chest_state == ChestState.FINAL_GIFT:
			_interior_glow.modulate = Color(1.2, 0.72, 0.95, 0.3 + 0.15 * sin(_idle_time * 1.7))
		else:
			_interior_glow.modulate.a = 0.12 + 0.08 * sin(_idle_time * 1.4)
		_highlight.modulate.a = 0.2 + 0.12 * sin(_idle_time * 1.8)


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
	tween.tween_property(self, "_press_scale", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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


func play_final_reopen_animation() -> void:
	if animating:
		return
	animating = true
	_input_locked = true
	_skip = false
	play_press_feedback()
	await _open_short()
	_apply_finished_state()
	animating = false
	_input_locked = false
	open_finished.emit()


func _open_short() -> void:
	_emit_burst()
	var tw := create_tween()
	tw.tween_method(_show_frame_state, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_interior_glow, "modulate:a", 0.75, 0.3)
	tw.parallel().tween_property(_root_visual, "scale", Vector2(1.02, 1.02), 0.12)
	tw.tween_property(_root_visual, "scale", Vector2.ONE, 0.15)
	await tw.finished


func _open_full() -> void:
	_layout_frames()

	# 0.00–0.12: compress ~2%
	var press := create_tween()
	press.tween_property(_root_visual, "scale", Vector2(1.0, 0.98), 0.12).set_trans(Tween.TRANS_SINE)
	press.parallel().tween_property(_contact_shadow, "scale", Vector2(0.96, 1.0), 0.12)
	await press.finished
	if _skip:
		_apply_finished_state()
		return

	# 0.12–0.32: return + latch shake + slight lock rotate
	_latch.modulate.a = 1.0
	_lock.modulate.a = 1.0
	HapticHelper.lock_release()
	var shake := create_tween()
	shake.tween_property(_root_visual, "scale", Vector2.ONE, 0.12)
	shake.parallel().tween_property(_contact_shadow, "scale", Vector2.ONE, 0.12)
	for i in 4:
		shake.tween_property(_latch, "position:x", (size.x * 0.5 - 70.0) + (3.0 if i % 2 == 0 else -3.0), 0.04)
	shake.tween_property(_latch, "position:x", size.x * 0.5 - 70.0, 0.04)
	shake.parallel().tween_property(_lock, "rotation", deg_to_rad(10.0), 0.18)
	await shake.finished
	if _skip:
		_apply_finished_state()
		return

	# 0.32–0.55: latch release, lock drops short distance
	var release := create_tween()
	release.tween_property(_latch, "modulate:a", 0.0, 0.18)
	release.parallel().tween_property(_lock, "position:y", _lock.position.y + 28.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	release.parallel().tween_property(_lock, "modulate:a", 0.0, 0.22)
	await release.finished
	if _skip:
		_apply_finished_state()
		return

	# 0.45–1.20: frame-based lid open (weighty ease)
	_front_lip.modulate.a = 1.0
	var lid := create_tween()
	lid.tween_method(_show_frame_state, 0.0, 1.0, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	lid.parallel().tween_property(_interior_glow, "modulate:a", 0.85, 0.55)
	await get_tree().create_timer(0.25).timeout
	if _skip:
		_apply_finished_state()
		return
	_emit_burst()
	await lid.finished
	if _skip:
		_apply_finished_state()
		return

	# Soft settle (no bounce)
	var settle := create_tween()
	settle.tween_method(_show_frame_state, 1.0, 0.97, 0.08)
	settle.tween_method(_show_frame_state, 0.97, 1.0, 0.12)
	await settle.finished

	# 1.10–1.60: scroll rises from spawn (no dramatic scale)
	await _emerge_scroll()
	scroll_emerged.emit(get_scroll_global_center())


func _emerge_scroll() -> void:
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.position = Vector2(0, 40)
	_rolled_scroll.rotation = deg_to_rad(-4.0)
	_rolled_scroll.scale = Vector2.ONE
	_front_lip.modulate.a = 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rolled_scroll, "modulate:a", 1.0, 0.2)
	tw.tween_property(_rolled_scroll, "position:y", -55.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "position:x", 8.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_rolled_scroll, "rotation", deg_to_rad(3.0), 0.5)
	await tw.finished
	var settle := create_tween()
	settle.tween_property(_rolled_scroll, "rotation", 0.0, 0.15)
	settle.parallel().tween_property(_rolled_scroll, "position:x", 0.0, 0.15)
	# Soften lip once scroll is clear.
	settle.parallel().tween_property(_front_lip, "modulate:a", 0.35, 0.2)
	await settle.finished


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
	_interior_glow.modulate.a = 0.75
	_latch.modulate.a = 0.0
	_lock.modulate.a = 0.0
	_lock.rotation = 0.0
	_root_visual.scale = Vector2.ONE
	_root_visual.position = Vector2.ZERO
	_contact_shadow.scale = Vector2.ONE
	_front_lip.modulate.a = 0.0
	_rolled_scroll.modulate.a = 1.0
	_rolled_scroll.position = Vector2(0, -55)
	_rolled_scroll.rotation = 0.0
	_rolled_scroll.scale = Vector2.ONE


func _emit_burst() -> void:
	_dust.restart()
	_dust.emitting = true
	_sparks.restart()
	_sparks.emitting = true


func request_skip() -> void:
	_skip = true
