extends CanvasLayer
class_name ScrollViewer

## Full-screen parchment scroll modal with zoom and Android back support.
## Uses container layout so text cannot escape the parchment bounds.

signal closed(date_iso: String)
signal archive_flight_requested(date_iso: String, screen_pos: Vector2)

const MIN_SCALE := 0.8
const MAX_SCALE := 2.2
const CARD_SIZE := Vector2(900, 1480)

var manager: AnniversaryManager
var current_date: String = ""
var _zoom: GestureZoomController
var _root: Control
var _dim: ColorRect
var _center: CenterContainer
var _card: PanelContainer
var _heading: Label
var _date_label: Label
var _message: RichTextLabel
var _scroll: ScrollContainer
var _hint: Label
var _btn_close: Button
var _btn_plus: Button
var _btn_minus: Button
var _btn_reset: Button
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _base_font_size: int = 26
var _animating: bool = false
var _short_open: bool = false
var _skip_text: bool = false
var _visible_modal: bool = false


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
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	_root.add_child(_dim)

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = CARD_SIZE
	_card.clip_contents = true
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", _make_parchment_style())
	_center.add_child(_card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_card.add_child(outer)

	_top_roller = _make_roller(true)
	outer.add_child(_top_roller)

	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 48)
	body_margin.add_theme_constant_override("margin_right", 48)
	body_margin.add_theme_constant_override("margin_top", 18)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	outer.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_child(body)

	_date_label = Label.new()
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.add_theme_color_override("font_color", Color(0.45, 0.2, 0.28))
	_date_label.add_theme_font_size_override("font_size", 22)
	body.add_child(_date_label)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.32, 0.14, 0.1))
	_heading.add_theme_font_size_override("font_size", 34)
	body.add_child(_heading)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(0.72, 0.52, 0.18, 0.55)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	_scroll.custom_minimum_size = Vector2(0, 700)
	body.add_child(_scroll)

	# Width-constrained wrapper so autowrap always has a finite width.
	var text_host := MarginContainer.new()
	text_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_host.add_theme_constant_override("margin_right", 8)
	_scroll.add_child(text_host)

	_message = RichTextLabel.new()
	_message.bbcode_enabled = false
	_message.fit_content = true
	_message.scroll_active = false
	_message.scroll_following = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.selection_enabled = false
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.add_theme_color_override("default_color", Color(0.2, 0.11, 0.09))
	_message.add_theme_font_size_override("normal_font_size", _base_font_size)
	text_host.add_child(_message)

	_hint = Label.new()
	_hint.text = "Pinch or use + and – to resize"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.4, 0.25, 0.18, 0.85))
	_hint.add_theme_font_size_override("font_size", 18)
	body.add_child(_hint)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	body.add_child(toolbar)
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

	_bottom_roller = _make_roller(false)
	outer.add_child(_bottom_roller)

	_apply_fonts()
	_card.resized.connect(_update_message_width)
	_scroll.resized.connect(_update_message_width)


func _make_parchment_style() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	if ResourceLoader.exists("res://assets/art/scroll/scroll_parchment.png"):
		sb.texture = load("res://assets/art/scroll/scroll_parchment.png")
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	# Keep texture edges from eating text.
	sb.texture_margin_left = 36
	sb.texture_margin_right = 36
	sb.texture_margin_top = 28
	sb.texture_margin_bottom = 28
	return sb


func _make_roller(top: bool) -> TextureRect:
	var tr := TextureRect.new()
	var path := "res://assets/art/scroll/scroll_top_roller.png" if top else "res://assets/art/scroll/scroll_bottom_roller.png"
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.custom_minimum_size = Vector2(0, 64)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _make_tool_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(100, 60)
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


func _fit_card_to_viewport() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1080, 2400)
	var scale_fit: float = minf((vp.x * 0.94) / CARD_SIZE.x, (vp.y * 0.86) / CARD_SIZE.y)
	scale_fit = clampf(scale_fit, 0.5, 1.0)
	_card.custom_minimum_size = CARD_SIZE * scale_fit
	_card.size = _card.custom_minimum_size
	_update_message_width()


func _update_message_width() -> void:
	# Force a concrete wrap width inside the scroll area.
	var w: float = maxf(_scroll.size.x - 16.0, 200.0)
	_message.custom_minimum_size = Vector2(w, 0)


func _on_viewport_resized() -> void:
	if visible:
		_fit_card_to_viewport()


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
	_fit_card_to_viewport()
	_date_label.text = DateService.format_display_date(date_iso)
	_heading.text = str(msg.get("heading", ""))
	_message.text = ""
	_zoom.reset(manager.get_text_scale())
	_on_zoom_changed(_zoom.current_scale)
	await _play_open_animation(str(msg.get("message", "")))


func _play_open_animation(full_text: String) -> void:
	_animating = true
	var reduced: bool = manager != null and manager.is_reduced_motion()
	if reduced or _short_open:
		_dim.color.a = 0.75
		_card.modulate = Color.WHITE
		_card.scale = Vector2.ONE
		_message.text = full_text
		await get_tree().process_frame
		_update_message_width()
		_animating = false
		return

	_dim.color.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.85, 0.85)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.75, 0.3)
	tw.tween_property(_card, "modulate:a", 1.0, 0.3)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not _visible_modal:
		return
	await _reveal_text(full_text)
	_update_message_width()
	_animating = false


func _reveal_text(full_text: String) -> void:
	if manager != null and manager.is_reduced_motion():
		_message.text = full_text
		return
	var chunks: PackedStringArray = _chunk_text(full_text)
	_message.text = ""
	for chunk in chunks:
		if _skip_text or not _visible_modal:
			_message.text = full_text
			return
		_message.text += chunk
		await get_tree().create_timer(0.03).timeout
	_message.text = full_text


func _chunk_text(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var words: PackedStringArray = text.split(" ")
	var buf := ""
	for i in words.size():
		buf += words[i]
		if i < words.size() - 1:
			buf += " "
		if buf.length() >= 20 or i == words.size() - 1:
			out.append(buf)
			buf = ""
	return out


func _on_zoom_changed(scale: float) -> void:
	var size_px: int = int(round(float(_base_font_size) * scale))
	_message.add_theme_font_size_override("normal_font_size", size_px)
	_update_message_width()
	if manager:
		manager.set_text_scale(scale)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _animating:
		_skip_text = true
		request_skip_open()


func request_skip_open() -> void:
	_skip_text = true
	_dim.color.a = 0.75
	_card.modulate = Color.WHITE
	_card.scale = Vector2.ONE


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	var date_copy: String = current_date
	var start_pos: Vector2 = _card.global_position + _card.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_card, "scale", Vector2(0.2, 0.12), 0.35)
	tw.tween_property(_card, "modulate:a", 0.0, 0.3)
	tw.tween_property(_dim, "color:a", 0.0, 0.28)
	await tw.finished
	visible = false
	_card.scale = Vector2.ONE
	_card.modulate = Color.WHITE
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
