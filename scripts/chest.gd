extends Control
class_name TreasureChest

## Photoreal layered treasure chest with rear-hinge lid animation.

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged

enum ChestState { LOCKED_SILHOUETTE, AVAILABLE, OPENING, OPENED, FINAL_GIFT }

const ART := "res://assets/art/chest/"
const SCROLL_ART := "res://assets/art/scroll/"

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _label: Label
var _root_visual: Control
var _contact_shadow: TextureRect
var _chest_base: TextureRect
var _chest_closed: TextureRect
var _chest_open: TextureRect
var _interior: TextureRect
var _inner_glow: TextureRect
var _lid_pivot: Control
var _lid: TextureRect
var _lid_trim: TextureRect
var _lock_pivot: Control
var _lock: TextureRect
var _latch: TextureRect
var _highlight: TextureRect
var _rolled_scroll: TextureRect
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _button: Button
var _press_scale: float = 1.0
var _anim_player: AnimationPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(560, 560)
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
	resized.connect(_on_resized)


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _make_layer(tex: Texture2D, z: int = 0) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.texture = tex
	tr.z_index = z
	return tr


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.name = "ChestRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_visual.pivot_offset = Vector2(280, 280)
	add_child(_root_visual)

	_contact_shadow = _make_layer(_tex(ART + "chest_contact_shadow.png"), 0)
	_contact_shadow.name = "ContactShadow"
	_contact_shadow.modulate = Color(1, 1, 1, 0.9)
	_root_visual.add_child(_contact_shadow)

	_chest_base = _make_layer(_tex(ART + "chest_base.png"), 1)
	_chest_base.name = "ChestBase"
	_chest_base.modulate.a = 0.0
	_root_visual.add_child(_chest_base)

	_interior = _make_layer(_tex(ART + "chest_interior.png"), 2)
	_interior.name = "ChestInterior"
	_interior.modulate.a = 0.0
	_root_visual.add_child(_interior)

	_inner_glow = _make_layer(_tex(ART + "chest_inner_glow.png"), 3)
	_inner_glow.name = "InnerGlow"
	_inner_glow.modulate = Color(1.15, 0.92, 0.55, 0.0)
	_root_visual.add_child(_inner_glow)

	# Rolled scroll sits inside and rises after the lid opens.
	_rolled_scroll = TextureRect.new()
	_rolled_scroll.name = "RolledScroll"
	_rolled_scroll.texture = _tex(SCROLL_ART + "scroll_rolled.png")
	_rolled_scroll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rolled_scroll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rolled_scroll.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rolled_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rolled_scroll.z_index = 4
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.set_anchors_preset(Control.PRESET_CENTER)
	_rolled_scroll.offset_left = -180
	_rolled_scroll.offset_right = 180
	_rolled_scroll.offset_top = 40
	_rolled_scroll.offset_bottom = 140
	_root_visual.add_child(_rolled_scroll)

	# Photoreal closed plate — primary idle artwork.
	_chest_closed = _make_layer(_tex(ART + "chest_closed.png"), 5)
	_chest_closed.name = "ChestClosed"
	_root_visual.add_child(_chest_closed)

	# Photoreal open plate revealed as the lid finishes.
	_chest_open = _make_layer(_tex(ART + "chest_open.png"), 5)
	_chest_open.name = "ChestOpen"
	_chest_open.modulate.a = 0.0
	_root_visual.add_child(_chest_open)

	# Lid pivot at rear hinge line (upper-back of chest face).
	_lid_pivot = Control.new()
	_lid_pivot.name = "ChestLidPivot"
	_lid_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lid_pivot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lid_pivot.pivot_offset = Vector2(280, 200)
	_lid_pivot.z_index = 6
	_root_visual.add_child(_lid_pivot)

	_lid = _make_layer(_tex(ART + "chest_lid.png"), 6)
	_lid.name = "ChestLid"
	_lid.modulate.a = 0.0
	_lid_pivot.add_child(_lid)

	_lid_trim = _make_layer(_tex(ART + "chest_front_trim.png"), 7)
	_lid_trim.name = "LidTrim"
	_lid_trim.modulate.a = 0.0
	_lid_pivot.add_child(_lid_trim)

	_lock_pivot = Control.new()
	_lock_pivot.name = "LockPivot"
	_lock_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_pivot.set_anchors_preset(Control.PRESET_CENTER)
	_lock_pivot.offset_left = -40
	_lock_pivot.offset_right = 40
	_lock_pivot.offset_top = 20
	_lock_pivot.offset_bottom = 140
	_lock_pivot.pivot_offset = Vector2(40, 20)
	_lock_pivot.z_index = 9
	_root_visual.add_child(_lock_pivot)

	_lock = TextureRect.new()
	_lock.name = "Lock"
	_lock.texture = _tex(ART + "chest_lock.png")
	_lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lock_pivot.add_child(_lock)

	_latch = TextureRect.new()
	_latch.name = "Latch"
	_latch.texture = _tex(ART + "chest_latch.png")
	_latch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_latch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_latch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_latch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_latch.z_index = 8
	_latch.set_anchors_preset(Control.PRESET_CENTER)
	_latch.offset_left = -90
	_latch.offset_right = 90
	_latch.offset_top = -10
	_latch.offset_bottom = 40
	_root_visual.add_child(_latch)

	_highlight = _make_layer(_tex(ART + "chest_highlight.png"), 10)
	_highlight.name = "Highlight"
	_highlight.modulate = Color(1, 1, 1, 0.4)
	_root_visual.add_child(_highlight)

	_dust = _make_particles(Color(0.85, 0.75, 0.55, 0.65), 16, Vector2(0, -1), 28.0)
	_dust.name = "DustParticles"
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.82, 0.42, 0.95), 18, Vector2(0, -1), 85.0)
	_sparks.name = "SparkParticles"
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

	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimationPlayer"
	add_child(_anim_player)
	_update_pivots()


func _make_particles(color: Color, amount: int, dir: Vector2, speed: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.65
	p.local_coords = false
	p.direction = dir
	p.spread = 46.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 30)
	p.scale_amount_min = 1.1
	p.scale_amount_max = 2.6
	p.color = color
	p.z_index = 11
	p.position = Vector2(280, 260)
	return p


func _on_resized() -> void:
	_update_pivots()


func _update_pivots() -> void:
	if _root_visual:
		_root_visual.pivot_offset = size * 0.5
	if _lid_pivot:
		# Rear hinge line — upper third of the chest art.
		_lid_pivot.pivot_offset = size * Vector2(0.5, 0.34)
	if _lock_pivot and size.y > 0.0:
		_lock_pivot.pivot_offset = Vector2(_lock_pivot.size.x * 0.5, 12.0)
	if _dust:
		_dust.position = size * Vector2(0.5, 0.48)
	if _sparks:
		_sparks.position = size * Vector2(0.5, 0.48)


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_reset_pose()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			modulate = Color(0.55, 0.55, 0.75, 0.9)
			_inner_glow.modulate.a = 0.12
			_label.visible = false
			_show_closed(true)
		ChestState.AVAILABLE:
			modulate = Color.WHITE
			_inner_glow.modulate.a = 0.18
			_label.visible = false
			_show_closed(true)
		ChestState.OPENED:
			modulate = Color.WHITE
			_show_closed(false)
			_label.visible = false
		ChestState.FINAL_GIFT:
			modulate = Color(1.05, 0.95, 1.05, 1.0)
			_inner_glow.modulate = Color(1.25, 0.75, 0.95, 0.5)
			_label.text = "One More Surprise"
			_label.visible = show_final_label
			_show_closed(true)
		_:
			pass


func _show_closed(closed: bool) -> void:
	# Idle closed uses the full photoreal plate (lock/latch baked in).
	# Separate lock/latch/lid layers only appear during the open sequence.
	_chest_closed.modulate.a = 1.0 if closed else 0.0
	_chest_open.modulate.a = 0.0 if closed else 1.0
	_chest_base.modulate.a = 0.0 if closed else 0.95
	_interior.modulate.a = 0.0 if closed else 0.9
	_lid.modulate.a = 0.0
	_lid_trim.modulate.a = 0.0
	_lock.modulate.a = 0.0
	_latch.modulate.a = 0.0
	_lock_pivot.modulate.a = 0.0
	_lid_pivot.rotation = 0.0
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.position = Vector2.ZERO
	_rolled_scroll.rotation = 0.0
	_inner_glow.modulate.a = 0.18 if closed else 0.7


func _reset_pose() -> void:
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
	_update_pivots()
	if _lid_pivot:
		_lid_pivot.rotation = 0.0
	if _lock_pivot:
		_lock_pivot.rotation = 0.0
		_lock_pivot.position = Vector2.ZERO
	if _lock:
		_lock.position = Vector2.ZERO
		_lock.rotation = 0.0
	if _latch:
		_latch.position = Vector2.ZERO
		_latch.rotation = 0.0


func _process(delta: float) -> void:
	if animating or reduced_motion:
		return
	_idle_time += delta
	if chest_state == ChestState.AVAILABLE or chest_state == ChestState.FINAL_GIFT:
		var breathe: float = 1.0 + sin(_idle_time * 1.2) * 0.01
		var float_y: float = sin(_idle_time * 0.9) * 2.5
		_root_visual.scale = Vector2(breathe, breathe) * _press_scale
		_root_visual.position = Vector2((1.0 - breathe) * size.x * 0.5, float_y)
		if chest_state == ChestState.FINAL_GIFT:
			_inner_glow.modulate = Color(1.2, 0.72, 0.95, 0.35 + 0.18 * sin(_idle_time * 1.8))
		else:
			_inner_glow.modulate.a = 0.16 + 0.1 * sin(_idle_time * 1.45)
		_highlight.modulate.a = 0.22 + 0.16 * sin(_idle_time * 1.9)
		var shadow_scale: float = 1.0 + sin(_idle_time * 0.9) * 0.025
		_contact_shadow.scale = Vector2(shadow_scale, 1.0)
		_contact_shadow.position.x = (1.0 - shadow_scale) * size.x * 0.5


func _on_pressed() -> void:
	if animating:
		_skip = true
		skip_requested.emit()
		return
	tapped.emit()


func play_press_feedback() -> void:
	HapticHelper.light_tap()
	var tween := create_tween()
	_press_scale = 0.98
	tween.tween_property(self, "_press_scale", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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
	_show_closed(false)
	_inner_glow.modulate.a = 0.8
	var tween := create_tween()
	tween.tween_property(_root_visual, "scale", Vector2(1.025, 1.025), 0.12)
	tween.tween_property(_root_visual, "scale", Vector2.ONE, 0.18)
	await tween.finished


func _open_full() -> void:
	_update_pivots()

	# 1) Compress ~2% on touch
	var press := create_tween()
	press.tween_property(_root_visual, "scale", Vector2(0.98, 0.98), 0.09).set_trans(Tween.TRANS_SINE)
	await press.finished
	if _skip:
		await _open_short()
		return

	# Reveal animatable hardware over the closed plate.
	_lock_pivot.modulate.a = 1.0
	_lock.modulate.a = 1.0
	_latch.modulate.a = 1.0
	_lock_pivot.rotation = 0.0
	_lock_pivot.position = Vector2.ZERO

	# 2) Latch shake
	HapticHelper.lock_release()
	var latch_tw := create_tween()
	for i in 6:
		latch_tw.tween_property(_latch, "position:x", 4.5 if i % 2 == 0 else -4.5, 0.03)
	latch_tw.tween_property(_latch, "position:x", 0.0, 0.04)
	await latch_tw.finished
	if _skip:
		await _open_short()
		return

	# 3-4) Lock rotates, releases, drops with weight
	var lock_tw := create_tween()
	lock_tw.tween_property(_lock_pivot, "rotation", deg_to_rad(22.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lock_tw.tween_property(_lock_pivot, "position:y", 48.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	lock_tw.parallel().tween_property(_lock_pivot, "modulate:a", 0.0, 0.28)
	lock_tw.parallel().tween_property(_latch, "modulate:a", 0.0, 0.22)
	await lock_tw.finished
	if _skip:
		await _open_short()
		return

	# Crossfade closed plate → layered body + hinged lid.
	_lid.modulate.a = 1.0
	_chest_base.modulate.a = 1.0
	_interior.modulate.a = 0.35
	_chest_closed.modulate.a = 0.0

	# 5) Lid resists
	var resist := create_tween()
	resist.tween_property(_lid_pivot, "rotation", deg_to_rad(-7.0), 0.2).set_trans(Tween.TRANS_SINE)
	resist.parallel().tween_property(_inner_glow, "modulate:a", 0.35, 0.2)
	await resist.finished
	if _skip:
		await _open_short()
		return

	# 6-9) Open from rear hinge, accelerate, slight overshoot, settle
	var lid_tw := create_tween()
	lid_tw.tween_property(_lid_pivot, "rotation", deg_to_rad(-122.0), 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	lid_tw.parallel().tween_property(_inner_glow, "modulate:a", 0.9, 0.6)
	lid_tw.parallel().tween_property(_interior, "modulate:a", 0.95, 0.55)
	lid_tw.parallel().tween_property(_chest_open, "modulate:a", 1.0, 0.55)
	lid_tw.parallel().tween_property(_contact_shadow, "scale", Vector2(1.1, 1.0), 0.7)
	await lid_tw.finished

	var settle := create_tween()
	settle.tween_property(_lid_pivot, "rotation", deg_to_rad(-108.0), 0.12) # overshoot
	settle.tween_property(_lid_pivot, "rotation", deg_to_rad(-114.0), 0.18).set_trans(Tween.TRANS_SINE)
	await settle.finished

	# 10-14) Dust + gold particles; hide separate lid (open plate already includes it)
	_emit_burst()
	var fade_lid := create_tween()
	fade_lid.tween_property(_lid, "modulate:a", 0.0, 0.2)
	fade_lid.parallel().tween_property(_root_visual, "scale", Vector2.ONE, 0.22)
	await fade_lid.finished

	# 15) Scroll rises from inside
	await _emerge_scroll()
	scroll_emerged.emit()


func _emerge_scroll() -> void:
	_rolled_scroll.modulate.a = 0.0
	_rolled_scroll.position = Vector2(0, 36)
	_rolled_scroll.rotation = deg_to_rad(-6.0)
	_rolled_scroll.scale = Vector2(0.72, 0.72)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rolled_scroll, "modulate:a", 1.0, 0.25)
	tw.tween_property(_rolled_scroll, "position:y", -70.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "rotation", deg_to_rad(4.0), 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_rolled_scroll, "scale", Vector2(1.0, 1.0), 0.55).set_trans(Tween.TRANS_SINE)
	await tw.finished
	var settle := create_tween()
	settle.tween_property(_rolled_scroll, "rotation", 0.0, 0.18)
	await settle.finished


func _emit_burst() -> void:
	var center := size * Vector2(0.5, 0.48)
	if center == Vector2.ZERO:
		center = Vector2(280, 260)
	_dust.position = center
	_sparks.position = center
	_dust.restart()
	_dust.emitting = true
	_sparks.restart()
	_sparks.emitting = true


func request_skip() -> void:
	_skip = true
