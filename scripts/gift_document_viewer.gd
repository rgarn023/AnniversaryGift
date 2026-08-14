extends Control
class_name GiftDocumentViewer
## In-app PDF page preview with compile-time texture packaging + external open/share.

signal closed

const PDF_PAGE_001: Texture2D = preload("res://assets/documents/pdf_pages/page_001.png")
const PDF_PAGE_002: Texture2D = preload("res://assets/documents/pdf_pages/page_002.png")
const PDF_PAGE_TEXTURES: Array[Texture2D] = [PDF_PAGE_001, PDF_PAGE_002]

const PAGE_GAP := 28.0
const HORIZONTAL_PAGE_MARGIN := 8.0
const SAFE_SIDE := 28.0
const SAFE_TOP_EXTRA := 12.0
const SAFE_BOTTOM_EXTRA := 12.0

@export var gift_document_pages: GiftDocumentPages

var _safe_margin: MarginContainer
var _main_vbox: VBoxContainer
var _title_label: Label
var _scroll: ScrollContainer
var _horizontal_center: CenterContainer
var _pages_box: VBoxContainer
var _loading_label: Label
var _error_panel: PanelContainer
var _error_label: Label
var _status_label: Label
var _open_button: Button
var _share_button: Button
var _fit_button: Button
var _close_button: Button

var _page_panels: Array[PanelContainer] = []
var _page_rects: Array[TextureRect] = []
var _page_textures: Array[Texture2D] = []
var _zoom: float = 1.0
var _gesture_zoom: GestureZoomController
var _layout_ready := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_gesture_zoom = GestureZoomController.new()
	_gesture_zoom.min_scale = 0.65
	_gesture_zoom.max_scale = 2.4
	_gesture_zoom.zoom_changed.connect(func(scale: float) -> void:
		_zoom = scale
		_apply_page_fit()
	)
	_build_ui()
	visible = false
	get_viewport().size_changed.connect(_on_viewport_resized)
	call_deferred("_refresh_safe_area")


func open_viewer() -> void:
	visible = true
	move_to_front()
	_zoom = 1.0
	_gesture_zoom.reset(1.0)
	_status_label.text = ""
	_loading_label.visible = true
	_error_panel.visible = false
	_scroll.visible = false
	await get_tree().process_frame
	_refresh_safe_area()
	load_pdf_previews()
	_layout_ready = true
	await get_tree().process_frame
	_apply_page_fit()
	_log_preview_diagnostics()


func close_viewer() -> void:
	visible = false
	_layout_ready = false
	closed.emit()


func load_pdf_previews() -> void:
	_populate_preview_pages()


func get_loaded_page_count() -> int:
	return _page_rects.size()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_safe_margin = MarginContainer.new()
	_safe_margin.name = "SafeAreaMargin"
	_safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin.add_theme_constant_override("margin_left", int(SAFE_SIDE))
	_safe_margin.add_theme_constant_override("margin_right", int(SAFE_SIDE))
	_safe_margin.add_theme_constant_override("margin_top", int(SAFE_SIDE + SAFE_TOP_EXTRA))
	_safe_margin.add_theme_constant_override("margin_bottom", int(SAFE_SIDE + SAFE_BOTTOM_EXTRA))
	add_child(_safe_margin)

	_main_vbox = VBoxContainer.new()
	_main_vbox.name = "MainVBox"
	_main_vbox.add_theme_constant_override("separation", 14)
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_safe_margin.add_child(_main_vbox)

	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_constant_override("separation", 12)
	_main_vbox.add_child(top_bar)

	_title_label = Label.new()
	_title_label.text = "Anniversary Gift"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 40)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	top_bar.add_child(_title_label)

	_fit_button = _make_button("Fit Width", _on_fit_pressed)
	top_bar.add_child(_fit_button)
	var zoom_out := _make_button("−", func() -> void: _gesture_zoom.adjust(1.0 / 1.15))
	top_bar.add_child(zoom_out)
	var zoom_in := _make_button("+", func() -> void: _gesture_zoom.adjust(1.15))
	top_bar.add_child(zoom_in)
	_close_button = _make_button("Close", close_viewer)
	top_bar.add_child(_close_button)

	_loading_label = Label.new()
	_loading_label.name = "LoadingIndicator"
	_loading_label.text = "Preparing page previews…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 28)
	_loading_label.add_theme_color_override("font_color", Color(0.86, 0.8, 0.7))
	_main_vbox.add_child(_loading_label)

	_error_panel = PanelContainer.new()
	_error_panel.name = "PreviewErrorPanel"
	_error_panel.visible = false
	var error_style := StyleBoxFlat.new()
	error_style.bg_color = Color(0.18, 0.1, 0.1, 0.92)
	error_style.set_corner_radius_all(14)
	error_style.content_margin_left = 22
	error_style.content_margin_right = 22
	error_style.content_margin_top = 18
	error_style.content_margin_bottom = 18
	_error_panel.add_theme_stylebox_override("panel", error_style)
	_main_vbox.add_child(_error_panel)

	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_font_size_override("font_size", 26)
	_error_label.add_theme_color_override("font_color", Color(0.98, 0.86, 0.8))
	_error_label.text = (
		"Page previews unavailable.\n\n"
		+ "You can still open or share the original PDF below."
	)
	_error_panel.add_child(_error_label)

	_scroll = ScrollContainer.new()
	_scroll.name = "PageScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.visible = false
	_main_vbox.add_child(_scroll)

	_horizontal_center = CenterContainer.new()
	_horizontal_center.name = "HorizontalCenter"
	_horizontal_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_horizontal_center)

	_pages_box = VBoxContainer.new()
	_pages_box.name = "PagesVBox"
	_pages_box.add_theme_constant_override("separation", int(PAGE_GAP))
	_pages_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_horizontal_center.add_child(_pages_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(0.82, 0.76, 0.66))
	_main_vbox.add_child(_status_label)

	var bottom := HBoxContainer.new()
	bottom.name = "BottomActions"
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	_main_vbox.add_child(bottom)

	_open_button = _make_button("Open Original PDF", _on_open_pressed)
	_open_button.custom_minimum_size = Vector2(280, 72)
	bottom.add_child(_open_button)

	_share_button = _make_button("Share PDF", _on_share_pressed)
	_share_button.custom_minimum_size = Vector2(220, 72)
	bottom.add_child(_share_button)


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96, 64)
	button.add_theme_font_size_override("font_size", 26)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.42, 0.28, 0.16, 0.96)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.52, 0.34, 0.2, 0.98)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(callback)
	return button


func _resolve_page_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for texture: Texture2D in PDF_PAGE_TEXTURES:
		if texture == null:
			push_error("PDF preview texture preload is null.")
			continue
		if texture.get_width() <= 0 or texture.get_height() <= 0:
			push_error(
				"PDF preview texture has invalid size %dx%d."
				% [texture.get_width(), texture.get_height()]
			)
			continue
		textures.append(texture)

	if textures.is_empty() and gift_document_pages != null:
		for texture: Texture2D in gift_document_pages.pages:
			if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
				textures.append(texture)
	return textures


func _clear_preview_pages() -> void:
	for child in _pages_box.get_children():
		child.queue_free()
	_page_panels.clear()
	_page_rects.clear()
	_page_textures.clear()


func _create_preview_page(page_texture: Texture2D, page_index: int) -> void:
	var panel := PanelContainer.new()
	panel.name = "PagePanel_%d" % (page_index + 1)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.96)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.55, 0.42, 0.28, 0.55)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	_pages_box.add_child(panel)

	var page_rect := TextureRect.new()
	page_rect.name = "PageTexture_%d" % (page_index + 1)
	page_rect.texture = page_texture
	page_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	page_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(page_rect)

	_page_panels.append(panel)
	_page_rects.append(page_rect)
	_page_textures.append(page_texture)


func _populate_preview_pages() -> void:
	_clear_preview_pages()
	var textures := _resolve_page_textures()
	for page_index: int in textures.size():
		var page_texture: Texture2D = textures[page_index]
		if page_texture == null:
			push_error("PDF preview texture %d is null." % (page_index + 1))
			continue
		_create_preview_page(page_texture, page_index)

	var loaded_count: int = get_loaded_page_count()
	_loading_label.visible = false
	_error_panel.visible = loaded_count == 0
	_scroll.visible = loaded_count > 0

	if OS.is_debug_build():
		print(
			"[GiftDocumentViewer] populated %d page control(s); error_visible=%s"
			% [loaded_count, str(_error_panel.visible)]
		)


func _refresh_safe_area() -> void:
	if _safe_margin == null or not is_instance_valid(_safe_margin):
		return
	var viewport_size := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var scale_x := viewport_size.x / float(maxi(screen.x, 1))
	var scale_y := viewport_size.y / float(maxi(screen.y, 1))
	var left := maxf(SAFE_SIDE, safe.position.x * scale_x)
	var top := maxf(SAFE_SIDE + SAFE_TOP_EXTRA, safe.position.y * scale_y)
	var right := maxf(
		SAFE_SIDE,
		(screen.x - (safe.position.x + safe.size.x)) * scale_x
	)
	var bottom := maxf(
		SAFE_SIDE + SAFE_BOTTOM_EXTRA,
		(screen.y - (safe.position.y + safe.size.y)) * scale_y
	)
	_safe_margin.add_theme_constant_override("margin_left", int(left))
	_safe_margin.add_theme_constant_override("margin_right", int(right))
	_safe_margin.add_theme_constant_override("margin_top", int(top))
	_safe_margin.add_theme_constant_override("margin_bottom", int(bottom))
	if _layout_ready:
		call_deferred("_apply_page_fit")


func _on_viewport_resized() -> void:
	_refresh_safe_area()


func _available_page_width() -> float:
	var scroll_width := _scroll.size.x
	if scroll_width <= 1.0:
		scroll_width = get_viewport_rect().size.x - (SAFE_SIDE * 2.0)
	return maxf(220.0, scroll_width - HORIZONTAL_PAGE_MARGIN)


func _apply_page_fit() -> void:
	if _page_rects.is_empty():
		return
	var available_width := _available_page_width() * _zoom
	for i in _page_rects.size():
		var page_texture := _page_textures[i]
		var page_rect := _page_rects[i]
		var panel := _page_panels[i]
		if page_texture == null:
			continue
		var tex_w := float(page_texture.get_width())
		var tex_h := float(page_texture.get_height())
		if tex_w <= 0.0 or tex_h <= 0.0:
			continue
		var display_height := available_width * tex_h / tex_w
		page_rect.custom_minimum_size = Vector2(available_width, display_height)
		panel.custom_minimum_size = Vector2(available_width + 12.0, display_height + 12.0)
	_pages_box.custom_minimum_size = Vector2(available_width + 12.0, 0)


func _on_fit_pressed() -> void:
	_gesture_zoom.reset(1.0)
	_zoom = 1.0
	_apply_page_fit()


func _log_preview_diagnostics() -> void:
	if not OS.is_debug_build():
		return
	var dims: Array[String] = []
	for i in PDF_PAGE_TEXTURES.size():
		var texture := PDF_PAGE_TEXTURES[i]
		if texture == null:
			dims.append("page_%d=null" % (i + 1))
		else:
			dims.append(
				"page_%d=%dx%d" % [i + 1, texture.get_width(), texture.get_height()]
			)
	print(
		"[GiftDocumentViewer] textures=%d controls=%d error_visible=%s %s"
		% [
			PDF_PAGE_TEXTURES.size(),
			_page_rects.size(),
			str(_error_panel.visible),
			", ".join(dims),
		]
	)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if _gesture_zoom.handle_input(event):
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and visible:
		_refresh_safe_area()
	elif what == NOTIFICATION_RESIZED and visible:
		_refresh_safe_area()


func _on_open_pressed() -> void:
	_status_label.text = "Opening original PDF…"
	var helper := PdfHelper.new()
	var result: Dictionary = helper.open_original_pdf()
	_status_label.text = str(result.get("message", ""))


func _on_share_pressed() -> void:
	_status_label.text = "Preparing share…"
	var helper := PdfHelper.new()
	var result: Dictionary = helper.share_original_pdf()
	_status_label.text = str(result.get("message", ""))
