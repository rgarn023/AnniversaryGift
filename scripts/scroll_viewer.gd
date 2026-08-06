extends CanvasLayer
class_name ScrollViewer

## Full-screen parchment scroll modal with zoom and Android back support.

signal closed(date_iso: String)
signal archive_flight_requested(date_iso: String, screen_pos: Vector2)

const MIN_SCALE := 0.8
const MAX_SCALE := 2.2
const DESIGN_SIZE := Vector2(920, 1500)
const TEXT_WIDTH := 680.0

var manager: AnniversaryManager
var current_date: String = ""
var _zoom: GestureZoomController
var _dim: ColorRect
var _panel: Control
var _content_clip: Control
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _parchment: TextureRect
var _heading: Label
var _date_label: Label
var _message: RichTextLabel
var _scroll: ScrollContainer
var _hint: Label
var _btn_close: Button
var _btn_plus: Button
var _btn_minus: Button
var _btn_reset: Button
var _base_font_size: int = 28
var _animating: bool = false
var _short_open: bool = false
var _skip_text: bool = false
var _visible_modal: bool = false
var _fit_scale: float = 1.0


func _ready() -> void:
	layer = 40
	_zoom = GestureZoomController.new()
	_zoom.min_scale = MIN_SCALE
	_zoom.max_scale = MAX_SCALE
	_zoom.zoom_changed.connect(_on_zoom_changed)
	_build_ui()
	visible = false
	set_process_input(true)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	add_child(_panel)

	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.position = Vector2(28, 40)
	shadow.size = Vector2(870, 1410)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(shadow)

	_parchment = TextureRect.new()
	_parchment.position = Vector2(40, 70)
	_parchment.size = Vector2(840, 1360)
	_parchment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_parchment.stretch_mode = TextureRect.STRETCH_SCALE
	_parchment.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/art/scroll/scroll_parchment.png"):
		_parchment.texture = load("res://assets/art/scroll/scroll_parchment.png")
	_panel.add_child(_parchment)

	_top_roller = _make_roller(true)
	_bottom_roller = _make_roller(false)
	_panel.add_child(_top_roller)
	_panel.add_child(_bottom_roller)

	# Clipped content region inside the parchment so text cannot spill out.
	_content_clip = Control.new()
	_content_clip.position = Vector2(100, 145)
	_content_clip.size = Vector2(720, 1120)
	_content_clip.clip_contents = true
	_content_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(_content_clip)

	_date_label = Label.new()
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.position = Vector2(20, 8)
	_date_label.size = Vector2(680, 36)
	_date_label.add_theme_color_override("font_color", Color(0.45, 0.2, 0.28))
	_date_label.add_theme_font_size_override("font_size", 24)
	_content_clip.add_child(_date_label)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.position = Vector2(20, 48)
	_heading.size = Vector2(680, 90)
	_heading.clip_text = false
	_heading.add_theme_color_override("font_color", Color(0.35, 0.16, 0.12))
	_heading.add_theme_font_size_override("font_size", 36)
	_content_clip.add_child(_heading)

	var divider := ColorRect.new()
	divider.color = Color(0.72, 0.52, 0.18, 0.55)
	divider.position = Vector2(160, 145)
	divider.size = Vector2(400, 2)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_clip.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(20, 165)
	_scroll.size = Vector2(680, 860)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	_content_clip.add_child(_scroll)

	_message = RichTextLabel.new()
	_message.bbcode_enabled = false
	_message.fit_content = true
	_message.scroll_active = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_message.add_theme_color_override("default_color", Color(0.22, 0.12, 0.1))
	_message.add_theme_font_size_override("normal_font_size", _base_font_size)
	_scroll.add_child(_message)

	_hint = Label.new()
	_hint.text = "Pinch or use + and – to resize"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(20, 1040)
	_hint.size = Vector2(680, 32)
	_hint.add_theme_color_override("font_color", Color(0.4, 0.25, 0.18, 0.85))
	_hint.add_theme_font_size_override("font_size", 20)
	_content_clip.add_child(_hint)

	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(100, 1345)
	toolbar.size = Vector2(720, 72)
	toolbar.add_theme_constant_override("separation", 16)
	_panel.add_child(toolbar)

	_btn_minus = _make_tool_button("–", "Decrease text size")
	_btn_plus = _make_tool_button("+", "Increase text size")
	_btn_reset = _make_tool_button("Reset", "Reset text size")
	_btn_close = _make_tool_button("Close", "Close message")
	for b in [_btn_minus, _btn_plus, _btn_reset, _btn_close]:
		toolbar.add_child(b)
	_btn_minus.pressed.connect(func() -> void: _zoom.adjust(0.9))
	_btn_plus.pressed.connect(func() -> void: _zoom.adjust(1.1))
	_btn_reset.pressed.connect(func() -> void: _zoom.reset(1.0))
	_btn_close.pressed.connect(close_viewer)

	_apply_fonts()
	_layout_panel()


func _make_roller(top: bool) -> TextureRect:
	var tr := TextureRect.new()
	var path := "res://assets/art/scroll/scroll_top_roller.png" if top else "res://assets/art/scroll/scroll_bottom_roller.png"
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.position = Vector2(20, 40 if top else 1400)
	tr.size = Vector2(880, 70)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _make_tool_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(120, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	return b


func _apply_fonts() -> void:
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_heading.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	if ResourceLoader.exists("res://assets/fonts/CormorantGaramond-Regular.ttf"):
		var body: FontFile = load("res://assets/fonts/CormorantGaramond-Regular.ttf")
		_message.add_theme_font_override("normal_font", body)
		_date_label.add_theme_font_override("font", body)
		_hint.add_theme_font_override("font", body)


func _layout_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1080, 2400)
	_panel.size = DESIGN_SIZE
	_fit_scale = minf((vp.x * 0.92) / DESIGN_SIZE.x, (vp.y * 0.78) / DESIGN_SIZE.y)
	_fit_scale = clampf(_fit_scale, 0.45, 1.0)
	_panel.scale = Vector2(_fit_scale, _fit_scale)
	_panel.rotation = 0.0
	_panel.modulate = Color.WHITE
	_panel.position = (vp - DESIGN_SIZE * _fit_scale) * 0.5
	_panel.pivot_offset = Vector2.ZERO
	_constrain_message_width()


func _constrain_message_width() -> void:
	_message.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_message.size = Vector2(TEXT_WIDTH, _message.size.y)


func _on_viewport_resized() -> void:
	if visible and not _animating:
		_layout_panel()


func open_message(date_iso: String, short_animation: bool = false) -> void:
	if manager == null:
		return
	var msg: Dictionary = manager.get_message_for_date(date_iso)
	if msg.is_empty():
		return
	current_date = date_iso
	_short_open = short_animation
	_skip_text = false
	_visible_modal = true
	visible = true
	_layout_panel()
	_date_label.text = DateService.format_display_date(date_iso)
	_heading.text = str(msg.get("heading", ""))
	_message.text = ""
	_top_roller.position.y = 40
	_bottom_roller.position.y = 1400
	_parchment.size.y = 1360
	_zoom.reset(manager.get_text_scale())
	_on_zoom_changed(_zoom.current_scale)
	await _play_open_animation(str(msg.get("message", "")))


func _play_open_animation(full_text: String) -> void:
	_animating = true
	var reduced: bool = manager != null and manager.is_reduced_motion()
	if reduced or _short_open:
		_dim.color.a = 0.72
		_layout_panel()
		_top_roller.position.y = 40
		_bottom_roller.position.y = 1400
		_parchment.size.y = 1360
		_message.text = full_text
		_constrain_message_width()
		_animating = false
		return

	var target_pos: Vector2 = _panel.position
	var target_scale: Vector2 = _panel.scale
	_panel.scale = target_scale * Vector2(0.42, 0.28)
	_panel.modulate.a = 0.0
	_panel.rotation = deg_to_rad(-6.0)
	_top_roller.position.y = 620
	_bottom_roller.position.y = 680
	_parchment.size.y = 40
	_dim.color.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.72, 0.35)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.3)
	tw.tween_property(_panel, "scale", target_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "rotation", 0.0, 0.4)
	tw.tween_property(_panel, "position", target_pos, 0.45)
	await tw.finished
	if not _visible_modal:
		return

	var unroll := create_tween()
	unroll.set_parallel(true)
	unroll.tween_property(_top_roller, "position:y", 40.0, 0.4).set_trans(Tween.TRANS_SINE)
	unroll.tween_property(_bottom_roller, "position:y", 1400.0, 0.5).set_trans(Tween.TRANS_SINE)
	unroll.tween_property(_parchment, "size:y", 1360.0, 0.5)
	await unroll.finished

	await _reveal_text(full_text)
	_layout_panel()
	_animating = false


func _reveal_text(full_text: String) -> void:
	if manager != null and manager.is_reduced_motion():
		_message.text = full_text
		_constrain_message_width()
		return
	var chunks: PackedStringArray = _chunk_text(full_text)
	_message.text = ""
	for chunk in chunks:
		if _skip_text or not _visible_modal:
			_message.text = full_text
			_constrain_message_width()
			return
		_message.text += chunk
		_constrain_message_width()
		await get_tree().create_timer(0.035).timeout
	_message.text = full_text
	_constrain_message_width()


func _chunk_text(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var words: PackedStringArray = text.split(" ")
	var buf := ""
	for i in words.size():
		buf += words[i]
		if i < words.size() - 1:
			buf += " "
		if buf.length() >= 18 or i == words.size() - 1:
			out.append(buf)
			buf = ""
	return out


func _on_zoom_changed(scale: float) -> void:
	var size_px: int = int(round(float(_base_font_size) * scale))
	_message.add_theme_font_size_override("normal_font_size", size_px)
	_constrain_message_width()
	if manager:
		manager.set_text_scale(scale)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _animating:
		_skip_text = true
		request_skip_open()


func request_skip_open() -> void:
	_skip_text = true
	_dim.color.a = 0.72
	_layout_panel()
	_top_roller.position.y = 40
	_bottom_roller.position.y = 1400
	_parchment.size.y = 1360


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	var date_copy: String = current_date
	var start_pos: Vector2 = _panel.global_position + (_panel.size * _panel.scale) * 0.5
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var end_pos: Vector2 = Vector2(vp.x * 0.5 - 40.0, vp.y * 0.82)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_top_roller, "position:y", 620.0, 0.25)
	tw.tween_property(_bottom_roller, "position:y", 680.0, 0.25)
	tw.tween_property(_panel, "scale", _panel.scale * Vector2(0.18, 0.1), 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_panel, "position", end_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.35)
	tw.tween_property(_dim, "color:a", 0.0, 0.3)
	await tw.finished
	visible = false
	_layout_panel()
	archive_flight_requested.emit(date_copy, start_pos)
	closed.emit(date_copy)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _zoom.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and _animating:
		_skip_text = true
		request_skip_open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()
