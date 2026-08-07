extends SceneTree
## Reliable SubViewport captures for mobile accessibility validation.
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
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	for size in SIZES:
		await _capture_size(size, "standard")
	MobileUi.set_text_size(MobileUi.TextSize.LARGE)
	await _capture_named("main_chest_large_1080x2340", Vector2i(1080, 2340), _build_main_mock())
	MobileUi.set_text_size(MobileUi.TextSize.EXTRA_LARGE)
	await _capture_named("main_chest_extra_large_1080x2340", Vector2i(1080, 2340), _build_main_mock())
	await _capture_named("compose_extra_large_1080x2340", Vector2i(1080, 2340), _build_compose_mock())
	await _capture_named("inventory_extra_large_1080x2340", Vector2i(1080, 2340), _build_inventory_mock())
	await _capture_named("friends_extra_large_1080x2340", Vector2i(1080, 2340), _build_friends_mock())
	await _capture_named("profile_extra_large_1080x2340", Vector2i(1080, 2340), _build_profile_mock())
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	await _capture_chest_frames()
	print("CAPTURE_DONE")
	quit(0)


func _capture_size(size: Vector2i, scale_tag: String) -> void:
	var tag := "%s_%dx%d" % [scale_tag, size.x, size.y]
	await _capture_named("main_chest_%s" % tag, size, _build_main_mock())
	await _capture_named("compose_%s" % tag, size, _build_compose_mock())
	await _capture_named("inventory_%s" % tag, size, _build_inventory_mock())
	await _capture_named("friends_%s" % tag, size, _build_friends_mock())
	await _capture_named("sent_%s" % tag, size, _build_sent_mock())
	await _capture_named("profile_%s" % tag, size, _build_profile_mock())
	await _capture_named("sign_in_%s" % tag, size, _build_sign_in_mock())


func _capture_named(name: String, size: Vector2i, root: Control) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	get_root().add_child(vp)
	# Top-left + explicit size — avoid full-rect size override races.
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = Vector2(size)
	root.custom_minimum_size = Vector2(size)
	vp.add_child(root)
	await process_frame
	await process_frame
	await process_frame
	var tex := vp.get_texture()
	if tex != null:
		var img: Image = tex.get_image()
		if img != null and not img.is_empty():
			img.save_png("%s/%s.png" % [OUT, name])
			print("saved ", name, " ", img.get_width(), "x", img.get_height())
		else:
			push_warning("empty image for " + name)
	vp.queue_free()
	await process_frame


func _bg(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)


func _title(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(lab, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	return lab


func _section(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	MobileUi.apply_label(lab, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	return lab


func _body(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	return lab


func _nav(selected: String) -> Control:
	var wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = MobileUi.COLOR_NAV_BG
	sb.set_content_margin_all(8)
	wrap.add_theme_stylebox_override("panel", sb)
	var nav := HBoxContainer.new()
	nav.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.TOUCH_NAV_H))
	nav.add_theme_constant_override("separation", 8)
	wrap.add_child(nav)
	for lab in ["Chest", "Compose", "Friends", "Sent", "Profile"]:
		var b := Button.new()
		b.text = lab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(b, MobileUi.TOUCH_NAV_H)
		if lab == selected:
			b.add_theme_color_override("font_color", MobileUi.COLOR_NAV_SELECTED)
		nav.add_child(b)
	return wrap


func _build_main_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 20)
	safe.add_theme_constant_override("margin_right", 20)
	safe.add_theme_constant_override("margin_top", 36)
	safe.add_theme_constant_override("margin_bottom", 18)
	root.add_child(safe)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	safe.add_child(v)
	v.add_child(_title("Chest of Love Notes"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MobileUi.card_style())
	v.add_child(card)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
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
	v.add_child(_nav("Chest"))
	return root


func _build_compose_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 36
	box.offset_bottom = -20
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	box.add_child(_title("Compose Scroll"))
	for section in ["Send To", "Scroll Title", "Your Message", "Special Locks", "Magic Password", "Location Lock", "Delivery Time"]:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", MobileUi.card_style())
		box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		col.add_child(_section(section))
		if section == "Your Message":
			var te := TextEdit.new()
			te.placeholder_text = "Write your note…"
			te.custom_minimum_size = Vector2(0, 260)
			MobileUi.style_text_edit(te)
			col.add_child(te)
		else:
			var field := LineEdit.new()
			field.placeholder_text = section
			MobileUi.style_line_edit(field)
			col.add_child(field)
	var send := Button.new()
	send.text = "Seal & Send"
	MobileUi.style_button(send)
	box.add_child(send)
	return root


func _build_inventory_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 36
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	box.add_child(_title("Chest Inventory"))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	box.add_child(chips)
	for pair in [["Current", "3"], ["Saved", "12"], ["Locked", "1"], ["Requests", "0"]]:
		var b := Button.new()
		b.text = "%s  %s" % [pair[0], pair[1]]
		b.custom_minimum_size = Vector2(160, MobileUi.font_touch(48))
		MobileUi.style_button(b, 48)
		chips.add_child(b)
	for i in range(3):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", MobileUi.card_style())
		box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		col.add_child(_section("Scroll %d" % (i + 1)))
		col.add_child(_body("A warm note waiting in your chest."))
	return root


func _build_friends_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 36
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	box.add_child(_title("Friends"))
	for name in ["Alex", "Sam", "Jordan"]:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", MobileUi.card_style())
		box.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var lab := Label.new()
		lab.text = name
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
		row.add_child(lab)
		var act := Button.new()
		act.text = "Message"
		MobileUi.style_button(act)
		row.add_child(act)
	box.add_child(_nav("Friends"))
	return root


func _build_sent_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 36
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	box.add_child(_title("Sent Scrolls"))
	for i in range(3):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", MobileUi.card_style())
		box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		col.add_child(_section("Delivered note %d" % (i + 1)))
		col.add_child(_body("Delivered · unlocked"))
	box.add_child(_nav("Sent"))
	return root


func _build_profile_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 36
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	box.add_child(_title("Profile"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MobileUi.card_style())
	box.add_child(card)
	var col := VBoxContainer.new()
	card.add_child(col)
	col.add_child(_section("Accessibility"))
	var text_btn := Button.new()
	text_btn.text = "Text Size: %s" % MobileUi.text_size_label()
	MobileUi.style_button(text_btn)
	col.add_child(text_btn)
	var motion := Button.new()
	motion.text = "Reduced Motion: OFF"
	MobileUi.style_button(motion)
	col.add_child(motion)
	var keep := Button.new()
	keep.text = "Keep Me Signed In: ON"
	MobileUi.style_button(keep)
	col.add_child(keep)
	box.add_child(_nav("Profile"))
	return root


func _build_sign_in_mock() -> Control:
	var root := Control.new()
	_bg(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	box.add_child(_title("Chest of Love Notes"))
	var sub := Label.new()
	sub.text = "Sign in to open your chest"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(sub, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	box.add_child(sub)
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	MobileUi.style_line_edit(email)
	box.add_child(email)
	var pw := LineEdit.new()
	pw.placeholder_text = "Password"
	pw.secret = true
	MobileUi.style_line_edit(pw)
	box.add_child(pw)
	var btn := Button.new()
	btn.text = "Sign In"
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
		await _capture_named("chest_open_%dpct" % int(keys[i] * 100.0), Vector2i(1080, 1920), root)
