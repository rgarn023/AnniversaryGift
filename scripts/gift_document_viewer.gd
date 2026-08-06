extends CanvasLayer
class_name GiftDocumentViewer

## In-app viewer for high-resolution PDF page previews.

signal closed

var pdf_helper: PdfHelper
var _zoom: GestureZoomController
var _dim: ColorRect
var _root: Control
var _scroll: ScrollContainer
var _page_box: VBoxContainer
var _status: Label
var _loading: Label
var _scale: float = 1.0
var _fit_width: bool = true
var _visible_modal: bool = false
var _pages: PackedStringArray = []


func _ready() -> void:
	layer = 50
	pdf_helper = PdfHelper.new()
	_zoom = GestureZoomController.new()
	_zoom.min_scale = 0.5
	_zoom.max_scale = 3.0
	_zoom.current_scale = 1.0
	_zoom.zoom_changed.connect(_on_zoom_changed)
	_build_ui()
	visible = false
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.06, 0.88)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 24
	_root.offset_top = 48
	_root.offset_right = -24
	_root.offset_bottom = -24
	add_child(_root)

	var title := Label.new()
	title.text = "Anniversary Gift"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_bottom = 48
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	title.add_theme_font_size_override("font_size", 34)
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		title.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	_root.add_child(title)

	_loading = Label.new()
	_loading.text = "Loading gift pages…"
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	_loading.add_theme_font_size_override("font_size", 28)
	_root.add_child(_loading)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 60
	_scroll.offset_bottom = -220
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)

	_page_box = VBoxContainer.new()
	_page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_box.add_theme_constant_override("separation", 18)
	_scroll.add_child(_page_box)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -210
	_status.offset_bottom = -150
	_status.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
	_status.add_theme_font_size_override("font_size", 20)
	_root.add_child(_status)

	var toolbar := GridContainer.new()
	toolbar.columns = 3
	toolbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar.offset_top = -140
	toolbar.offset_bottom = -8
	toolbar.add_theme_constant_override("h_separation", 12)
	toolbar.add_theme_constant_override("v_separation", 12)
	_root.add_child(toolbar)

	var buttons := [
		["–", "Decrease zoom", func() -> void: _zoom.adjust(0.9)],
		["+", "Increase zoom", func() -> void: _zoom.adjust(1.1)],
		["Reset", "Reset zoom", func() -> void: _zoom.reset(1.0)],
		["Fit Width", "Fit page width", func() -> void: _apply_fit_width()],
		["Open Original PDF", "Open original PDF", func() -> void: _open_pdf()],
		["Share or Save PDF", "Share or save PDF", func() -> void: _share_pdf()],
	]
	for spec in buttons:
		var b := Button.new()
		b.text = str(spec[0])
		b.tooltip_text = str(spec[1])
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[2])
		toolbar.add_child(b)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.tooltip_text = "Close gift viewer"
	close_btn.custom_minimum_size = Vector2(0, 64)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close_viewer)
	toolbar.add_child(close_btn)


func open_viewer() -> void:
	_visible_modal = true
	visible = true
	_status.text = "Pinch or use + and – to resize"
	_loading.visible = true
	_clear_pages()
	await get_tree().process_frame
	_pages = pdf_helper.list_page_previews()
	if _pages.is_empty():
		_loading.text = "Page previews are unavailable, but you can still open the original PDF."
		_status.text = "Preview images missing. Use Open Original PDF if a PDF app is installed."
	else:
		_loading.visible = false
		_populate_pages()
		_apply_fit_width()


func _clear_pages() -> void:
	for child in _page_box.get_children():
		child.queue_free()


func _populate_pages() -> void:
	_clear_pages()
	for path in _pages:
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tex: Texture2D = load(path)
		tr.texture = tex
		tr.custom_minimum_size = Vector2(0, 400)
		_page_box.add_child(tr)
	_apply_page_sizes()


func _apply_page_sizes() -> void:
	var width: float = maxf(_scroll.size.x - 8.0, 200.0) * _scale
	for child in _page_box.get_children():
		if child is TextureRect:
			var tr := child as TextureRect
			if tr.texture:
				var tex_size: Vector2 = tr.texture.get_size()
				var height: float = width * (tex_size.y / maxf(tex_size.x, 1.0))
				tr.custom_minimum_size = Vector2(width, height)


func _on_zoom_changed(scale: float) -> void:
	_fit_width = false
	_scale = scale
	_apply_page_sizes()


func _apply_fit_width() -> void:
	_fit_width = true
	_scale = 1.0
	_zoom.current_scale = 1.0
	_apply_page_sizes()


func _open_pdf() -> void:
	var result: Dictionary = pdf_helper.open_original_pdf()
	_status.text = str(result.get("message", ""))
	if not bool(result.get("ok", false)):
		_status.text += " The in-app page preview remains available."


func _share_pdf() -> void:
	var result: Dictionary = pdf_helper.share_original_pdf()
	_status.text = str(result.get("message", ""))
	if not bool(result.get("ok", false)):
		_status.text += " The in-app page preview remains available."


func close_viewer() -> void:
	if not _visible_modal:
		return
	_visible_modal = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _zoom.handle_input(event):
		# While pinching, prevent scroll fighting.
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_viewer()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_viewer()


func _on_viewport_resized() -> void:
	if visible and _fit_width:
		_apply_page_sizes()
