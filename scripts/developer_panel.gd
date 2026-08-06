extends CanvasLayer
class_name DeveloperPanel

## Hidden developer test panel. Uses a separate save file and simulated dates.

signal closed
signal request_test_final_message
signal request_test_final_gift
signal request_test_pdf_viewer
signal request_test_pdf_plugin
signal request_simulate_restart

const PIN := "0813"
const DATE_OPTIONS: PackedStringArray = [
	"2026-08-05", "2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09",
	"2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14",
]

var manager: AnniversaryManager
var _banner: Label
var _body: Control
var _date_option: OptionButton
var _status: Label
var _pin_layer: Control
var _pin_input: LineEdit


func _ready() -> void:
	layer = 60
	_build()
	visible = false
	set_process_unhandled_input(true)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.08, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_banner = Label.new()
	_banner.text = "DEVELOPER TEST MODE"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 24
	_banner.offset_bottom = 72
	_banner.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_banner.add_theme_font_size_override("font_size", 30)
	add_child(_banner)

	_body = ScrollContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = 32
	_body.offset_top = 90
	_body.offset_right = -32
	_body.offset_bottom = -32
	add_child(_body)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	_body.add_child(col)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	_status.add_theme_font_size_override("font_size", 20)
	col.add_child(_status)

	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 10)
	col.add_child(date_row)
	var date_lbl := Label.new()
	date_lbl.text = "Date"
	date_lbl.custom_minimum_size = Vector2(100, 0)
	date_row.add_child(date_lbl)
	_date_option = OptionButton.new()
	_date_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_option.custom_minimum_size = Vector2(0, 56)
	for d in DATE_OPTIONS:
		_date_option.add_item(d)
	_date_option.item_selected.connect(_on_date_selected)
	date_row.add_child(_date_option)

	_add_button(col, "Previous Day", func() -> void:
		manager.developer_set_date(DateService.add_days(manager.get_effective_date(), -1))
		_sync_date_option()
		_refresh_status()
	)
	_add_button(col, "Next Day", func() -> void:
		manager.developer_set_date(DateService.add_days(manager.get_effective_date(), 1))
		_sync_date_option()
		_refresh_status()
	)
	_add_button(col, "Set to Real Device Date", func() -> void:
		manager.date_service.clear_simulated_date()
		manager.refresh_unlocks()
		_sync_date_option()
		_refresh_status()
	)
	_add_button(col, "Simulate App Restart", func() -> void:
		request_simulate_restart.emit()
		_refresh_status()
	)
	_add_button(col, "Reset Developer-Test Progress", func() -> void:
		manager.developer_reset_progress()
		_refresh_status()
	)
	_add_button(col, "Mark Selected Chest Unopened", func() -> void:
		manager.developer_mark_chest_unopened(_selected_date())
		_refresh_status()
	)
	_add_button(col, "Mark Selected Scroll Unread", func() -> void:
		manager.developer_mark_scroll_unread(_selected_date())
		_refresh_status()
	)
	_add_button(col, "Unlock All Test Dates", func() -> void:
		manager.developer_unlock_all()
		_sync_date_option()
		_refresh_status()
	)
	_add_button(col, "Test Final Message", func() -> void: request_test_final_message.emit())
	_add_button(col, "Test Final Gift Chest", func() -> void: request_test_final_gift.emit())
	_add_button(col, "Test PDF Viewer", func() -> void: request_test_pdf_viewer.emit())
	_add_button(col, "Test PDF Open/Share Plugin", func() -> void: request_test_pdf_plugin.emit())
	_add_button(col, "Toggle Reduced Motion", func() -> void:
		manager.set_reduced_motion(not manager.is_reduced_motion())
		_refresh_status()
	)
	_add_button(col, "Close Developer Mode", close_panel)

	_pin_layer = Control.new()
	_pin_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pin_layer.visible = false
	add_child(_pin_layer)
	var pin_dim := ColorRect.new()
	pin_dim.color = Color(0, 0, 0, 0.75)
	pin_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pin_layer.add_child(pin_dim)
	var pin_box := VBoxContainer.new()
	pin_box.set_anchors_preset(Control.PRESET_CENTER)
	pin_box.custom_minimum_size = Vector2(520, 280)
	pin_box.position = Vector2(-260, -140)
	pin_box.add_theme_constant_override("separation", 16)
	_pin_layer.add_child(pin_box)
	var pin_title := Label.new()
	pin_title.text = "Enter Developer PIN"
	pin_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pin_title.add_theme_font_size_override("font_size", 28)
	pin_title.add_theme_color_override("font_color", Color.WHITE)
	pin_box.add_child(pin_title)
	_pin_input = LineEdit.new()
	_pin_input.secret = true
	_pin_input.placeholder_text = "PIN"
	_pin_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin_input.custom_minimum_size = Vector2(0, 64)
	_pin_input.text_submitted.connect(func(_t: String) -> void: _submit_pin())
	pin_box.add_child(_pin_input)
	var pin_btns := HBoxContainer.new()
	pin_btns.add_theme_constant_override("separation", 12)
	pin_box.add_child(pin_btns)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(0, 64)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_submit_pin)
	pin_btns.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 64)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void:
		_pin_layer.visible = false
		visible = false
	)
	pin_btns.add_child(cancel)


func _add_button(parent: Node, text: String, callable: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callable)
	parent.add_child(b)


func prompt_pin() -> void:
	visible = true
	_body.visible = false
	_banner.visible = true
	_pin_layer.visible = true
	_pin_input.text = ""
	_pin_input.grab_focus()


func open_panel() -> void:
	if manager == null:
		return
	visible = true
	_pin_layer.visible = false
	_body.visible = true
	_banner.visible = true
	manager.enter_developer_mode()
	_sync_date_option()
	_refresh_status()


func close_panel() -> void:
	if manager:
		manager.exit_developer_mode()
	visible = false
	closed.emit()


func _submit_pin() -> void:
	if _pin_input.text.strip_edges() == PIN:
		_pin_layer.visible = false
		open_panel()
	else:
		_pin_input.text = ""
		_pin_input.placeholder_text = "Incorrect PIN"


func _selected_date() -> String:
	return DATE_OPTIONS[_date_option.selected]


func _on_date_selected(index: int) -> void:
	manager.developer_set_date(DATE_OPTIONS[index])
	_refresh_status()


func _sync_date_option() -> void:
	var current: String = manager.get_effective_date()
	var idx := DATE_OPTIONS.find(current)
	if idx < 0:
		# Closest clamp into list
		if current < DATE_OPTIONS[0]:
			idx = 0
		elif current > DATE_OPTIONS[DATE_OPTIONS.size() - 1]:
			idx = DATE_OPTIONS.size() - 1
		else:
			idx = 0
		manager.developer_set_date(DATE_OPTIONS[idx])
	_date_option.select(idx)


func _refresh_status() -> void:
	if manager == null:
		return
	_status.text = "Effective: %s\nDevice: %s\nUnlocked: %d\nCatch-up queue: %s\nReduced motion: %s\nFinal message viewed: %s\nFinal gift opened: %s" % [
		manager.get_effective_date(),
		manager.date_service.get_device_date(),
		manager.get_unlocked_dates().size(),
		", ".join(manager.catchup_queue) if not manager.catchup_queue.is_empty() else "(empty)",
		str(manager.is_reduced_motion()),
		str(manager.is_final_message_viewed()),
		str(manager.is_final_gift_opened()),
	]


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _pin_layer.visible:
			_pin_layer.visible = false
			visible = false
		else:
			close_panel()
		get_viewport().set_input_as_handled()
