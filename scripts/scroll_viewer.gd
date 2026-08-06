extends CanvasLayer
class_name ScrollViewer

## Photoreal layered parchment scroll with physical unroll animation.

signal closed(date_iso: String)
signal archive_flight_requested(date_iso: String, screen_pos: Vector2)

const ART := "res://assets/art/scroll/"
const MIN_SCALE := 0.8
const MAX_SCALE := 2.2
const CARD_SIZE := Vector2(920, 1520)

var manager: AnniversaryManager
var current_date: String = ""
var _zoom: GestureZoomController
var _root: Control
var _dim: ColorRect
var _center: CenterContainer
var _scroll_root: Control
var _shadow: TextureRect
var _highlight: TextureRect
var _rolled: TextureRect
var _parchment_host: Control
var _parchment: TextureRect
var _left_edge: TextureRect
var _right_edge: TextureRect
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _content: Control
var _heading: Label
var _date_label: Label
var _message: RichTextLabel
var _scroll: ScrollContainer
var _hint: Label
var _btn_close: Button
var _btn_plus: Button
var _btn_minus: Button
var _btn_reset: Button
var _base_font_size: int = 26
var _animating: bool = false
var _short_open: bool = false
var _skip_text: bool = false
var _visible_modal: bool = false
var _card_size: Vector2 = CARD_SIZE


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


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _make_tex_rect(path: String) -> TextureRect:
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
	_dim.color = Color(0.02, 0.01, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	_root.add_child(_dim)

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)

	_scroll_root = Control.new()
	_scroll_root.name = "ScrollRoot"
	_scroll_root.custom_minimum_size = CARD_SIZE
	_scroll_root.clip_contents = false
	_scroll_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.add_child(_scroll_root)

	_shadow = _make_tex_rect(ART + "scroll_shadow.png")
	_shadow.name = "ScrollShadow"
	_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shadow.modulate = Color(1, 1, 1, 0.55)
	_shadow.position = Vector2(10, 18)
	_scroll_root.add_child(_shadow)

	_rolled = _make_tex_rect(ART + "scroll_rolled.png")
	_rolled.name = "RolledScroll"
	_rolled.set_anchors_preset(Control.PRESET_CENTER)
	_rolled.offset_left = -360
	_rolled.offset_right = 360
	_rolled.offset_top = -70
	_rolled.offset_bottom = 70
	_rolled.visible = false
	_scroll_root.add_child(_rolled)

	_parchment_host = Control.new()
	_parchment_host.name = "ParchmentHost"
	_parchment_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_host.clip_contents = true
	_parchment_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_root.add_child(_parchment_host)

	_parchment = _make_tex_rect(ART + "scroll_parchment_center.png")
	_parchment.name = "ParchmentCenter"
	_parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_host.add_child(_parchment)

	_left_edge = _make_tex_rect(ART + "scroll_left_edge.png")
	_left_edge.name = "LeftEdge"
	_left_edge.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_left_edge.offset_right = 70
	_left_edge.modulate.a = 0.85
	_parchment_host.add_child(_left_edge)

	_right_edge = _make_tex_rect(ART + "scroll_right_edge.png")
	_right_edge.name = "RightEdge"
	_right_edge.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_right_edge.offset_left = -90
	_right_edge.modulate.a = 0.85
	_parchment_host.add_child(_right_edge)

	_highlight = _make_tex_rect(ART + "scroll_highlight.png")
	_highlight.name = "ScrollHighlight"
	_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight.modulate = Color(1, 1, 1, 0.28)
	_parchment_host.add_child(_highlight)

	_top_roller = _make_tex_rect(ART + "scroll_top_roller.png")
	_top_roller.name = "TopRoller"
	_top_roller.anchor_left = 0.0
	_top_roller.anchor_top = 0.0
	_top_roller.anchor_right = 0.0
	_top_roller.anchor_bottom = 0.0
	_top_roller.size = Vector2(920, 72)
	_scroll_root.add_child(_top_roller)

	_bottom_roller = _make_tex_rect(ART + "scroll_bottom_roller.png")
	_bottom_roller.name = "BottomRoller"
	_bottom_roller.anchor_left = 0.0
	_bottom_roller.anchor_top = 0.0
	_bottom_roller.anchor_right = 0.0
	_bottom_roller.anchor_bottom = 0.0
	_bottom_roller.size = Vector2(920, 72)
	_scroll_root.add_child(_bottom_roller)

	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 56
	_content.offset_right = -56
	_content.offset_top = 88
	_content.offset_bottom = -96
	_content.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll_root.add_child(_content)

	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 12)
	_content.add_child(body)

	_date_label = Label.new()
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.add_theme_color_override("font_color", Color(0.42, 0.22, 0.16))
	_date_label.add_theme_font_size_override("font_size", 22)
	body.add_child(_date_label)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.28, 0.13, 0.09))
	_heading.add_theme_font_size_override("font_size", 34)
	body.add_child(_heading)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	_scroll.custom_minimum_size = Vector2(0, 700)
	body.add_child(_scroll)

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
	_message.add_theme_color_override("default_color", Color(0.18, 0.1, 0.08))
	_message.add_theme_font_size_override("normal_font_size", _base_font_size)
	text_host.add_child(_message)

	_hint = Label.new()
	_hint.text = "Pinch or use + and – to resize"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.38, 0.24, 0.16, 0.85))
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

	_apply_fonts()
	_scroll_root.resized.connect(_update_message_width)
	_scroll.resized.connect(_update_message_width)


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
	_card_size = CARD_SIZE * scale_fit
	_scroll_root.custom_minimum_size = _card_size
	_scroll_root.size = _card_size
	_update_message_width()


func _update_message_width() -> void:
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
		_set_unrolled_pose(true)
		_dim.color.a = 0.75
		_scroll_root.modulate = Color.WHITE
		_message.text = full_text
		await get_tree().process_frame
		_update_message_width()
		_animating = false
		return

	_dim.color.a = 0.0
	_scroll_root.modulate = Color.WHITE
	_set_rolled_pose()
	_content.modulate.a = 0.0

	var rise := create_tween()
	rise.set_parallel(true)
	rise.tween_property(_dim, "color:a", 0.72, 0.35)
	rise.tween_property(_rolled, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(_rolled, "rotation", deg_to_rad(2.0), 0.45)
	rise.tween_property(_rolled, "modulate:a", 1.0, 0.25)
	await rise.finished
	if not _visible_modal:
		return
	if _skip_text:
		_set_unrolled_pose(true)
		_message.text = full_text
		_animating = false
		return

	# Unroll: rollers travel apart, parchment reveals between them.
	_parchment_host.visible = true
	_parchment_host.modulate.a = 1.0
	_top_roller.visible = true
	_bottom_roller.visible = true
	_top_roller.modulate.a = 1.0
	_bottom_roller.modulate.a = 1.0
	_shadow.modulate.a = 0.25

	var mid_y: float = _card_size.y * 0.5
	var roller_w: float = _card_size.x
	_top_roller.size = Vector2(roller_w, 72.0)
	_bottom_roller.size = Vector2(roller_w, 72.0)
	_top_roller.position = Vector2(0.0, mid_y - 36.0)
	_bottom_roller.position = Vector2(0.0, mid_y - 36.0)
	# Clip parchment open from center by shrinking host height via offsets.
	_parchment_host.offset_top = mid_y - 20.0
	_parchment_host.offset_bottom = -(_card_size.y - mid_y - 20.0)
	_left_edge.scale = Vector2(1.15, 1.0)
	_right_edge.scale = Vector2(1.15, 1.0)

	var unroll := create_tween()
	unroll.set_parallel(true)
	unroll.tween_property(_rolled, "modulate:a", 0.0, 0.2)
	unroll.tween_property(_top_roller, "position:y", -4.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_bottom_roller, "position:y", _card_size.y - 68.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_host, "offset_top", 64.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_host, "offset_bottom", -80.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_left_edge, "scale", Vector2(1.0, 1.0), 0.75).set_trans(Tween.TRANS_SINE)
	unroll.tween_property(_right_edge, "scale", Vector2(1.0, 1.0), 0.75).set_trans(Tween.TRANS_SINE)
	unroll.tween_property(_shadow, "modulate:a", 0.55, 0.55)
	unroll.tween_property(_highlight, "modulate:a", 0.3, 0.55)
	await unroll.finished
	if not _visible_modal:
		return

	# Flex / settle
	var settle := create_tween()
	settle.tween_property(_scroll_root, "rotation", deg_to_rad(0.4), 0.1)
	settle.tween_property(_scroll_root, "rotation", 0.0, 0.16)
	await settle.finished

	_rolled.visible = false
	_content.modulate.a = 0.0
	var text_in := create_tween()
	text_in.tween_property(_content, "modulate:a", 1.0, 0.25)
	await text_in.finished
	if not _visible_modal:
		return
	await _reveal_text(full_text)
	_update_message_width()
	_animating = false


func _set_rolled_pose() -> void:
	_rolled.visible = true
	_rolled.modulate.a = 0.0
	_rolled.rotation = deg_to_rad(-8.0)
	_rolled.position = Vector2((_card_size.x - 720.0) * 0.5, _card_size.y * 0.55)
	_rolled.size = Vector2(720, 140)
	_parchment_host.visible = true
	_parchment_host.modulate.a = 0.0
	_top_roller.visible = false
	_bottom_roller.visible = false
	_content.modulate.a = 0.0
	_shadow.modulate.a = 0.15
	_scroll_root.rotation = 0.0


func _set_unrolled_pose(show_content: bool) -> void:
	_rolled.visible = false
	_parchment_host.visible = true
	_parchment_host.modulate.a = 1.0
	_parchment_host.offset_top = 64.0
	_parchment_host.offset_bottom = -80.0
	_scroll_root.rotation = 0.0
	_top_roller.visible = true
	_bottom_roller.visible = true
	_top_roller.modulate.a = 1.0
	_bottom_roller.modulate.a = 1.0
	_top_roller.size = Vector2(_card_size.x, 72.0)
	_bottom_roller.size = Vector2(_card_size.x, 72.0)
	_top_roller.position = Vector2(0.0, -4.0)
	_bottom_roller.position = Vector2(0.0, _card_size.y - 68.0)
	_left_edge.scale = Vector2.ONE
	_right_edge.scale = Vector2.ONE
	_shadow.modulate.a = 0.55
	_highlight.modulate.a = 0.28
	_content.modulate.a = 1.0 if show_content else 0.0


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
	_set_unrolled_pose(true)
	_scroll_root.modulate = Color.WHITE


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	var date_copy: String = current_date
	var start_pos: Vector2 = _scroll_root.global_position + _scroll_root.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_scroll_root, "scale", Vector2(0.2, 0.12), 0.35)
	tw.tween_property(_scroll_root, "modulate:a", 0.0, 0.3)
	tw.tween_property(_dim, "color:a", 0.0, 0.28)
	await tw.finished
	visible = false
	_scroll_root.scale = Vector2.ONE
	_scroll_root.modulate = Color.WHITE
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
