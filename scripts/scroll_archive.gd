extends Control
class_name ScrollArchive

## Persistent bottom archive of viewed scrolls.

signal scroll_selected(date_iso: String)

var manager: AnniversaryManager
var _scroll: ScrollContainer
var _row: HBoxContainer
var _empty_label: Label
var _items: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 190)
	clip_contents = false
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.1, 0.62)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "Scroll Archive"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 6
	title.offset_bottom = 34
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.55))
	title.add_theme_font_size_override("font_size", 20)
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Regular.ttf"):
		title.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Regular.ttf"))
	add_child(title)

	_empty_label = Label.new()
	_empty_label.text = "Opened messages will rest here"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.set_anchors_preset(Control.PRESET_CENTER)
	_empty_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.85, 0.8))
	_empty_label.add_theme_font_size_override("font_size", 18)
	add_child(_empty_label)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 12
	_scroll.offset_top = 36
	_scroll.offset_right = -12
	_scroll.offset_bottom = -10
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = false
	add_child(_scroll)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 14)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scroll.add_child(_row)


func refresh() -> void:
	if manager == null:
		return
	for child in _row.get_children():
		child.queue_free()
	_items.clear()
	var dates: Array[String] = manager.get_archived_dates()
	_empty_label.visible = dates.is_empty()
	for d in dates:
		var item := _make_item(d, true)
		_row.add_child(item)
		_items[d] = item


func _make_item(date_iso: String, read: bool) -> Control:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size = Vector2(96, 130)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var btn := TextureButton.new()
	btn.custom_minimum_size = Vector2(72, 72)
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.ignore_texture_size = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "Open message for %s" % DateService.format_display_date(date_iso)
	var tex_path := "res://assets/art/scroll/scroll_mini.png"
	if not read and ResourceLoader.exists("res://assets/art/scroll/scroll_mini_unread.png"):
		tex_path = "res://assets/art/scroll/scroll_mini_unread.png"
	if ResourceLoader.exists(tex_path):
		btn.texture_normal = load(tex_path)
	btn.modulate = Color(0.95, 0.92, 0.98, 1.0) if read else Color(1.1, 1.0, 0.85, 1.0)
	btn.pressed.connect(func() -> void: scroll_selected.emit(date_iso))
	wrap.add_child(btn)

	var label := Label.new()
	label.text = DateService.short_display_date(date_iso)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.65))
	label.add_theme_font_size_override("font_size", 16)
	wrap.add_child(label)
	return wrap


func bounce_item(date_iso: String) -> void:
	refresh()
	await get_tree().process_frame
	if not _items.has(date_iso):
		return
	var item: Control = _items[date_iso]
	HapticHelper.scroll_land()
	var tw := create_tween()
	tw.tween_property(item, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(item, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BOUNCE)
	await tw.finished


func get_item_global_center(date_iso: String) -> Vector2:
	if _items.has(date_iso):
		var item: Control = _items[date_iso]
		return item.global_position + item.size * 0.5
	return global_position + size * Vector2(0.5, 0.5)
