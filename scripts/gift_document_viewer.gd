extends CanvasLayer
class_name GiftDocumentViewer

## In-app viewer for high-resolution PDF page PNG previews.
## Loads pages via explicit ResourceLoader paths (never DirAccess scans).

signal closed

const MIN_ZOOM := 0.5
const MAX_ZOOM := 4.0
const PAGE_GAP := 24.0

var pdf_helper: PdfHelper
var _zoom: GestureZoomController
var _root: Control
var _top_bar: HBoxContainer
var _scroll: ScrollContainer
var _zoom_root: Control
var _pages_box: VBoxContainer
var _loading: Label
var _error_panel: Label
var _status: Label
var _visible_modal: bool = false
var _page_rects: Array[TextureRect] = []
var _page_shadows: Array[Panel] = []
var _fit_width_scale: float = 1.0
var _user_zoom: float = 1.0
var _mode_fit_width: bool = true


func _ready() -> void:
	layer = 50
	pdf_helper = PdfHelper.new()
	_zoom = GestureZoomController.new()
	_zoom.min_scale = MIN_ZOOM
	_zoom.max_scale = MAX_ZOOM
	_zoom.current_scale = 1.0
	_zoom.zoom_changed.connect(_on_zoom_changed)
	_build_ui()
	visible = false
	set_process_input(true)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.07, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_root = Control.new()
	_root.name = "GiftDocumentViewerRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 16
	_root.offset_top = 24
	_root.offset_right = -16
	_root.offset_bottom = -16
	add_child(_root)

	_top_bar = HBoxContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 64
	_top_bar.add_theme_constant_override("separation", 8)
	_root.add_child(_top_bar)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Anniversary Gift"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	title.add_theme_font_size_override("font_size", 30)
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		title.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	_top_bar.add_child(title)

	_top_bar.add_child(_tool_button("−", "Zoom out", func() -> void: _adjust_zoom(0.9)))
	_top_bar.add_child(_tool_button("Reset", "Reset zoom to 100%", func() -> void: _reset_zoom()))
	_top_bar.add_child(_tool_button("+", "Zoom in", func() -> void: _adjust_zoom(1.1)))
	_top_bar.add_child(_tool_button("Fit", "Fit page width", func() -> void: _apply_fit_width()))
	_top_bar.add_child(_tool_button("Close", "Close gift viewer", close_viewer))

	_scroll = ScrollContainer.new()
	_scroll.name = "PageScrollContainer"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 72
	_scroll.offset_bottom = -150
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	_root.add_child(_scroll)

	_zoom_root = Control.new()
	_zoom_root.name = "PageZoomRoot"
	_zoom_root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_zoom_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_zoom_root)

	_pages_box = VBoxContainer.new()
	_pages_box.name = "PagesVBox"
	_pages_box.add_theme_constant_override("separation", int(PAGE_GAP))
	_pages_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pages_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_root.add_child(_pages_box)

	_loading = Label.new()
	_loading.name = "LoadingIndicator"
	_loading.text = "Loading gift pages…"
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	_loading.add_theme_font_size_override("font_size", 28)
	_root.add_child(_loading)

	_error_panel = Label.new()
	_error_panel.name = "PreviewErrorPanel"
	_error_panel.text = "Page previews unavailable.\nYou can still open or share the original PDF below."
	_error_panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_panel.set_anchors_preset(Control.PRESET_CENTER)
	_error_panel.custom_minimum_size = Vector2(640, 120)
	_error_panel.add_theme_color_override("font_color", Color(1.0, 0.75, 0.7))
	_error_panel.add_theme_font_size_override("font_size", 26)
	_error_panel.visible = false
	_root.add_child(_error_panel)

	var bottom := VBoxContainer.new()
	bottom.name = "BottomActions"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -140
	bottom.offset_bottom = 0
	bottom.add_theme_constant_override("separation", 8)
	_root.add_child(bottom)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
	_status.add_theme_font_size_override("font_size", 18)
	bottom.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	bottom.add_child(actions)
	var open_btn := _tool_button("Open Original PDF", "Open original PDF in another app", _open_pdf)
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.custom_minimum_size = Vector2(0, 64)
	actions.add_child(open_btn)
	var share_btn := _tool_button("Share or Save PDF", "Share or save the original PDF", _share_pdf)
	share_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_btn.custom_minimum_size = Vector2(0, 64)
	actions.add_child(share_btn)


func _tool_button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 56)
	b.pressed.connect(cb)
	return b


func open_viewer() -> void:
	_visible_modal = true
	visible = true
	_status.text = "Pinch or use + / − to zoom. Fit keeps pages readable."
	_loading.visible = true
	_loading.text = "Loading gift pages…"
	_error_panel.visible = false
	_scroll.visible = false
	_clear_pages()
	await get_tree().process_frame
	await get_tree().process_frame
	load_pdf_previews()
	if not _page_rects.is_empty():
		_apply_fit_width()


func load_pdf_previews() -> void:
	_clear_pages()
	var successfully_loaded: int = 0
	for page_path: String in PdfHelper.PDF_PAGE_PATHS:
		if not ResourceLoader.exists(page_path):
			push_error("Missing PDF preview resource: %s" % page_path)
			continue
		var resource: Resource = ResourceLoader.load(page_path)
		if resource == null or not (resource is Texture2D):
			push_error("PDF preview did not load as Texture2D: %s" % page_path)
			continue
		_add_preview_page(resource as Texture2D, successfully_loaded)
		successfully_loaded += 1

	_loading.visible = false
	if successfully_loaded == 0:
		_error_panel.visible = true
		_scroll.visible = false
		_status.text = "Preview images missing. Use Open Original PDF if a PDF app is installed."
	else:
		_error_panel.visible = false
		_scroll.visible = true
		_status.text = "Showing %d page preview(s). Pinch or use + / − to zoom." % successfully_loaded


func _clear_pages() -> void:
	for child in _pages_box.get_children():
		child.queue_free()
	_page_rects.clear()
	_page_shadows.clear()
	_zoom_root.custom_minimum_size = Vector2.ZERO
	_pages_box.custom_minimum_size = Vector2.ZERO


func _add_preview_page(texture: Texture2D, index: int) -> void:
	var wrap := Control.new()
	wrap.name = "PageWrap_%d" % (index + 1)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages_box.add_child(wrap)

	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_offset = Vector2(0, 4)
	shadow.add_theme_stylebox_override("panel", sb)
	wrap.add_child(shadow)

	var tr := TextureRect.new()
	tr.name = "Page_%d" % (index + 1)
	tr.texture = texture
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wrap.add_child(tr)

	_page_rects.append(tr)
	_page_shadows.append(shadow)


func get_loaded_page_count() -> int:
	return _page_rects.size()


func _apply_page_layout() -> void:
	if _page_rects.is_empty():
		return
	var available_w: float = maxf(_scroll.size.x - 24.0, 200.0)
	if available_w <= 200.0:
		available_w = maxf(get_viewport().get_visible_rect().size.x - 64.0, 200.0)

	# Fit-width scale is relative to native texture width of the first page.
	var first_tex: Texture2D = _page_rects[0].texture
	var native_w: float = maxf(first_tex.get_width(), 1.0)
	_fit_width_scale = available_w / native_w

	var zoom: float = _fit_width_scale if _mode_fit_width else (_fit_width_scale * _user_zoom)
	zoom = clampf(zoom, MIN_ZOOM * _fit_width_scale * 0.5, MAX_ZOOM)

	var max_w: float = 0.0
	var total_h: float = 0.0
	for i in _page_rects.size():
		var tr: TextureRect = _page_rects[i]
		var tex: Texture2D = tr.texture
		var tw: float = tex.get_width() * zoom
		var th: float = tex.get_height() * zoom
		var wrap: Control = tr.get_parent() as Control
		wrap.custom_minimum_size = Vector2(tw + 16.0, th + 16.0)
		wrap.size = wrap.custom_minimum_size
		tr.position = Vector2(8, 8)
		tr.size = Vector2(tw, th)
		var shadow: Panel = _page_shadows[i]
		shadow.position = Vector2(4, 6)
		shadow.size = Vector2(tw + 8.0, th + 8.0)
		max_w = maxf(max_w, wrap.custom_minimum_size.x)
		total_h += wrap.custom_minimum_size.y
		if i < _page_rects.size() - 1:
			total_h += PAGE_GAP

	_pages_box.custom_minimum_size = Vector2(max_w, total_h)
	_pages_box.size = _pages_box.custom_minimum_size
	_zoom_root.custom_minimum_size = _pages_box.custom_minimum_size
	_zoom_root.size = _zoom_root.custom_minimum_size


func _on_zoom_changed(scale: float) -> void:
	_mode_fit_width = false
	_user_zoom = clampf(scale, MIN_ZOOM, MAX_ZOOM)
	_apply_page_layout()


func _adjust_zoom(factor: float) -> void:
	if _mode_fit_width:
		_user_zoom = 1.0
		_mode_fit_width = false
	_user_zoom = clampf(_user_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_zoom.current_scale = _user_zoom
	_apply_page_layout()


func _reset_zoom() -> void:
	_mode_fit_width = false
	_user_zoom = 1.0
	_zoom.current_scale = 1.0
	_apply_page_layout()


func _apply_fit_width() -> void:
	_mode_fit_width = true
	_user_zoom = 1.0
	_zoom.current_scale = 1.0
	_apply_page_layout()


func _open_pdf() -> void:
	var result: Dictionary = pdf_helper.open_original_pdf()
	_status.text = str(result.get("message", ""))
	if not bool(result.get("ok", false)) and get_loaded_page_count() > 0:
		_status.text += " The in-app page preview remains available."


func _share_pdf() -> void:
	var result: Dictionary = pdf_helper.share_original_pdf()
	_status.text = str(result.get("message", ""))
	if not bool(result.get("ok", false)) and get_loaded_page_count() > 0:
		_status.text += " The in-app page preview remains available."


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	visible = false
	_clear_pages()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _zoom.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()


func _on_viewport_resized() -> void:
	if visible and not _page_rects.is_empty():
		_apply_page_layout()
