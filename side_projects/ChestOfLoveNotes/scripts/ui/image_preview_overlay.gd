extends CanvasLayer
class_name ImagePreviewOverlay
## Full-screen image preview with Close + Android Back. No trapping.

signal closed

var _root: Control
var _dim: ColorRect
var _tex: TextureRect
var _title: Label
var _alive: bool = false


func _ready() -> void:
	layer = 55
	visible = false


func open_path(path: String, title: String = "Photo") -> void:
	var tex := AttachmentHelper.make_thumbnail_texture(path, 2048)
	if tex == null:
		return
	open_texture(tex, title)


func open_texture(tex: Texture2D, title: String = "Photo") -> void:
	_ensure_ui()
	_tex.texture = tex
	_title.text = title
	_alive = true
	visible = true
	_dim.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 0.88, 0.18)


func close_preview() -> void:
	if not _alive:
		return
	_alive = false
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 0.0, 0.16)
	await tw.finished
	visible = false
	_tex.texture = null
	closed.emit()


func _ensure_ui() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.04, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, 12)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.98))
	top.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.custom_minimum_size = Vector2(120, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	MobileUi.style_button(close_btn, 48)
	close_btn.pressed.connect(close_preview)
	top.add_child(close_btn)

	var host := Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	col.add_child(host)

	_tex = TextureRect.new()
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_tex)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close_preview()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_preview()
		get_viewport().set_input_as_handled()
