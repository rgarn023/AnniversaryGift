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
const COL_CARD := Color(0.14, 0.09, 0.20, 0.55)
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
## Optional current-user profile for debug self-send (real account id).
var self_profile: Dictionary = {}
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
var _location_radius_slider: HSlider
var _location_radius_edit: LineEdit
var _location_radius_warn: Label
var _location_preset_row: HBoxContainer
var _radius_edit_syncing: bool = false

var _delivery_card: PanelContainer
var _location_card: PanelContainer
var _password_card: PanelContainer
var _attachments_card: PanelContainer
var _delivery_body: VBoxContainer
var _location_body: VBoxContainer
var _password_body: VBoxContainer
var _attachments_body: VBoxContainer
var _delivery_summary: Label
var _location_header_summary: Label
var _password_header_summary: Label
var _attachments_header_summary: Label
var _delivery_expanded: bool = true
var _location_expanded: bool = false
var _password_expanded: bool = false
var _attachments_expanded: bool = false
var _activity_expanded: bool = false
var _focus_expanded: bool = false

var _activity_card: PanelContainer
var _activity_body: VBoxContainer
var _activity_header_summary: Label
var _activity_toggle: CheckButton
var _activity_fields: VBoxContainer
var _activity_slider: HSlider
var _activity_edit: LineEdit
var _activity_km: float = ActivityLockHelper.DEFAULT_KM
var _activity_edit_syncing: bool = false

var _focus_card: PanelContainer
var _focus_body: VBoxContainer
var _focus_header_summary: Label
var _focus_toggle: CheckButton
var _focus_fields: VBoxContainer
var _focus_slider: HSlider
var _focus_edit: LineEdit
var _focus_hours: int = FocusLockHelper.DEFAULT_HOURS
var _focus_edit_syncing: bool = false

var _attachments: Array = []
var _attach_count_label: Label
var _attach_strip: HBoxContainer
var _attach_status: Label
var _image_preview: ImagePreviewOverlay
var _file_dialog: FileDialog
var _media_picker: MediaPickerHelper
var _last_validation: Dictionary = {}
var _pw2_user_edited: bool = false
var _pw2_syncing: bool = false

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


func setup(p_friends: Array, show_onboarding_chip: bool = false, draft: Dictionary = {}, p_self_profile: Dictionary = {}) -> void:
	friends = p_friends
	self_profile = p_self_profile.duplicate(true) if not p_self_profile.is_empty() else {}
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


func _self_send_enabled() -> bool:
	## Debug/test builds only — never expose in production release UI.
	if not BuildFlags.DEBUG_SELF_SEND:
		return false
	if not OS.is_debug_build():
		return false
	return not str(self_profile.get("id", "")).is_empty()


func _self_recipient_dict() -> Dictionary:
	return {
		"id": str(self_profile.get("id", "")),
		"display_name": str(self_profile.get("display_name", "Me")),
		"username": str(self_profile.get("username", "")),
		"is_self_test": true,
	}


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
		"activity_lock_enabled": _activity_toggle.button_pressed if _activity_toggle else false,
		"activity_target_km": _activity_km,
		"focus_lock_enabled": _focus_toggle.button_pressed if _focus_toggle else false,
		"focus_duration_hours": _focus_hours,
		"attachments": [],
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
				"username": str(draft.get("username", draft.get("recipient_username", ""))),
			}
			if _self_send_enabled() and rid == str(self_profile.get("id", "")):
				_selected_friend["is_self_test"] = true
				_selected_friend["display_name"] = str(self_profile.get("display_name", _selected_friend["display_name"]))
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
	_location_radius_m = AttachmentHelper.clamp_radius(int(draft.get("location_radius_m", LocationHelper.DEFAULT_RADIUS_M)))
	_location_fix_ok = bool(draft.get("location_fix_ok", false))
	_attachments = []  ## Attachments disabled in active UI.
	_activity_km = ActivityLockHelper.clamp_km(float(draft.get("activity_target_km", ActivityLockHelper.DEFAULT_KM)))
	_focus_hours = FocusLockHelper.clamp_hours(int(draft.get("focus_duration_hours", FocusLockHelper.DEFAULT_HOURS)))
	if _location_toggle:
		_location_toggle.set_pressed_no_signal(_has_location_lock)
	if _location_search and not _location_fix_ok:
		_location_search.text = ""
	_sync_location_visibility()
	_sync_radius_controls()
	_refresh_location_summary()
	_refresh_attachments_ui()
	if _activity_toggle:
		_activity_toggle.set_pressed_no_signal(bool(draft.get("activity_lock_enabled", false)))
		if _activity_fields:
			_activity_fields.visible = _activity_toggle.button_pressed
	_sync_activity_controls()
	if _focus_toggle:
		_focus_toggle.set_pressed_no_signal(bool(draft.get("focus_lock_enabled", false)))
		if _focus_fields:
			_focus_fields.visible = _focus_toggle.button_pressed
	_sync_focus_controls()
	_refresh_optional_summaries()
	_refresh_recipient_row()
	_refresh_schedule_labels()
	_sync_delivery_visibility()
	_refresh_summary()
	_update_validation()


func set_sending(active: bool) -> void:
	_sending = active
	if _send_btn:
		_send_btn.text = "Sending…" if active else "Send Scroll"
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
	if _image_preview != null and is_instance_valid(_image_preview) and _image_preview.visible:
		_image_preview.close_preview()
		return true
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

	## Fully transparent over shared chrome starfield — no tinted full-screen ColorRect.
	mouse_filter = Control.MOUSE_FILTER_STOP

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
	_form.add_child(_build_activity_card())
	_form.add_child(_build_focus_card())
	_form.add_child(_build_password_card())
	## Attachments removed from active product UI (backend preserved).
	_form.add_child(_build_summary_card())
	_refresh_optional_summaries()

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
	_delivery_card = _make_card()
	var col := _card_body(_delivery_card)
	col.add_child(_make_optional_header("When Should It Open?", "delivery"))
	_delivery_summary = Label.new()
	_delivery_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_delivery_summary.add_theme_font_size_override("font_size", 15)
	_delivery_summary.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(_delivery_summary)
	_delivery_body = VBoxContainer.new()
	_delivery_body.add_theme_constant_override("separation", 10)
	col.add_child(_delivery_body)
	var card := _delivery_card
	col = _delivery_body

	_open_immediately = CheckBox.new()
	_open_immediately.text = "Open Immediately"
	_open_immediately.button_pressed = true
	_open_immediately.custom_minimum_size = Vector2(0, MobileUi.font_touch(48))
	_open_immediately.focus_mode = Control.FOCUS_NONE
	_open_immediately.add_theme_font_size_override("font_size", 19)
	_open_immediately.add_theme_color_override("font_color", COL_TEXT)
	_open_immediately.toggled.connect(func(_on: bool) -> void:
		_sync_delivery_visibility()
		_refresh_optional_summaries()
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
	_delivery_body.visible = true
	_delivery_expanded = true
	return card


func _build_location_card() -> PanelContainer:
	_location_card = _make_card()
	var shell := _card_body(_location_card)
	shell.add_child(_make_optional_header("Location Lock", "location"))
	_location_header_summary = Label.new()
	_location_header_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location_header_summary.add_theme_font_size_override("font_size", 15)
	_location_header_summary.add_theme_color_override("font_color", COL_SUPPORT)
	shell.add_child(_location_header_summary)

	_location_body = VBoxContainer.new()
	_location_body.visible = false
	_location_body.add_theme_constant_override("separation", 10)
	shell.add_child(_location_body)
	var col := _location_body

	var blurb := Label.new()
	blurb.text = "Require your friend to be near a specific place to open this scroll."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 15)
	blurb.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(blurb)
	var info := Label.new()
	info.text = "ⓘ Location is checked only when needed."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.7, 0.64, 0.78, 0.9))
	col.add_child(info)

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
		_refresh_optional_summaries()
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

	_location_summary = PanelContainer.new()
	_location_summary.visible = false
	var sum_style := StyleBoxFlat.new()
	sum_style.bg_color = Color(0.12, 0.08, 0.18, 0.5)
	sum_style.set_corner_radius_all(12)
	sum_style.content_margin_left = 12
	sum_style.content_margin_right = 12
	sum_style.content_margin_top = 10
	sum_style.content_margin_bottom = 10
	_location_summary.add_theme_stylebox_override("panel", sum_style)
	var sum_col := VBoxContainer.new()
	sum_col.add_theme_constant_override("separation", 4)
	_location_summary.add_child(sum_col)
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
	var radius_row := HBoxContainer.new()
	radius_row.add_theme_constant_override("separation", 8)
	_location_fields.add_child(radius_row)
	var radius_prefix := Label.new()
	radius_prefix.text = "Radius:"
	radius_prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	radius_prefix.add_theme_font_size_override("font_size", 16)
	radius_prefix.add_theme_color_override("font_color", COL_TEXT)
	radius_row.add_child(radius_prefix)
	_location_radius_edit = LineEdit.new()
	_location_radius_edit.custom_minimum_size = Vector2(96, 48)
	_location_radius_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_location_radius_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_location_radius_edit.add_theme_font_size_override("font_size", 18)
	_style_line_edit(_location_radius_edit)
	_location_radius_edit.text_submitted.connect(func(_t: String) -> void: _commit_radius_edit())
	_location_radius_edit.focus_exited.connect(_commit_radius_edit)
	radius_row.add_child(_location_radius_edit)
	var unit := Label.new()
	unit.text = "m"
	unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unit.add_theme_font_size_override("font_size", 16)
	unit.add_theme_color_override("font_color", COL_SUPPORT)
	radius_row.add_child(unit)

	_location_radius_slider = HSlider.new()
	_location_radius_slider.min_value = LocationHelper.MIN_RADIUS_M
	_location_radius_slider.max_value = LocationHelper.MAX_RADIUS_M
	_location_radius_slider.step = 1
	_location_radius_slider.value = _location_radius_m
	_location_radius_slider.custom_minimum_size = Vector2(0, 36)
	_location_radius_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_location_radius_slider.value_changed.connect(_on_radius_slider_changed)
	_location_fields.add_child(_location_radius_slider)

	_location_preset_row = HBoxContainer.new()
	_location_preset_row.add_theme_constant_override("separation", 6)
	_location_fields.add_child(_location_preset_row)
	for meters in LocationHelper.RADIUS_OPTIONS:
		var rb := Button.new()
		rb.text = LocationHelper.format_radius(meters)
		rb.custom_minimum_size = Vector2(0, 44)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.focus_mode = Control.FOCUS_NONE
		_style_secondary_button(rb)
		var mcopy: int = meters
		rb.pressed.connect(func() -> void:
			_set_radius_m(mcopy)
		)
		_location_preset_row.add_child(rb)

	_location_radius_warn = Label.new()
	_location_radius_warn.visible = false
	_location_radius_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location_radius_warn.text = "Very small radii may be difficult to verify accurately with phone GPS."
	_location_radius_warn.add_theme_font_size_override("font_size", 14)
	_location_radius_warn.add_theme_color_override("font_color", COL_WARN)
	_location_fields.add_child(_location_radius_warn)

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
	_sync_radius_controls()
	return _location_card


func _sync_radius_buttons() -> void:
	_sync_radius_controls()


func _set_radius_m(meters: int) -> void:
	_location_radius_m = AttachmentHelper.clamp_radius(meters)
	_sync_radius_controls()
	_refresh_location_summary()
	_refresh_optional_summaries()
	_refresh_summary()
	_update_validation()
	if _map_picker != null and is_instance_valid(_map_picker):
		_map_picker.set_radius(_location_radius_m)


func _on_radius_slider_changed(v: float) -> void:
	if _radius_edit_syncing:
		return
	_set_radius_m(int(round(v)))


func _commit_radius_edit() -> void:
	if _location_radius_edit == null:
		return
	var parsed := AttachmentHelper.parse_radius_text(_location_radius_edit.text)
	if not bool(parsed.get("ok", false)):
		_location_status.text = str(parsed.get("error", "Enter a valid radius."))
		_sync_radius_controls()
		return
	_set_radius_m(int(parsed.value))


func _sync_radius_controls() -> void:
	_radius_edit_syncing = true
	if _location_radius_slider:
		_location_radius_slider.set_value_no_signal(float(_location_radius_m))
	if _location_radius_edit:
		_location_radius_edit.text = str(_location_radius_m)
	if _location_radius_warn:
		_location_radius_warn.visible = _location_radius_m < LocationHelper.SMALL_RADIUS_WARN_M
	_radius_edit_syncing = false


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
		_location_summary_addr.text = _location_address if not _location_address.is_empty() else "Resolved place"
	if _location_status:
		if not _has_location_lock:
			_location_status.text = ""
		elif _location_fix_ok:
			_location_status.text = "Place selected."
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
	_refresh_optional_summaries()
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
		var pname := str(place.get("name", ""))
		var addr := str(place.get("address", ""))
		var selected := _location_fix_ok and pname == _location_name
		btn.text = ("✓ 📍 %s\n     %s" % [pname, addr]) if not addr.is_empty() else ("✓ 📍 %s" % pname if selected else "📍 %s%s" % [pname, ("" if addr.is_empty() else "\n     " + addr)])
		if not selected:
			btn.text = "📍 %s" % pname if addr.is_empty() else "📍 %s\n     %s" % [pname, addr]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 64)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.focus_mode = Control.FOCUS_NONE
		_style_secondary_button(btn)
		if selected:
			btn.add_theme_color_override("font_color", COL_GOLD)
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
	elif LocationHelper.permission_status() == "granted" or OS.get_name() != "Android":
		## Prefer sender current location over unrelated hardcoded city when available.
		var fix0 := LocationHelper.get_current_fix(false)
		if bool(fix0.get("ok", false)):
			initial = {
				"lat": float(fix0.get("lat")),
				"lng": float(fix0.get("lng")),
				"name": "",
				"address": "",
				"ok": false,
				"center_only": true,
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
	if _location_use_btn == null:
		return
	if _location_use_btn.disabled:
		return
	_location_use_btn.disabled = true
	_location_use_btn.text = "Getting your location…"
	_location_status.text = "Getting your location…"
	if OS.get_name() == "Android":
		var status := LocationHelper.request_permission_if_needed()
		## Permission dialog is async — poll briefly for grant.
		var waits := 0
		while status != "granted" and waits < 20:
			await get_tree().create_timer(0.25).timeout
			status = LocationHelper.permission_status()
			waits += 1
			if waits == 1 and status != "granted":
				_location_status.text = "Allow location access to use your current position."
		if status != "granted":
			_location_status.text = "Location permission is required. Enable it in Android Settings if you previously denied it."
			_location_use_btn.text = "Use Current Location"
			_location_use_btn.disabled = false
			_update_validation()
			return
	## Prefer a fresh fix; fall back to last-known.
	var fix: Dictionary = await LocationHelper.get_fresh_fix(true)
	if not bool(fix.get("ok", false)):
		_location_status.text = str(fix.get("error", "We couldn't determine your location. Try again."))
		_location_use_btn.text = "Use Current Location"
		_location_use_btn.disabled = false
		_update_validation()
		return
	var lat := float(fix.get("lat", 0.0))
	var lng := float(fix.get("lng", 0.0))
	_location_status.text = "Resolving place…"
	var token := _location_search_service.next_token()
	var rev: Dictionary = await _location_search_service.reverse_geocode(lat, lng, token)
	_location_use_btn.text = "Use Current Location"
	_location_use_btn.disabled = false
	if bool(rev.get("ok", false)) and typeof(rev.get("place")) == TYPE_DICTIONARY:
		var place: Dictionary = (rev.get("place") as Dictionary).duplicate(true)
		place["lat"] = lat
		place["lng"] = lng
		_apply_resolved_place(place)
		_location_status.text = "Using your current location."
	else:
		_apply_resolved_place({
			"name": "Current location",
			"address": "",
			"lat": lat,
			"lng": lng,
		})
		_location_status.text = "Using your current location."


func _build_password_card() -> PanelContainer:
	_password_card = _make_card()
	var shell := _card_body(_password_card)
	shell.add_child(_make_optional_header("Magic Password", "password"))
	_password_header_summary = Label.new()
	_password_header_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_password_header_summary.add_theme_font_size_override("font_size", 15)
	_password_header_summary.add_theme_color_override("font_color", COL_SUPPORT)
	shell.add_child(_password_header_summary)
	_password_body = VBoxContainer.new()
	_password_body.visible = false
	_password_body.add_theme_constant_override("separation", 10)
	shell.add_child(_password_body)
	var col := _password_body
	var card := _password_card

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
			_pw2_syncing = true
			_pw_edit.text = ""
			_pw2_edit.text = ""
			_pw2_syncing = false
			_pw2_user_edited = false
		_refresh_optional_summaries()
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
	_pw_edit.text_changed.connect(func(_t: String) -> void:
		## Keep confirm in sync until the user edits it themselves.
		## Must not mark confirm as user-edited during programmatic sync
		## (that was leaving Send disabled after typing a password).
		if _pw2_edit and not _pw2_user_edited and _pw2_edit.text != _pw_edit.text:
			_pw2_syncing = true
			_pw2_edit.text = _pw_edit.text
			_pw2_syncing = false
		_update_validation()
	)
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
	_pw2_edit.text_changed.connect(func(_t: String) -> void:
		if not _pw2_syncing:
			_pw2_user_edited = true
		_update_validation()
	)
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



func _build_activity_card() -> PanelContainer:
	_activity_card = _make_card()
	var shell := _card_body(_activity_card)
	shell.add_child(_make_optional_header("Activity Lock", "activity"))
	_activity_header_summary = Label.new()
	_activity_header_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_activity_header_summary.add_theme_font_size_override("font_size", 15)
	_activity_header_summary.add_theme_color_override("font_color", COL_SUPPORT)
	shell.add_child(_activity_header_summary)
	_activity_body = VBoxContainer.new()
	_activity_body.visible = false
	_activity_body.add_theme_constant_override("separation", 10)
	shell.add_child(_activity_body)
	var help := Label.new()
	help.text = "Travel a set distance to unlock this scroll."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", COL_SUPPORT)
	_activity_body.add_child(help)
	var toggle_row := HBoxContainer.new()
	toggle_row.custom_minimum_size = Vector2(0, 56)
	_activity_body.add_child(toggle_row)
	var tl := Label.new()
	tl.text = "Require Activity Lock"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 19)
	tl.add_theme_color_override("font_color", COL_TEXT)
	toggle_row.add_child(tl)
	_activity_toggle = CheckButton.new()
	_activity_toggle.custom_minimum_size = Vector2(72, 48)
	_activity_toggle.focus_mode = Control.FOCUS_NONE
	_activity_toggle.toggled.connect(func(on: bool) -> void:
		_activity_fields.visible = on
		_refresh_optional_summaries()
		_update_validation()
	)
	toggle_row.add_child(_activity_toggle)
	_activity_fields = VBoxContainer.new()
	_activity_fields.visible = false
	_activity_fields.add_theme_constant_override("separation", 10)
	_activity_body.add_child(_activity_fields)
	_activity_fields.add_child(_field_caption("Distance to travel"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_activity_fields.add_child(row)
	_activity_edit = LineEdit.new()
	_activity_edit.custom_minimum_size = Vector2(96, 48)
	_activity_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_activity_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_activity_edit.add_theme_font_size_override("font_size", 18)
	_style_line_edit(_activity_edit)
	_activity_edit.text_submitted.connect(func(_t: String) -> void: _commit_activity_edit())
	_activity_edit.focus_exited.connect(_commit_activity_edit)
	row.add_child(_activity_edit)
	var unit := Label.new()
	unit.text = "km"
	unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unit.add_theme_font_size_override("font_size", 16)
	unit.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(unit)
	_activity_slider = HSlider.new()
	_activity_slider.min_value = ActivityLockHelper.MIN_KM
	_activity_slider.max_value = ActivityLockHelper.MAX_KM
	_activity_slider.step = 0.5
	_activity_slider.value = _activity_km
	_activity_slider.custom_minimum_size = Vector2(0, 36)
	_activity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity_slider.value_changed.connect(func(v: float) -> void:
		if _activity_edit_syncing:
			return
		_set_activity_km(float(v))
	)
	_activity_fields.add_child(_activity_slider)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	_activity_fields.add_child(presets)
	for km in ActivityLockHelper.PRESETS_KM:
		var b := Button.new()
		b.text = ActivityLockHelper.format_km(km)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_secondary_button(b)
		var captured := float(km)
		b.pressed.connect(func() -> void: _set_activity_km(captured))
		presets.add_child(b)
	_sync_activity_controls()
	return _activity_card


func _set_activity_km(km: float) -> void:
	_activity_km = ActivityLockHelper.clamp_km(km)
	_sync_activity_controls()
	_refresh_optional_summaries()
	_update_validation()


func _commit_activity_edit() -> void:
	if _activity_edit == null:
		return
	var parsed := ActivityLockHelper.parse_km_text(_activity_edit.text)
	if not bool(parsed.get("ok", false)):
		_sync_activity_controls()
		_update_validation()
		return
	_set_activity_km(float(parsed.value))


func _sync_activity_controls() -> void:
	_activity_edit_syncing = true
	if _activity_slider:
		_activity_slider.set_value_no_signal(_activity_km)
	if _activity_edit:
		if is_equal_approx(_activity_km, floor(_activity_km)):
			_activity_edit.text = str(int(_activity_km))
		else:
			_activity_edit.text = "%.1f" % _activity_km
	_activity_edit_syncing = false


func _build_focus_card() -> PanelContainer:
	_focus_card = _make_card()
	var shell := _card_body(_focus_card)
	shell.add_child(_make_optional_header("Focus Lock", "focus"))
	_focus_header_summary = Label.new()
	_focus_header_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_focus_header_summary.add_theme_font_size_override("font_size", 15)
	_focus_header_summary.add_theme_color_override("font_color", COL_SUPPORT)
	shell.add_child(_focus_header_summary)
	_focus_body = VBoxContainer.new()
	_focus_body.visible = false
	_focus_body.add_theme_constant_override("separation", 10)
	shell.add_child(_focus_body)
	var help := Label.new()
	help.text = "Stay off your phone for a set amount of time to unlock this scroll."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", COL_SUPPORT)
	_focus_body.add_child(help)
	var toggle_row := HBoxContainer.new()
	toggle_row.custom_minimum_size = Vector2(0, 56)
	_focus_body.add_child(toggle_row)
	var tl := Label.new()
	tl.text = "Require Focus Lock"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 19)
	tl.add_theme_color_override("font_color", COL_TEXT)
	toggle_row.add_child(tl)
	_focus_toggle = CheckButton.new()
	_focus_toggle.custom_minimum_size = Vector2(72, 48)
	_focus_toggle.focus_mode = Control.FOCUS_NONE
	_focus_toggle.toggled.connect(func(on: bool) -> void:
		_focus_fields.visible = on
		_refresh_optional_summaries()
		_update_validation()
	)
	toggle_row.add_child(_focus_toggle)
	_focus_fields = VBoxContainer.new()
	_focus_fields.visible = false
	_focus_fields.add_theme_constant_override("separation", 10)
	_focus_body.add_child(_focus_fields)
	_focus_fields.add_child(_field_caption("Focus time"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_focus_fields.add_child(row)
	_focus_edit = LineEdit.new()
	_focus_edit.custom_minimum_size = Vector2(96, 48)
	_focus_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_focus_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_focus_edit.add_theme_font_size_override("font_size", 18)
	_style_line_edit(_focus_edit)
	_focus_edit.text_submitted.connect(func(_t: String) -> void: _commit_focus_edit())
	_focus_edit.focus_exited.connect(_commit_focus_edit)
	row.add_child(_focus_edit)
	var unit := Label.new()
	unit.text = "hours"
	unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unit.add_theme_font_size_override("font_size", 16)
	unit.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(unit)
	_focus_slider = HSlider.new()
	_focus_slider.min_value = FocusLockHelper.MIN_HOURS
	_focus_slider.max_value = FocusLockHelper.MAX_HOURS
	_focus_slider.step = 1
	_focus_slider.value = _focus_hours
	_focus_slider.custom_minimum_size = Vector2(0, 36)
	_focus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus_slider.value_changed.connect(func(v: float) -> void:
		if _focus_edit_syncing:
			return
		_set_focus_hours(int(round(v)))
	)
	_focus_fields.add_child(_focus_slider)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	_focus_fields.add_child(presets)
	for h in FocusLockHelper.PRESETS_HOURS:
		var b := Button.new()
		b.text = "%dh" % int(h)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_secondary_button(b)
		var captured := int(h)
		b.pressed.connect(func() -> void: _set_focus_hours(captured))
		presets.add_child(b)
	_sync_focus_controls()
	return _focus_card


func _set_focus_hours(hours: int) -> void:
	_focus_hours = FocusLockHelper.clamp_hours(hours)
	_sync_focus_controls()
	_refresh_optional_summaries()
	_update_validation()


func _commit_focus_edit() -> void:
	if _focus_edit == null:
		return
	var parsed := FocusLockHelper.parse_hours_text(_focus_edit.text)
	if not bool(parsed.get("ok", false)):
		_sync_focus_controls()
		_update_validation()
		return
	_set_focus_hours(int(parsed.value))


func _sync_focus_controls() -> void:
	_focus_edit_syncing = true
	if _focus_slider:
		_focus_slider.set_value_no_signal(float(_focus_hours))
	if _focus_edit:
		_focus_edit.text = str(_focus_hours)
	_focus_edit_syncing = false


func _build_attachments_card() -> PanelContainer:
	## Kept for compatibility but not added to the active Compose form.
	_attachments_card = _make_card()
	var shell := _card_body(_attachments_card)
	shell.add_child(_make_optional_header("Attachments", "attachments"))
	_attachments_header_summary = Label.new()
	_attachments_header_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attachments_header_summary.add_theme_font_size_override("font_size", 15)
	_attachments_header_summary.add_theme_color_override("font_color", COL_SUPPORT)
	shell.add_child(_attachments_header_summary)
	_attachments_body = VBoxContainer.new()
	_attachments_body.visible = false
	_attachments_body.add_theme_constant_override("separation", 10)
	shell.add_child(_attachments_body)

	var help := Label.new()
	help.text = "Add up to %d photos to this scroll." % AttachmentHelper.MAX_ATTACHMENTS
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", COL_SUPPORT)
	_attachments_body.add_child(help)

	_attach_count_label = Label.new()
	_attach_count_label.add_theme_font_size_override("font_size", 15)
	_attach_count_label.add_theme_color_override("font_color", COL_TEXT)
	_attachments_body.add_child(_attach_count_label)

	_attach_strip = HBoxContainer.new()
	_attach_strip.add_theme_constant_override("separation", 8)
	_attachments_body.add_child(_attach_strip)

	var add_btn := Button.new()
	add_btn.text = "Add Photo"
	add_btn.custom_minimum_size = Vector2(0, 52)
	add_btn.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(add_btn)
	add_btn.pressed.connect(_on_add_photo_pressed)
	_attachments_body.add_child(add_btn)

	_attach_status = Label.new()
	_attach_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attach_status.add_theme_font_size_override("font_size", 14)
	_attach_status.add_theme_color_override("font_color", COL_SUPPORT)
	_attachments_body.add_child(_attach_status)
	_refresh_attachments_ui()
	return _attachments_card


func _make_optional_header(title: String, key: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", COL_GOLD)
	if _title_font:
		b.add_theme_font_override("font", _title_font)
	b.text = "▸  %s" % title
	b.set_meta("section_key", key)
	b.set_meta("section_title", title)
	b.pressed.connect(func() -> void:
		_toggle_optional_section(key, b)
	)
	return b


func _toggle_optional_section(key: String, header: Button) -> void:
	var expanded := false
	match key:
		"delivery":
			_delivery_expanded = not _delivery_expanded
			expanded = _delivery_expanded
			if _delivery_body:
				_delivery_body.visible = expanded
		"location":
			_location_expanded = not _location_expanded
			expanded = _location_expanded
			if _location_body:
				_location_body.visible = expanded
		"password":
			_password_expanded = not _password_expanded
			expanded = _password_expanded
			if _password_body:
				_password_body.visible = expanded
		"attachments":
			_attachments_expanded = not _attachments_expanded
			expanded = _attachments_expanded
			if _attachments_body:
				_attachments_body.visible = expanded
		"activity":
			_activity_expanded = not _activity_expanded
			expanded = _activity_expanded
			if _activity_body:
				_activity_body.visible = expanded
		"focus":
			_focus_expanded = not _focus_expanded
			expanded = _focus_expanded
			if _focus_body:
				_focus_body.visible = expanded
	var title := str(header.get_meta("section_title", key))
	header.text = ("%s  %s" % ["▾" if expanded else "▸", title])
	_refresh_optional_summaries()


func _refresh_optional_summaries() -> void:
	if _delivery_summary:
		var immediate := _open_immediately != null and _open_immediately.button_pressed
		_delivery_summary.text = "Immediately" if immediate else "%s at %s" % [_format_date(_unlock_date), _format_time(_unlock_hour, _unlock_minute)]
		_delivery_summary.visible = not _delivery_expanded
	if _location_header_summary:
		if _has_location_lock and _location_fix_ok:
			_location_header_summary.text = "%s · %s" % [_location_name, LocationHelper.format_radius(_location_radius_m)]
		elif _has_location_lock:
			_location_header_summary.text = "Enabled — choose a place"
		else:
			_location_header_summary.text = "Off"
		_location_header_summary.visible = not _location_expanded
	if _password_header_summary:
		_password_header_summary.text = "Enabled" if (_pw_toggle and _pw_toggle.button_pressed) else "Off"
		_password_header_summary.visible = not _password_expanded
	if _attachments_header_summary:
		_attachments_header_summary.visible = false
	if _activity_header_summary:
		if _activity_toggle and _activity_toggle.button_pressed:
			_activity_header_summary.text = ActivityLockHelper.format_km(_activity_km)
		else:
			_activity_header_summary.text = "Off"
		_activity_header_summary.visible = not _activity_expanded
	if _focus_header_summary:
		if _focus_toggle and _focus_toggle.button_pressed:
			_focus_header_summary.text = FocusLockHelper.format_hours(_focus_hours)
		else:
			_focus_header_summary.text = "Off"
		_focus_header_summary.visible = not _focus_expanded


func _refresh_attachments_ui() -> void:
	if _attach_count_label:
		_attach_count_label.text = "%d of %d photos" % [_attachments.size(), AttachmentHelper.MAX_ATTACHMENTS]
	if _attach_strip == null:
		return
	for c in _attach_strip.get_children():
		c.queue_free()
	for i in range(_attachments.size()):
		var item: Dictionary = _attachments[i]
		var path := str(item.get("path", ""))
		var wrap := VBoxContainer.new()
		wrap.custom_minimum_size = Vector2(84, 0)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(84, 84)
		btn.clip_contents = true
		btn.focus_mode = Control.FOCUS_NONE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.12, 0.08, 0.16, 0.55)
		st.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", st)
		if not path.is_empty() and FileAccess.file_exists(path):
			var tex := AttachmentHelper.make_thumbnail_texture(path, 180)
			if tex:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(tr)
		var idx := i
		btn.pressed.connect(func() -> void:
			_preview_attachment_at(idx)
		)
		wrap.add_child(btn)
		var rm := Button.new()
		rm.text = "Remove"
		rm.focus_mode = Control.FOCUS_NONE
		rm.custom_minimum_size = Vector2(0, 36)
		_style_secondary_button(rm)
		rm.pressed.connect(func() -> void:
			_remove_attachment_at(idx)
		)
		wrap.add_child(rm)
		_attach_strip.add_child(wrap)
	_refresh_optional_summaries()


func _on_add_photo_pressed() -> void:
	if _attachments.size() >= AttachmentHelper.MAX_ATTACHMENTS:
		_attach_status.text = "You can attach up to %d photos." % AttachmentHelper.MAX_ATTACHMENTS
		return
	_pick_photo_from_gallery()


func _pick_photo_from_gallery() -> void:
	var remaining := AttachmentHelper.MAX_ATTACHMENTS - _attachments.size()
	if remaining <= 0:
		_attach_status.text = "You can attach up to %d photos." % AttachmentHelper.MAX_ATTACHMENTS
		return
	_attach_status.text = "Opening photos…"
	if _media_picker == null:
		_media_picker = MediaPickerHelper.new()
		_media_picker.images_picked.connect(_on_photos_picked)
		_media_picker.cancelled.connect(func() -> void:
			_attach_status.text = ""
		)
	_media_picker.pick_images(remaining, self)


func _on_photos_picked(paths: PackedStringArray) -> void:
	if paths.is_empty():
		_attach_status.text = ""
		return
	_attach_status.text = "Preparing photos…"
	await get_tree().process_frame
	var added := 0
	for path in paths:
		if _attachments.size() >= AttachmentHelper.MAX_ATTACHMENTS:
			break
		var prepared: Dictionary = AttachmentHelper.compress_to_draft(str(path))
		if not bool(prepared.get("ok", false)):
			continue
		_attachments.append({
			"id": str(prepared.get("id", "")),
			"path": str(prepared.get("path", "")),
			"mime": str(prepared.get("mime", "image/jpeg")),
			"width": int(prepared.get("width", 0)),
			"height": int(prepared.get("height", 0)),
			"byte_size": int(prepared.get("byte_size", 0)),
		})
		added += 1
	if added <= 0:
		_attach_status.text = "Could not add that photo."
	else:
		_attach_status.text = "%d of %d photos" % [_attachments.size(), AttachmentHelper.MAX_ATTACHMENTS]
	_refresh_attachments_ui()
	_update_validation()


func _on_photo_file_selected(path: String) -> void:
	_on_photos_picked(PackedStringArray([path]))


func _remove_attachment_at(idx: int) -> void:
	if idx < 0 or idx >= _attachments.size():
		return
	var item: Dictionary = _attachments[idx]
	var path := str(item.get("path", ""))
	_attachments.remove_at(idx)
	if not path.is_empty() and path.begins_with(AttachmentHelper.DRAFT_DIR) and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_refresh_attachments_ui()
	_refresh_summary()


func _preview_attachment_at(idx: int) -> void:
	if idx < 0 or idx >= _attachments.size():
		return
	var item: Dictionary = _attachments[idx]
	var path := str(item.get("path", ""))
	if path.is_empty():
		return
	if _image_preview == null:
		_image_preview = ImagePreviewOverlay.new()
		get_tree().root.add_child(_image_preview)
	_image_preview.open_path(path, "Attachment %d" % (idx + 1))


func _clear_attachments() -> void:
	for item in _attachments:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var path := str(item.get("path", ""))
		if path.begins_with(AttachmentHelper.DRAFT_DIR) and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_attachments.clear()
	_refresh_attachments_ui()


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
	style.bg_color = Color(0.06, 0.04, 0.12, 0.42)
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
	## No heavy drop-shadow rectangles that read as purple bands on OLED.
	style.shadow_size = 0
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
	elif bool(_selected_friend.get("is_self_test", false)):
		_recipient_btn.text = "Self (Test)  ›"
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
		"Recipient:",
		to_name,
		"",
		"Opens:",
		schedule_label,
	])
	if loc_on:
		var place := _location_name if not _location_name.is_empty() else "Not selected"
		lines.append("")
		lines.append("Location:")
		lines.append(place)
		if not _location_address.is_empty():
			lines.append(_location_address)
		lines.append("")
		lines.append("Radius:")
		lines.append(LocationHelper.format_radius(_location_radius_m))
	var act_on := _activity_toggle != null and _activity_toggle.button_pressed
	if act_on:
		lines.append("")
		lines.append("Activity:")
		lines.append("Travel %s" % ActivityLockHelper.format_km(_activity_km))
	var focus_on := _focus_toggle != null and _focus_toggle.button_pressed
	if focus_on:
		lines.append("")
		lines.append("Focus:")
		lines.append("%s uninterrupted" % FocusLockHelper.format_hours(_focus_hours))
	var pw_on := _pw_toggle != null and _pw_toggle.button_pressed
	lines.append("")
	lines.append("Password:")
	lines.append("Required" if pw_on else "Not required")
	## Shared validation model — Ready Check never disagrees with Send.
	var v: Dictionary = _last_validation if not _last_validation.is_empty() else validate_compose_draft()
	var blockers: PackedStringArray = v.get("blockers", PackedStringArray())
	lines.append("")
	if blockers.is_empty():
		lines.append("Status:")
		lines.append("Ready to send")
	else:
		lines.append("Before sending:")
		for b in blockers:
			lines.append("• %s" % b)
	_summary_label.text = "\n".join(lines)
	_refresh_optional_summaries()


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
	## Interpret unlock fields as LOCAL wall-clock time.
	## Godot treats datetime dicts as UTC, so compensate with system timezone bias.
	var dt := {
		"year": int(_unlock_date.year),
		"month": int(_unlock_date.month),
		"day": int(_unlock_date.day),
		"hour": _unlock_hour,
		"minute": _unlock_minute,
		"second": 0,
	}
	var as_utc := int(Time.get_unix_time_from_datetime_dict(dt))
	var bias_min := int(Time.get_time_zone_from_system().get("bias", 0))
	return as_utc - bias_min * 60


func _password_value() -> String:
	if _pw_toggle == null or not _pw_toggle.button_pressed:
		return ""
	return _pw_edit.text


func validate_compose_draft() -> Dictionary:
	## Single source of truth for Ready Check + Send button.
	var blockers: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()
	var has_self := _self_send_enabled()
	if friends.is_empty() and not has_self:
		blockers.append("Add a friend before composing a scroll.")
	elif _selected_friend.is_empty() or str(_selected_friend.get("id", "")).is_empty():
		blockers.append("Select a recipient")
	if _message_edit == null or _message_edit.text.strip_edges().is_empty():
		blockers.append("Enter a message")
	if _open_immediately == null or not _open_immediately.button_pressed:
		var unlock := _compute_unlock_unix()
		var now_u := int(Time.get_unix_time_from_system())
		if unlock < now_u - 30:
			blockers.append("Set an unlock time in the future")
	if _pw_toggle != null and _pw_toggle.button_pressed:
		var p1 := _pw_edit.text if _pw_edit else ""
		var p2 := _pw2_edit.text if _pw2_edit else ""
		if p1.strip_edges().is_empty():
			blockers.append("Enter a Magic Password")
		elif p1.length() < MIN_PASSWORD or p1.length() > MAX_PASSWORD:
			blockers.append("Magic password must be 4–64 characters")
		elif _pw2_user_edited and p1 != p2:
			blockers.append("Confirm Magic Password — values do not match")
		elif (not _pw2_user_edited) and p2.strip_edges().is_empty() and not p1.strip_edges().is_empty():
			## Confirm still mirrors password; treat as valid.
			pass
		elif p1 != p2:
			blockers.append("Confirm Magic Password — values do not match")
	if _location_toggle != null and _location_toggle.button_pressed:
		if not _location_fix_ok or not is_finite(_location_lat) or not is_finite(_location_lng):
			blockers.append("Select a valid location")
		elif _location_name.strip_edges().is_empty():
			blockers.append("Select a valid location")
		if _location_radius_m < LocationHelper.MIN_RADIUS_M:
			blockers.append("Enter a radius of at least 1 m")
		elif _location_radius_m > LocationHelper.MAX_RADIUS_M:
			blockers.append("Radius can be at most 10 km")
		elif _location_radius_m < LocationHelper.SMALL_RADIUS_WARN_M:
			warnings.append("Very small radii may be difficult to verify accurately with phone GPS.")
	if _activity_toggle != null and _activity_toggle.button_pressed:
		if _activity_km < ActivityLockHelper.MIN_KM:
			blockers.append("Set Activity distance to at least 1 km.")
		elif _activity_km > ActivityLockHelper.MAX_KM:
			blockers.append("Activity distance can be at most 100 km.")
	if _focus_toggle != null and _focus_toggle.button_pressed:
		if _focus_hours < FocusLockHelper.MIN_HOURS or _focus_hours > FocusLockHelper.MAX_HOURS:
			blockers.append("Set Focus time between 1 and 24 hours.")
	## Attachments removed from active UI — never block.
	var valid := blockers.is_empty()
	var result := {
		"valid": valid,
		"blockers": blockers,
		"warnings": warnings,
		"ready_label": "Ready to send" if valid else (
			"Fix %d item%s before sending" % [blockers.size(), "" if blockers.size() == 1 else "s"]
		),
	}
	_last_validation = result
	print("compose_validation valid=%s reasons=%s" % [str(valid), str(blockers)])
	return result


func _validation_error() -> String:
	var v := validate_compose_draft()
	var blockers: PackedStringArray = v.get("blockers", PackedStringArray())
	if blockers.is_empty():
		return ""
	return blockers[0]


func _update_validation() -> void:
	var v := validate_compose_draft()
	var blockers: PackedStringArray = v.get("blockers", PackedStringArray())
	var warnings: PackedStringArray = v.get("warnings", PackedStringArray())
	if _validation_label:
		if blockers.is_empty():
			if warnings.is_empty():
				_validation_label.visible = true
				_validation_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.62))
				_validation_label.text = "Ready to send"
			else:
				_validation_label.visible = true
				_validation_label.add_theme_color_override("font_color", COL_WARN)
				_validation_label.text = "\n".join(warnings)
		else:
			_validation_label.visible = true
			_validation_label.add_theme_color_override("font_color", COL_ERROR)
			if blockers.size() == 1:
				_validation_label.text = blockers[0]
			else:
				var lines: PackedStringArray = PackedStringArray(["Fix %d items before sending:" % blockers.size()])
				for b in blockers:
					lines.append("• %s" % b)
				_validation_label.text = "\n".join(lines)
	if _send_btn:
		_send_btn.disabled = (not bool(v.get("valid", false))) or _sending
		_send_btn.text = "Sending…" if _sending else "Send Scroll"
	if _preview_btn:
		_preview_btn.disabled = _sending or (_message_edit != null and _message_edit.text.strip_edges().is_empty())
	_refresh_summary()


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

	if _self_send_enabled():
		var self_row := Button.new()
		self_row.custom_minimum_size = Vector2(0, 60)
		self_row.focus_mode = Control.FOCUS_NONE
		self_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		self_row.text = "Send to Myself (Test)"
		_style_row_button(self_row)
		self_row.pressed.connect(func() -> void:
			_selected_friend = _self_recipient_dict()
			_refresh_recipient_row()
			_refresh_summary()
			_update_validation()
			_hide_overlay()
		)
		list.add_child(self_row)
		var hint := Label.new()
		hint.text = "Uses your real account as recipient. All locks still apply."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", COL_SUPPORT)
		list.add_child(hint)
	if friends.is_empty() and not _self_send_enabled():
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
		## Commit visible SpinBox text before reading — do not require focus loss.
		_unlock_date = {
			"year": _commit_spin_value(year.spin),
			"month": _commit_spin_value(month.spin),
			"day": _commit_spin_value(day.spin),
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
	var help := Label.new()
	help.text = "Use + / − to set the time, then tap Save Time."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", COL_SUPPORT)
	col.add_child(help)

	## Mobile steppers — values live in these refs; Save never depends on focus-loss.
	var hour12 := _unlock_hour % 12
	if hour12 == 0:
		hour12 = 12
	var is_pm := _unlock_hour >= 12
	var state := {
		"hour12": hour12,
		"minute": _unlock_minute,
		"is_pm": is_pm,
	}
	var hour_ctrl := _make_time_stepper("Hour", 1, 12, hour12, func(v: int) -> void:
		state["hour12"] = v
	)
	var minute_ctrl := _make_time_stepper("Minute", 0, 59, _unlock_minute, func(v: int) -> void:
		state["minute"] = v
	, true)
	col.add_child(hour_ctrl)
	col.add_child(minute_ctrl)

	var ampm_row := HBoxContainer.new()
	ampm_row.add_theme_constant_override("separation", 10)
	col.add_child(ampm_row)
	var am_btn := Button.new()
	am_btn.text = "AM"
	am_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	am_btn.custom_minimum_size = Vector2(0, 56)
	am_btn.focus_mode = Control.FOCUS_NONE
	var pm_btn := Button.new()
	pm_btn.text = "PM"
	pm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm_btn.custom_minimum_size = Vector2(0, 56)
	pm_btn.focus_mode = Control.FOCUS_NONE
	var sync_ampm := func() -> void:
		if bool(state["is_pm"]):
			_style_primary_button(pm_btn)
			_style_secondary_button(am_btn)
		else:
			_style_primary_button(am_btn)
			_style_secondary_button(pm_btn)
	am_btn.pressed.connect(func() -> void:
		state["is_pm"] = false
		sync_ampm.call()
	)
	pm_btn.pressed.connect(func() -> void:
		state["is_pm"] = true
		sync_ampm.call()
	)
	ampm_row.add_child(am_btn)
	ampm_row.add_child(pm_btn)
	sync_ampm.call()

	var err := Label.new()
	err.text = ""
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.add_theme_font_size_override("font_size", 15)
	err.add_theme_color_override("font_color", Color(0.95, 0.45, 0.5))
	col.add_child(err)

	col.add_child(_modal_action("Save Time", func() -> void:
		## Explicitly commit CURRENT stepper values — no focus_exited / IME required.
		var h12 := int(state.get("hour12", 12))
		var mins := int(state.get("minute", 0))
		var pm := bool(state.get("is_pm", false))
		if h12 < 1 or h12 > 12:
			err.text = "Hour must be between 1 and 12."
			return
		if mins < 0 or mins > 59:
			err.text = "Minute must be between 0 and 59."
			return
		var h24 := h12 % 12
		if pm:
			h24 += 12
		if not pm and h12 == 12:
			h24 = 0
		if pm and h12 == 12:
			h24 = 12
		_unlock_hour = h24
		_unlock_minute = mins
		_refresh_schedule_labels()
		_refresh_summary()
		_update_validation()
		_hide_overlay()
	))
	col.add_child(_modal_action("Cancel", _hide_overlay, false))


func _commit_spin_value(spin: SpinBox) -> int:
	## Read CURRENT visible editor text even if the field still has focus.
	if spin == null:
		return 0
	var le := spin.get_line_edit()
	if le != null:
		var t := le.text.strip_edges()
		if t.is_valid_int():
			spin.value = clampf(float(t), spin.min_value, spin.max_value)
		le.release_focus()
	return int(spin.value)


func _make_spin(label: String, min_v: int, max_v: int, value: int) -> Dictionary:
	## Used by date picker. Time picker uses steppers instead.
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.add_child(_field_caption(label))
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = value
	spin.custom_minimum_size = Vector2(0, 56)
	spin.add_theme_font_size_override("font_size", 18)
	if spin.has_method("set_update_on_text_changed"):
		spin.set("update_on_text_changed", true)
	elif "update_on_text_changed" in spin:
		spin.update_on_text_changed = true
	root.add_child(spin)
	return {"root": root, "spin": spin}


func _make_time_stepper(label: String, min_v: int, max_v: int, value: int, on_change: Callable, pad2: bool = false) -> Control:
	## Tappable +/- steppers — no keyboard/SpinBox text commit needed.
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.add_child(_field_caption(label))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	var cur := {"v": clampi(value, min_v, max_v)}
	var val_lab := Label.new()
	val_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lab.custom_minimum_size = Vector2(0, 56)
	val_lab.add_theme_font_size_override("font_size", 28)
	val_lab.add_theme_color_override("font_color", COL_GOLD)
	var refresh := func() -> void:
		if pad2:
			val_lab.text = "%02d" % int(cur["v"])
		else:
			val_lab.text = str(int(cur["v"]))
	refresh.call()
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(64, 56)
	minus.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(minus)
	minus.pressed.connect(func() -> void:
		var n := int(cur["v"]) - 1
		if n < min_v:
			n = max_v
		cur["v"] = n
		refresh.call()
		on_change.call(n)
	)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(64, 56)
	plus.focus_mode = Control.FOCUS_NONE
	_style_secondary_button(plus)
	plus.pressed.connect(func() -> void:
		var n := int(cur["v"]) + 1
		if n > max_v:
			n = min_v
		cur["v"] = n
		refresh.call()
		on_change.call(n)
	)
	row.add_child(minus)
	row.add_child(val_lab)
	row.add_child(plus)
	return root


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
	var v := validate_compose_draft()
	if not bool(v.get("valid", false)):
		_update_validation()
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
