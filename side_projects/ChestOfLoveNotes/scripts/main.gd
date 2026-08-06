extends Control
## Chest of Love Notes — root navigation and MVP screens.

var state: AppState
var _scroll_viewer: LoveNotesScrollViewer
var _chest: LoveNotesChest
var _screen_host: Control
var _banner: Label
var _toast: Label
var _current_screen: String = ""
var _inventory_filter: String = "all"
var _compose_draft: Dictionary = {}
var _password_target: Dictionary = {}
var _overlay: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state = AppState.new()
	state.bootstrap()
	_build_chrome()
	_scroll_viewer = LoveNotesScrollViewer.new()
	_scroll_viewer.set_reduced_motion(state.reduced_motion)
	_scroll_viewer.closed.connect(_on_scroll_closed)
	add_child(_scroll_viewer)
	_show_welcome()


func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if ResourceLoader.exists("res://assets/art/background/starfield.png"):
		var stars := TextureRect.new()
		stars.texture = load("res://assets/art/background/starfield.png")
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stars.stretch_mode = TextureRect.STRETCH_SCALE
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stars)

	_banner = Label.new()
	_banner.text = "LOCAL DEMO MODE"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = state.is_demo()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 8
	_banner.offset_bottom = 44
	_banner.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.z_index = 50
	add_child(_banner)

	_screen_host = Control.new()
	_screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_host.offset_top = 48 if state.is_demo() else 0
	add_child(_screen_host)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-420, -180)
	_toast.size = Vector2(840, 80)
	_toast.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.modulate.a = 0.0
	_toast.z_index = 60
	add_child(_toast)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.z_index = 55
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)


func _clear_screen() -> void:
	for c in _screen_host.get_children():
		c.queue_free()


func _title_font() -> Font:
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		return load("res://assets/fonts/Cinzel-Bold.ttf")
	return null


func _body_font() -> Font:
	if ResourceLoader.exists("res://assets/fonts/CormorantGaramond-Regular.ttf"):
		return load("res://assets/fonts/CormorantGaramond-Regular.ttf")
	return null


func _make_button(text: String, cb: Callable, min_size: Vector2 = Vector2(320, 72)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.42, 0.24, 0.14, 0.95)
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.52, 0.32, 0.18, 0.98)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(cb)
	return b


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.35)


func _show_welcome() -> void:
	_current_screen = "welcome"
	_clear_screen()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-420, -520)
	box.size = Vector2(840, 1100)
	box.add_theme_constant_override("separation", 22)
	_screen_host.add_child(box)

	var title := Label.new()
	title.text = "Chest of Love Notes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Send sealed scrolls to friends.\nThey wait in the chest until their unlock time."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.92, 0.86, 0.95))
	if _body_font():
		sub.add_theme_font_override("font", _body_font())
	box.add_child(sub)

	if state.is_demo():
		box.add_child(_make_button("Enter Local Demo", _enter_demo))
		var note := Label.new()
		note.text = "No Supabase credentials found. Demo uses fictional accounts only."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 22)
		note.add_theme_color_override("font_color", Color(1.0, 0.8, 0.55, 0.95))
		box.add_child(note)
	elif state.is_online():
		box.add_child(_make_button("Sign In", func() -> void: _show_auth(false)))
		box.add_child(_make_button("Create Account", func() -> void: _show_auth(true)))
	else:
		var err := Label.new()
		err.text = "Backend is not configured.\nAdd config/backend_config.json (see example)."
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err.add_theme_font_size_override("font_size", 26)
		err.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		box.add_child(err)


func _enter_demo() -> void:
	_show_main_chest()


func _show_auth(sign_up: bool) -> void:
	_current_screen = "auth"
	_clear_screen()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-400, -480)
	box.size = Vector2(800, 960)
	box.add_theme_constant_override("separation", 16)
	_screen_host.add_child(box)
	var title := Label.new()
	title.text = "Create Account" if sign_up else "Sign In"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.custom_minimum_size = Vector2(0, 64)
	box.add_child(email)
	var password := LineEdit.new()
	password.placeholder_text = "Password"
	password.secret = true
	password.custom_minimum_size = Vector2(0, 64)
	box.add_child(password)
	if sign_up:
		var confirm := LineEdit.new()
		confirm.placeholder_text = "Confirm password"
		confirm.secret = true
		confirm.custom_minimum_size = Vector2(0, 64)
		box.add_child(confirm)
		var agree := CheckBox.new()
		agree.text = "I agree to the terms and privacy notice"
		box.add_child(agree)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = (
		"Online auth requires a configured Supabase project. "
		+ "This build cannot complete cloud signup without your credentials."
	)
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	box.add_child(info)
	box.add_child(_make_button("Back", _show_welcome))


func _show_main_chest() -> void:
	_current_screen = "main_chest"
	_clear_screen()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_host.add_child(root)

	var title := Label.new()
	title.text = "Chest of Love Notes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-420, 40)
	title.size = Vector2(840, 80)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	root.add_child(title)

	var counts := state.demo.counts() if state.is_demo() else {"unread": 0, "locked": 0, "requests": 0}
	var stats := Label.new()
	stats.text = "Unread %d   ·   Locked %d   ·   Requests %d" % [
		counts.unread, counts.locked, counts.requests
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.set_anchors_preset(Control.PRESET_CENTER_TOP)
	stats.position = Vector2(-420, 120)
	stats.size = Vector2(840, 48)
	stats.add_theme_font_size_override("font_size", 26)
	stats.add_theme_color_override("font_color", Color(0.9, 0.84, 0.95))
	root.add_child(stats)

	_chest = LoveNotesChest.new()
	_chest.custom_minimum_size = Vector2(520, 520)
	_chest.size = Vector2(520, 520)
	_chest.set_anchors_preset(Control.PRESET_CENTER)
	_chest.position = Vector2(-260, -80)
	_chest.z_index = 5
	_chest.tapped.connect(_on_chest_tapped)
	root.add_child(_chest)
	_chest.configure(LoveNotesChest.ChestState.READY, true)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	actions.position = Vector2(-460, -280)
	actions.size = Vector2(920, 90)
	root.add_child(actions)
	actions.add_child(_make_button("Compose", _show_compose, Vector2(220, 72)))
	actions.add_child(_make_button("Friends", _show_friends, Vector2(220, 72)))
	actions.add_child(_make_button("Sent", _show_sent, Vector2(180, 72)))
	actions.add_child(_make_button("Profile", _show_profile, Vector2(200, 72)))

	if state.is_demo():
		var demo_row := HBoxContainer.new()
		demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
		demo_row.add_theme_constant_override("separation", 12)
		demo_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		demo_row.position = Vector2(-420, -180)
		demo_row.size = Vector2(840, 70)
		root.add_child(demo_row)
		demo_row.add_child(_make_button("+15 min", func() -> void:
			state.demo.advance_minutes(15)
			_show_toast("Demo time advanced 15 minutes")
			_show_main_chest()
		, Vector2(200, 64)))
		demo_row.add_child(_make_button("Refresh", _show_main_chest, Vector2(180, 64)))


func _on_chest_tapped() -> void:
	if _chest.animating:
		return
	await _chest.play_open_animation(true)
	_show_inventory()


func _show_inventory() -> void:
	_current_screen = "inventory"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28
	root.offset_right = -28
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Your Chest"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(160, 64)))

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	root.add_child(filters)
	for f in ["all", "unread", "locked", "requests"]:
		var fname: String = str(f)
		filters.add_child(_make_button(fname.capitalize(), func() -> void:
			_inventory_filter = fname
			_show_inventory()
		, Vector2(140, 56)))
	filters.add_child(_make_button("Saved", _show_saved, Vector2(140, 56)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_chest_items(_inventory_filter)
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No scrolls in this view."
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
		list.add_child(empty)
		return
	for item in items:
		list.add_child(_make_chest_item_row(item))


func _make_chest_item_row(item: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.16, 0.92)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	match str(item.get("state", "")):
		"friend_request":
			style.border_color = Color(0.55, 0.75, 1.0)
			style.set_border_width_all(2)
		"locked":
			style.border_color = Color(0.55, 0.45, 0.35)
			style.set_border_width_all(1)
		"unlocked_unread", "password_unlocked_unread":
			style.border_color = Color(0.95, 0.75, 0.35)
			style.set_border_width_all(2)
		"opened":
			style.bg_color = Color(0.1, 0.08, 0.12, 0.85)
	panel.add_theme_stylebox_override("panel", style)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var title := Label.new()
	title.text = str(item.get("title", "Scroll"))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.75))
	row.add_child(title)
	var meta := Label.new()
	var state_label := str(item.get("state", "")).replace("_", " ")
	meta.text = "%s  ·  %s" % [str(item.get("sender_display_name", "")), state_label]
	if bool(item.get("has_magic_password", false)):
		meta.text += "  ·  Magic Password Required"
	if str(item.get("state", "")) == "locked":
		var remain := int(item.get("unlock_at_unix", 0)) - state.demo.now_unix()
		meta.text += "  ·  unlocks in %dm" % maxi(int(ceil(remain / 60.0)), 0)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", 22)
	meta.add_theme_color_override("font_color", Color(0.82, 0.76, 0.88))
	row.add_child(meta)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	actions.add_child(_make_button("Open", func() -> void: _open_chest_item(item), Vector2(160, 56)))
	if str(item.get("kind", "love_note")) != "friend_request":
		var fav := bool(item.get("is_favorite", false))
		actions.add_child(_make_button("★" if fav else "☆", func() -> void:
			_toggle_favorite(str(item.id), not fav)
		, Vector2(80, 56)))
		actions.add_child(_make_button("Delete", func() -> void:
			_confirm_delete_received(str(item.id))
		, Vector2(140, 56)))
	return panel


func _show_saved() -> void:
	_current_screen = "saved"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28
	root.offset_right = -28
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Saved Scrolls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_inventory, Vector2(160, 64)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_saved_scrolls()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No saved scrolls yet. Open a note to keep it here."
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
		list.add_child(empty)
		return
	for item in items:
		list.add_child(_make_chest_item_row(item))


func _toggle_favorite(scroll_id: String, is_favorite: bool) -> void:
	if state.is_demo():
		var result := state.demo.set_scroll_favorite(scroll_id, is_favorite)
		if bool(result.get("ok", false)):
			_show_toast("Favorite updated")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not update favorite.")))
		return
	_show_toast("Online favorite update is ready after Edge deploy.")


func _confirm_delete_received(scroll_id: String) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-340, -220)
	box.size = Vector2(680, 420)
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Hide this scroll?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var body := Label.new()
	body.text = "This hides the note from your Current and Saved views only. It does not erase the sender's history or permanently destroy the message."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	box.add_child(body)
	box.add_child(_make_button("Hide from my chest", func() -> void:
		_hide_overlay()
		_delete_received(scroll_id)
	))
	box.add_child(_make_button("Cancel", _hide_overlay, Vector2(220, 64)))


func _delete_received(scroll_id: String) -> void:
	if state.is_demo():
		var result := state.demo.delete_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			_show_toast("Scroll hidden from your chest")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not delete.")))
		return
	_show_toast("Online delete-received is ready after Edge deploy.")


func _open_chest_item(item: Dictionary) -> void:
	var st := str(item.get("state", ""))
	if st == "friend_request":
		_show_friend_request(item)
		return
	if st == "locked":
		_show_locked_details(item)
		return
	if bool(item.get("has_magic_password", false)) and st != "opened":
		_show_password_dialog(item)
		return
	if st == "opened" and bool(item.get("has_magic_password", false)):
		_show_password_dialog(item)
		return
	await _open_authorized_scroll(str(item.id), "")


func _show_locked_details(item: Dictionary) -> void:
	_show_modal_panel("Sealed Scroll", [
		"From: %s" % str(item.get("sender_display_name", "")),
		"Title: %s" % str(item.get("title", "")),
		"This message body is not available yet.",
		"Unlock is authorized by server time (demo clock here).",
		"Magic password: %s" % ("Yes" if bool(item.get("has_magic_password", false)) else "No"),
	], "Close", func() -> void: _hide_overlay())


func _show_friend_request(item: Dictionary) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-360, -280)
	box.size = Vector2(720, 560)
	box.add_theme_constant_override("separation", 16)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Friend Request"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(title)
	var body := Label.new()
	body.text = "%s would like to become your friend." % str(item.get("sender_display_name", "Someone"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 28)
	body.add_theme_color_override("font_color", Color(0.95, 0.9, 0.98))
	box.add_child(body)
	box.add_child(_make_button("Accept", func() -> void:
		state.demo.respond_friend_request(str(item.id), true)
		_hide_overlay()
		_show_toast("Friend request accepted")
		_show_inventory()
	))
	box.add_child(_make_button("Decline", func() -> void:
		state.demo.respond_friend_request(str(item.id), false)
		_hide_overlay()
		_show_inventory()
	))
	box.add_child(_make_button("Close", _hide_overlay, Vector2(220, 64)))


func _show_password_dialog(item: Dictionary) -> void:
	_password_target = item
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-340, -260)
	box.size = Vector2(680, 520)
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Magic Password"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 1.0))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Demo password for the sealed note: starlight"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
	box.add_child(hint)
	var field := LineEdit.new()
	field.placeholder_text = "Enter magic password"
	field.secret = true
	field.custom_minimum_size = Vector2(0, 64)
	box.add_child(field)
	var show_toggle := CheckBox.new()
	show_toggle.text = "Show password"
	show_toggle.toggled.connect(func(on: bool) -> void: field.secret = not on)
	box.add_child(show_toggle)
	box.add_child(_make_button("Submit", func() -> void:
		var pw := field.text
		field.text = ""
		_hide_overlay()
		await _open_authorized_scroll(str(item.id), pw)
	))
	box.add_child(_make_button("Cancel", func() -> void:
		field.text = ""
		_hide_overlay()
	, Vector2(220, 64)))


func _open_authorized_scroll(scroll_id: String, magic_password: String) -> void:
	var result: Dictionary = {}
	if state.is_demo():
		result = state.demo.open_scroll(scroll_id, magic_password)
	elif state.is_online():
		result = await state.scrolls.open_scroll(scroll_id, magic_password)
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			result = {
				"ok": true,
				"message": str(data.get("message", "")),
				"scroll": data.get("scroll", {}),
				"ephemeral": bool(data.get("ephemeral", false)),
			}
		else:
			result = {"ok": false, "error": str(result.get("error", "Could not open scroll."))}
	else:
		_show_toast("Backend is not configured.")
		return
	if not bool(result.get("ok", false)):
		if bool(result.get("locked", false)):
			_show_toast("Still locked on demo server clock.")
		else:
			_show_toast(str(result.get("error", "Could not open scroll.")))
		return
	var meta: Dictionary = result.get("scroll", {})
	var body := str(result.get("message", ""))
	state.open_message_plaintext = body
	var ephemeral := bool(result.get("ephemeral", false))
	var heading := str(meta.get("title", "A Love Note"))
	var meta_line := "From %s" % str(meta.get("sender_display_name", meta.get("sender_id", "Friend")))
	await _scroll_viewer.open_message(heading, meta_line, body, false, ephemeral)


func _on_scroll_closed() -> void:
	# Clear plaintext from memory when the viewer closes.
	state.clear_open_message()
	if state.is_demo():
		state.demo.open_message_plaintext = ""
	match _current_screen:
		"inventory":
			_show_inventory()
		"saved":
			_show_saved()
		"sent":
			_show_sent()
		_:
			_show_main_chest()


func _show_compose() -> void:
	_current_screen = "compose"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_right = -32
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Compose Scroll"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(160, 64)))

	var friends := state.demo.get_friends() if state.is_demo() else []
	var recipient := OptionButton.new()
	recipient.custom_minimum_size = Vector2(0, 64)
	for f in friends:
		recipient.add_item("%s (@%s)" % [f.display_name, f.username])
		recipient.set_item_metadata(recipient.item_count - 1, f.id)
	root.add_child(recipient)

	var title_edit := LineEdit.new()
	title_edit.placeholder_text = "Optional title (max 80)"
	title_edit.custom_minimum_size = Vector2(0, 60)
	root.add_child(title_edit)

	var message := TextEdit.new()
	message.placeholder_text = "Write your love note…"
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message.custom_minimum_size = Vector2(0, 280)
	root.add_child(message)

	var count := Label.new()
	count.add_theme_font_size_override("font_size", 20)
	count.add_theme_color_override("font_color", Color(0.8, 0.75, 0.85))
	root.add_child(count)
	message.text_changed.connect(func() -> void:
		count.text = "%d / 5000" % message.text.length()
	)

	var unlock_mins := SpinBox.new()
	unlock_mins.min_value = 0
	unlock_mins.max_value = 60 * 24 * 30
	unlock_mins.value = 0
	unlock_mins.prefix = "Unlock in minutes: "
	root.add_child(unlock_mins)

	var tz := Label.new()
	tz.text = "Timezone: device local (converted to UTC for the server)"
	tz.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tz.add_theme_font_size_override("font_size", 20)
	root.add_child(tz)

	var pw_toggle := CheckBox.new()
	pw_toggle.text = "Require a Magic Password"
	root.add_child(pw_toggle)
	var pw := LineEdit.new()
	pw.placeholder_text = "Magic password"
	pw.secret = true
	pw.visible = false
	root.add_child(pw)
	var pw2 := LineEdit.new()
	pw2.placeholder_text = "Confirm magic password"
	pw2.secret = true
	pw2.visible = false
	root.add_child(pw2)
	pw_toggle.toggled.connect(func(on: bool) -> void:
		pw.visible = on
		pw2.visible = on
	)
	var warn := Label.new()
	warn.text = "If you set a magic password, the app cannot reveal it later. Share it privately."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_font_size_override("font_size", 20)
	warn.add_theme_color_override("font_color", Color(1.0, 0.78, 0.55))
	root.add_child(warn)

	root.add_child(_make_button("Send Scroll", func() -> void:
		if friends.is_empty():
			_show_toast("No accepted friends available.")
			return
		var rid := str(recipient.get_selected_metadata())
		var body := message.text
		if body.strip_edges().is_empty():
			_show_toast("Message cannot be empty.")
			return
		var magic := ""
		if pw_toggle.button_pressed:
			magic = pw.text
			if magic.length() < 4 or magic.length() > 64:
				_show_toast("Magic password must be 4–64 characters.")
				return
			if magic != pw2.text:
				_show_toast("Magic passwords do not match.")
				return
		var unlock_unix := state.demo.now_unix() + int(unlock_mins.value) * 60
		var result: Dictionary = state.demo.send_scroll(rid, title_edit.text, body, unlock_unix, magic)
		pw.text = ""
		pw2.text = ""
		if bool(result.get("ok", false)):
			_show_toast("Scroll sent.")
			_show_main_chest()
		else:
			_show_toast(str(result.get("error", "Send failed.")))
	))


func _show_friends() -> void:
	_current_screen = "friends"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_right = -32
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Friends"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(160, 64)))

	var search := LineEdit.new()
	search.placeholder_text = "Exact username or friend code"
	search.custom_minimum_size = Vector2(0, 60)
	root.add_child(search)
	root.add_child(_make_button("Add Friend", func() -> void:
		var result: Dictionary = state.demo.send_friend_request(search.text)
		_show_toast("Friend request sent." if bool(result.get("ok", false)) else str(result.get("error", "Failed")))
	))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	root.add_child(list)
	var section := Label.new()
	section.text = "Accepted friends"
	section.add_theme_font_size_override("font_size", 28)
	section.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	list.add_child(section)
	for f in state.demo.get_friends():
		var row := Label.new()
		row.text = "%s  ·  @%s  ·  %s" % [f.display_name, f.username, f.friend_code]
		row.add_theme_font_size_override("font_size", 24)
		row.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
		list.add_child(row)
	var me := state.demo.get_profile()
	var code := Label.new()
	code.text = "Your friend code: %s" % str(me.get("friend_code", ""))
	code.add_theme_font_size_override("font_size", 24)
	code.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	root.add_child(code)


func _show_sent() -> void:
	_current_screen = "sent"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_right = -32
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Sent Scrolls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(160, 64)))
	var sent_items: Array[Dictionary] = []
	if state.is_demo():
		sent_items = state.demo.get_sent_scrolls()
	if sent_items.is_empty():
		var empty := Label.new()
		empty.text = "No sent scrolls."
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
		root.add_child(empty)
		return
	for s in sent_items:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.08, 0.16, 0.92)
		style.set_corner_radius_all(14)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", style)
		var col := VBoxContainer.new()
		panel.add_child(col)
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text = "%s → %s · unlock_unix=%d · password=%s · opened=%d" % [
			str(s.get("title", "")),
			str(s.get("recipient_display_name", "")),
			int(s.get("unlock_at_unix", 0)),
			"yes" if bool(s.get("has_password", false)) else "no",
			int(s.get("opened_count", 0)),
		]
		row.add_theme_font_size_override("font_size", 22)
		row.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
		col.add_child(row)
		var sid := str(s.id)
		col.add_child(_make_button("Hide from Sent", func() -> void:
			if state.is_demo():
				var result := state.demo.delete_sent_scroll(sid)
				if bool(result.get("ok", false)):
					_show_toast("Hidden from your Sent history")
					_show_sent()
				else:
					_show_toast(str(result.get("error", "Could not hide sent scroll.")))
			else:
				_show_toast("Online delete-sent is ready after Edge deploy.")
		, Vector2(240, 56)))
		root.add_child(panel)


func _show_profile() -> void:
	_current_screen = "profile"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 40
	root.offset_bottom = -40
	root.add_theme_constant_override("separation", 16)
	_screen_host.add_child(root)
	var title := Label.new()
	title.text = "Profile / Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	root.add_child(title)
	var me := state.demo.get_profile() if state.is_demo() else {}
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = (
		"Display name: %s\nUsername: @%s\nFriend code: %s\n\n%s\n\nMode: %s"
		% [
			str(me.get("display_name", "")),
			str(me.get("username", "")),
			str(me.get("friend_code", "")),
			state.tokens.limitation_message,
			"LOCAL DEMO" if state.is_demo() else ("ONLINE" if state.is_online() else "UNCONFIGURED"),
		]
	)
	info.add_theme_font_size_override("font_size", 26)
	info.add_theme_color_override("font_color", Color(0.92, 0.88, 0.96))
	root.add_child(info)
	root.add_child(_make_button("Sign Out / Exit Demo", func() -> void:
		state.sign_out()
		if state.is_demo():
			state.demo.enable()
		_show_welcome()
	))
	root.add_child(_make_button("Back", _show_main_chest))


func _show_modal_panel(title_text: String, lines: Array, button_text: String, cb: Callable) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-360, -300)
	box.size = Vector2(720, 600)
	box.add_theme_constant_override("separation", 12)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	for line in lines:
		var lab := Label.new()
		lab.text = str(line)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 24)
		lab.add_theme_color_override("font_color", Color(0.92, 0.88, 0.95))
		box.add_child(lab)
	box.add_child(_make_button(button_text, cb))


func _hide_overlay() -> void:
	_overlay.visible = false
	for c in _overlay.get_children():
		c.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _scroll_viewer.visible:
			_scroll_viewer.close_viewer()
			return
		if _overlay.visible:
			_hide_overlay()
			return
		match _current_screen:
			"inventory", "saved", "compose", "friends", "sent", "profile":
				_show_main_chest()
			"main_chest":
				_show_welcome()
			_:
				pass
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		if _current_screen == "main_chest" and state.is_demo():
			# Refresh counts/state after resume.
			pass
