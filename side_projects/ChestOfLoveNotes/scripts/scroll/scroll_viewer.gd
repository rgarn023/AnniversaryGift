extends CanvasLayer
class_name LoveNotesScrollViewer
## Responsive parchment message viewer adapted from Anniversary Gift layout fixes.
## Zoom changes font size only — never Control.scale on the text branch.

signal closed
signal archive_flight_requested(screen_pos: Vector2)

const ART := "res://assets/art/scroll/"
const BASE_BODY_FONT_SIZE: int = 34
const MIN_BODY_FONT_SIZE: int = 26
const MAX_BODY_FONT_SIZE: int = 64
const BASE_HEADING_FONT_SIZE: int = 40
const BASE_META_FONT_SIZE: int = 24
const MIN_MESSAGE_ZOOM: float = 0.8
const MAX_MESSAGE_ZOOM: float = 1.9
const MAX_PARCHMENT_WIDTH: float = 900.0
const SIDE_GAP: float = 32.0
const MIN_SIDE_GAP: float = 24.0

var message_zoom: float = 1.0
var _zoom: GestureZoomController
var _root: Control
var _dim: ColorRect
var _full_screen_margin: MarginContainer
var _center: CenterContainer
var _parchment_aspect: Control
var _anim_root: Control
var _viewer_layout: Control
var _shadow: TextureRect
var _rolled: TextureRect
var _unrolled_root: Control
var _parchment_panel: Control
var _parchment: TextureRect
var _left_edge: TextureRect
var _right_edge: TextureRect
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _highlight: TextureRect
var _content_margin: MarginContainer
var _content: VBoxContainer
var _heading: Label
var _meta_label: Label
var _message: RichTextLabel
var _scroll: ScrollContainer
var _hint: Label
var _btn_close: Button
var _btn_plus: Button
var _btn_minus: Button
var _btn_reset: Button
var _animating: bool = false
var _short_open: bool = false
var _skip: bool = false
var _visible_modal: bool = false
var _parchment_size: Vector2 = Vector2(900, 1480)
var _zoom_enabled: bool = false
var _content_pad_left: float = 48.0
var _content_pad_right: float = 48.0
var _safe_left: float = 24.0
var _safe_right: float = 24.0
var _safe_top: float = 24.0
var _safe_bottom: float = 24.0
var _clear_on_close: bool = false
var _reduced_motion: bool = false


func _ready() -> void:
	layer = 40
	_zoom = GestureZoomController.new()
	_zoom.min_scale = MIN_MESSAGE_ZOOM
	_zoom.max_scale = MAX_MESSAGE_ZOOM
	_zoom.zoom_changed.connect(_on_zoom_changed)
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
	_dim.color = Color(0.02, 0.01, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	_root.add_child(_dim)

	_full_screen_margin = MarginContainer.new()
	_full_screen_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_screen_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_full_screen_margin)

	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_screen_margin.add_child(_center)

	_parchment_aspect = Control.new()
	_parchment_aspect.custom_minimum_size = _parchment_size
	_parchment_aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_parchment_aspect)

	_anim_root = Control.new()
	_anim_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_anim_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_parchment_aspect.add_child(_anim_root)

	_viewer_layout = Control.new()
	_viewer_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer_layout.mouse_filter = Control.MOUSE_FILTER_STOP
	_anim_root.add_child(_viewer_layout)

	_shadow = _make_tex(ART + "scroll_shadow.png")
	_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shadow.modulate = Color(1, 1, 1, 0.45)
	_shadow.position = Vector2(8, 14)
	_viewer_layout.add_child(_shadow)

	_rolled = _make_tex(ART + "scroll_rolled.png")
	_rolled.size = Vector2(640, 140)
	_rolled.pivot_offset = Vector2(320, 70)
	_viewer_layout.add_child(_rolled)

	_unrolled_root = Control.new()
	_unrolled_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_unrolled_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unrolled_root.visible = false
	_viewer_layout.add_child(_unrolled_root)

	_parchment_panel = Control.new()
	_parchment_panel.clip_contents = true
	_parchment_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_parchment_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_panel.offset_left = 20.0
	_parchment_panel.offset_right = -20.0
	_parchment_panel.offset_top = 58.0
	_parchment_panel.offset_bottom = -72.0
	_unrolled_root.add_child(_parchment_panel)

	_parchment = _make_tex(ART + "scroll_parchment_center.png")
	_parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_panel.add_child(_parchment)

	_left_edge = _make_tex(ART + "scroll_left_edge.png")
	_left_edge.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_left_edge.offset_right = 40
	_left_edge.modulate.a = 0.7
	_parchment_panel.add_child(_left_edge)

	_right_edge = _make_tex(ART + "scroll_right_edge.png")
	_right_edge.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_right_edge.offset_left = -48
	_right_edge.modulate.a = 0.7
	_parchment_panel.add_child(_right_edge)

	_highlight = _make_tex(ART + "scroll_highlight.png")
	_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight.modulate = Color(1, 1, 1, 0.16)
	_parchment_panel.add_child(_highlight)

	_content_margin = MarginContainer.new()
	_content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_margin.add_theme_constant_override("margin_left", 48)
	_content_margin.add_theme_constant_override("margin_right", 48)
	_content_margin.add_theme_constant_override("margin_top", 48)
	_content_margin.add_theme_constant_override("margin_bottom", 40)
	_content_margin.modulate.a = 0.0
	_parchment_panel.add_child(_content_margin)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_content_margin.add_child(_content)

	_meta_label = Label.new()
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_label.add_theme_color_override("font_color", Color(0.42, 0.22, 0.16))
	_meta_label.add_theme_font_size_override("font_size", BASE_META_FONT_SIZE)
	_content.add_child(_meta_label)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.28, 0.13, 0.09))
	_heading.add_theme_font_size_override("font_size", BASE_HEADING_FONT_SIZE)
	_content.add_child(_heading)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(_scroll)

	_message = RichTextLabel.new()
	_message.bbcode_enabled = true
	_message.fit_content = true
	_message.scroll_active = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.clip_contents = false
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("default_color", Color(0.18, 0.1, 0.08))
	_message.add_theme_font_size_override("normal_font_size", BASE_BODY_FONT_SIZE)
	_scroll.add_child(_message)

	_hint = Label.new()
	_hint.text = "Pinch or use A− / A+ to resize text"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.38, 0.24, 0.16, 0.85))
	_hint.add_theme_font_size_override("font_size", 18)
	_content.add_child(_hint)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	_content.add_child(toolbar)
	_btn_minus = _make_tool_button("A−")
	_btn_plus = _make_tool_button("A+")
	_btn_reset = _make_tool_button("Reset")
	_btn_close = _make_tool_button("Close")
	for b in [_btn_minus, _btn_plus, _btn_reset, _btn_close]:
		toolbar.add_child(b)

	_top_roller = _make_tex(ART + "scroll_top_roller.png")
	_top_roller.size = Vector2(900, 70)
	_top_roller.z_index = 2
	_unrolled_root.add_child(_top_roller)
	_bottom_roller = _make_tex(ART + "scroll_bottom_roller.png")
	_bottom_roller.size = Vector2(900, 70)
	_bottom_roller.z_index = 2
	_unrolled_root.add_child(_bottom_roller)

	_btn_minus.pressed.connect(func() -> void:
		if _zoom_enabled:
			_zoom.adjust(0.9)
	)
	_btn_plus.pressed.connect(func() -> void:
		if _zoom_enabled:
			_zoom.adjust(1.1)
	)
	_btn_reset.pressed.connect(func() -> void:
		if _zoom_enabled:
			_zoom.reset(1.0)
	)
	_btn_close.pressed.connect(close_viewer)
	_apply_fonts()


func _make_tool_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
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
		_meta_label.add_theme_font_override("font", body)
		_hint.add_theme_font_override("font", body)


func _logical_viewport_size() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return Vector2(1080, 2400)
	return viewport_size


func _compute_safe_insets() -> void:
	var viewport_size := _logical_viewport_size()
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var scale_x := viewport_size.x / float(maxi(screen.x, 1))
	var scale_y := viewport_size.y / float(maxi(screen.y, 1))
	_safe_left = maxf(MIN_SIDE_GAP, safe.position.x * scale_x)
	_safe_top = maxf(MIN_SIDE_GAP, safe.position.y * scale_y)
	_safe_right = maxf(MIN_SIDE_GAP, (screen.x - (safe.position.x + safe.size.x)) * scale_x)
	_safe_bottom = maxf(MIN_SIDE_GAP, (screen.y - (safe.position.y + safe.size.y)) * scale_y)
	_full_screen_margin.add_theme_constant_override("margin_left", int(_safe_left))
	_full_screen_margin.add_theme_constant_override("margin_right", int(_safe_right))
	_full_screen_margin.add_theme_constant_override("margin_top", int(_safe_top))
	_full_screen_margin.add_theme_constant_override("margin_bottom", int(_safe_bottom))


func _fit_panel() -> void:
	_compute_safe_insets()
	var viewport_size := _logical_viewport_size()
	var safe_width := viewport_size.x - _safe_left - _safe_right
	var safe_height := viewport_size.y - _safe_top - _safe_bottom
	var parchment_width := minf(safe_width - SIDE_GAP, MAX_PARCHMENT_WIDTH)
	parchment_width = maxf(parchment_width, 280.0)
	var parchment_height := minf(safe_height - 16.0, parchment_width * 1.62)
	parchment_height = maxf(parchment_height, 520.0)
	_parchment_size = Vector2(parchment_width, parchment_height)
	_parchment_aspect.custom_minimum_size = _parchment_size
	_parchment_aspect.size = _parchment_size
	var pad_scale := clampf(parchment_width / 900.0, 0.55, 1.0)
	_content_pad_left = maxf(24.0, 48.0 * pad_scale)
	_content_pad_right = maxf(24.0, 48.0 * pad_scale)
	_content_margin.add_theme_constant_override("margin_left", int(_content_pad_left))
	_content_margin.add_theme_constant_override("margin_right", int(_content_pad_right))
	_content_margin.add_theme_constant_override("margin_top", int(maxf(24.0, 48.0 * pad_scale)))
	_content_margin.add_theme_constant_override("margin_bottom", int(maxf(24.0, 40.0 * pad_scale)))
	_top_roller.size = Vector2(_parchment_size.x, 64.0)
	_bottom_roller.size = Vector2(_parchment_size.x, 64.0)
	_anim_root.position = Vector2.ZERO
	_anim_root.scale = Vector2.ONE
	call_deferred("_refresh_message_layout")


func _usable_message_width() -> float:
	var panel_side_inset := 40.0
	return maxf(_parchment_size.x - panel_side_inset - _content_pad_left - _content_pad_right, 160.0)


func _refresh_message_layout() -> void:
	var w := _usable_message_width()
	_message.custom_minimum_size = Vector2(w, 0)
	_heading.custom_minimum_size = Vector2(w, 0)
	_meta_label.custom_minimum_size = Vector2(w, 0)
	_hint.custom_minimum_size = Vector2(w, 0)


func _on_viewport_resized() -> void:
	if visible:
		_fit_panel()


func open_message(
	title: String,
	meta: String,
	body: String,
	short_animation: bool = false,
	clear_on_close: bool = false
) -> void:
	_short_open = short_animation
	_clear_on_close = clear_on_close
	_skip = false
	_zoom_enabled = false
	_visible_modal = true
	visible = true
	_fit_panel()
	_heading.text = title if not title.is_empty() else "A Love Note"
	_meta_label.text = meta
	_set_message_text("")
	message_zoom = 1.0
	_zoom.reset(1.0)
	apply_message_zoom()
	await _play_open_animation(body)
	_zoom_enabled = true


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _set_message_text(plain: String) -> void:
	if plain.is_empty():
		_message.text = ""
		return
	_message.text = "[center]%s[/center]" % _escape_bbcode(plain)


func apply_message_zoom() -> void:
	message_zoom = clampf(message_zoom, MIN_MESSAGE_ZOOM, MAX_MESSAGE_ZOOM)
	var body_size: int = clampi(roundi(BASE_BODY_FONT_SIZE * message_zoom), MIN_BODY_FONT_SIZE, MAX_BODY_FONT_SIZE)
	var heading_size: int = clampi(roundi(BASE_HEADING_FONT_SIZE * message_zoom), 28, 72)
	var meta_size: int = clampi(roundi(BASE_META_FONT_SIZE * message_zoom), 18, 40)
	_message.add_theme_font_size_override("normal_font_size", body_size)
	_heading.add_theme_font_size_override("font_size", heading_size)
	_meta_label.add_theme_font_size_override("font_size", meta_size)
	_message.scale = Vector2.ONE
	_scroll.scale = Vector2.ONE
	_content_margin.scale = Vector2.ONE
	call_deferred("_refresh_message_layout")


func _play_open_animation(full_text: String) -> void:
	_animating = true
	if _reduced_motion or _short_open:
		_set_fully_unrolled()
		_dim.color.a = 0.75
		_content_margin.modulate.a = 1.0
		_set_message_text(full_text)
		await get_tree().process_frame
		_refresh_message_layout()
		_animating = false
		return

	_dim.color.a = 0.0
	_anim_root.scale = Vector2.ONE
	_set_rolled_at_start()
	_anim_root.position = Vector2(0, _parchment_size.y * 0.18)
	var rise := create_tween()
	rise.set_parallel(true)
	rise.tween_property(_dim, "color:a", 0.72, 0.35)
	rise.tween_property(_anim_root, "position", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await rise.finished
	if not _visible_modal or _skip:
		_finish_open_immediate(full_text)
		return

	_unrolled_root.visible = true
	_content_margin.modulate.a = 0.0
	var mid_y: float = _parchment_size.y * 0.5
	_top_roller.position = Vector2(0, mid_y - 32.0)
	_bottom_roller.position = Vector2(0, mid_y - 32.0)
	_parchment_panel.offset_top = mid_y - 16.0
	_parchment_panel.offset_bottom = -(_parchment_size.y - mid_y - 16.0)
	var unroll := create_tween()
	unroll.set_parallel(true)
	unroll.tween_property(_rolled, "modulate:a", 0.0, 0.18)
	unroll.tween_property(_top_roller, "position:y", -2.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_bottom_roller, "position:y", _parchment_size.y - 62.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_panel, "offset_top", 58.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_panel, "offset_bottom", -72.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await unroll.finished
	if not _visible_modal:
		return
	_rolled.visible = false
	var text_in := create_tween()
	text_in.tween_property(_content_margin, "modulate:a", 1.0, 0.28)
	await text_in.finished
	_set_message_text(full_text)
	_refresh_message_layout()
	_animating = false


func _set_rolled_at_start() -> void:
	_rolled.visible = true
	_rolled.modulate.a = 1.0
	_rolled.size = Vector2(minf(640.0, _parchment_size.x * 0.85), 140.0)
	_rolled.pivot_offset = _rolled.size * 0.5
	_rolled.position = Vector2((_parchment_size.x - _rolled.size.x) * 0.5, (_parchment_size.y - _rolled.size.y) * 0.5)
	_unrolled_root.visible = false
	_content_margin.modulate.a = 0.0


func _set_fully_unrolled() -> void:
	_rolled.visible = false
	_unrolled_root.visible = true
	_parchment_panel.offset_left = 20.0
	_parchment_panel.offset_right = -20.0
	_parchment_panel.offset_top = 58.0
	_parchment_panel.offset_bottom = -72.0
	_top_roller.position = Vector2(0, -2.0)
	_bottom_roller.position = Vector2(0, _parchment_size.y - 62.0)
	_top_roller.size = Vector2(_parchment_size.x, 64)
	_bottom_roller.size = Vector2(_parchment_size.x, 64)
	_content_margin.modulate.a = 1.0
	_anim_root.position = Vector2.ZERO
	_anim_root.scale = Vector2.ONE
	_refresh_message_layout()


func _finish_open_immediate(full_text: String) -> void:
	_set_fully_unrolled()
	_dim.color.a = 0.75
	_set_message_text(full_text)
	_animating = false


func _on_zoom_changed(scale: float) -> void:
	if not _zoom_enabled:
		return
	message_zoom = clampf(scale, MIN_MESSAGE_ZOOM, MAX_MESSAGE_ZOOM)
	apply_message_zoom()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _animating:
		_skip = true


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	_zoom_enabled = false
	var start_pos: Vector2 = _anim_root.global_position + _parchment_size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_anim_root, "scale", Vector2(0.35, 0.35), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_anim_root, "modulate:a", 0.0, 0.24)
	tw.tween_property(_dim, "color:a", 0.0, 0.24)
	await tw.finished
	if _clear_on_close:
		_set_message_text("")
	visible = false
	_anim_root.scale = Vector2.ONE
	_anim_root.modulate = Color.WHITE
	archive_flight_requested.emit(start_pos)
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _zoom_enabled and _zoom.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()
