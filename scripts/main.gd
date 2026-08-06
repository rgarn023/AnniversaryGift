extends Control

## Anniversary Gift main screen orchestration.

const TITLE_TAP_WINDOW := 5.0
const TITLE_TAP_TARGET := 7
const DATE_POLL_SECONDS := 15.0

var manager: AnniversaryManager
var _title: Label
var _subtitle: Label
var _safe_top: Control
var _safe_bottom: Control
var _chest: TreasureChest
var _archive: ScrollArchive
var _scroll_viewer: ScrollViewer
var _gift_viewer: GiftDocumentViewer
var _developer: DeveloperPanel
var _bg: ColorRect
var _vignette: TextureRect
var _particles: CPUParticles2D
var _dev_banner: Label
var _input_locked: bool = false
var _title_taps: Array[float] = []
var _poll_timer: float = 0.0
var _sparkle_trail: CPUParticles2D
var _status_toast: Label
var _date_bar: HBoxContainer
var _date_label: Label
var _test_btn: Button
var _title_press_time: float = -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	manager = AnniversaryManager.new()
	_build_background()
	_build_ui()
	_build_modals()
	_apply_safe_areas()
	_refresh_presentation()
	manager.state_changed.connect(_refresh_presentation)
	set_process(true)
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(_apply_safe_areas)


func _build_background() -> void:
	# Smooth painted night sky texture (filtered) — avoids blocky purple pixelation.
	if ResourceLoader.exists("res://assets/art/background/starfield.png"):
		var stars := TextureRect.new()
		stars.texture = load("res://assets/art/background/starfield.png")
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stars.stretch_mode = TextureRect.STRETCH_SCALE
		stars.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stars)
		_bg = ColorRect.new()
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg.color = Color(0.04, 0.02, 0.1, 0.18)
		var mat := ShaderMaterial.new()
		if ResourceLoader.exists("res://assets/shaders/starfield.gdshader"):
			mat.shader = load("res://assets/shaders/starfield.gdshader")
			_bg.material = mat
			_bg.color = Color(1, 1, 1, 0.22)
		add_child(_bg)
	else:
		_bg = ColorRect.new()
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg.color = Color(0.05, 0.03, 0.12)
		var mat2 := ShaderMaterial.new()
		if ResourceLoader.exists("res://assets/shaders/starfield.gdshader"):
			mat2.shader = load("res://assets/shaders/starfield.gdshader")
			_bg.material = mat2
		add_child(_bg)

	_particles = CPUParticles2D.new()
	_particles.amount = 36
	_particles.lifetime = 6.0
	_particles.preprocess = 3.0
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(540, 1200)
	_particles.direction = Vector2(0, -1)
	_particles.spread = 180.0
	_particles.gravity = Vector2(0, -4)
	_particles.initial_velocity_min = 4.0
	_particles.initial_velocity_max = 16.0
	_particles.scale_amount_min = 0.5
	_particles.scale_amount_max = 1.8
	_particles.color = Color(1.0, 0.85, 0.95, 0.55)
	_particles.position = Vector2(540, 1200)
	_particles.z_index = 1
	add_child(_particles)

	if ResourceLoader.exists("res://assets/art/background/vignette.png"):
		_vignette = TextureRect.new()
		_vignette.texture = load("res://assets/art/background/vignette.png")
		_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vignette.z_index = 2
		add_child(_vignette)

	_sparkle_trail = CPUParticles2D.new()
	_sparkle_trail.emitting = false
	_sparkle_trail.one_shot = true
	_sparkle_trail.amount = 24
	_sparkle_trail.lifetime = 0.7
	_sparkle_trail.explosiveness = 0.2
	_sparkle_trail.local_coords = false
	_sparkle_trail.color = Color(1.0, 0.85, 0.45, 0.9)
	_sparkle_trail.scale_amount_min = 1.0
	_sparkle_trail.scale_amount_max = 2.0
	_sparkle_trail.z_index = 30
	add_child(_sparkle_trail)


func _build_ui() -> void:
	_safe_top = Control.new()
	_safe_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_safe_top.offset_bottom = 220
	_safe_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_top)

	_title = Label.new()
	_title.text = "Anniversary Gift"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.offset_top = 40
	_title.offset_bottom = -40
	_title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	_title.add_theme_font_size_override("font_size", 56)
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_title.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.gui_input.connect(_on_title_input)
	_safe_top.add_child(_title)

	_dev_banner = Label.new()
	_dev_banner.text = "DEVELOPER TEST MODE"
	_dev_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dev_banner.visible = false
	_dev_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_dev_banner.offset_top = 8
	_dev_banner.offset_bottom = 40
	_dev_banner.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_dev_banner.add_theme_font_size_override("font_size", 22)
	_dev_banner.z_index = 25
	add_child(_dev_banner)

	# Status line sits between title and chest with clear clearance (not over the chest).
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	_subtitle.position = Vector2(-460, -430)
	_subtitle.size = Vector2(920, 130)
	_subtitle.add_theme_color_override("font_color", Color(0.95, 0.88, 0.98, 0.98))
	_subtitle.add_theme_font_size_override("font_size", 40)
	if ResourceLoader.exists("res://assets/fonts/CormorantGaramond-Regular.ttf"):
		_subtitle.add_theme_font_override("font", load("res://assets/fonts/CormorantGaramond-Regular.ttf"))
	_subtitle.z_index = 6
	add_child(_subtitle)

	# Instance scene so realistic frame textures are packed/preloaded with the node.
	var chest_scene: PackedScene = load("res://scenes/Chest.tscn")
	_chest = chest_scene.instantiate() as TreasureChest
	_chest.custom_minimum_size = Vector2(520, 520)
	_chest.size = Vector2(520, 520)
	_chest.set_anchors_preset(Control.PRESET_CENTER)
	# Lowered slightly so subtitle above has breathing room.
	_chest.position = Vector2(-260, -90)
	_chest.z_index = 5
	# Chest fades itself in after textures are ready; keep hidden until then.
	_chest.visible = false
	_chest.tapped.connect(_on_chest_tapped)
	_chest.scroll_emerged.connect(_on_scroll_emerged)
	add_child(_chest)

	_safe_bottom = Control.new()
	_safe_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_safe_bottom.offset_top = -300
	add_child(_safe_bottom)

	_archive = ScrollArchive.new()
	_archive.manager = manager
	_archive.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_archive.scroll_selected.connect(_on_archive_selected)
	_safe_bottom.add_child(_archive)

	_status_toast = Label.new()
	_status_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_toast.position = Vector2(-400, -260)
	_status_toast.size = Vector2(800, 48)
	_status_toast.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_status_toast.add_theme_font_size_override("font_size", 22)
	_status_toast.modulate.a = 0.0
	add_child(_status_toast)

	# Small always-available entry to date testing (PIN protected).
	_test_btn = Button.new()
	_test_btn.text = "Test Dates"
	_test_btn.tooltip_text = "Open date simulator (PIN required)"
	_test_btn.focus_mode = Control.FOCUS_NONE
	_test_btn.custom_minimum_size = Vector2(160, 56)
	_test_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_test_btn.position = Vector2(-180, 56)
	_test_btn.size = Vector2(160, 56)
	_test_btn.z_index = 26
	_test_btn.pressed.connect(func() -> void: _developer.prompt_pin())
	add_child(_test_btn)

	# Compact simulated-date strip while a developer date is active.
	_date_bar = HBoxContainer.new()
	_date_bar.visible = false
	_date_bar.z_index = 27
	_date_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_date_bar.position = Vector2(-460, 96)
	_date_bar.size = Vector2(920, 72)
	_date_bar.add_theme_constant_override("separation", 12)
	_date_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_date_bar)

	_date_label = Label.new()
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_date_label.custom_minimum_size = Vector2(420, 64)
	_date_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_date_label.add_theme_font_size_override("font_size", 26)
	_date_bar.add_child(_date_label)

	var change_btn := Button.new()
	change_btn.text = "Change date"
	change_btn.custom_minimum_size = Vector2(180, 64)
	change_btn.focus_mode = Control.FOCUS_NONE
	change_btn.pressed.connect(func() -> void: _developer.open_panel())
	_date_bar.add_child(change_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.custom_minimum_size = Vector2(120, 64)
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.pressed.connect(func() -> void: _developer.exit_simulation())
	_date_bar.add_child(exit_btn)


func _build_modals() -> void:
	_scroll_viewer = ScrollViewer.new()
	_scroll_viewer.manager = manager
	_scroll_viewer.closed.connect(_on_scroll_closed)
	_scroll_viewer.archive_flight_requested.connect(_on_archive_flight)
	add_child(_scroll_viewer)

	_gift_viewer = GiftDocumentViewer.new()
	_gift_viewer.closed.connect(func() -> void: _input_locked = false)
	add_child(_gift_viewer)

	_developer = DeveloperPanel.new()
	_developer.manager = manager
	_developer.closed.connect(_on_developer_closed)
	_developer.date_applied.connect(_on_developer_date_applied)
	_developer.request_test_gift_preview.connect(_on_test_gift_preview)
	add_child(_developer)


func _apply_safe_areas() -> void:
	var safe: Rect2 = DisplayServer.get_display_safe_area()
	var full: Vector2i = DisplayServer.screen_get_size()
	if full.x <= 0 or full.y <= 0:
		full = Vector2i(int(size.x), int(size.y))
	var top_pad: float = maxf(safe.position.y, 28.0)
	# Samsung nav/gesture bars often need more than the reported inset.
	var bottom_pad: float = maxf(float(full.y) - (safe.position.y + safe.size.y), 0.0)
	bottom_pad = maxf(bottom_pad, 72.0)
	if size.y > 0.0 and full.y > 0:
		var scale_y: float = size.y / float(full.y)
		top_pad = maxf(top_pad * scale_y, 28.0)
		bottom_pad = maxf(bottom_pad * scale_y, 72.0)
	_safe_top.offset_top = top_pad
	_safe_top.offset_bottom = top_pad + 180.0
	# Keep the whole archive (icons + date labels) above the system nav area.
	var archive_h: float = 280.0
	_safe_bottom.offset_top = -(archive_h + bottom_pad)
	_safe_bottom.offset_bottom = -bottom_pad
	if _bg and _bg.material is ShaderMaterial:
		var sm := _bg.material as ShaderMaterial
		sm.set_shader_parameter("parallax_offset", Vector2(0.0, top_pad * 0.001))


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= DATE_POLL_SECONDS:
		_poll_timer = 0.0
		manager.refresh_unlocks()
	# Long-press title (~1s) also opens test PIN dialog.
	if _title_press_time >= 0.0:
		var held: float = Time.get_ticks_msec() / 1000.0 - _title_press_time
		if held >= 1.0:
			_title_press_time = -1.0
			_developer.prompt_pin()
	# Gentle parallax drift
	if _bg and _bg.material is ShaderMaterial and not manager.is_reduced_motion():
		var sm := _bg.material as ShaderMaterial
		var t: float = Time.get_ticks_msec() * 0.00005
		sm.set_shader_parameter("parallax_offset", Vector2(sin(t) * 0.4, cos(t * 0.7) * 0.3))
	_particles.emitting = not manager.is_reduced_motion()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		manager.refresh_unlocks()
		_refresh_presentation()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _gift_viewer.visible:
			_gift_viewer.close_viewer()
		elif _scroll_viewer.visible:
			_scroll_viewer.close_viewer()
		elif _developer.visible:
			_developer.close_panel()


func _refresh_presentation() -> void:
	_dev_banner.visible = manager.developer_mode
	_date_bar.visible = manager.developer_mode
	_test_btn.visible = not manager.developer_mode
	if manager.developer_mode:
		_date_label.text = "Simulated: %s" % DateService.format_display_date(manager.get_effective_date())
		_dev_banner.text = "SIMULATED DATE — %s" % manager.get_effective_date()
	_chest.reduced_motion = manager.is_reduced_motion()
	_archive.refresh()

	if manager.is_before_start():
		_subtitle.text = manager.get_prestart_message()
		_chest.configure(TreasureChest.ChestState.LOCKED_SILHOUETTE)
		_chest.visible = true
		return

	var next: String = manager.get_next_chest_date()
	if next.is_empty():
		if manager.is_final_gift_ready():
			_subtitle.text = "Your anniversary scrolls are waiting below."
			_chest.configure(TreasureChest.ChestState.FINAL_GIFT, true)
			_chest.visible = true
		else:
			_subtitle.text = "Your anniversary scrolls are waiting below."
			_chest.visible = false
		return

	if next == AnniversaryManager.FINAL_DATE and manager.is_final_gift_ready():
		_subtitle.text = "One more surprise awaits."
		_chest.configure(TreasureChest.ChestState.FINAL_GIFT, true)
		_chest.visible = true
		return

	if manager.is_chest_opened(next) and not manager.is_scroll_viewed(next):
		_subtitle.text = "Your scroll is ready."
		_chest.configure(TreasureChest.ChestState.OPENED)
		_chest.visible = true
		return

	var remaining: int = manager.catchup_queue.size()
	if remaining > 1:
		_subtitle.text = "A chest awaits — %d surprises to catch up." % remaining
	else:
		_subtitle.text = "A chest awaits you."
	_chest.configure(TreasureChest.ChestState.AVAILABLE)
	_chest.visible = true


func _on_chest_tapped() -> void:
	if _input_locked or _scroll_viewer.visible or _gift_viewer.visible:
		return
	if manager.is_before_start():
		_toast(manager.get_prestart_message())
		return

	# Final gift stage
	if manager.is_final_gift_ready():
		_input_locked = true
		await _chest.play_final_reopen_animation()
		manager.mark_final_gift_opened()
		await _gift_viewer.open_viewer()
		_input_locked = false
		return

	var next: String = manager.get_next_chest_date()
	if next.is_empty():
		return

	_input_locked = true
	if not manager.is_chest_opened(next):
		await _chest.play_open_animation(manager.is_reduced_motion())
		manager.mark_chest_opened(next)
		_scroll_viewer.set_emerge_from(_chest.get_scroll_global_center())
		_chest.hide_rolled_scroll()
	await _scroll_viewer.open_message(next, false)
	_input_locked = false


func _on_scroll_emerged(global_pos: Vector2) -> void:
	_scroll_viewer.set_emerge_from(global_pos)


func _on_archive_selected(date_iso: String) -> void:
	if _input_locked or _scroll_viewer.visible or _gift_viewer.visible:
		return
	_input_locked = true
	await _scroll_viewer.open_message(date_iso, true)
	_input_locked = false


func _on_scroll_closed(date_iso: String) -> void:
	manager.mark_scroll_viewed(date_iso)
	# After final message closes, keep chest in gift state.
	_refresh_presentation()


func _on_archive_flight(date_iso: String, from_pos: Vector2) -> void:
	var target: Vector2 = _archive.get_item_global_center(date_iso)
	_sparkle_trail.position = from_pos
	_sparkle_trail.emitting = false
	_sparkle_trail.restart()
	_sparkle_trail.emitting = true
	var tw := create_tween()
	# Curved movement via mid control point.
	var mid := Vector2(lerp(from_pos.x, target.x, 0.5) + 80.0, minf(from_pos.y, target.y) - 120.0)
	tw.tween_method(func(t: float) -> void:
		var p: Vector2 = _quad_bezier(from_pos, mid, target, t)
		_sparkle_trail.position = p
	, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	await tw.finished
	await _archive.bounce_item(date_iso)


func _quad_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_register_title_tap()
			_title_press_time = Time.get_ticks_msec() / 1000.0
		else:
			_title_press_time = -1.0
	elif event is InputEventScreenTouch:
		if event.pressed:
			_register_title_tap()
			_title_press_time = Time.get_ticks_msec() / 1000.0
		else:
			_title_press_time = -1.0


func _register_title_tap() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_title_taps.append(now)
	while not _title_taps.is_empty() and now - _title_taps[0] > TITLE_TAP_WINDOW:
		_title_taps.remove_at(0)
	if _title_taps.size() >= TITLE_TAP_TARGET:
		_title_taps.clear()
		_developer.prompt_pin()


func _on_developer_closed() -> void:
	_refresh_presentation()


func _on_developer_date_applied(iso_date: String) -> void:
	_refresh_presentation()
	_toast("Simulating open on %s" % DateService.format_display_date(iso_date))


func _on_test_gift_preview() -> void:
	## Same viewer path as the final chest gift.
	_input_locked = true
	await _gift_viewer.open_viewer()
	_input_locked = false


func _toast(text: String) -> void:
	_status_toast.text = text
	_status_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_status_toast, "modulate:a", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _gift_viewer.visible:
			_gift_viewer.close_viewer()
			get_viewport().set_input_as_handled()
		elif _scroll_viewer.visible:
			_scroll_viewer.close_viewer()
			get_viewport().set_input_as_handled()
		elif _developer.visible:
			_developer.close_panel()
			get_viewport().set_input_as_handled()
