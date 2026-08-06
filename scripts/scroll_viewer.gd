extends CanvasLayer
class_name ScrollViewer

## Responsive parchment message viewer.
## Zoom changes font size only — never Control.scale on the text branch.

signal closed(date_iso: String)
signal archive_flight_requested(date_iso: String, screen_pos: Vector2)

const ART := "res://assets/art/scroll/"

const BASE_BODY_FONT_SIZE: int = 34
const MIN_BODY_FONT_SIZE: int = 26
const MAX_BODY_FONT_SIZE: int = 64
const BASE_HEADING_FONT_SIZE: int = 40
const BASE_DATE_FONT_SIZE: int = 24

const MIN_MESSAGE_ZOOM: float = 0.8
const MAX_MESSAGE_ZOOM: float = 1.9
const MAX_PARCHMENT_WIDTH: float = 900.0
const SIDE_GAP: float = 32.0
const MIN_SIDE_GAP: float = 24.0

var manager: AnniversaryManager
var current_date: String = ""
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
var _date_label: Label
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
var _emerge_from: Vector2 = Vector2.ZERO
var _use_emerge_from: bool = false
var _content_pad_left: float = 48.0
var _content_pad_right: float = 48.0
var _safe_left: float = 24.0
var _safe_right: float = 24.0
var _safe_top: float = 24.0
var _safe_bottom: float = 24.0
var _pending_message_text: String = ""
## Headless tests may override the logical viewport size.
var _test_override_viewport: Vector2 = Vector2.ZERO


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
	_root.name = "ScrollViewerRoot"
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
	_full_screen_margin.name = "FullScreenMargin"
	_full_screen_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_screen_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_full_screen_margin)

	_center = CenterContainer.new()
	_center.name = "CenterContainer"
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_screen_margin.add_child(_center)

	_parchment_aspect = Control.new()
	_parchment_aspect.name = "ParchmentAspectContainer"
	_parchment_aspect.custom_minimum_size = _parchment_size
	_parchment_aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_parchment_aspect)

	# Free-position host for emerge / archive motion around the centered rest pose.
	_anim_root = Control.new()
	_anim_root.name = "ScrollAnimationRoot"
	_anim_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_anim_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_parchment_aspect.add_child(_anim_root)

	_viewer_layout = Control.new()
	_viewer_layout.name = "ParchmentPanel"
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

	_parchment_panel = Control.new()
	_parchment_panel.name = "ParchmentClip"
	_parchment_panel.clip_contents = true
	_parchment_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_parchment_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_panel.offset_left = 20.0
	_parchment_panel.offset_right = -20.0
	_parchment_panel.offset_top = 58.0
	_parchment_panel.offset_bottom = -72.0
	_unrolled_root.add_child(_parchment_panel)

	_parchment = _make_tex(ART + "scroll_parchment_center.png")
	_parchment.name = "ParchmentCenter"
	_parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment.offset_left = -12.0
	_parchment.offset_right = 12.0
	_parchment_panel.add_child(_parchment)

	_left_edge = _make_tex(ART + "scroll_left_edge.png")
	_left_edge.name = "LeftEdge"
	_left_edge.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_left_edge.offset_right = 40
	_left_edge.modulate.a = 0.7
	_parchment_panel.add_child(_left_edge)

	_right_edge = _make_tex(ART + "scroll_right_edge.png")
	_right_edge.name = "RightEdge"
	_right_edge.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_right_edge.offset_left = -48
	_right_edge.modulate.a = 0.7
	_parchment_panel.add_child(_right_edge)

	_highlight = _make_tex(ART + "scroll_highlight.png")
	_highlight.name = "ScrollHighlight"
	_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight.modulate = Color(1, 1, 1, 0.16)
	_parchment_panel.add_child(_highlight)

	_content_margin = MarginContainer.new()
	_content_margin.name = "ParchmentContentMargin"
	_content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_margin.add_theme_constant_override("margin_left", 48)
	_content_margin.add_theme_constant_override("margin_right", 48)
	_content_margin.add_theme_constant_override("margin_top", 48)
	_content_margin.add_theme_constant_override("margin_bottom", 40)
	_content_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_content_margin.modulate.a = 0.0
	_parchment_panel.add_child(_content_margin)

	_content = VBoxContainer.new()
	_content.name = "MessageVBox"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_content_margin.add_child(_content)

	_date_label = Label.new()
	_date_label.name = "DateHeading"
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.add_theme_color_override("font_color", Color(0.42, 0.22, 0.16))
	_date_label.add_theme_font_size_override("font_size", BASE_DATE_FONT_SIZE)
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_date_label)

	_heading = Label.new()
	_heading.name = "MessageHeading"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.28, 0.13, 0.09))
	_heading.add_theme_font_size_override("font_size", BASE_HEADING_FONT_SIZE)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.clip_text = false
	_content.add_child(_heading)

	_scroll = ScrollContainer.new()
	_scroll.name = "MessageScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	_content.add_child(_scroll)

	_message = RichTextLabel.new()
	_message.name = "MessageText"
	_message.bbcode_enabled = true
	_message.fit_content = true
	_message.scroll_active = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.selection_enabled = false
	_message.clip_contents = false
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_message.add_theme_color_override("default_color", Color(0.18, 0.1, 0.08))
	_message.add_theme_font_size_override("normal_font_size", BASE_BODY_FONT_SIZE)
	_scroll.add_child(_message)

	_hint = Label.new()
	_hint.name = "ZoomInstructions"
	_hint.text = "Pinch or use A− / A+ to resize text"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.38, 0.24, 0.16, 0.85))
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_hint)

	var toolbar := HBoxContainer.new()
	toolbar.name = "ButtonRow"
	toolbar.add_theme_constant_override("separation", 10)
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(toolbar)
	_btn_minus = _make_tool_button("A−", "Decrease text size")
	_btn_plus = _make_tool_button("A+", "Increase text size")
	_btn_reset = _make_tool_button("Reset", "Reset text size")
	_btn_close = _make_tool_button("Close", "Close message")
	for b in [_btn_minus, _btn_plus, _btn_reset, _btn_close]:
		toolbar.add_child(b)

	_top_roller = _make_tex(ART + "scroll_top_roller.png")
	_top_roller.name = "TopRoller"
	_top_roller.size = Vector2(900, 70)
	_top_roller.z_index = 2
	_unrolled_root.add_child(_top_roller)

	_bottom_roller = _make_tex(ART + "scroll_bottom_roller.png")
	_bottom_roller.name = "BottomRoller"
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
	_content_margin.resized.connect(_queue_layout_refresh)
	_scroll.resized.connect(_queue_layout_refresh)


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


func _logical_viewport_size() -> Vector2:
	if _test_override_viewport.x > 1.0 and _test_override_viewport.y > 1.0:
		return _test_override_viewport
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return Vector2(1080, 2400)
	return viewport_size


func _compute_safe_insets() -> void:
	var viewport_size := _logical_viewport_size()
	if _test_override_viewport.x > 1.0:
		# Deterministic insets for layout tests / narrow simulated phones.
		_safe_left = MIN_SIDE_GAP
		_safe_right = MIN_SIDE_GAP
		_safe_top = MIN_SIDE_GAP
		_safe_bottom = MIN_SIDE_GAP
	else:
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		var scale_x := viewport_size.x / float(maxi(screen.x, 1))
		var scale_y := viewport_size.y / float(maxi(screen.y, 1))
		_safe_left = maxf(MIN_SIDE_GAP, safe.position.x * scale_x)
		_safe_top = maxf(MIN_SIDE_GAP, safe.position.y * scale_y)
		_safe_right = maxf(
			MIN_SIDE_GAP,
			(screen.x - (safe.position.x + safe.size.x)) * scale_x
		)
		_safe_bottom = maxf(
			MIN_SIDE_GAP,
			(screen.y - (safe.position.y + safe.size.y)) * scale_y
		)
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

	# Keep a tall portrait parchment that still fits the safe area.
	var parchment_height := minf(safe_height - 16.0, parchment_width * 1.62)
	parchment_height = maxf(parchment_height, 520.0)
	if parchment_height > safe_height - 16.0:
		parchment_height = maxf(safe_height - 16.0, 480.0)
		parchment_width = minf(parchment_width, parchment_height / 1.45)

	_parchment_size = Vector2(parchment_width, parchment_height)
	_parchment_aspect.custom_minimum_size = _parchment_size
	_parchment_aspect.size = _parchment_size

	# Proportional internal padding; never below ~24px.
	var pad_scale := clampf(parchment_width / 900.0, 0.55, 1.0)
	_content_pad_left = maxf(24.0, 48.0 * pad_scale)
	_content_pad_right = maxf(24.0, 48.0 * pad_scale)
	var pad_top := maxf(24.0, 48.0 * pad_scale)
	var pad_bottom := maxf(24.0, 40.0 * pad_scale)
	_content_margin.add_theme_constant_override("margin_left", int(_content_pad_left))
	_content_margin.add_theme_constant_override("margin_right", int(_content_pad_right))
	_content_margin.add_theme_constant_override("margin_top", int(pad_top))
	_content_margin.add_theme_constant_override("margin_bottom", int(pad_bottom))

	_top_roller.size = Vector2(_parchment_size.x, 64.0)
	_bottom_roller.size = Vector2(_parchment_size.x, 64.0)
	_anim_root.position = Vector2.ZERO
	_anim_root.scale = Vector2.ONE
	_queue_layout_refresh()


func _usable_message_width() -> float:
	# Authoritative width from parchment size — never grow from unconstrained
	# child sizes, or custom_minimum_size will force right-side overflow.
	var panel_side_inset := 40.0 # parchment_panel offset_left + |offset_right|
	var usable := (
		_parchment_size.x
		- panel_side_inset
		- _content_pad_left
		- _content_pad_right
	)
	return maxf(usable, 160.0)


func _queue_layout_refresh() -> void:
	call_deferred("_refresh_message_layout")


func _refresh_message_layout() -> void:
	if not is_instance_valid(_message):
		return
	var w := _usable_message_width()
	_message.custom_minimum_size = Vector2(w, 0)
	_heading.custom_minimum_size = Vector2(w, 0)
	_date_label.custom_minimum_size = Vector2(w, 0)
	_hint.custom_minimum_size = Vector2(w, 0)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Keep the parchment shell from being stretched by text minimum sizes.
	_parchment_aspect.custom_minimum_size = _parchment_size
	_parchment_aspect.size = _parchment_size
	_content_margin.queue_sort()
	_content.queue_sort()
	_scroll.queue_sort()
	if OS.is_debug_build():
		call_deferred("_validate_message_layout")


func _validate_message_layout() -> void:
	var viewport_width := _logical_viewport_size().x
	var safe_width := viewport_width - _safe_left - _safe_right
	var body_size := int(_message.get_theme_font_size("normal_font_size"))
	var usable := _usable_message_width()
	print(
		"[ScrollViewer] vp=%.0f safe=%.0f parchment=%.0f pads=%.0f/%.0f usable=%.1f msg_w=%.1f msg_min=%.1f scroll_w=%.1f font=%d"
		% [
			viewport_width,
			safe_width,
			_parchment_size.x,
			_content_pad_left,
			_content_pad_right,
			usable,
			_message.size.x,
			_message.custom_minimum_size.x,
			_scroll.size.x,
			body_size,
		]
	)
	if _message.custom_minimum_size.x > usable + 1.0:
		push_error(
			"MessageText minimum width %.1f exceeds usable parchment width %.1f."
			% [_message.custom_minimum_size.x, usable]
		)
	if _parchment_size.x > safe_width - MIN_SIDE_GAP + 1.0:
		push_error(
			"Parchment width %.1f exceeds safe area width %.1f."
			% [_parchment_size.x, safe_width]
		)
	var expected_margin_w := _parchment_size.x - 40.0
	if (
		_message.size.x > 1.0
		and _content_margin.size.x > 1.0
		and absf(_content_margin.size.x - expected_margin_w) <= 8.0
	):
		if _message.global_position.x + 0.5 < _content_margin.global_position.x:
			push_error("MessageText starts left of parchment content margin.")
		var msg_right := _message.global_position.x + _message.size.x
		var margin_right := (
			_content_margin.global_position.x + _content_margin.size.x
		)
		if msg_right > margin_right + 1.0:
			push_error(
				"MessageText exceeds parchment content width (%.1f > %.1f)."
				% [msg_right, margin_right]
			)


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
	_set_message_text("")
	var stored: float = clampf(manager.get_text_scale(), MIN_MESSAGE_ZOOM, MAX_MESSAGE_ZOOM)
	message_zoom = stored
	_zoom.reset(stored)
	apply_message_zoom()
	await _play_open_animation(str(msg.get("message", "")))
	_zoom_enabled = true
	_use_emerge_from = false
	await get_tree().process_frame
	_refresh_message_layout()


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _set_message_text(plain: String) -> void:
	_pending_message_text = plain
	if plain.is_empty():
		_message.text = ""
		return
	# Center paragraphs via BBCode; escape brackets so punctuation stays literal.
	_message.text = "[center]%s[/center]" % _escape_bbcode(plain)


func apply_message_zoom() -> void:
	message_zoom = clampf(message_zoom, MIN_MESSAGE_ZOOM, MAX_MESSAGE_ZOOM)
	var body_size: int = roundi(BASE_BODY_FONT_SIZE * message_zoom)
	var heading_size: int = roundi(BASE_HEADING_FONT_SIZE * message_zoom)
	var date_size: int = roundi(BASE_DATE_FONT_SIZE * message_zoom)
	body_size = clampi(body_size, MIN_BODY_FONT_SIZE, MAX_BODY_FONT_SIZE)
	heading_size = clampi(heading_size, 28, 72)
	date_size = clampi(date_size, 18, 40)

	var previous_ratio := 0.0
	if _scroll.get_v_scroll_bar() != null:
		var bar := _scroll.get_v_scroll_bar()
		if bar.max_value > bar.page:
			previous_ratio = bar.value / maxf(bar.max_value - bar.page, 1.0)

	_message.add_theme_font_size_override("normal_font_size", body_size)
	_heading.add_theme_font_size_override("font_size", heading_size)
	_date_label.add_theme_font_size_override("font_size", date_size)
	# Never zoom via Control.scale on text/containers.
	_message.scale = Vector2.ONE
	_scroll.scale = Vector2.ONE
	_content_margin.scale = Vector2.ONE
	_viewer_layout.scale = Vector2.ONE
	_queue_layout_refresh()

	if previous_ratio > 0.0:
		call_deferred("_restore_scroll_ratio", previous_ratio)


func _restore_scroll_ratio(ratio: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.value = clampf(ratio, 0.0, 1.0) * maxf(bar.max_value - bar.page, 0.0)


func _play_open_animation(full_text: String) -> void:
	_animating = true
	var reduced: bool = manager != null and manager.is_reduced_motion()
	if reduced or _short_open:
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
	_anim_root.rotation = 0.0
	_set_rolled_at_start()

	var rest_pos := Vector2.ZERO
	var start_pos := Vector2(0, _parchment_size.y * 0.18)
	if _use_emerge_from:
		var local_from := _parchment_aspect.get_global_transform().affine_inverse() * _emerge_from
		start_pos = local_from - _parchment_size * 0.5
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

	var face := create_tween()
	face.tween_property(_rolled, "rotation", 0.0, 0.18)
	await face.finished
	if _skip:
		_finish_open_immediate(full_text)
		return

	_unrolled_root.visible = true
	_unrolled_root.modulate.a = 1.0
	_content_margin.modulate.a = 0.0
	var mid_y: float = _parchment_size.y * 0.5
	_top_roller.position = Vector2(0, mid_y - 32.0)
	_bottom_roller.position = Vector2(0, mid_y - 32.0)
	_parchment_panel.offset_left = 20.0
	_parchment_panel.offset_right = -20.0
	_parchment_panel.offset_top = mid_y - 16.0
	_parchment_panel.offset_bottom = -(_parchment_size.y - mid_y - 16.0)
	_shadow.modulate.a = 0.25

	var unroll := create_tween()
	unroll.set_parallel(true)
	unroll.tween_property(_rolled, "modulate:a", 0.0, 0.18)
	unroll.tween_property(_top_roller, "position:y", -2.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_bottom_roller, "position:y", _parchment_size.y - 62.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_panel, "offset_top", 58.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_parchment_panel, "offset_bottom", -72.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	text_in.tween_property(_content_margin, "modulate:a", 1.0, 0.28)
	await text_in.finished
	if not _visible_modal:
		return
	await _reveal_text(full_text)
	_refresh_message_layout()
	_animating = false


func _set_rolled_at_start() -> void:
	_rolled.visible = true
	_rolled.modulate.a = 0.0
	_rolled.rotation = deg_to_rad(-5.0)
	_rolled.size = Vector2(minf(640.0, _parchment_size.x * 0.85), 140.0)
	_rolled.pivot_offset = _rolled.size * 0.5
	_rolled.position = Vector2(
		(_parchment_size.x - _rolled.size.x) * 0.5,
		(_parchment_size.y - _rolled.size.y) * 0.5
	)
	_unrolled_root.visible = false
	_content_margin.modulate.a = 0.0
	_shadow.modulate.a = 0.2
	_anim_root.rotation = 0.0


func _set_fully_unrolled() -> void:
	_rolled.visible = false
	_unrolled_root.visible = true
	_unrolled_root.modulate.a = 1.0
	_parchment_panel.offset_left = 20.0
	_parchment_panel.offset_right = -20.0
	_parchment_panel.offset_top = 58.0
	_parchment_panel.offset_bottom = -72.0
	_top_roller.position = Vector2(0, -2.0)
	_bottom_roller.position = Vector2(0, _parchment_size.y - 62.0)
	_top_roller.size = Vector2(_parchment_size.x, 64)
	_bottom_roller.size = Vector2(_parchment_size.x, 64)
	_shadow.modulate.a = 0.5
	_content_margin.modulate.a = 1.0
	_anim_root.position = Vector2.ZERO
	_anim_root.rotation = 0.0
	_anim_root.scale = Vector2.ONE
	_refresh_message_layout()


func _finish_open_immediate(full_text: String) -> void:
	_set_fully_unrolled()
	_dim.color.a = 0.75
	_set_message_text(full_text)
	_animating = false


func _reveal_text(full_text: String) -> void:
	if manager != null and manager.is_reduced_motion():
		_set_message_text(full_text)
		return
	var chunks: PackedStringArray = _chunk_text(full_text)
	_set_message_text("")
	var built := ""
	for chunk in chunks:
		if _skip or not _visible_modal:
			_set_message_text(full_text)
			return
		built += chunk
		_set_message_text(built)
		await get_tree().create_timer(0.03).timeout
	_set_message_text(full_text)


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
	if not _zoom_enabled:
		return
	message_zoom = clampf(scale, MIN_MESSAGE_ZOOM, MAX_MESSAGE_ZOOM)
	apply_message_zoom()
	if manager:
		manager.set_text_scale(message_zoom)


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
	var start_pos: Vector2 = _anim_root.global_position + _parchment_size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	# Close motion only — not text zoom.
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
