extends CanvasLayer
class_name DeveloperPanel

## Simple date simulator: pick a day, panel closes, app behaves as if opened that day.

signal closed
signal date_applied(iso_date: String)

const PIN := "0813"
const DATE_OPTIONS: PackedStringArray = [
	"2026-08-05", "2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09",
	"2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14",
]

var manager: AnniversaryManager
var _banner: Label
var _body: Control
var _pin_layer: Control
var _pin_input: LineEdit
var _hint: Label


func _ready() -> void:
	layer = 60
	_build()
	visible = false
	set_process_unhandled_input(true)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.08, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			# Tap outside list cancels without exiting an active simulation.
			if manager != null and manager.developer_mode:
				_hide_ui()
			else:
				visible = false
	)
	add_child(dim)

	_banner = Label.new()
	_banner.text = "Simulate Open Date"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 36
	_banner.offset_bottom = 96
	_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_banner.add_theme_font_size_override("font_size", 34)
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_banner.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	add_child(_banner)

	_hint = Label.new()
	_hint.text = "Choose a day. The app will behave as if it were opened on that date."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_left = 40
	_hint.offset_right = -40
	_hint.offset_top = 100
	_hint.offset_bottom = 160
	_hint.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	_hint.add_theme_font_size_override("font_size", 22)
	add_child(_hint)

	_body = ScrollContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = 48
	_body.offset_top = 170
	_body.offset_right = -48
	_body.offset_bottom = -120
	add_child(_body)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	_body.add_child(col)

	for d in DATE_OPTIONS:
		var label := DateService.format_display_date(d) if d >= "2026-08-06" and d <= "2026-08-13" else d
		if d == "2026-08-05":
			label = "August 5, 2026 (before start)"
		elif d == "2026-08-14":
			label = "August 14, 2026 (after finale)"
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(0, 72)
		b.focus_mode = Control.FOCUS_NONE
		var iso := d
		b.pressed.connect(func() -> void: _apply_date_and_close(iso))
		col.add_child(b)

	var exit_btn := Button.new()
	exit_btn.text = "Exit simulation (use real date)"
	exit_btn.custom_minimum_size = Vector2(0, 64)
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	exit_btn.offset_left = 48
	exit_btn.offset_right = -48
	exit_btn.offset_top = -100
	exit_btn.offset_bottom = -32
	exit_btn.pressed.connect(exit_simulation)
	add_child(exit_btn)

	_pin_layer = Control.new()
	_pin_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pin_layer.visible = false
	_pin_layer.z_index = 2
	add_child(_pin_layer)
	var pin_dim := ColorRect.new()
	pin_dim.color = Color(0, 0, 0, 0.8)
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


func prompt_pin() -> void:
	# If already simulating, reopen the date list without asking for PIN again.
	if manager != null and manager.developer_mode:
		open_panel()
		return
	visible = true
	_body.visible = false
	_banner.visible = true
	_hint.visible = false
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
	_hint.visible = true
	if not manager.developer_mode:
		manager.enter_developer_mode()


func _apply_date_and_close(iso_date: String) -> void:
	if manager == null:
		return
	if not manager.developer_mode:
		manager.enter_developer_mode()
	manager.developer_set_date(iso_date)
	# Behave as if the app was just opened on that calendar day.
	manager.refresh_unlocks()
	_hide_ui()
	date_applied.emit(iso_date)
	closed.emit()


func _hide_ui() -> void:
	visible = false
	_pin_layer.visible = false


func exit_simulation() -> void:
	if manager:
		manager.exit_developer_mode()
	_hide_ui()
	closed.emit()


func close_panel() -> void:
	## Back / cancel: if a simulation is active, only hide the picker.
	if manager != null and manager.developer_mode:
		_hide_ui()
		closed.emit()
	else:
		exit_simulation()


func _submit_pin() -> void:
	if _pin_input.text.strip_edges() == PIN:
		_pin_layer.visible = false
		open_panel()
	else:
		_pin_input.text = ""
		_pin_input.placeholder_text = "Incorrect PIN"


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _pin_layer.visible:
			_pin_layer.visible = false
			visible = false
		else:
			close_panel()
		get_viewport().set_input_as_handled()
