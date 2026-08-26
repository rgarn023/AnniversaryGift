extends CanvasLayer
class_name LoveNotesScrollViewer
## Scroll Preview with whole-composite pinch/pan on ZoomPanRoot.
## A− / A+ change font size only inside ContentRect — never scale/pan.
## Attachments are not shown in the active product UI.

signal closed
signal archive_flight_requested(screen_pos: Vector2)
signal attachment_tapped(attachment: Dictionary)

const ART := "res://assets/art/scroll/"
const DEFAULT_BODY_FONT: int = 20
const MIN_BODY_FONT: int = 15
const MAX_BODY_FONT: int = 30
const DEFAULT_HEADING_FONT: int = 26
const MIN_HEADING_FONT: int = 20
const MAX_HEADING_FONT: int = 34
const DEFAULT_META_FONT: int = 15
const MIN_META_FONT: int = 13
const MAX_META_FONT: int = 20
const MIN_COMPOSITE_SCALE: float = 1.0
const MAX_COMPOSITE_SCALE: float = 3.0

var _font_step: int = 0
var _root: Control
var _dim: ColorRect
var _safe: MarginContainer
var _shell: VBoxContainer
var _top_bar: HBoxContainer
var _title_label: Label
var _btn_close: Button
var _stage: Control
## ZoomPanRoot — only node that pinch/pan transforms.
var _zoom_pan_root: Control
## ParchmentComposite under ZoomPanRoot.
var _parchment_root: Control
var _shadow: TextureRect
var _parchment: TextureRect
var _top_roller: TextureRect
var _bottom_roller: TextureRect
var _content_rect: MarginContainer
var _content: VBoxContainer
var _to_label: Label
var _meta_label: Label
var _divider: ColorRect
var _heading: Label
var _message_scroll: ScrollContainer
var _message: RichTextLabel
var _bottom_bar: HBoxContainer
var _btn_minus: Button
var _btn_plus: Button
var _btn_reset: Button
var _visible_modal: bool = false
var _clear_on_close: bool = false
var _reduced_motion: bool = false
var _unit_size: Vector2 = Vector2(360, 560)
var _body_text: String = ""
var _to_text: String = ""
var _meta_text: String = ""
var _composite_scale: float = 1.0
var _composite_offset: Vector2 = Vector2.ZERO
var _pinch_touches: Dictionary = {}
var _pinch_last_dist: float = 0.0
var _pinch_active: bool = false
var _pan_active: bool = false
var _pan_last: Vector2 = Vector2.ZERO


func _ready() -> void:
	## Above Compose chrome / overlays so nothing shows through.
	layer = 100
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

	## Fully opaque backdrop — Compose must never show through Preview.
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.03, 0.09, 1.0)
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
	_top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.clip_contents = true
	_shell.add_child(_top_bar)
	_title_label = Label.new()
	_title_label.text = "LOVE NOTE"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.size_flags_stretch_ratio = 1.0
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.98))
	_top_bar.add_child(_title_label)
	_btn_close = Button.new()
	_btn_close.text = "Close"
	_btn_close.focus_mode = Control.FOCUS_NONE
	_btn_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_close.custom_minimum_size = Vector2(88, 48)
	_style_chrome_button(_btn_close)
	_btn_close.pressed.connect(close_viewer)
	_top_bar.add_child(_btn_close)

	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	_shell.add_child(_stage)
	## Android multitouch often skips Control.gui_input — also handle via _input.
	set_process_input(true)

	## ZoomPanRoot — pinch/pan applies ONLY here.
	_zoom_pan_root = Control.new()
	_zoom_pan_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_zoom_pan_root)

	## ParchmentComposite
	_parchment_root = Control.new()
	_parchment_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_pan_root.add_child(_parchment_root)

	_shadow = _make_tex(ART + "scroll_shadow.png")
	_shadow.modulate = Color(1, 1, 1, 0.35)
	_parchment_root.add_child(_shadow)

	_parchment = _make_tex(ART + "scroll_parchment_center.png")
	_parchment_root.add_child(_parchment)

	_top_roller = _make_tex(ART + "scroll_top_roller.png")
	_top_roller.z_index = 2
	_parchment_root.add_child(_top_roller)

	_bottom_roller = _make_tex(ART + "scroll_bottom_roller.png")
	_bottom_roller.z_index = 2
	_parchment_root.add_child(_bottom_roller)

	_content_rect = MarginContainer.new()
	_content_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_content_rect.clip_contents = true
	_parchment_root.add_child(_content_rect)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_content_rect.add_child(_content)

	_to_label = Label.new()
	_to_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_to_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_to_label.add_theme_color_override("font_color", Color(0.38, 0.2, 0.14))
	_content.add_child(_to_label)

	_meta_label = Label.new()
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_label.add_theme_color_override("font_color", Color(0.36, 0.18, 0.12))
	_meta_label.add_theme_constant_override("line_spacing", 6)
	_content.add_child(_meta_label)

	_divider = ColorRect.new()
	_divider.custom_minimum_size = Vector2(0, 1)
	_divider.color = Color(0.45, 0.28, 0.18, 0.35)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_divider)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_color_override("font_color", Color(0.28, 0.13, 0.09))
	_content.add_child(_heading)

	_message_scroll = ScrollContainer.new()
	_message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
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
	_message.scale = Vector2.ONE
	_message_scroll.add_child(_message)

	_bottom_bar = HBoxContainer.new()
	_bottom_bar.custom_minimum_size = Vector2(0, 56)
	_bottom_bar.add_theme_constant_override("separation", 10)
	_shell.add_child(_bottom_bar)
	_btn_minus = _make_tool_button("A−")
	_btn_plus = _make_tool_button("A+")
	_btn_reset = _make_tool_button("Reset")
	for b in [_btn_minus, _btn_plus, _btn_reset]:
		_bottom_bar.add_child(b)
	_btn_minus.pressed.connect(func() -> void:
		_font_step = maxi(_font_step - 1, -3)
		_apply_font_sizes()
	)
	_btn_plus.pressed.connect(func() -> void:
		_font_step = mini(_font_step + 1, 4)
		_apply_font_sizes()
	)
	_btn_reset.pressed.connect(_reset_preview_state)
	_apply_fonts()
	_apply_font_sizes()


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
		_to_label.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
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
	var left := maxi(16, int(safe.position.x * scale_x))
	var top := maxi(16, int(safe.position.y * scale_y))
	var right := maxi(16, int((screen.x - (safe.position.x + safe.size.x)) * scale_x))
	var bottom := maxi(16, int((screen.y - (safe.position.y + safe.size.y)) * scale_y))
	_safe.add_theme_constant_override("margin_left", left)
	_safe.add_theme_constant_override("margin_right", right)
	_safe.add_theme_constant_override("margin_top", top)
	_safe.add_theme_constant_override("margin_bottom", bottom)
	## Keep chrome within viewport — never let Close clip off-screen.
	if _top_bar:
		_top_bar.custom_minimum_size = Vector2(0, 52)


func _fit_parchment() -> void:
	_compute_safe_insets()
	await get_tree().process_frame
	var stage_size := _stage.size
	if stage_size.x < 8.0 or stage_size.y < 8.0:
		stage_size = get_viewport().get_visible_rect().size - Vector2(24, 140)
	var max_w := stage_size.x - 20.0
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
	_parchment_root.size = _unit_size
	_parchment_root.position = Vector2.ZERO
	_parchment_root.scale = Vector2.ONE
	_layout_content_rect()
	_sync_text_widths()
	_apply_composite_transform()


func _layout_content_rect() -> void:
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
	var pad_x := int(clampf(w * 0.12, 32.0, 52.0))
	var pad_top := int(clampf(roller_h * 0.95, 30.0, 48.0))
	var pad_bottom := int(clampf(roller_h * 0.9, 28.0, 46.0))
	_content_rect.position = _parchment.position
	_content_rect.size = _parchment.size
	_content_rect.add_theme_constant_override("margin_left", pad_x)
	_content_rect.add_theme_constant_override("margin_right", pad_x)
	_content_rect.add_theme_constant_override("margin_top", pad_top)
	_content_rect.add_theme_constant_override("margin_bottom", pad_bottom)
	for n in [_content_rect, _content, _to_label, _meta_label, _heading, _message, _message_scroll, _parchment_root]:
		if n:
			n.scale = Vector2.ONE
			n.pivot_offset = Vector2.ZERO


func _sync_text_widths() -> void:
	var inner_w := maxf(_content_rect.size.x - float(
		_content_rect.get_theme_constant("margin_left") + _content_rect.get_theme_constant("margin_right")
	), 120.0)
	_message.custom_minimum_size = Vector2(inner_w, 0)
	_heading.custom_minimum_size = Vector2(0, 0)
	_meta_label.custom_minimum_size = Vector2(0, 0)
	_to_label.custom_minimum_size = Vector2(0, 0)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_to_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _apply_composite_transform() -> void:
	if _zoom_pan_root == null or _stage == null:
		return
	_composite_scale = clampf(_composite_scale, MIN_COMPOSITE_SCALE, MAX_COMPOSITE_SCALE)
	var stage_size := _stage.size
	if stage_size.x < 8.0:
		stage_size = Vector2(360, 560)
	var scaled := _unit_size * _composite_scale
	## Center + offset; clamp so a meaningful portion stays on screen.
	var base := (stage_size - scaled) * 0.5
	var min_x := stage_size.x * 0.15 - scaled.x
	var max_x := stage_size.x * 0.85
	var min_y := stage_size.y * 0.12 - scaled.y
	var max_y := stage_size.y * 0.88
	_composite_offset.x = clampf(_composite_offset.x, min_x - base.x, max_x - base.x)
	_composite_offset.y = clampf(_composite_offset.y, min_y - base.y, max_y - base.y)
	if is_equal_approx(_composite_scale, MIN_COMPOSITE_SCALE):
		_composite_offset = Vector2.ZERO
	_zoom_pan_root.pivot_offset = Vector2.ZERO
	_zoom_pan_root.scale = Vector2(_composite_scale, _composite_scale)
	_zoom_pan_root.size = _unit_size
	_zoom_pan_root.position = base + _composite_offset
	## At fit zoom, allow MessageScroll to own vertical drag.
	if _message_scroll:
		_message_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if is_equal_approx(_composite_scale, MIN_COMPOSITE_SCALE) else Control.MOUSE_FILTER_IGNORE


func _on_stage_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_pinch_touches[st.index] = st.position
		else:
			_pinch_touches.erase(st.index)
			if _pinch_touches.size() < 2:
				_pinch_active = false
				_pinch_last_dist = 0.0
			if _pinch_touches.is_empty():
				_pan_active = false
		if _pinch_touches.size() == 1 and _composite_scale > MIN_COMPOSITE_SCALE + 0.01:
			_pan_active = st.pressed
			_pan_last = st.position
		_stage.accept_event()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_pinch_touches[sd.index] = sd.position
		if _pinch_touches.size() >= 2:
			_handle_preview_pinch()
			_stage.accept_event()
		elif _composite_scale > MIN_COMPOSITE_SCALE + 0.01:
			_composite_offset += sd.relative
			_apply_composite_transform()
			_stage.accept_event()
	elif ev is InputEventMagnifyGesture:
		var mag := ev as InputEventMagnifyGesture
		_set_composite_scale(_composite_scale * clampf(mag.factor, 0.85, 1.15), mag.position)
		_stage.accept_event()
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and (mb.ctrl_pressed or mb.meta_pressed):
			_set_composite_scale(_composite_scale * 1.08, mb.position)
			_stage.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and (mb.ctrl_pressed or mb.meta_pressed):
			_set_composite_scale(_composite_scale * 0.92, mb.position)
			_stage.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_pan_active = mb.pressed and _composite_scale > MIN_COMPOSITE_SCALE + 0.01
			_pan_last = mb.position
	elif ev is InputEventMouseMotion and _pan_active:
		var mm := ev as InputEventMouseMotion
		_composite_offset += mm.position - _pan_last
		_pan_last = mm.position
		_apply_composite_transform()
		_stage.accept_event()


func _handle_preview_pinch() -> void:
	var keys: Array = _pinch_touches.keys()
	keys.sort()
	if keys.size() < 2:
		return
	var a: Vector2 = _pinch_touches[keys[0]]
	var b: Vector2 = _pinch_touches[keys[1]]
	var dist := a.distance_to(b)
	if dist < 12.0:
		return
	var mid := (a + b) * 0.5
	if not _pinch_active:
		_pinch_active = true
		_pinch_last_dist = dist
		_pan_active = false
		return
	var ratio := dist / maxf(_pinch_last_dist, 1.0)
	ratio = clampf(ratio, 0.90, 1.10)
	_set_composite_scale(_composite_scale * ratio, mid)
	_pinch_last_dist = dist


func _set_composite_scale(s: float, focal: Vector2 = Vector2.INF) -> void:
	var prev := _composite_scale
	var next := clampf(s, MIN_COMPOSITE_SCALE, MAX_COMPOSITE_SCALE)
	if is_equal_approx(prev, next):
		return
	## Keep focal point stable-ish while scaling.
	if is_finite(focal.x) and _stage:
		var stage_size := _stage.size
		var base_prev := (stage_size - _unit_size * prev) * 0.5 + _composite_offset
		var local := (focal - base_prev) / maxf(prev, 0.001)
		var base_next_centered := (stage_size - _unit_size * next) * 0.5
		_composite_offset = focal - local * next - base_next_centered
	_composite_scale = next
	_apply_composite_transform()


func _on_viewport_resized() -> void:
	if visible:
		_fit_parchment()


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
	_visible_modal = true
	visible = true
	_title_label.text = chrome_title
	_heading.text = title if not title.is_empty() else "A Love Note"
	_parse_meta(meta)
	_body_text = body
	_set_message_text(body)
	_reset_preview_state()
	_dim.color = Color(0.05, 0.03, 0.09, 1.0)
	_zoom_pan_root.modulate.a = 0.0
	await _fit_parchment()
	if _reduced_motion:
		_zoom_pan_root.modulate.a = 1.0
		return
	var tw := create_tween()
	tw.tween_property(_zoom_pan_root, "modulate:a", 1.0, 0.22)
	await tw.finished


func _parse_meta(meta: String) -> void:
	var lines := meta.strip_edges().split("\n")
	var to_line := ""
	var rest: PackedStringArray = PackedStringArray()
	for i in range(lines.size()):
		var line := str(lines[i]).strip_edges()
		if line.is_empty():
			continue
		if to_line.is_empty() and (line.begins_with("To ") or line.begins_with("For ")):
			to_line = line
		else:
			rest.append(line)
	_to_text = to_line
	_meta_text = "\n".join(rest)
	_to_label.text = _to_text
	_to_label.visible = not _to_text.is_empty()
	_meta_label.text = _meta_text
	_meta_label.visible = not _meta_text.is_empty()
	_divider.visible = _to_label.visible or _meta_label.visible


func set_attachments(_attachments: Array) -> void:
	pass


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _set_message_text(plain: String) -> void:
	if plain.is_empty():
		_message.text = ""
		return
	_message.text = "[center]%s[/center]" % _escape_bbcode(plain)
	## Short notes: add gentle top spacer so content isn't glued under the roller
	## with a huge empty parchment below — long notes keep normal scroll.
	call_deferred("_balance_short_note_layout")


func _balance_short_note_layout() -> void:
	if _content == null or _message_scroll == null:
		return
	var plain := _body_text.strip_edges()
	var short := plain.length() > 0 and plain.length() < 220 and plain.count("\n") < 6
	## Remove prior spacer if any.
	if _content.get_child_count() > 0:
		var first = _content.get_child(0)
		if first is Control and str(first.name) == "ShortNoteSpacer":
			first.queue_free()
	if not short:
		return
	var spacer := Control.new()
	spacer.name = "ShortNoteSpacer"
	spacer.custom_minimum_size = Vector2(0, 36)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(spacer)
	_content.move_child(spacer, 0)


func _apply_font_sizes() -> void:
	var body := clampi(DEFAULT_BODY_FONT + _font_step * 2, MIN_BODY_FONT, MAX_BODY_FONT)
	var heading := clampi(DEFAULT_HEADING_FONT + _font_step * 2, MIN_HEADING_FONT, MAX_HEADING_FONT)
	var meta := clampi(DEFAULT_META_FONT + _font_step, MIN_META_FONT, MAX_META_FONT)
	_message.add_theme_font_size_override("normal_font_size", body)
	_heading.add_theme_font_size_override("font_size", heading)
	_meta_label.add_theme_font_size_override("font_size", meta)
	_to_label.add_theme_font_size_override("font_size", meta + 2)
	## Font changes must NOT touch ZoomPanRoot scale/position.
	for n in [_content_rect, _content, _to_label, _meta_label, _heading, _message, _message_scroll, _parchment_root]:
		if n:
			n.scale = Vector2.ONE
	call_deferred("_sync_text_widths")


func apply_message_zoom() -> void:
	_apply_font_sizes()


func _on_view_zoom_changed(scale: float) -> void:
	## Compatibility hook for tests / older call sites.
	_set_composite_scale(scale)


func _reset_preview_state() -> void:
	_font_step = 0
	_composite_scale = MIN_COMPOSITE_SCALE
	_composite_offset = Vector2.ZERO
	_pinch_touches.clear()
	_pinch_active = false
	_pan_active = false
	_pinch_last_dist = 0.0
	_apply_font_sizes()
	if _message_scroll:
		_message_scroll.scroll_vertical = 0
	_apply_composite_transform()


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	var start_pos: Vector2 = _zoom_pan_root.global_position + _unit_size * _composite_scale * 0.5
	if _reduced_motion:
		_zoom_pan_root.modulate.a = 1.0
	else:
		var tw := create_tween()
		tw.tween_property(_zoom_pan_root, "modulate:a", 0.0, 0.18)
		await tw.finished
	if _clear_on_close:
		_set_message_text("")
	visible = false
	_zoom_pan_root.modulate = Color.WHITE
	_reset_preview_state()
	archive_flight_requested.emit(start_pos)
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()
		return
	## Multitouch pinch/pan for Preview on Android (gui_input alone is unreliable).
	if _stage == null:
		return
	var area := _stage.get_global_rect()
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if area.has_point(st.position) or _pinch_touches.has(st.index):
				_pinch_touches[st.index] = st.position
				get_viewport().set_input_as_handled()
		else:
			if _pinch_touches.has(st.index):
				_pinch_touches.erase(st.index)
				if _pinch_touches.size() < 2:
					_pinch_active = false
					_pinch_last_dist = 0.0
				get_viewport().set_input_as_handled()
		if _pinch_touches.size() == 1 and _composite_scale > MIN_COMPOSITE_SCALE + 0.01:
			_pan_active = st.pressed
			_pan_last = st.position
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _pinch_touches.is_empty() and not area.has_point(sd.position):
			return
		_pinch_touches[sd.index] = sd.position
		if _pinch_touches.size() >= 2:
			_handle_preview_pinch()
			get_viewport().set_input_as_handled()
		elif _composite_scale > MIN_COMPOSITE_SCALE + 0.01:
			_composite_offset += sd.relative
			_apply_composite_transform()
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		if area.has_point(mag.position) or not _pinch_touches.is_empty():
			_set_composite_scale(_composite_scale * clampf(mag.factor, 0.85, 1.15), mag.position)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()
