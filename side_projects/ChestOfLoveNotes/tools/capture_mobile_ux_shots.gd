extends SceneTree
## Headless-ish layout capture for mobile accessibility validation.
## Usage: godot --path . --script res://tools/capture_mobile_ux_shots.gd

const OUT := "/opt/cursor/artifacts/screenshots"
const SIZES := [
	Vector2i(1080, 2340),
	Vector2i(1080, 2400),
	Vector2i(1440, 3120),
	Vector2i(720, 1600),
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	call_deferred("_run")


func _run() -> void:
	MobileUi.ensure_loaded()
	for size in SIZES:
		DisplayServer.window_set_size(size)
		await process_frame
		await process_frame
		_capture_size(size)
	# Extra Large text pass on Galaxy-like size
	MobileUi.set_text_size(MobileUi.TextSize.EXTRA_LARGE)
	DisplayServer.window_set_size(Vector2i(1080, 2340))
	await process_frame
	await process_frame
	_capture_named("main_chest_extra_large_1080x2340", _build_main_mock())
	MobileUi.set_text_size(MobileUi.TextSize.LARGE)
	_capture_named("main_chest_large_1080x2340", _build_main_mock())
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	# Chest frame openness captures via treasure chest
	await _capture_chest_frames()
	quit(0)


func _capture_size(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	_capture_named("main_chest_%s" % tag, _build_main_mock())
	_capture_named("compose_%s" % tag, _build_compose_mock())
	_capture_named("sign_in_%s" % tag, _build_sign_in_mock())


func _capture_named(name: String, root: Control) -> void:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(DisplayServer.window_get_size())
	get_root().add_child(root)
	await process_frame
	await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [OUT, name])
		print("saved ", name)
	root.queue_free()
	await process_frame


func _build_main_mock() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 20)
	safe.add_theme_constant_override("margin_right", 20)
	safe.add_theme_constant_override("margin_top", 28)
	safe.add_theme_constant_override("margin_bottom", 18)
	root.add_child(safe)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	safe.add_child(v)
	var title := Label.new()
	title.text = "Chest of Love Notes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	v.add_child(title)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MobileUi.card_style())
	v.add_child(card)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)
	for pair in [["Unread", "2"], ["Locked", "1"], ["Requests", "0"]]:
		var col := VBoxContainer.new()
		var n := Label.new()
		n.text = pair[1]
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(n, MobileUi.SIZE_STAT_NUMBER, MobileUi.COLOR_TITLE)
		var l := Label.new()
		l.text = pair[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(l, MobileUi.SIZE_STAT_LABEL, MobileUi.COLOR_BODY)
		col.add_child(n)
		col.add_child(l)
		row.add_child(col)
	var your := Label.new()
	your.text = "Your Chest"
	your.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(your, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	v.add_child(your)
	var chest := TextureRect.new()
	if ResourceLoader.exists("res://assets/art/chest/chest_closed.png"):
		chest.texture = load("res://assets/art/chest/chest_closed.png")
	chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.custom_minimum_size = Vector2(560, 420)
	chest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(chest)
	var nav := HBoxContainer.new()
	nav.custom_minimum_size = Vector2(0, MobileUi.TOUCH_NAV_H)
	nav.add_theme_constant_override("separation", 8)
	for lab in ["Chest", "Compose", "Friends", "Sent", "Profile"]:
		var b := Button.new()
		b.text = lab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, MobileUi.TOUCH_NAV_H)
		MobileUi.style_button(b, MobileUi.TOUCH_NAV_H)
		nav.add_child(b)
	v.add_child(nav)
	return root


func _build_compose_mock() -> Control:
	var root := Control.new()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 28
	box.offset_bottom = -20
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	var title := Label.new()
	title.text = "Compose Scroll"
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	box.add_child(title)
	for section in ["Send To", "Scroll Title", "Your Message", "Special Locks"]:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", MobileUi.card_style())
		box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		var h := Label.new()
		h.text = section
		MobileUi.apply_label(h, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
		col.add_child(h)
		var field := LineEdit.new()
		field.placeholder_text = section
		field.custom_minimum_size = Vector2(0, MobileUi.TOUCH_PRIMARY_H)
		MobileUi.style_line_edit(field)
		col.add_child(field)
	var send := Button.new()
	send.text = "Seal & Send"
	send.custom_minimum_size = Vector2(0, MobileUi.TOUCH_PRIMARY_H)
	MobileUi.style_button(send)
	box.add_child(send)
	return root


func _build_sign_in_mock() -> Control:
	var root := Control.new()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(640, 520)
	box.position = Vector2(220, 400)
	root.add_child(box)
	var title := Label.new()
	title.text = "Chest of Love Notes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	box.add_child(title)
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.custom_minimum_size = Vector2(0, MobileUi.TOUCH_PRIMARY_H)
	MobileUi.style_line_edit(email)
	box.add_child(email)
	var pw := LineEdit.new()
	pw.placeholder_text = "Password"
	pw.secret = true
	pw.custom_minimum_size = Vector2(0, MobileUi.TOUCH_PRIMARY_H)
	MobileUi.style_line_edit(pw)
	box.add_child(pw)
	var btn := Button.new()
	btn.text = "Sign In"
	btn.custom_minimum_size = Vector2(0, MobileUi.TOUCH_PRIMARY_H)
	MobileUi.style_button(btn)
	box.add_child(btn)
	return root


func _capture_chest_frames() -> void:
	var keys := [0.0, 0.10, 0.25, 0.50, 0.75, 0.90, 1.0]
	var files := [
		"chest_closed.png",
		"chest_open_10.png",
		"chest_open_25.png",
		"chest_open_50.png",
		"chest_open_75.png",
		"chest_open_90.png",
		"chest_open.png",
	]
	for i in range(keys.size()):
		var root := Control.new()
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)
		var tr := TextureRect.new()
		tr.texture = load("res://assets/art/chest/%s" % files[i])
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		root.add_child(tr)
		_capture_named("chest_open_%dpct" % int(keys[i] * 100.0), root)
		await process_frame
