extends CanvasLayer
class_name ScrollViewer

## Photoreal parchment scroll with physical rise + clipped unroll.
## Text zoom is isolated from entrance animation scale.

signal closed(date_iso: String)
signal archive_flight_requested(date_iso: String, screen_pos: Vector2)

const ART := "res://assets/art/scroll/"
const MIN_TEXT_SCALE := 0.8
const MAX_TEXT_SCALE := 2.2
const PANEL_SIZE := Vector2(900, 1480)

var manager: AnniversaryManager
var current_date: String = ""
var _zoom: GestureZoomController
var _root: Control
var _dim: ColorRect
var _center: Control

## Entrance motion root (position/rotation only — never user zoom).
var _anim_root: Control
## Final layout shell.
var _viewer_layout: Control
var _shadow: TextureRect
var _rolled: TextureRect
var _unrolled_root: Control
var _parchment_clip: Control
var _parchment: TextureRect
var _left_edge: TextureRect
var _right_edge: TextureRect
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _highlight: TextureRect
## User text zoom only affects this branch.
var _text_zoom: Control
var _content: VBoxContainer
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
var _skip: bool = false
var _visible_modal: bool = false
var _panel_size: Vector2 = PANEL_SIZE
var _zoom_enabled: bool = false
var _emerge_from: Vector2 = Vector2.ZERO
var _use_emerge_from: bool = false


func _ready() -> void:
	layer = 40
	_zoom = GestureZoomController.new()
	_zoom.min_scale = MIN_TEXT_SCALE
	_zoom.max_scale = MAX_TEXT_SCALE
	_zoom.zoom_changed.connect(_on_zoom_changed)
	_build_ui()
	visible = false
	set_process_input(true)
	get_viewport().size_changed.connect(_on_viewport_resized)


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

	# Free-position host (not CenterContainer) so emerge tweens can move the scroll.
	_center = Control.new()
	_center.name = "ScrollStage"
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)

	_anim_root = Control.new()
	_anim_root.name = "ScrollAnimationRoot"
	_anim_root.custom_minimum_size = PANEL_SIZE
	_anim_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.add_child(_anim_root)

	_viewer_layout = Control.new()
	_viewer_layout.name = "ScrollViewerLayout"
	_viewer_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer_layout.mouse_filter = Control.MOUSE_FILTER_STOP
	_anim_root.add_child(_viewer_layout)

	_shadow = _make_tex(ART + "scroll_shadow.png")
	_shadow.name = "ScrollShadow"
	_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shadow.modulate = Color(1, 1, 1, 0.45)
	_shadow.position = Vector2(8, 14)
	_viewer_layout.add_child(_shadow)

	_rolled = _make_tex(ART + "scroll_rolled.png")
	_rolled.name = "RolledScroll"
	_rolled.anchor_left = 0.0
	_rolled.anchor_top = 0.0
	_rolled.anchor_right = 0.0
	_rolled.anchor_bottom = 0.0
	_rolled.size = Vector2(640, 140)
	_rolled.pivot_offset = Vector2(320, 70)
	_viewer_layout.add_child(_rolled)

	_unrolled_root = Control.new()
	_unrolled_root.name = "UnrolledScrollRoot"
	_unrolled_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_unrolled_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unrolled_root.visible = false
	_viewer_layout.add_child(_unrolled_root)

	_parchment_clip = Control.new()
	_parchment_clip.name = "ParchmentClip"
	_parchment_clip.clip_contents = true
	_parchment_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parchment_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_clip.offset_top = 64.0
	_parchment_clip.offset_bottom = -80.0
	_unrolled_root.add_child(_parchment_clip)

	_parchment = _make_tex(ART + "scroll_parchment_center.png")
	_parchment.name = "ParchmentCenter"
	_parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_clip.add_child(_parchment)

	_left_edge = _make_tex(ART + "scroll_left_edge.png")
	_left_edge.name = "LeftEdge"
	_left_edge.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_left_edge.offset_right = 64
	_left_edge.modulate.a = 0.8
	_parchment_clip.add_child(_left_edge)

	_right_edge = _make_tex(ART + "scroll_right_edge.png")
	_right_edge.name = "RightEdge"
	_right_edge.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_right_edge.offset_left = -80
	_right_edge.modulate.a = 0.8
	_parchment_clip.add_child(_right_edge)

	_highlight = _make_tex(ART + "scroll_highlight.png")
	_highlight.name = "ScrollHighlight"
	_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight.modulate = Color(1, 1, 1, 0.22)
	_parchment_clip.add_child(_highlight)

	_top_roller = _make_tex(ART + "scroll_top_roller.png")
	_top_roller.name = "TopRoller"
	_top_roller.size = Vector2(900, 70)
	_unrolled_root.add_child(_top_roller)

	_bottom_roller = _make_tex(ART + "scroll_bottom_roller.png")
	_bottom_roller.name = "BottomRoller"
	_bottom_roller.size = Vector2(900, 70)
	_unrolled_root.add_child(_bottom_roller)

	_text_zoom = Control.new()
	_text_zoom.name = "TextZoomContainer"
	_text_zoom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text_zoom.offset_left = 52
	_text_zoom.offset_right = -52
	_text_zoom.offset_top = 88
	_text_zoom.offset_bottom = -96
	_text_zoom.mouse_filter = Control.MOUSE_FILTER_STOP
	_text_zoom.modulate.a = 0.0
	_unrolled_root.add_child(_text_zoom)

	_content = VBoxContainer.new()
	_content.name = "MessageContent"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_theme_constant_override("separation", 12)
	_text_zoom.add_child(_content)

	_date_label = Label.new()
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.add_theme_color_override("font_color", Color(0.42, 0.22, 0.16))
	_date_label.add_theme_font_size_override("font_size", 22)
	_content.add_child(_date_label)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.28, 0.13, 0.09))
	_heading.add_theme_font_size_override("font_size", 34)
	_content.add_child(_heading)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	_scroll.custom_minimum_size = Vector2(0, 680)
	_content.add_child(_scroll)

	var text_host := MarginContainer.new()
	text_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_host.add_theme_constant_override("margin_right", 8)
	_scroll.add_child(text_host)

	_message = RichTextLabel.new()
	_message.name = "MessageText"
	_message.bbcode_enabled = false
	_message.fit_content = true
	_message.scroll_active = false
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
	_content.add_child(_hint)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	_content.add_child(toolbar)
	_btn_minus = _make_tool_button("–", "Decrease text size")
	_btn_plus = _make_tool_button("+", "Increase text size")
	_btn_reset = _make_tool_button("Reset", "Reset text size")
	_btn_close = _make_tool_button("Close", "Close message")
	for b in [_btn_minus, _btn_plus, _btn_reset, _btn_close]:
		toolbar.add_child(b)
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
	_anim_root.resized.connect(_update_message_width)
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


func _fit_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1080, 2400)
	var scale_fit: float = minf((vp.x * 0.94) / PANEL_SIZE.x, (vp.y * 0.86) / PANEL_SIZE.y)
	scale_fit = clampf(scale_fit, 0.5, 1.0)
	_panel_size = PANEL_SIZE * scale_fit
	_anim_root.custom_minimum_size = _panel_size
	_anim_root.size = _panel_size
	# Center the panel in the stage; emerge tweens offset from this rest pose.
	_anim_root.position = (vp - _panel_size) * 0.5
	_top_roller.size = Vector2(_panel_size.x, 70)
	_bottom_roller.size = Vector2(_panel_size.x, 70)
	_update_message_width()


func _update_message_width() -> void:
	var w: float = maxf(_scroll.size.x - 16.0, 200.0)
	_message.custom_minimum_size = Vector2(w, 0)


func _on_viewport_resized() -> void:
	if visible:
		_fit_panel()


func set_emerge_from(global_pos: Vector2) -> void:
	_emerge_from = global_pos
	_use_emerge_from = true


func open_message(date_iso: String, short_animation: bool = false) -> void:
	if manager == null:
		return
	var msg: Dictionary = manager.get_message_for_date(date_iso)
	if msg.is_empty():
		return
	current_date = date_iso
	_short_open = short_animation
	_skip = false
	_zoom_enabled = false
	_visible_modal = true
	visible = true
	_fit_panel()
	_date_label.text = DateService.format_display_date(date_iso)
	_heading.text = str(msg.get("heading", ""))
	_message.text = ""
	# Apply stored zoom to font only — never animate this with entrance.
	var stored: float = clampf(manager.get_text_scale(), MIN_TEXT_SCALE, MAX_TEXT_SCALE)
	_zoom.reset(stored)
	_apply_text_scale(stored)
	await _play_open_animation(str(msg.get("message", "")))
	_zoom_enabled = true
	_use_emerge_from = false


func _play_open_animation(full_text: String) -> void:
	_animating = true
	var reduced: bool = manager != null and manager.is_reduced_motion()
	if reduced or _short_open:
		_set_fully_unrolled()
		_dim.color.a = 0.75
		_text_zoom.modulate.a = 1.0
		_message.text = full_text
		await get_tree().process_frame
		_update_message_width()
		_animating = false
		return

	_dim.color.a = 0.0
	_anim_root.scale = Vector2.ONE
	_anim_root.rotation = 0.0
	_set_rolled_at_start()

	# Rise from chest position toward centered rest pose (no scale grow).
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var rest_pos: Vector2 = (vp - _panel_size) * 0.5
	var start_pos: Vector2 = rest_pos + Vector2(0, _panel_size.y * 0.18)
	if _use_emerge_from:
		start_pos = _emerge_from - _panel_size * 0.5
	_anim_root.position = start_pos
	_rolled.modulate.a = 1.0

	var rise := create_tween()
	rise.set_parallel(true)
	rise.tween_property(_dim, "color:a", 0.72, 0.35)
	rise.tween_property(_anim_root, "position", rest_pos, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(_rolled, "rotation", deg_to_rad(2.0), 0.45)
	await rise.finished
	if not _visible_modal:
		return
	if _skip:
		_finish_open_immediate(full_text)
		return

	# Settle facing viewer
	var face := create_tween()
	face.tween_property(_rolled, "rotation", 0.0, 0.18)
	await face.finished
	if _skip:
		_finish_open_immediate(full_text)
		return

	# Unroll with clipped parchment height (rollers do not stretch).
	_unrolled_root.visible = true
	_unrolled_root.modulate.a = 1.0
	_text_zoom.modulate.a = 0.0
	var mid_y: float = _panel_size.y * 0.5
	_top_roller.position = Vector2(0, mid_y - 35.0)
	_bottom_roller.position = Vector2(0, mid_y - 35.0)
	_parchment_clip.offset_top = mid_y - 16.0
	_parchment_clip.offset_bottom = -(_panel_size.y - mid_y - 16.0)
	_shadow.modulate.a = 0.25

	var unroll := create_tween()
	unroll.set_parallel(true)
	unroll.tween_property(_rolled, "modulate:a", 0.0, 0.18)
	unroll.tween_property(_top_roller, "position:y", -2.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_bottom_roller, "position:y", _panel_size.y - 68.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_clip, "offset_top", 64.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_clip, "offset_bottom", -80.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_shadow, "modulate:a", 0.5, 0.6)
	await unroll.finished
	if not _visible_modal:
		return

	_rolled.visible = false
	var settle := create_tween()
	settle.tween_property(_anim_root, "rotation", deg_to_rad(0.3), 0.08)
	settle.tween_property(_anim_root, "rotation", 0.0, 0.14)
	await settle.finished

	var text_in := create_tween()
	text_in.tween_property(_text_zoom, "modulate:a", 1.0, 0.28)
	await text_in.finished
	if not _visible_modal:
		return
	await _reveal_text(full_text)
	_update_message_width()
	_animating = false


func _set_rolled_at_start() -> void:
	_rolled.visible = true
	_rolled.modulate.a = 0.0
	_rolled.rotation = deg_to_rad(-5.0)
	_rolled.size = Vector2(minf(640.0, _panel_size.x * 0.85), 140.0)
	_rolled.pivot_offset = _rolled.size * 0.5
	_rolled.position = Vector2((_panel_size.x - _rolled.size.x) * 0.5, (_panel_size.y - _rolled.size.y) * 0.5)
	_unrolled_root.visible = false
	_text_zoom.modulate.a = 0.0
	_shadow.modulate.a = 0.2
	_anim_root.rotation = 0.0


func _set_fully_unrolled() -> void:
	_rolled.visible = false
	_unrolled_root.visible = true
	_unrolled_root.modulate.a = 1.0
	_parchment_clip.offset_top = 64.0
	_parchment_clip.offset_bottom = -80.0
	_top_roller.position = Vector2(0, -2.0)
	_bottom_roller.position = Vector2(0, _panel_size.y - 68.0)
	_top_roller.size = Vector2(_panel_size.x, 70)
	_bottom_roller.size = Vector2(_panel_size.x, 70)
	_shadow.modulate.a = 0.5
	_text_zoom.modulate.a = 1.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_anim_root.position = (vp - _panel_size) * 0.5
	_anim_root.rotation = 0.0
	_anim_root.scale = Vector2.ONE


func _finish_open_immediate(full_text: String) -> void:
	_set_fully_unrolled()
	_dim.color.a = 0.75
	_message.text = full_text
	_animating = false


func _reveal_text(full_text: String) -> void:
	if manager != null and manager.is_reduced_motion():
		_message.text = full_text
		return
	var chunks: PackedStringArray = _chunk_text(full_text)
	_message.text = ""
	for chunk in chunks:
		if _skip or not _visible_modal:
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


func _apply_text_scale(scale: float) -> void:
	scale = clampf(scale, MIN_TEXT_SCALE, MAX_TEXT_SCALE)
	var size_px: int = int(round(float(_base_font_size) * scale))
	_message.add_theme_font_size_override("normal_font_size", size_px)
	_update_message_width()


func _on_zoom_changed(scale: float) -> void:
	if not _zoom_enabled:
		return
	_apply_text_scale(scale)
	if manager:
		manager.set_text_scale(clampf(scale, MIN_TEXT_SCALE, MAX_TEXT_SCALE))


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _animating:
		_skip = true
		request_skip_open()


func request_skip_open() -> void:
	_skip = true
	_dim.color.a = 0.75
	_set_fully_unrolled()


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	_zoom_enabled = false
	var date_copy: String = current_date
	var start_pos: Vector2 = _anim_root.global_position + _anim_root.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	# Uniform mild shrink toward archive — not a flat squash.
	tw.tween_property(_anim_root, "scale", Vector2(0.35, 0.35), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_anim_root, "modulate:a", 0.0, 0.28)
	tw.tween_property(_dim, "color:a", 0.0, 0.28)
	await tw.finished
	visible = false
	_anim_root.scale = Vector2.ONE
	_anim_root.modulate = Color.WHITE
	_anim_root.position = Vector2.ZERO
	archive_flight_requested.emit(date_copy, start_pos)
	closed.emit(date_copy)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _zoom_enabled and _zoom.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and _animating:
		_skip = true
		request_skip_open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()
