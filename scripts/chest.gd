extends Control
class_name TreasureChest

## Layered treasure chest with idle, opening, opened, and final-gift states.

signal tapped
signal open_finished
signal skip_requested

enum ChestState { LOCKED_SILHOUETTE, AVAILABLE, OPENING, OPENED, FINAL_GIFT }

const ART := "res://assets/art/chest/"

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _label: Label
var _layers: Dictionary = {}
var _particles_sparkle: CPUParticles2D
var _particles_beam: CPUParticles2D
var _root_visual: Control
var _lid: Control
var _lock: Control
var _glow: Control
var _press_scale: float = 1.0
var _button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(420, 420)
	_build_visuals()
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = "Anniversary treasure chest"
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	set_process(true)


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_visual)

	var order: PackedStringArray = [
		"chest_glow", "chest_shadow", "chest_interior", "chest_base",
		"chest_hinges", "chest_lid", "chest_trim", "chest_highlight", "chest_lock"
	]
	for name in order:
		var tex_rect := TextureRect.new()
		tex_rect.name = name
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var path: String = ART.path_join(name + ".png")
		if ResourceLoader.exists(path):
			tex_rect.texture = load(path)
		_root_visual.add_child(tex_rect)
		_layers[name] = tex_rect

	_glow = _layers.get("chest_glow")
	_lid = _layers.get("chest_lid")
	_lock = _layers.get("chest_lock")

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(0, -8)
	_label.size = Vector2(420, 36)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_particles_sparkle = _make_particles(Color(1.0, 0.9, 0.55, 1.0), 18)
	_particles_beam = _make_particles(Color(1.0, 0.75, 0.35, 1.0), 28)
	_particles_beam.position = size * 0.5 if size.x > 0.0 else Vector2(210, 210)
	_root_visual.add_child(_particles_sparkle)
	_root_visual.add_child(_particles_beam)


func _make_particles(color: Color, amount: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2(0, 30)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = color
	p.z_index = 20
	return p


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_reset_visual_transforms()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			modulate = Color(0.55, 0.55, 0.75, 0.85)
			if _glow:
				_glow.modulate.a = 0.35
			_label.visible = false
		ChestState.AVAILABLE:
			modulate = Color.WHITE
			if _glow:
				_glow.modulate.a = 1.0
			_label.visible = false
		ChestState.OPENED:
			modulate = Color.WHITE
			_set_opened_pose()
			_label.visible = false
		ChestState.FINAL_GIFT:
			modulate = Color(1.05, 0.95, 1.0, 1.0)
			if _glow:
				_glow.modulate = Color(1.2, 0.75, 0.95, 1.0)
			_label.text = "One More Surprise"
			_label.visible = show_final_label
			_reset_visual_transforms()
		_:
			pass


func _reset_visual_transforms() -> void:
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
	if _lid:
		_lid.rotation = 0.0
		_lid.position = Vector2.ZERO
		_lid.pivot_offset = _lid.size * Vector2(0.5, 1.0) if _lid.size.y > 0.0 else Vector2(210, 250)
	if _lock:
		_lock.rotation = 0.0
		_lock.position = Vector2.ZERO
		_lock.modulate.a = 1.0


func _set_opened_pose() -> void:
	if _lid:
		_lid.pivot_offset = Vector2(_lid.size.x * 0.5, _lid.size.y * 0.45)
		_lid.rotation = deg_to_rad(-118.0)
	if _lock:
		_lock.modulate.a = 0.0
	if _layers.has("chest_interior"):
		_layers["chest_interior"].modulate.a = 1.0


func _process(delta: float) -> void:
	if animating or reduced_motion:
		return
	_idle_time += delta
	if chest_state == ChestState.AVAILABLE or chest_state == ChestState.FINAL_GIFT:
		var breathe: float = 1.0 + sin(_idle_time * 1.4) * 0.012
		var float_y: float = sin(_idle_time * 1.1) * 4.0
		if _root_visual:
			_root_visual.scale = Vector2(breathe, breathe) * _press_scale
			_root_visual.position = Vector2((1.0 - breathe) * size.x * 0.5, float_y)
		if _glow:
			var pulse: float = 0.75 + 0.25 * sin(_idle_time * 1.7)
			if chest_state == ChestState.FINAL_GIFT:
				pulse = 0.85 + 0.25 * sin(_idle_time * 2.1)
				_glow.modulate = Color(1.15, 0.7 + 0.15 * sin(_idle_time), 0.9, pulse)
			else:
				_glow.modulate.a = pulse
		if _layers.has("chest_highlight"):
			_layers["chest_highlight"].modulate.a = 0.35 + 0.35 * sin(_idle_time * 2.4 + 1.2)
		if _layers.has("chest_shadow"):
			var shadow_scale: float = 1.0 + sin(_idle_time * 1.1) * 0.04
			_layers["chest_shadow"].scale = Vector2(shadow_scale, 1.0)
			_layers["chest_shadow"].position.x = (1.0 - shadow_scale) * size.x * 0.5


func _on_pressed() -> void:
	if animating:
		_skip = true
		skip_requested.emit()
		return
	tapped.emit()


func play_press_feedback() -> void:
	HapticHelper.light_tap()
	var tween := create_tween()
	_press_scale = 0.97
	tween.tween_property(self, "_press_scale", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_open_animation(short: bool = false) -> void:
	if animating:
		return
	animating = true
	_skip = false
	chest_state = ChestState.OPENING
	play_press_feedback()
	if reduced_motion or short:
		await _open_short()
	else:
		await _open_full()
	chest_state = ChestState.OPENED
	animating = false
	open_finished.emit()


func play_final_reopen_animation() -> void:
	if animating:
		return
	animating = true
	_skip = false
	play_press_feedback()
	await _open_short()
	animating = false
	open_finished.emit()


func _open_short() -> void:
	_emit_burst()
	_set_opened_pose()
	var tween := create_tween()
	tween.tween_property(_root_visual, "scale", Vector2(1.04, 1.04), 0.12)
	tween.tween_property(_root_visual, "scale", Vector2.ONE, 0.18)
	await tween.finished


func _open_full() -> void:
	if _lid:
		_lid.pivot_offset = Vector2(_lid.size.x * 0.5, _lid.size.y * 0.48)

	# Lock shake + release
	if _lock and not _skip:
		var lock_tween := create_tween()
		for i in 4:
			lock_tween.tween_property(_lock, "position:x", 6.0 if i % 2 == 0 else -6.0, 0.04)
		lock_tween.tween_property(_lock, "position", Vector2(0, 28), 0.22).set_trans(Tween.TRANS_BACK)
		lock_tween.parallel().tween_property(_lock, "modulate:a", 0.0, 0.25)
		HapticHelper.lock_release()
		await lock_tween.finished
	if _skip:
		_set_opened_pose()
		_emit_burst()
		return

	# Anticipation dip
	var dip := create_tween()
	dip.tween_property(_root_visual, "position:y", 10.0, 0.12).set_trans(Tween.TRANS_SINE)
	dip.tween_property(_root_visual, "position:y", -6.0, 0.18).set_trans(Tween.TRANS_BACK)
	await dip.finished
	if _skip:
		_set_opened_pose()
		_emit_burst()
		return

	# Lid open with overshoot
	if _lid:
		var lid_tween := create_tween()
		lid_tween.tween_property(_lid, "rotation", deg_to_rad(-130.0), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lid_tween.tween_property(_lid, "rotation", deg_to_rad(-118.0), 0.18)
		await lid_tween.finished
	_emit_burst()
	if _skip:
		_set_opened_pose()


func _emit_burst() -> void:
	var center := size * 0.5
	if center == Vector2.ZERO:
		center = Vector2(210, 220)
	_particles_sparkle.position = center + Vector2(0, -20)
	_particles_beam.position = center + Vector2(0, -10)
	_particles_sparkle.restart()
	_particles_sparkle.emitting = true
	_particles_beam.restart()
	_particles_beam.emitting = true
	if _glow:
		var g := create_tween()
		g.tween_property(_glow, "modulate:a", 1.4, 0.15)
		g.tween_property(_glow, "modulate:a", 0.9, 0.45)


func request_skip() -> void:
	_skip = true
