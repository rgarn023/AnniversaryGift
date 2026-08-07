extends Control
class_name ComposeScrollScreen
## Mobile-first Compose Scroll UI. Preserves draft fields and emits send/preview
## drafts for the host to execute existing send-scroll / viewer logic.

signal back_pressed
signal preview_requested(draft: Dictionary)
signal send_requested(draft: Dictionary)

const MAX_TITLE := 80
const MAX_MESSAGE := 5000
const MIN_PASSWORD := 4
const MAX_PASSWORD := 64

const COL_BG := Color(0.05, 0.03, 0.12, 1.0)
const COL_CARD := Color(0.14, 0.09, 0.20, 0.92)
const COL_GOLD := Color(0.98, 0.86, 0.45)
const COL_GOLD_MUTED := Color(0.72, 0.58, 0.32, 0.85)
const COL_TEXT := Color(0.94, 0.90, 0.96)
const COL_SUPPORT := Color(0.78, 0.72, 0.84)
const COL_WARN := Color(0.96, 0.78, 0.55)
const COL_BURGUNDY := Color(0.48, 0.18, 0.24, 0.98)
const COL_BURGUNDY_HOVER := Color(0.58, 0.24, 0.30, 1.0)
const COL_DISABLED := Color(0.28, 0.22, 0.30, 0.85)
const COL_ERROR := Color(1.0, 0.55, 0.48)

var friends: Array = []
var private_onboarding_label: bool = false
## Host sets this so Compose never extends under bottom navigation.
var bottom_chrome_inset: int = 0

var _safe_margin: MarginContainer
var _main_vbox: VBoxContainer
var _scroll: ScrollContainer
var _form: VBoxContainer
var _bottom_area: PanelContainer
var _send_btn: Button
var _preview_btn: Button
var _validation_label: Label
var _keyboard_pad: Control

var _recipient_btn: Button
var _recipient_label: Label
var _selected_friend: Dictionary = {}

var _title_edit: LineEdit
var _title_count: Label
var _message_edit: TextEdit
var _message_count: Label
var _message_card: PanelContainer

var _open_immediately: CheckBox
var _date_btn: Button
var _time_btn: Button
var _tz_label: Label
var _delivery_controls: VBoxContainer
var _unlock_date: Dictionary = {}
var _unlock_hour: int = 20
var _unlock_minute: int = 0

var _location_toggle: CheckButton
var _location_fields: VBoxContainer
var _location_search: LineEdit
var _location_status: Label
var _location_use_btn: Button
var _location_map_btn: Button
var _location_summary: PanelContainer
var _location_summary_title: Label
var _location_summary_addr: Label
var _location_suggestions: VBoxContainer
var _location_radius_row: HBoxContainer
var _location_search_spinner: Label
var _has_location_lock: bool = false
var _location_name: String = ""
var _location_address: String = ""
var _location_lat: float = 0.0
var _location_lng: float = 0.0
var _location_radius_m: int = LocationHelper.DEFAULT_RADIUS_M
var _location_fix_ok: bool = false
var _location_search_service: LocationSearchService = LocationSearchService.new()
var _location_search_token: int = 0
var _location_debounce: Timer
var _map_picker: MapLocationPicker

var _pw_toggle: CheckButton
var _pw_fields: VBoxContainer
var _pw_edit: LineEdit
var _pw2_edit: LineEdit
var _pw_show: Button
var _pw2_show: Button

var _summary_label: Label
var _overlay: Control
var _sending: bool = false
var _title_font: Font
var _body_font: Font


func setup(p_friends: Array, show_onboarding_chip: bool = false, draft: Dictionary = {}) -> void:
	friends = p_friends
	private_onboarding_label = show_onboarding_chip
	_init_default_schedule()
	_build_ui()
	if not draft.is_empty():
		apply_draft(draft)
	else:
		_refresh_recipient_row()
		_refresh_schedule_labels()
		_sync_delivery_visibility()
		_refresh_summary()
		_update_validation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_chrome_inset()
		_apply_safe_area()
		_resize_message_box()


func get_draft() -> Dictionary:
	return {
		"recipient_id": str(_selected_friend.get("id", "")),
		"recipient_display_name": str(_selected_friend.get("display_name", "")),
		"recipient_username": str(_selected_friend.get("username", "")),
		"title": _title_edit.text.strip_edges() if _title_edit else "",
		"message": _message_edit.text if _message_edit else "",
		"open_immediately": _open_immediately.button_pressed if _open_immediately else true,
		"unlock_unix": _compute_unlock_unix(),
		"password": _password_value(),
		"has_password": _pw_toggle.button_pressed if _pw_toggle else false,
		"has_location_lock": _location_toggle.button_pressed if _location_toggle else _has_location_lock,
		"location_name": _location_name,
		"location_address": _location_address,
		"location_lat": _location_lat,
		"location_lng": _location_lng,
		"location_radius_m": _location_radius_m,
		"location_fix_ok": _location_fix_ok,
	}


func apply_draft(draft: Dictionary) -> void:
	## Restore Compose fields after navigating away (not after a successful send).
	if draft.is_empty():
		return
	var rid := str(draft.get("recipient_id", ""))
	_selected_friend = {}
	if not rid.is_empty():
		for f in friends:
			if typeof(f) == TYPE_DICTIONARY and str(f.get("id", "")) == rid:
				_selected_friend = (f as Dictionary).duplicate(true)
				break
		if _selected_friend.is_empty():
			_selected_friend = {
				"id": rid,
				"display_name": str(draft.get("recipient_display_name", "Friend")),
				"username": str(draft.get("recipient_username", "")),
			}
	if _title_edit:
		_title_edit.text = str(draft.get("title", ""))
		if _title_count:
			_title_count.text = "%d / %d" % [_title_edit.text.length(), MAX_TITLE]
	if _message_edit:
		_message_edit.text = str(draft.get("message", ""))
		if _message_count:
			_message_count.text = "%d / %d" % [_message_edit.text.length(), MAX_MESSAGE]
	var immediate := bool(draft.get("open_immediately", true))
	if _open_immediately:
		_open_immediately.set_pressed_no_signal(immediate)
	if not immediate:
		var unlock_unix := int(draft.get("unlock_unix", 0))
		if unlock_unix > 0:
			var dt := Time.get_datetime_dict_from_unix_time(unlock_unix)
			_unlock_date = {
				"year": int(dt.year),
				"month": int(dt.month),
				"day": int(dt.day),
			}
			_unlock_hour = int(dt.hour)
			_unlock_minute = int(dt.minute)
	if _pw_toggle:
		var has_pw := bool(draft.get("has_password", false))
		_pw_toggle.set_pressed_no_signal(has_pw)
		if _pw_fields:
			_pw_fields.visible = has_pw
		var pw := str(draft.get("password", ""))
		if _pw_edit:
			_pw_edit.text = pw
		if _pw2_edit:
			_pw2_edit.text = pw
	_has_location_lock = bool(draft.get("has_location_lock", false))
	_location_name = str(draft.get("location_name", ""))
	_location_address = str(draft.get("location_address", ""))
	_location_lat = float(draft.get("location_lat", 0.0))
	_location_lng = float(draft.get("location_lng", 0.0))
	_location_radius_m = int(draft.get("location_radius_m", LocationHelper.DEFAULT_RADIUS_M))
	_location_fix_ok = bool(draft.get("location_fix_ok", false))
	if _location_toggle:
		_location_toggle.set_pressed_no_signal(_has_location_lock)
	if _location_search and not _location_fix_ok:
		_location_search.text = ""
	_sync_location_visibility()
	_refresh_location_summary()
	_refresh_recipient_row()
	_refresh_schedule_labels()
	_sync_delivery_visibility()
	_refresh_summary()
	_update_validation()


func set_sending(active: bool) -> void:
	_sending = active
	_update_validation()
	if active:
		_show_sending_overlay()
	else:
		_hide_overlay()


func restore_after_failed_send() -> void:
	set_sending(false)
	_set_inline_error("Could not send your scroll. Please try again.")


func handle_back() -> bool:
	## Returns true when back was consumed by an open overlay.
	if _map_picker != null and is_instance_valid(_map_picker):
		_map_picker.cancelled.emit()
		if is_instance_valid(_map_picker):
			_map_picker.queue_free()
		_map_picker = null
		return true
	if _overlay != null and _overlay.visible:
		_hide_overlay()
		return true
	return false


func _init_default_schedule() -> void:
	var now := Time.get_datetime_dict_from_system()
	_unlock_date = {
		"year": int(now.year),
		"month": int(now.month),
		"day": int(now.day),
	}
	_unlock_hour = 20
	_unlock_minute = 0


func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	## Keep host-applied bottom chrome inset — do not reset offsets to full-bleed.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	_apply_chrome_inset()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_title_font = _load_font("res://assets/fonts/Cinzel-Bold.ttf")
	_body_font = _load_font("res://assets/fonts/CormorantGaramond-Regular.ttf")

	## Transparent form over the shared chrome starfield — avoid a second full-screen blit.
	var bg := ColorRect.new()
	bg.color = Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_safe_margin = MarginContainer.new()
	_safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin.clip_contents = true
	add_child(_safe_margin)
	_apply_safe_area()

	_main_vbox = VBoxContainer.new()
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_vbox.clip_contents = true
	_main_vbox.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_safe_margin.add_child(_main_vbox)

	_main_vbox.add_child(_build_header())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.clip_contents = true
	MobileUi.configure_scroll(_scroll)
	_main_vbox.add_child(_scroll)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_left", 2)
	content_margin.add_theme_constant_override("margin_right", 2)
	content_margin.add_theme_constant_override("margin_bottom", 28)
	_scroll.add_child(content_margin)

	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.clip_contents = true
	_form.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	content_margin.add_child(_form)
	MobileUi.enable_touch_scroll_on_tree(_form)

	_form.add_child(_build_recipient_card())
	_form.add_child(_build_title_card())
	_form.add_child(_build_message_card())
	_form.add_child(_build_delivery_card())
	_form.add_child(_build_location_card())
	_form.add_child(_build_password_card())
	_form.add_child(_build_summary_card())

	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.add_theme_font_size_override("font_size", 16)
	_validation_label.add_theme_color_override("font_color", COL_ERROR)
	_validation_label.visible = false
	_form.add_child(_validation_label)

	## Document-flow actions so the keyboard never traps a nested fixed footer.
	_form.add_child(_build_bottom_actions())
	_keyboard_pad = Control.new()
	_keyboard_pad.custom_minimum_size = Vector2(0, 0)
	_form.add_child(_keyboard_pad)
	MobileUi.wire_keyboard_avoidance(self, _scroll, _keyboard_pad)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.z_index = 80
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	call_deferred("_resize_message_box")


func _build_header() -> VBoxContainer:
	## Primary bottom-nav destination — no redundant top Back control.
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	if private_onboarding_label:
		var chip := Label.new()
		chip.text = "Private Onboarding Build"
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", 16)
		chip.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45, 0.85))
		wrap.add_child(chip)
	var heading := MobileUi.make_page_title("Compose", _title_font)
	wrap.add_child(heading)
	return wrap


func _build_recipient_card() -> PanelContainer:
	var card := _make_card()
	card.clip_contents = true
	var col := _card_body(card)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.clip_contents = true
	col.add_child(_section_heading("Send To"))
	## Bound the recipient row so long "Name · @user" labels cannot widen the page.
	var row_wrap := Control.new()
	row_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_wrap.clip_contents = true
	row_wrap.custom_minimum_size = Vector2(0, MobileUi.font_touch(54))
	col.add_child(row_wrap)
	_recipient_btn = Button.new()
	_recipient_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recipient_btn.custom_minimum_size = Vector2(0, MobileUi.font_touch(54))
	_recipient_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipient_btn.focus_mode = Control.FOCUS_NONE
	_recipient_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_recipient_btn.clip_text = true
	_recipient_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_row_button(_recipient_btn)
	_recipient_btn.pressed.connect(_open_friend_picker)
	row_wrap.add_child(_recipient_btn)
	_recipient_label = Label.new()
	_recipient_label.visible = false
	return card


func _build_title_card() -> PanelContainer:
	var card := _make_card()
	var col := _card_body(card)
	var head := HBoxContainer.new()
	head.add_child(_section_heading("Scroll Title"))
	var opt := Label.new()
	opt.text = "Optional"
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	opt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opt.add_theme_font_size_override("font_size", 16)
	opt.add_theme_color_override("font_color", COL_SUPPORT)
	head.add_child(opt)
	col.add_child(head)
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "Give your scroll a title..."
	_title_edit.max_length = MAX_TITLE
	_title_edit.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.INPUT_H))
	_title_edit.add_theme_font_size_override("font_size", 19)
	_style_line_edit(_title_edit)
	_title_edit.text_changed.connect(func(_t: String) -> void:
		_title_count.text = "%d / %d" % [_title_edit.text.length(), MAX_TITLE]
		_refresh_summary()
		_update_validation()
	)
	col.add_child(_title_edit)
	_title_count = Label.new()
	_title_count.text = "0 / %d" % MAX_TITLE
	_title_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_count.add_theme_font_size_override("font_size", 16)
	_title_count.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(_title_count)
	return card


func _build_message_card() -> PanelContainer:
	_message_card = _make_card()
	var col := _card_body(_message_card)
	col.add_child(_section_heading("Your Message"))
	_message_edit = TextEdit.new()
	_message_edit.placeholder_text = "Write your love note..."
	_message_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_message_edit.scroll_fit_content_height = false
	_message_edit.custom_minimum_size = Vector2(0, 200)
	_message_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_message_edit.add_theme_font_size_override("font_size", 19)
	_style_text_edit(_message_edit)
	_message_edit.text_changed.connect(func() -> void:
		if _message_edit.text.length() > MAX_MESSAGE:
			_message_edit.text = _message_edit.text.substr(0, MAX_MESSAGE)
			_message_edit.set_caret_column(_message_edit.text.length())
		_message_count.text = "%d / %d" % [_message_edit.text.length(), MAX_MESSAGE]
		_refresh_summary()
		_update_validation()
	)
	col.add_child(_message_edit)
	_message_count = Label.new()
	_message_count.text = "0 / %d" % MAX_MESSAGE
	_message_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message_count.add_theme_font_size_override("font_size", 16)
	_message_count.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(_message_count)
	return _message_card


func _build_delivery_card() -> PanelContainer:
	var card := _make_card()
	var col := _card_body(card)
	col.add_child(_section_heading("When Should It Open?"))

	_open_immediately = CheckBox.new()
	_open_immediately.text = "Open Immediately"
	_open_immediately.button_pressed = true
	_open_immediately.custom_minimum_size = Vector2(0, MobileUi.font_touch(48))
	_open_immediately.focus_mode = Control.FOCUS_NONE
	_open_immediately.add_theme_font_size_override("font_size", 19)
	_open_immediately.add_theme_color_override("font_color", COL_TEXT)
	_open_immediately.toggled.connect(func(_on: bool) -> void:
		_sync_delivery_visibility()
		_refresh_summary()
		_update_validation()
	)
	col.add_child(_open_immediately)

	_delivery_controls = VBoxContainer.new()
	_delivery_controls.add_theme_constant_override("separation", 10)
	_delivery_controls.visible = false
	col.add_child(_delivery_controls)

	_delivery_controls.add_child(_field_caption("Unlock Date"))
	_date_btn = Button.new()
	_date_btn.custom_minimum_size = Vector2(0, 56)
	_date_btn.disabled = true
	_date_btn.focus_mode = Control.FOCUS_NONE
	_date_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_row_button(_date_btn)
	_date_btn.pressed.connect(_open_date_picker)
	_delivery_controls.add_child(_date_btn)

	_delivery_controls.add_child(_field_caption("Unlock Time"))
	_time_btn = Button.new()
	_time_btn.custom_minimum_size = Vector2(0, 56)
	_time_btn.disabled = true
	_time_btn.focus_mode = Control.FOCUS_NONE
	_time_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_row_button(_time_btn)
	_time_btn.pressed.connect(_open_time_picker)
	_delivery_controls.add_child(_time_btn)

	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	_delivery_controls.add_child(quick)
	for item in [
		{"label": "+ 1 hour", "secs": 3600},
		{"label": "Tomorrow", "secs": 86400},
		{"label": "+ 1 week", "secs": 604800},
	]:
		var b := Button.new()
		b.text = str(item.label)
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		_style_secondary_button(b)
		var secs: int = int(item.secs)
		b.pressed.connect(func() -> void:
			_open_immediately.button_pressed = false
			_apply_relative_unlock(secs)
		)
		quick.add_child(b)

	var tz_title := _field_caption("Your timezone")
	col.add_child(tz_title)
	_tz_label = Label.new()
	_tz_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tz_label.text = "%s\nWe'll convert this securely for delivery." % _timezone_friendly_name()
	_tz_label.add_theme_font_size_override("font_size", 16)
	_tz_label.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(_tz_label)
	return card


func _build_location_card() -> PanelContainer:
	var card := _make_card()
	var col := _card_body(card)
	col.add_child(_section_heading("Location Lock"))
	var blurb := Label.new()
	blurb.text = "Require your friend to be near a specific place to open this scroll. Location is checked only when needed to create or open a location-locked scroll."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 16)
	blurb.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(blurb)

	## Whole row is tappable — not only the tiny switch.
	var toggle_row := Button.new()
	toggle_row.flat = true
	toggle_row.focus_mode = Control.FOCUS_NONE
	toggle_row.custom_minimum_size = Vector2(0, 56)
	toggle_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(toggle_row)
	var toggle_inner := HBoxContainer.new()
	toggle_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toggle_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_row.add_child(toggle_inner)
	var toggle_label := Label.new()
	toggle_label.text = "Lock to a place"
	toggle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toggle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_label.add_theme_font_size_override("font_size", 19)
	toggle_label.add_theme_color_override("font_color", COL_TEXT)
	toggle_inner.add_child(toggle_label)
	_location_toggle = CheckButton.new()
	_location_toggle.custom_minimum_size = Vector2(72, 48)
	_location_toggle.focus_mode = Control.FOCUS_NONE
	_location_toggle.toggled.connect(func(on: bool) -> void:
		_has_location_lock = on
		_sync_location_visibility()
		_refresh_summary()
		_update_validation()
	)
	toggle_inner.add_child(_location_toggle)
	toggle_row.pressed.connect(func() -> void:
		_location_toggle.button_pressed = not _location_toggle.button_pressed
	)

	_location_fields = VBoxContainer.new()
	_location_fields.visible = false
	_location_fields.add_theme_constant_override("separation", 10)
	col.add_child(_location_fields)

	_location_fields.add_child(_field_caption("Search for a place or address"))
	_location_search = LineEdit.new()
	_location_search.placeholder_text = "City, address, landmark, venue…"
	_location_search.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.INPUT_H))
	_location_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_location_search.add_theme_font_size_override("font_size", 19)
	_style_line_edit(_location_search)
	_location_search.text_changed.connect(_on_location_search_changed)
	_location_fields.add_child(_location_search)

	_location_search_spinner = Label.new()
	_location_search_spinner.visible = false
	_location_search_spinner.text = "Searching…"
	_location_search_spinner.add_theme_font_size_override("font_size", 14)
	_location_search_spinner.add_theme_color_override("font_color", COL_SUPPORT)
	_location_fields.add_child(_location_search_spinner)

	_location_suggestions = VBoxContainer.new()
	_location_suggestions.visible = false
	_location_suggestions.add_theme_constant_override("separation", 4)
	_location_fields.add_child(_location_suggestions)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	_location_fields.add_child(action_row)
	_location_map_btn = Button.new()
	_location_map_btn.text = "Choose on Map"
	_location_map_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_location_map_btn.custom_minimum_size = Vector2(0, MobileUi.font_touch(48))
	_location_map_btn.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(_location_map_btn)
	_location_map_btn.pressed.connect(_on_choose_on_map)
	action_row.add_child(_location_map_btn)
	_location_use_btn = Button.new()
	_location_use_btn.text = "Use Current Location"
	_location_use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_location_use_btn.custom_minimum_size = Vector2(0, MobileUi.font_touch(48))
	_location_use_btn.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(_location_use_btn)
	_location_use_btn.pressed.connect(_on_use_current_location)
	action_row.add_child(_location_use_btn)

	_location_summary = _make_card()
	_location_summary.visible = false
	var sum_col := _card_body(_location_summary)
	var sel_cap := _field_caption("Selected Location")
	sum_col.add_child(sel_cap)
	_location_summary_title = Label.new()
	_location_summary_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location_summary_title.add_theme_font_size_override("font_size", 19)
	_location_summary_title.add_theme_color_override("font_color", COL_GOLD)
	sum_col.add_child(_location_summary_title)
	_location_summary_addr = Label.new()
	_location_summary_addr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location_summary_addr.add_theme_font_size_override("font_size", 15)
	_location_summary_addr.add_theme_color_override("font_color", COL_SUPPORT)
	sum_col.add_child(_location_summary_addr)
	var change_btn := Button.new()
	change_btn.text = "Change Location"
	change_btn.custom_minimum_size = Vector2(0, 48)
	change_btn.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(change_btn)
	change_btn.pressed.connect(func() -> void:
		_clear_resolved_location()
		if _location_search:
			_location_search.grab_focus()
	)
	sum_col.add_child(change_btn)
	_location_fields.add_child(_location_summary)

	_location_fields.add_child(_field_caption("Unlock radius"))
	_location_radius_row = HBoxContainer.new()
	_location_radius_row.add_theme_constant_override("separation", 6)
	_location_fields.add_child(_location_radius_row)
	for meters in LocationHelper.RADIUS_OPTIONS:
		var rb := Button.new()
		rb.text = LocationHelper.format_radius(meters)
		rb.toggle_mode = true
		rb.button_pressed = meters == _location_radius_m
		rb.custom_minimum_size = Vector2(0, 48)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.focus_mode = Control.FOCUS_NONE
		_style_secondary_button(rb)
		var mcopy: int = meters
		rb.pressed.connect(func() -> void:
			_location_radius_m = mcopy
			_sync_radius_buttons()
			_refresh_location_summary()
			_refresh_summary()
			_update_validation()
		)
		_location_radius_row.add_child(rb)

	_location_status = Label.new()
	_location_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location_status.add_theme_font_size_override("font_size", 15)
	_location_status.add_theme_color_override("font_color", COL_SUPPORT)
	_location_status.text = "Select a location from search results or the map."
	_location_fields.add_child(_location_status)

	if _location_debounce == null:
		_location_debounce = Timer.new()
		_location_debounce.one_shot = true
		_location_debounce.wait_time = 0.35
		_location_debounce.timeout.connect(_run_location_search)
		add_child(_location_debounce)
	return card


func _sync_radius_buttons() -> void:
	if _location_radius_row == null:
		return
	var i := 0
	for child in _location_radius_row.get_children():
		if child is Button and i < LocationHelper.RADIUS_OPTIONS.size():
			(child as Button).set_pressed_no_signal(LocationHelper.RADIUS_OPTIONS[i] == _location_radius_m)
		i += 1


func _sync_location_visibility() -> void:
	var on := _location_toggle != null and _location_toggle.button_pressed
	_has_location_lock = on
	if _location_fields:
		_location_fields.visible = on
	if not on:
		_hide_location_suggestions()
	_refresh_location_summary()


func _refresh_location_summary() -> void:
	if _location_summary == null:
		return
	_location_summary.visible = _has_location_lock and _location_fix_ok
	if _location_summary_title:
		_location_summary_title.text = _location_name if not _location_name.is_empty() else "Selected place"
	if _location_summary_addr:
		var line := _location_address
		if line.is_empty():
			line = "Unlock within %s" % LocationHelper.format_radius(_location_radius_m)
		else:
			line = "%s\nUnlock within %s" % [line, LocationHelper.format_radius(_location_radius_m)]
		_location_summary_addr.text = line
	if _location_status:
		if not _has_location_lock:
			_location_status.text = ""
		elif _location_fix_ok:
			_location_status.text = "Place locked · unlock within %s" % LocationHelper.format_radius(_location_radius_m)
		else:
			_location_status.text = "Select a location from the search results or choose one on the map."


func _clear_resolved_location() -> void:
	_location_fix_ok = false
	_location_name = ""
	_location_address = ""
	_location_lat = 0.0
	_location_lng = 0.0
	_refresh_location_summary()
	_refresh_summary()
	_update_validation()


func _apply_resolved_place(place: Dictionary) -> void:
	_location_lat = float(place.get("lat", 0.0))
	_location_lng = float(place.get("lng", 0.0))
	_location_name = str(place.get("name", "Selected place")).strip_edges()
	_location_address = str(place.get("address", "")).strip_edges()
	_location_fix_ok = is_finite(_location_lat) and is_finite(_location_lng)
	_hide_location_suggestions()
	if _location_search:
		_location_search.text = ""
		_location_search.release_focus()
	_refresh_location_summary()
	_refresh_summary()
	_update_validation()


func _on_location_search_changed(_t: String) -> void:
	## Typing free text never counts as a resolved place.
	if _location_fix_ok:
		## Keep resolved place until user picks a new result; don't wipe on every keystroke.
		pass
	if _location_debounce:
		_location_debounce.start()


func _run_location_search() -> void:
	if _location_search == null:
		return
	var q := _location_search.text.strip_edges()
	if q.length() < LocationSearchService.MIN_QUERY_LEN:
		_hide_location_suggestions()
		return
	_location_search_token = _location_search_service.next_token()
	var token := _location_search_token
	if _location_search_spinner:
		_location_search_spinner.visible = true
	var result: Dictionary = await _location_search_service.search_places(q, token)
	if not is_inside_tree() or not _location_search_service.is_current(token):
		return
	if _location_search_spinner:
		_location_search_spinner.visible = false
	if not bool(result.get("ok", false)):
		_location_status.text = "Couldn't search locations. Try again."
		_hide_location_suggestions()
		return
	_show_location_suggestions(result.get("results", []) as Array)


func _show_location_suggestions(results: Array) -> void:
	_hide_location_suggestions()
	if _location_suggestions == null:
		return
	if results.is_empty():
		_location_status.text = "No places found. Try a different search."
		return
	for place in results:
		if typeof(place) != TYPE_DICTIONARY:
			continue
		var btn := Button.new()
		var name := str(place.get("name", ""))
		var addr := str(place.get("address", ""))
		btn.text = name if addr.is_empty() else "%s\n%s" % [name, addr]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 56)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.focus_mode = Control.FOCUS_NONE
		_style_secondary_button(btn)
		var captured: Dictionary = (place as Dictionary).duplicate(true)
		btn.pressed.connect(func() -> void:
			_apply_resolved_place(captured)
		)
		_location_suggestions.add_child(btn)
	_location_suggestions.visible = true


func _hide_location_suggestions() -> void:
	if _location_suggestions == null:
		return
	for c in _location_suggestions.get_children():
		c.queue_free()
	_location_suggestions.visible = false


func _on_choose_on_map() -> void:
	## Create map only while open — release when closed.
	if _map_picker != null and is_instance_valid(_map_picker):
		return
	MobileUi.release_text_focus(self)
	var initial := {}
	if _location_fix_ok:
		initial = {
			"lat": _location_lat,
			"lng": _location_lng,
			"name": _location_name,
			"address": _location_address,
			"ok": true,
		}
	_map_picker = MapLocationPicker.new()
	get_tree().root.add_child(_map_picker)
	_map_picker.confirmed.connect(func(place: Dictionary) -> void:
		_apply_resolved_place(place)
		_map_picker = null
	)
	_map_picker.cancelled.connect(func() -> void:
		_map_picker = null
	)
	_map_picker.setup(initial, _location_radius_m, _location_search_service)


func _on_use_current_location() -> void:
	## GPS permission only for this sender action — never for typing search.
	_location_status.text = "Allow location access to use your current position for this lock."
	_location_use_btn.disabled = true
	if OS.get_name() == "Android":
		var status := LocationHelper.request_permission_if_needed()
		if status != "granted":
			await get_tree().create_timer(0.35).timeout
			status = LocationHelper.permission_status()
		if status != "granted":
			_location_status.text = "Location access is needed only when using your current position."
			_location_use_btn.disabled = false
			_update_validation()
			return
	var fix: Dictionary = LocationHelper.get_current_fix(true)
	if not bool(fix.get("ok", false)):
		_location_status.text = str(fix.get("error", "We couldn't verify your location. Try again."))
		_location_use_btn.disabled = false
		_update_validation()
		return
	var lat := float(fix.get("lat", 0.0))
	var lng := float(fix.get("lng", 0.0))
	_location_status.text = "Resolving place…"
	var token := _location_search_service.next_token()
	var rev: Dictionary = await _location_search_service.reverse_geocode(lat, lng, token)
	_location_use_btn.disabled = false
	if bool(rev.get("ok", false)) and typeof(rev.get("place")) == TYPE_DICTIONARY:
		var place: Dictionary = (rev.get("place") as Dictionary).duplicate(true)
		place["lat"] = lat
		place["lng"] = lng
		_apply_resolved_place(place)
	else:
		_apply_resolved_place({
			"name": "Current place",
			"address": "",
			"lat": lat,
			"lng": lng,
		})


func _build_password_card() -> PanelContainer:
	var card := _make_card()
	var col := _card_body(card)
	col.add_child(_section_heading("Magic Password"))

	var toggle_row := HBoxContainer.new()
	toggle_row.custom_minimum_size = Vector2(0, 56)
	col.add_child(toggle_row)
	var toggle_label := Label.new()
	toggle_label.text = "Require a Magic Password"
	toggle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toggle_label.add_theme_font_size_override("font_size", 19)
	toggle_label.add_theme_color_override("font_color", COL_TEXT)
	toggle_row.add_child(toggle_label)
	_pw_toggle = CheckButton.new()
	_pw_toggle.custom_minimum_size = Vector2(72, 48)
	_pw_toggle.focus_mode = Control.FOCUS_NONE
	_pw_toggle.toggled.connect(func(on: bool) -> void:
		_pw_fields.visible = on
		if not on:
			_pw_edit.text = ""
			_pw2_edit.text = ""
		_refresh_summary()
		_update_validation()
	)
	toggle_row.add_child(_pw_toggle)

	_pw_fields = VBoxContainer.new()
	_pw_fields.visible = false
	_pw_fields.add_theme_constant_override("separation", 10)
	col.add_child(_pw_fields)

	var help := Label.new()
	help.text = "The recipient will need this password every time they open the scroll."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", COL_SUPPORT)
	_pw_fields.add_child(help)

	_pw_fields.add_child(_field_caption("Magic Password"))
	var pw_row := HBoxContainer.new()
	pw_row.add_theme_constant_override("separation", 8)
	_pw_fields.add_child(pw_row)
	_pw_edit = LineEdit.new()
	_pw_edit.secret = true
	_pw_edit.placeholder_text = "Enter password"
	_pw_edit.custom_minimum_size = Vector2(0, 56)
	_pw_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pw_edit.add_theme_font_size_override("font_size", 19)
	_style_line_edit(_pw_edit)
	_pw_edit.text_changed.connect(func(_t: String) -> void: _update_validation())
	pw_row.add_child(_pw_edit)
	_pw_show = Button.new()
	_pw_show.text = "👁"
	_pw_show.custom_minimum_size = Vector2(52, 54)
	_pw_show.focus_mode = Control.FOCUS_NONE
	_style_icon_button(_pw_show)
	_pw_show.pressed.connect(func() -> void:
		_pw_edit.secret = not _pw_edit.secret
	)
	pw_row.add_child(_pw_show)

	_pw_fields.add_child(_field_caption("Confirm Password"))
	var pw2_row := HBoxContainer.new()
	pw2_row.add_theme_constant_override("separation", 8)
	_pw_fields.add_child(pw2_row)
	_pw2_edit = LineEdit.new()
	_pw2_edit.secret = true
	_pw2_edit.placeholder_text = "Confirm password"
	_pw2_edit.custom_minimum_size = Vector2(0, 56)
	_pw2_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pw2_edit.add_theme_font_size_override("font_size", 19)
	_style_line_edit(_pw2_edit)
	_pw2_edit.text_changed.connect(func(_t: String) -> void: _update_validation())
	pw2_row.add_child(_pw2_edit)
	_pw2_show = Button.new()
	_pw2_show.text = "👁"
	_pw2_show.custom_minimum_size = Vector2(52, 54)
	_pw2_show.focus_mode = Control.FOCUS_NONE
	_style_icon_button(_pw2_show)
	_pw2_show.pressed.connect(func() -> void:
		_pw2_edit.secret = not _pw2_edit.secret
	)
	pw2_row.add_child(_pw2_show)

	var warn := Label.new()
	warn.text = "Important: Share this password privately. You can reveal it later from your Sent Scrolls."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_font_size_override("font_size", 16)
	warn.add_theme_color_override("font_color", COL_WARN)
	_pw_fields.add_child(warn)
	return card


func _build_summary_card() -> PanelContainer:
	var card := _make_card()
	var col := _card_body(card)
	col.add_child(_section_heading("Ready Check"))
	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override("font_size", 16)
	_summary_label.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(_summary_label)
	return card


func _build_bottom_actions() -> PanelContainer:
	_bottom_area = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.12, 0.96)
	style.border_color = COL_GOLD_MUTED
	style.border_width_top = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_bottom_area.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_bottom_area.add_child(col)

	_preview_btn = Button.new()
	_preview_btn.text = "Preview Scroll"
	_preview_btn.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.TOUCH_SECONDARY_H))
	_preview_btn.focus_mode = Control.FOCUS_NONE
	_preview_btn.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BUTTON))
	_style_secondary_button(_preview_btn)
	_preview_btn.pressed.connect(_on_preview_pressed)
	col.add_child(_preview_btn)

	_send_btn = Button.new()
	_send_btn.text = "Send Scroll"
	_send_btn.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.TOUCH_PRIMARY_H))
	_send_btn.focus_mode = Control.FOCUS_NONE
	_send_btn.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BUTTON))
	_style_primary_button(_send_btn)
	_send_btn.pressed.connect(_on_send_pressed)
	col.add_child(_send_btn)
	return _bottom_area


func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.border_color = COL_GOLD_MUTED
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = MobileUi.CARD_PAD
	style.content_margin_right = MobileUi.CARD_PAD
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)
	return card


func _card_body(card: PanelContainer) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.clip_contents = true
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	return col


func _section_heading(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 19)
	lab.add_theme_color_override("font_color", COL_GOLD)
	if _title_font:
		lab.add_theme_font_override("font", _title_font)
	return lab


func _field_caption(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", COL_SUPPORT)
	return lab


func _style_icon_button(b: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.14, 0.28, 0.95)
	style.border_color = COL_GOLD_MUTED
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.30, 0.18, 0.36, 0.98)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", COL_GOLD)


func _style_row_button(b: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.16, 0.95)
	style.border_color = Color(0.55, 0.42, 0.28, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.16, 0.10, 0.22, 0.98)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", style)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_disabled_color", COL_SUPPORT)
	b.add_theme_font_size_override("font_size", 19)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _style_line_edit(le: LineEdit) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.06, 0.14, 0.98)
	style.border_color = Color(0.55, 0.42, 0.28, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	le.add_theme_stylebox_override("normal", style)
	le.add_theme_stylebox_override("focus", style)
	le.add_theme_color_override("font_color", COL_TEXT)
	le.add_theme_color_override("font_placeholder_color", Color(0.65, 0.58, 0.72))


func _style_text_edit(te: TextEdit) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.06, 0.14, 0.98)
	style.border_color = Color(0.55, 0.42, 0.28, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	te.add_theme_stylebox_override("normal", style)
	te.add_theme_stylebox_override("focus", style)
	te.add_theme_color_override("font_color", COL_TEXT)


func _style_primary_button(b: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BURGUNDY
	style.border_color = COL_GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = COL_BURGUNDY_HOVER
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var disabled := style.duplicate()
	disabled.bg_color = COL_DISABLED
	disabled.border_color = Color(0.4, 0.35, 0.3, 0.5)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", COL_GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.55, 0.5))


func _style_secondary_button(b: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.12, 0.24, 0.95)
	style.border_color = COL_GOLD_MUTED
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.24, 0.16, 0.30, 0.98)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", COL_TEXT)


func _apply_chrome_inset() -> void:
	offset_bottom = -float(maxi(0, bottom_chrome_inset))


func _apply_safe_area() -> void:
	if _safe_margin:
		## Bottom chrome is handled by bottom_chrome_inset on this Control.
		SafeAreaHelper.apply_to_margin(_safe_margin, MobileUi.SCREEN_GUTTER, 10, 10)


func _sync_delivery_visibility() -> void:
	var immediate := _open_immediately != null and _open_immediately.button_pressed
	if _delivery_controls:
		_delivery_controls.visible = not immediate
		_delivery_controls.modulate.a = 1.0
	if _date_btn:
		_date_btn.disabled = immediate
	if _time_btn:
		_time_btn.disabled = immediate


func _resize_message_box() -> void:
	if _message_edit == null:
		return
	var vp_h := get_viewport().get_visible_rect().size.y
	## Compact Compose density: ~180–230 logical px message field.
	var h := clampf(vp_h * 0.22, 180.0, 230.0)
	_message_edit.custom_minimum_size = Vector2(0, h)


func _refresh_recipient_row() -> void:
	if _recipient_btn == null:
		return
	## Short label text — ellipsis handles overflow inside the bounded row.
	if _selected_friend.is_empty():
		_recipient_btn.text = "Choose a friend  ›"
	else:
		var name := str(_selected_friend.get("display_name", "Friend"))
		var user := str(_selected_friend.get("username", ""))
		if user.is_empty():
			_recipient_btn.text = "%s  ›" % name
		else:
			_recipient_btn.text = "%s · @%s  ›" % [name, user]


func _refresh_schedule_labels() -> void:
	if _date_btn:
		_date_btn.text = "%s                    ›" % _format_date(_unlock_date)
	if _time_btn:
		_time_btn.text = "%s                    ›" % _format_time(_unlock_hour, _unlock_minute)


func _refresh_summary() -> void:
	if _summary_label == null:
		return
	var to_name := str(_selected_friend.get("display_name", "Not chosen"))
	var immediate := _open_immediately != null and _open_immediately.button_pressed
	var schedule_label := "Immediately" if immediate else (
		"%s at %s" % [_format_date(_unlock_date), _format_time(_unlock_hour, _unlock_minute)]
	)
	var loc_on := _location_toggle != null and _location_toggle.button_pressed
	var lines: PackedStringArray = PackedStringArray([
		"Recipient: %s" % to_name,
		"Opens: %s" % schedule_label,
	])
	if loc_on:
		var place := _location_name if not _location_name.is_empty() else "Not selected"
		if not _location_address.is_empty():
			place = "%s, %s" % [_location_name, _location_address]
		if immediate:
			lines.append("Location: %s" % place)
			lines.append("Unlock radius: %s" % LocationHelper.format_radius(_location_radius_m))
		else:
			lines.append("Available after: %s" % schedule_label)
			lines.append("And only within %s of %s" % [LocationHelper.format_radius(_location_radius_m), _location_name if not _location_name.is_empty() else "selected place"])
	var pw := "Required" if (_pw_toggle and _pw_toggle.button_pressed) else "Not required"
	lines.append("Magic Password: %s" % pw)
	_summary_label.text = "\n".join(lines)


func _timezone_friendly_name() -> String:
	var tz: Dictionary = Time.get_time_zone_from_system()
	var name := str(tz.get("name", "")).strip_edges()
	if name.is_empty():
		var bias := int(tz.get("bias", 0))
		var sign := "+" if bias <= 0 else "-"
		var abs_bias := absi(bias)
		name = "UTC%s%02d:%02d" % [sign, abs_bias / 60, abs_bias % 60]
	return name


func _format_date(d: Dictionary) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var m := clampi(int(d.get("month", 1)), 1, 12)
	return "%s %d, %d" % [months[m - 1], int(d.get("day", 1)), int(d.get("year", 2026))]


func _format_time(hour: int, minute: int) -> String:
	var h := hour % 24
	var suffix := "AM"
	var display := h
	if h == 0:
		display = 12
	elif h == 12:
		suffix = "PM"
	elif h > 12:
		display = h - 12
		suffix = "PM"
	return "%d:%02d %s" % [display, minute, suffix]


func _compute_unlock_unix() -> int:
	if _open_immediately and _open_immediately.button_pressed:
		return int(Time.get_unix_time_from_system())
	var dt := {
		"year": int(_unlock_date.year),
		"month": int(_unlock_date.month),
		"day": int(_unlock_date.day),
		"hour": _unlock_hour,
		"minute": _unlock_minute,
		"second": 0,
	}
	return int(Time.get_unix_time_from_datetime_dict(dt))


func _password_value() -> String:
	if _pw_toggle == null or not _pw_toggle.button_pressed:
		return ""
	return _pw_edit.text


func _validation_error() -> String:
	if friends.is_empty():
		return "Add a friend before composing a scroll."
	if _selected_friend.is_empty() or str(_selected_friend.get("id", "")).is_empty():
		return "Please choose a friend."
	if _message_edit == null or _message_edit.text.strip_edges().is_empty():
		return "Your scroll needs a message."
	if _open_immediately == null or not _open_immediately.button_pressed:
		var unlock := _compute_unlock_unix()
		if unlock < int(Time.get_unix_time_from_system()) - 30:
			return "Choose an unlock time in the future."
	if _pw_toggle and _pw_toggle.button_pressed:
		var p1 := _pw_edit.text
		var p2 := _pw2_edit.text
		if p1.length() < MIN_PASSWORD or p1.length() > MAX_PASSWORD:
			return "Magic password must be 4–64 characters."
		if p1 != p2:
			return "Passwords do not match."
	if _location_toggle and _location_toggle.button_pressed:
		if not _location_fix_ok or not is_finite(_location_lat) or not is_finite(_location_lng):
			return "Select a location from the search results or choose one on the map."
		if _location_name.strip_edges().is_empty():
			return "Select a location from the search results or choose one on the map."
	return ""


func _update_validation() -> void:
	var err := _validation_error()
	if _validation_label:
		if err.is_empty():
			_validation_label.visible = false
			_validation_label.text = ""
		else:
			# Keep quiet until user interacts; still disable send.
			pass
	if _send_btn:
		_send_btn.disabled = (not err.is_empty()) or _sending
	if _preview_btn:
		_preview_btn.disabled = _sending or (_message_edit != null and _message_edit.text.strip_edges().is_empty())


func _set_inline_error(msg: String) -> void:
	if _validation_label:
		_validation_label.visible = true
		_validation_label.text = msg


func _apply_relative_unlock(offset_secs: int) -> void:
	var target := int(Time.get_unix_time_from_system()) + offset_secs
	var dt := Time.get_datetime_dict_from_unix_time(target)
	_unlock_date = {"year": int(dt.year), "month": int(dt.month), "day": int(dt.day)}
	_unlock_hour = int(dt.hour)
	_unlock_minute = int(dt.minute)
	_refresh_schedule_labels()
	_refresh_summary()
	_update_validation()


func _open_friend_picker() -> void:
	_clear_overlay()
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeAreaHelper.apply_to_margin(host, 24, 24, 24)
	_overlay.add_child(host)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.16, 0.98)
	style.border_color = COL_GOLD_MUTED
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	host.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Choose a Friend"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	MobileUi.configure_scroll(list_scroll)
	col.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	list_scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)

	if friends.is_empty():
		var empty := Label.new()
		empty.text = "No accepted friends yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 19)
		empty.add_theme_color_override("font_color", COL_SUPPORT)
		list.add_child(empty)
	else:
		for f in friends:
			if typeof(f) != TYPE_DICTIONARY:
				continue
			var friend: Dictionary = f
			var row := Button.new()
			row.custom_minimum_size = Vector2(0, 60)
			row.focus_mode = Control.FOCUS_NONE
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.text = "%s  ·  @%s" % [str(friend.get("display_name", "")), str(friend.get("username", ""))]
			_style_row_button(row)
			row.pressed.connect(func() -> void:
				_selected_friend = friend.duplicate(true)
				_refresh_recipient_row()
				_refresh_summary()
				_update_validation()
				_hide_overlay()
			)
			list.add_child(row)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 52)
	cancel.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(cancel)
	cancel.pressed.connect(_hide_overlay)
	col.add_child(cancel)


func _open_date_picker() -> void:
	if _open_immediately.button_pressed:
		return
	_clear_overlay()
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := _modal_box()
	_overlay.add_child(box.get_meta("_modal_host"))
	var col: VBoxContainer = box.get_child(0)
	col.add_child(_modal_title("Unlock Date"))

	var year := _make_spin("Year", 2024, 2100, int(_unlock_date.year))
	var month := _make_spin("Month", 1, 12, int(_unlock_date.month))
	var day := _make_spin("Day", 1, 31, int(_unlock_date.day))
	col.add_child(year.root)
	col.add_child(month.root)
	col.add_child(day.root)

	col.add_child(_modal_action("Save Date", func() -> void:
		_unlock_date = {
			"year": int(year.spin.value),
			"month": int(month.spin.value),
			"day": int(day.spin.value),
		}
		_refresh_schedule_labels()
		_refresh_summary()
		_update_validation()
		_hide_overlay()
	))
	col.add_child(_modal_action("Cancel", _hide_overlay, false))


func _open_time_picker() -> void:
	if _open_immediately.button_pressed:
		return
	_clear_overlay()
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := _modal_box()
	_overlay.add_child(box.get_meta("_modal_host"))
	var col: VBoxContainer = box.get_child(0)
	col.add_child(_modal_title("Unlock Time"))

	var hour12 := _unlock_hour % 12
	if hour12 == 0:
		hour12 = 12
	var is_pm := _unlock_hour >= 12
	var hour := _make_spin("Hour", 1, 12, hour12)
	var minute := _make_spin("Minute", 0, 59, _unlock_minute)
	col.add_child(hour.root)
	col.add_child(minute.root)

	var ampm := OptionButton.new()
	ampm.custom_minimum_size = Vector2(0, 56)
	ampm.add_item("AM")
	ampm.add_item("PM")
	ampm.select(1 if is_pm else 0)
	ampm.add_theme_font_size_override("font_size", 18)
	col.add_child(ampm)

	col.add_child(_modal_action("Save Time", func() -> void:
		var h := int(hour.spin.value) % 12
		if ampm.selected == 1:
			h += 12
		if ampm.selected == 0 and int(hour.spin.value) == 12:
			h = 0
		if ampm.selected == 1 and int(hour.spin.value) == 12:
			h = 12
		_unlock_hour = h
		_unlock_minute = int(minute.spin.value)
		_refresh_schedule_labels()
		_refresh_summary()
		_update_validation()
		_hide_overlay()
	))
	col.add_child(_modal_action("Cancel", _hide_overlay, false))


func _make_spin(label: String, min_v: int, max_v: int, value: int) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.add_child(_field_caption(label))
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = value
	spin.custom_minimum_size = Vector2(0, 56)
	spin.add_theme_font_size_override("font_size", 18)
	root.add_child(spin)
	return {"root": root, "spin": spin}


func _modal_box(_pos: Vector2 = Vector2.ZERO, _size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeAreaHelper.apply_to_margin(host, 28, 80, 40)
	# Caller adds this panel; wrap so layout fills safely on phones.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(0, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.16, 0.98)
	style.border_color = COL_GOLD_MUTED
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	# Attach host as metadata parent via temporary property on panel.
	panel.set_meta("_modal_host", host)
	host.add_child(panel)
	return panel


func _modal_title(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", COL_GOLD)
	return lab


func _modal_action(text: String, cb: Callable, primary: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	if primary:
		_style_primary_button(b)
	else:
		_style_secondary_button(b)
	b.pressed.connect(cb)
	return b


func _on_preview_pressed() -> void:
	if _message_edit.text.strip_edges().is_empty():
		_set_inline_error("Your scroll needs a message.")
		return
	preview_requested.emit(get_draft())


func _on_send_pressed() -> void:
	var err := _validation_error()
	if not err.is_empty():
		_set_inline_error(err)
		return
	_show_confirm_modal()


func _show_confirm_modal() -> void:
	_clear_overlay()
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := _modal_box()
	_overlay.add_child(box.get_meta("_modal_host"))
	var col: VBoxContainer = box.get_child(0)
	col.add_child(_modal_title("Ready to Send?"))
	var draft := get_draft()
	var when := "Immediately"
	if not bool(draft.open_immediately):
		when = "%s at %s" % [_format_date(_unlock_date), _format_time(_unlock_hour, _unlock_minute)]
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.text = "To:\n%s\n\nOpens:\n%s\n\nMagic Password:\n%s" % [
		str(draft.recipient_display_name),
		when,
		"Required" if bool(draft.has_password) else "Not Required",
	]
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", COL_TEXT)
	col.add_child(body)
	col.add_child(_modal_action("Send Scroll", func() -> void:
		_hide_overlay()
		send_requested.emit(get_draft())
	))
	col.add_child(_modal_action("Cancel", _hide_overlay, false))


func _show_sending_overlay() -> void:
	_clear_overlay()
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-280, -180)
	col.size = Vector2(560, 320)
	col.add_theme_constant_override("separation", 16)
	_overlay.add_child(col)
	var parchment := Label.new()
	parchment.text = "📜"
	parchment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parchment.add_theme_font_size_override("font_size", 64)
	col.add_child(parchment)
	var lab := Label.new()
	lab.text = "Sending your scroll…"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 22)
	lab.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(lab)
	var tw := create_tween().set_loops()
	tw.tween_property(parchment, "modulate:a", 0.35, 0.55)
	tw.tween_property(parchment, "modulate:a", 1.0, 0.55)


func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()


func _hide_overlay() -> void:
	_overlay.visible = false
	_clear_overlay()


func _ensure_focused_visible() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not (focus is Control):
		return
	if _scroll == null:
		return
	var ctrl := focus as Control
	if not _scroll.is_ancestor_of(ctrl):
		return
	var global_rect := ctrl.get_global_rect()
	var scroll_rect := _scroll.get_global_rect()
	var kb := SafeAreaHelper.keyboard_height_viewport()
	var visible_bottom := scroll_rect.position.y + scroll_rect.size.y - kb
	if global_rect.position.y + global_rect.size.y > visible_bottom - 12.0:
		var delta := (global_rect.position.y + global_rect.size.y) - (visible_bottom - 12.0)
		_scroll.scroll_vertical = int(_scroll.scroll_vertical + delta)
	elif global_rect.position.y < scroll_rect.position.y + 12.0:
		var delta2 := (scroll_rect.position.y + 12.0) - global_rect.position.y
		_scroll.scroll_vertical = int(maxi(_scroll.scroll_vertical - int(delta2), 0))


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return null
