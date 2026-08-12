extends SceneTree
## Headless visual validation for v45 chest grounding + vertical scroll fix.
## Writes PNGs under /tmp/coln_v45_validate/ and /opt/cursor/artifacts/screenshots/.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_tmp := "/tmp/coln_v45_validate"
	var out_art := "/opt/cursor/artifacts/screenshots"
	DirAccess.make_dir_recursive_absolute(out_tmp)
	DirAccess.make_dir_recursive_absolute(out_art)

	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()

	var root_c := Control.new()
	root_c.name = "LandingRoot"
	root_c.size = Vector2(390, 844)
	root.add_child(root_c)

	var env := ChestEnvironment.new()
	env.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	env.size = Vector2(390, 844)
	root_c.add_child(env)

	var header := Control.new()
	header.name = "ChestHeaderRow"
	header.position = Vector2(18, 40)
	header.size = Vector2(354, 52)
	root_c.add_child(header)
	var title := Label.new()
	title.name = "ChestTitle"
	title.text = "CHEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.10, 0.72))
	header.add_child(title)

	## Explicit: no refresh button on main CHEST reward screen.
	var refresh_found := false
	for n in root_c.find_children("*", "", true, false):
		if str(n.name).findn("Refresh") >= 0:
			refresh_found = true
	print("LANDING_NO_REFRESH=", str(not refresh_found))

	var msg_zone := Control.new()
	msg_zone.name = "ChestMessageSafeZone"
	msg_zone.position = Vector2(18, 98)
	msg_zone.size = Vector2(354, 44)
	root_c.add_child(msg_zone)

	var chest := LoveNotesChest.new()
	chest.position = Vector2(69, 280)
	chest.size = Vector2(252, 326)
	chest.clip_contents = false
	root_c.add_child(chest)
	await process_frame
	chest.set_unread_badge(2)

	for bad in ["Current", "Unread", "Locked", "Requests", "Saved", "Hidden", "Your Chest"]:
		var found := false
		for n in root_c.find_children("*", "", true, false):
			if n is Label and str((n as Label).text).findn(bad) >= 0 and n != title:
				found = true
			if n is Button and str((n as Button).text).findn(bad) >= 0:
				found = true
		print("LANDING_NO_%s=%s" % [bad.replace(" ", "_").to_upper(), str(not found)])

	print(
		"BADGE_POS x=%.1f y=%.1f chest=(%.1f,%.1f,%.1f,%.1f)" % [
			chest._badge.position.x, chest._badge.position.y,
			chest._anchor_rect.position.x, chest._anchor_rect.position.y,
			chest._anchor_rect.size.x, chest._anchor_rect.size.y
		]
	)
	print(
		"SHADOW_POS y=%.1f h=%.1f foot_y=%.1f" % [
			chest._shadow_view.position.y, chest._shadow_view.size.y,
			chest._anchor_rect.position.y + chest._anchor_rect.size.y * 0.74
		]
	)

	var shots := [
		{"name": "01_closed_beach", "p": 0.0, "scroll": false, "badge": true},
		{"name": "02_empty_early", "p": 0.18, "scroll": false, "badge": false},
		{"name": "03_empty_quarter", "p": 0.32, "scroll": false, "badge": false},
		{"name": "04_empty_half", "p": 0.50, "scroll": false, "badge": false},
		{"name": "05_empty_late", "p": 0.78, "scroll": false, "badge": false},
		{"name": "06_empty_full", "p": 1.0, "scroll": false, "badge": false},
		{"name": "07_unread_early", "p": 0.18, "scroll": true, "badge": false},
		{"name": "08_unread_half", "p": 0.40, "scroll": true, "badge": false},
		{"name": "09_unread_full", "p": 0.55, "scroll": true, "badge": false},
		{"name": "10_scroll_peek", "p": 0.60, "scroll": true, "badge": false},
		{"name": "11_scroll_25", "p": 0.70, "scroll": true, "badge": false},
		{"name": "12_scroll_50", "p": 0.82, "scroll": true, "badge": false},
		{"name": "13_scroll_70", "p": 0.92, "scroll": true, "badge": false},
		{"name": "14_scroll_final", "p": 1.0, "scroll": true, "badge": false},
		{"name": "15_reward_hold", "p": 1.0, "scroll": true, "badge": false},
	]
	for s in shots:
		chest._set_badge_suppressed(not bool(s["badge"]))
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if float(s["p"]) >= 0.5 and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_SETTLE_A if bool(s["scroll"]) else LoveNotesChest.GLOW_OPEN_A
		elif chest._glow_pulse:
			chest._glow_pulse.modulate.a = 0.0
		await process_frame
		await process_frame
		var chest_count := 0
		for n in chest.find_children("*", "TextureRect", true, false):
			if str(n.name) == "ChestFrame":
				chest_count += 1
		print(
			"STATE %s frame=%d rise=%.2f clip_vis=%s rim_vis=%s modulate.a=%.3f frame.a=%.3f chests=%d z=%d/%d/%d" % [
				s["name"], chest._frame_index, chest._scroll_rise,
				str(chest._scroll_clip.visible), str(chest._rim_view.visible),
				chest.modulate.a, chest._frame_view.modulate.a, chest_count,
				chest._frame_view.z_index, chest._scroll_clip.z_index, chest._rim_view.z_index
			]
		)
		var img: Image = root_c.get_viewport().get_texture().get_image()
		if img:
			var crop := img.get_region(Rect2i(0, 0, mini(390, img.get_width()), mini(844, img.get_height())))
			var path_t := out_tmp.path_join("%s.png" % s["name"])
			crop.save_png(path_t)
			crop.save_png(out_art.path_join("v45_%s.png" % s["name"]))
			print("WROTE ", path_t)

	chest._set_frame_progress(1.0, false)
	chest.hide_rolled_scroll()
	chest._set_badge_suppressed(false)
	var msg := Label.new()
	msg.text = "No new scrolls today."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	msg_zone.add_child(msg)
	await process_frame
	await process_frame
	var img2: Image = root_c.get_viewport().get_texture().get_image()
	if img2:
		var crop2 := img2.get_region(Rect2i(0, 0, mini(390, img2.get_width()), mini(844, img2.get_height())))
		crop2.save_png(out_tmp.path_join("16_empty_open_message.png"))
		crop2.save_png(out_art.path_join("v45_16_empty_open_message.png"))
		print("WROTE empty message")

	root_c.queue_free()
	await process_frame
	var mgmt := Control.new()
	mgmt.size = Vector2(390, 844)
	root.add_child(mgmt)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mgmt.add_child(bg)
	var mt := Label.new()
	mt.text = "YOUR CHEST"
	mt.position = Vector2(20, 36)
	mt.size = Vector2(350, 40)
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mt.add_theme_font_size_override("font_size", 22)
	mt.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	mgmt.add_child(mt)
	var row := HBoxContainer.new()
	row.position = Vector2(12, 90)
	row.size = Vector2(366, 40)
	mgmt.add_child(row)
	var filters := ["Current", "Unread", "Locked", "Requests", "Saved", "Hidden"]
	var buttons: Array[Button] = []
	for f in filters:
		var b := Button.new()
		b.text = f
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(56, 36)
		row.add_child(b)
		buttons.append(b)
	buttons[4].button_pressed = true
	await process_frame
	await process_frame
	var img3: Image = mgmt.get_viewport().get_texture().get_image()
	if img3:
		var crop3 := img3.get_region(Rect2i(0, 0, mini(390, img3.get_width()), mini(844, img3.get_height())))
		crop3.save_png(out_tmp.path_join("17_your_chest_saved.png"))
		crop3.save_png(out_art.path_join("v45_17_your_chest_saved.png"))
		print("WROTE your_chest_saved Hidden_visible=", str(buttons[5].visible))
	buttons[4].button_pressed = false
	buttons[5].button_pressed = true
	await process_frame
	await process_frame
	var img4: Image = mgmt.get_viewport().get_texture().get_image()
	if img4:
		var crop4 := img4.get_region(Rect2i(0, 0, mini(390, img4.get_width()), mini(844, img4.get_height())))
		crop4.save_png(out_tmp.path_join("18_your_chest_hidden.png"))
		crop4.save_png(out_art.path_join("v45_18_your_chest_hidden.png"))
		print("WROTE your_chest_hidden Saved_visible=", str(buttons[4].visible))

	print("VALIDATION_COMPLETE")
	quit(0)
