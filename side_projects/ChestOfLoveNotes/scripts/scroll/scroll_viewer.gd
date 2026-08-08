extends CanvasLayer
class_name LoveNotesScrollViewer
## Full-screen scroll preview/open modal.
## Pinch zoom + pan transform ONE composite PreviewRoot/ScrollVisualRoot.
## A− / A+ change message font size only — never Control.scale on text nodes.

signal closed
signal archive_flight_requested(screen_pos: Vector2)
signal attachment_tapped(attachment: Dictionary)

const ART := "res://assets/art/scroll/"
const BASE_BODY_FONT_SIZE: int = 30
const MIN_BODY_FONT_SIZE: int = 22
const MAX_BODY_FONT_SIZE: int = 48
const BASE_HEADING_FONT_SIZE: int = 34
const BASE_META_FONT_SIZE: int = 18
const MIN_FONT_ZOOM: float = 0.85
const MAX_FONT_ZOOM: float = 1.55
const MIN_VIEW_ZOOM: float = 1.0
const MAX_VIEW_ZOOM: float = 2.75

var message_zoom: float = 1.0
var _view_zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _pinch: GestureZoomController
var _root: Control
var _dim: ColorRect
var _safe: MarginContainer
var _shell: VBoxContainer
var _top_bar: HBoxContainer
var _title_label: Label
var _btn_close: Button
var _stage: Control
var _preview_root: Control
var _scroll_unit: Control
var _shadow: TextureRect
var _parchment: TextureRect
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _content_margin: MarginContainer
var _content: VBoxContainer
var _meta_label: Label
var _heading: Label
var _message_scroll: ScrollContainer
var _message: RichTextLabel
var _attach_label: Label
var _attach_row: HBoxContainer
var _bottom_bar: HBoxContainer
var _btn_minus: Button
var _btn_plus: Button
var _btn_reset: Button
var _visible_modal: bool = false
var _clear_on_close: bool = false
var _reduced_motion: bool = false
var _attachments: Array = []
var _unit_size: Vector2 = Vector2(360, 560)
var _base_center: Vector2 = Vector2.ZERO
var _dragging_pan: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _body_text: String = ""


func _ready() -> void:
	layer = 40
	_pinch = GestureZoomController.new()
	_pinch.min_scale = MIN_VIEW_ZOOM
	_pinch.max_scale = MAX_VIEW_ZOOM
	_pinch.zoom_changed.connect(_on_view_zoom_changed)
	_build_ui()
	visible = false
	set_process_input(true)
	get_viewport().size_changed.connect(_on_viewport_resized)


func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _make_tex(path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _tex(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.02, 0.06, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_safe = MarginContainer.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_safe)

	_shell = VBoxContainer.new()
	_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell.add_theme_constant_override("separation", 8)
	_safe.add_child(_shell)

	_top_bar = HBoxContainer.new()
	_top_bar.custom_minimum_size = Vector2(0, 52)
	_shell.add_child(_top_bar)
	_title_label = Label.new()
	_title_label.text = "Scroll Preview"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.98))
	_top_bar.add_child(_title_label)
	_btn_close = Button.new()
	_btn_close.text = "✕ Close"
	_btn_close.focus_mode = Control.FOCUS_NONE
	_btn_close.custom_minimum_size = Vector2(120, 48)
	_style_chrome_button(_btn_close)
	_btn_close.pressed.connect(close_viewer)
	_top_bar.add_child(_btn_close)

	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_gui_input)
	_shell.add_child(_stage)

	## PreviewRoot holds the composite transform (pinch zoom + pan).
	_preview_root = Control.new()
	_preview_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_preview_root)

	## ScrollVisualRoot — parchment, rollers, and all content children.
	_scroll_unit = Control.new()
	_scroll_unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_root.add_child(_scroll_unit)

	_shadow = _make_tex(ART + "scroll_shadow.png")
	_shadow.modulate = Color(1, 1, 1, 0.35)
	_scroll_unit.add_child(_shadow)

	_parchment = _make_tex(ART + "scroll_parchment_center.png")
	_scroll_unit.add_child(_parchment)

	_top_roller = _make_tex(ART + "scroll_top_roller.png")
	_top_roller.z_index = 2
	_scroll_unit.add_child(_top_roller)

	_bottom_roller = _make_tex(ART + "scroll_bottom_roller.png")
	_bottom_roller.z_index = 2
	_scroll_unit.add_child(_bottom_roller)

	_content_margin = MarginContainer.new()
	_content_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll_unit.add_child(_content_margin)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_content_margin.add_child(_content)

	_meta_label = Label.new()
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_label.add_theme_color_override("font_color", Color(0.42, 0.22, 0.16))
	_content.add_child(_meta_label)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.28, 0.13, 0.09))
	_content.add_child(_heading)

	_message_scroll = ScrollContainer.new()
	_message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	MobileUi.configure_scroll(_message_scroll)
	_content.add_child(_message_scroll)

	_message = RichTextLabel.new()
	_message.bbcode_enabled = true
	_message.fit_content = true
	_message.scroll_active = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("default_color", Color(0.18, 0.1, 0.08))
	_message_scroll.add_child(_message)

	_attach_label = Label.new()
	_attach_label.visible = false
	_attach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attach_label.add_theme_color_override("font_color", Color(0.35, 0.2, 0.14))
	_attach_label.add_theme_font_size_override("font_size", 16)
	_content.add_child(_attach_label)

	_attach_row = HBoxContainer.new()
	_attach_row.visible = false
	_attach_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_attach_row.add_theme_constant_override("separation", 8)
	_content.add_child(_attach_row)

	_bottom_bar = HBoxContainer.new()
	_bottom_bar.custom_minimum_size = Vector2(0, 56)
	_bottom_bar.add_theme_constant_override("separation", 10)
	_shell.add_child(_bottom_bar)
	_btn_minus = _make_tool_button("A−")
	_btn_plus = _make_tool_button("A+")
	_btn_reset = _make_tool_button("Reset View")
	for b in [_btn_minus, _btn_plus, _btn_reset]:
		_bottom_bar.add_child(b)
	_btn_minus.pressed.connect(func() -> void:
		message_zoom = clampf(message_zoom * 0.9, MIN_FONT_ZOOM, MAX_FONT_ZOOM)
		apply_message_zoom()
	)
	_btn_plus.pressed.connect(func() -> void:
		message_zoom = clampf(message_zoom * 1.1, MIN_FONT_ZOOM, MAX_FONT_ZOOM)
		apply_message_zoom()
	)
	_btn_reset.pressed.connect(_reset_preview_state)
	_apply_fonts()


func _style_chrome_button(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.16, 0.1, 0.22, 0.95)
	n.set_corner_radius_all(12)
	n.content_margin_left = 14
	n.content_margin_right = 14
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_color_override("font_color", Color(0.96, 0.9, 0.98))
	b.add_theme_font_size_override("font_size", 17)


func _make_tool_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	_style_chrome_button(b)
	return b


func _apply_fonts() -> void:
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_heading.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
		_title_label.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	if ResourceLoader.exists("res://assets/fonts/CormorantGaramond-Regular.ttf"):
		var body: FontFile = load("res://assets/fonts/CormorantGaramond-Regular.ttf")
		_message.add_theme_font_override("normal_font", body)
		_meta_label.add_theme_font_override("font", body)


func _compute_safe_insets() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0:
		viewport_size = Vector2(390, 844)
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var scale_x := viewport_size.x / float(maxi(screen.x, 1))
	var scale_y := viewport_size.y / float(maxi(screen.y, 1))
	var left := maxi(12, int(safe.position.x * scale_x))
	var top := maxi(12, int(safe.position.y * scale_y))
	var right := maxi(12, int((screen.x - (safe.position.x + safe.size.x)) * scale_x))
	var bottom := maxi(12, int((screen.y - (safe.position.y + safe.size.y)) * scale_y))
	_safe.add_theme_constant_override("margin_left", left)
	_safe.add_theme_constant_override("margin_right", right)
	_safe.add_theme_constant_override("margin_top", top)
	_safe.add_theme_constant_override("margin_bottom", bottom)


func _fit_scroll_unit() -> void:
	_compute_safe_insets()
	await get_tree().process_frame
	var stage_size := _stage.size
	if stage_size.x < 8.0 or stage_size.y < 8.0:
		stage_size = get_viewport().get_visible_rect().size - Vector2(24, 140)
	var max_w := stage_size.x - 16.0
	var max_h := stage_size.y - 8.0
	var aspect := 0.62
	var w := max_w
	var h := w / aspect
	if h > max_h:
		h = max_h
		w = h * aspect
	w = clampf(w, 240.0, 520.0)
	h = clampf(h, 360.0, max_h)
	_unit_size = Vector2(w, h)
	_scroll_unit.size = _unit_size
	_base_center = stage_size * 0.5
	_layout_scroll_visual()
	_apply_view_transform()
	_refresh_message_width()


func _layout_scroll_visual() -> void:
	var w := _unit_size.x
	var h := _unit_size.y
	var roller_h := clampf(w * 0.085, 36.0, 56.0)
	_top_roller.position = Vector2(0, 0)
	_top_roller.size = Vector2(w, roller_h)
	_bottom_roller.position = Vector2(0, h - roller_h)
	_bottom_roller.size = Vector2(w, roller_h)
	_parchment.position = Vector2(w * 0.04, roller_h * 0.72)
	_parchment.size = Vector2(w * 0.92, h - roller_h * 1.55)
	_shadow.position = Vector2(8, 10)
	_shadow.size = Vector2(w, h)
	var pad_x := int(clampf(w * 0.1, 28.0, 48.0))
	var pad_y := int(clampf(roller_h * 0.85, 28.0, 44.0))
	_content_margin.position = _parchment.position + Vector2(8, 8)
	_content_margin.size = _parchment.size - Vector2(16, 16)
	_content_margin.add_theme_constant_override("margin_left", pad_x - 8)
	_content_margin.add_theme_constant_override("margin_right", pad_x - 8)
	_content_margin.add_theme_constant_override("margin_top", pad_y - 8)
	_content_margin.add_theme_constant_override("margin_bottom", pad_y - 8)


func _apply_view_transform() -> void:
	_view_zoom = clampf(_view_zoom, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	_scroll_unit.scale = Vector2(_view_zoom, _view_zoom)
	var scaled := _unit_size * _view_zoom
	var pos := _base_center - scaled * 0.5 + _pan
	## Keep some portion of the scroll recoverable on screen.
	var stage_size := _stage.size if _stage.size.x > 8.0 else Vector2(360, 600)
	var min_x := -scaled.x + 80.0
	var max_x := stage_size.x - 80.0
	var min_y := -scaled.y + 80.0
	var max_y := stage_size.y - 80.0
	pos.x = clampf(pos.x, min_x, max_x)
	pos.y = clampf(pos.y, min_y, max_y)
	_pan = pos - (_base_center - scaled * 0.5)
	_scroll_unit.position = pos


func _refresh_message_width() -> void:
	var w := maxf(_content_margin.size.x - 24.0, 140.0)
	_message.custom_minimum_size = Vector2(w, 0)
	_heading.custom_minimum_size = Vector2(w, 0)
	_meta_label.custom_minimum_size = Vector2(w, 0)


func _on_viewport_resized() -> void:
	if visible:
		_fit_scroll_unit()


func open_message(
	title: String,
	meta: String,
	body: String,
	short_animation: bool = true,
	clear_on_close: bool = false,
	attachments: Array = [],
	chrome_title: String = "Scroll Preview"
) -> void:
	_clear_on_close = clear_on_close
	_attachments = attachments.duplicate(true) if not attachments.is_empty() else []
	_visible_modal = true
	visible = true
	_title_label.text = chrome_title
	_heading.text = title if not title.is_empty() else "A Love Note"
	_meta_label.text = meta
	_body_text = body
	_set_message_text(body)
	_populate_attachments()
	_reset_preview_state()
	_dim.color.a = 0.0
	_scroll_unit.modulate.a = 0.0
	await _fit_scroll_unit()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.86, 0.2)
	tw.tween_property(_scroll_unit, "modulate:a", 1.0, 0.22)
	await tw.finished


func set_attachments(attachments: Array) -> void:
	_attachments = attachments.duplicate(true)
	_populate_attachments()


func _populate_attachments() -> void:
	for c in _attach_row.get_children():
		c.queue_free()
	var count := _attachments.size()
	_attach_label.visible = count > 0
	_attach_row.visible = count > 0
	if count <= 0:
		return
	_attach_label.text = "Attachments (%d)" % count
	for item in _attachments:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var path := str(item.get("path", item.get("local_path", "")))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_contents = true
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.14, 0.1, 0.35)
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", style)
		if not path.is_empty() and FileAccess.file_exists(path):
			var tex := AttachmentHelper.make_thumbnail_texture(path, 160)
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(tr)
		elif not str(item.get("signed_url", "")).is_empty():
			btn.text = "Photo"
			_load_remote_thumb(str(item.get("signed_url", "")), btn)
		else:
			btn.text = "Photo"
		var captured: Dictionary = (item as Dictionary).duplicate(true)
		btn.pressed.connect(func() -> void:
			attachment_tapped.emit(captured)
		)
		_attach_row.add_child(btn)


func _load_remote_thumb(url: String, btn: Button) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return
	var completed: Array = await http.request_completed
	http.queue_free()
	if not is_instance_valid(btn) or completed.is_empty():
		return
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS or int(completed[1]) != 200:
		return
	var bytes: PackedByteArray = completed[3]
	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK and img.load_png_from_buffer(bytes) != OK and img.load_webp_from_buffer(bytes) != OK:
		return
	var long_edge := maxi(img.get_width(), img.get_height())
	if long_edge > 180:
		var scale := 180.0 / float(long_edge)
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	btn.text = ""
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tr)


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _set_message_text(plain: String) -> void:
	if plain.is_empty():
		_message.text = ""
		return
	_message.text = "[center]%s[/center]" % _escape_bbcode(plain)


func apply_message_zoom() -> void:
	message_zoom = clampf(message_zoom, MIN_FONT_ZOOM, MAX_FONT_ZOOM)
	var body_size: int = clampi(roundi(BASE_BODY_FONT_SIZE * message_zoom), MIN_BODY_FONT_SIZE, MAX_BODY_FONT_SIZE)
	var heading_size: int = clampi(roundi(BASE_HEADING_FONT_SIZE * message_zoom), 26, 44)
	var meta_size: int = clampi(roundi(BASE_META_FONT_SIZE * message_zoom), 14, 24)
	_message.add_theme_font_size_override("normal_font_size", body_size)
	_heading.add_theme_font_size_override("font_size", heading_size)
	_meta_label.add_theme_font_size_override("font_size", meta_size)
	## Font zoom must never scale Control nodes.
	_message.scale = Vector2.ONE
	_message_scroll.scale = Vector2.ONE
	_heading.scale = Vector2.ONE
	_meta_label.scale = Vector2.ONE
	call_deferred("_refresh_message_width")


func _on_view_zoom_changed(scale: float) -> void:
	if not _visible_modal:
		return
	_view_zoom = clampf(scale, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	_apply_view_transform()


func _reset_preview_state() -> void:
	message_zoom = 1.0
	_view_zoom = 1.0
	_pan = Vector2.ZERO
	_pinch.reset(1.0)
	apply_message_zoom()
	if _message_scroll:
		_message_scroll.scroll_vertical = 0
	_apply_view_transform()


func _on_stage_gui_input(event: InputEvent) -> void:
	if not _visible_modal:
		return
	if _view_zoom <= 1.001:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_dragging_pan = st.pressed
		_drag_last = st.position
	elif event is InputEventScreenDrag and _dragging_pan and not _pinch.is_pinching():
		var sd := event as InputEventScreenDrag
		_pan += sd.relative
		_apply_view_transform()
		_stage.accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging_pan = mb.pressed
			_drag_last = mb.position
	elif event is InputEventMouseMotion and _dragging_pan:
		var mm := event as InputEventMouseMotion
		_pan += mm.relative
		_apply_view_transform()


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	var start_pos: Vector2 = _scroll_unit.global_position + _unit_size * 0.5 * _view_zoom
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_scroll_unit, "modulate:a", 0.0, 0.18)
	tw.tween_property(_dim, "color:a", 0.0, 0.18)
	await tw.finished
	if _clear_on_close:
		_set_message_text("")
		_attachments.clear()
		_populate_attachments()
	visible = false
	_scroll_unit.modulate = Color.WHITE
	_reset_preview_state()
	archive_flight_requested.emit(start_pos)
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _pinch.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()
