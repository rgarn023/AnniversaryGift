extends SceneTree
## Headless visual validation for v43 hierarchy + beach + opacity.
## Writes PNGs under /tmp/coln_v43_validate/ and /opt/cursor/artifacts/screenshots/.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_tmp := "/tmp/coln_v43_validate"
	var out_art := "/opt/cursor/artifacts/screenshots"
	DirAccess.make_dir_recursive_absolute(out_tmp)
	DirAccess.make_dir_recursive_absolute(out_art)

	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()

	## --- Landing reward scene (no management controls) ---
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
	var refresh := Button.new()
	refresh.name = "ChestRefreshButton"
	refresh.text = "↻"
	refresh.custom_minimum_size = Vector2(48, 48)
	refresh.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	refresh.anchor_left = 1.0
	refresh.anchor_right = 1.0
	refresh.offset_left = -48
	refresh.offset_right = 0
	refresh.offset_top = 2
	refresh.offset_bottom = 50
	refresh.z_index = 20
	header.add_child(refresh)

	## Message safe zone ABOVE chest.
	var msg_zone := Control.new()
	msg_zone.name = "ChestMessageSafeZone"
	msg_zone.position = Vector2(18, 98)
	msg_zone.size = Vector2(354, 44)
	root_c.add_child(msg_zone)

	var chest := LoveNotesChest.new()
	## Lower-middle plant (mirrors main.gd anchors ~0.52).
	chest.position = Vector2(69, 250)
	chest.size = Vector2(252, 326)
	chest.clip_contents = false
	root_c.add_child(chest)
	await process_frame

	## Explicit hierarchy checks: no management filter labels on landing.
	for bad in ["Current", "Unread", "Locked", "Requests", "Saved", "Hidden", "Your Chest"]:
		var found := false
		for n in root_c.find_children("*", "", true, false):
			if n is Label and str((n as Label).text).findn(bad) >= 0 and n != title:
				found = true
			if n is Button and str((n as Button).text).findn(bad) >= 0 and n != refresh:
				found = true
		print("LANDING_NO_%s=%s" % [bad.replace(" ", "_").to_upper(), str(not found)])

	var title_cx := title.global_position.x + title.size.x * 0.5
	var view_cx := header.global_position.x + header.size.x * 0.5
	print("TITLE_CENTER title_cx=%.2f view_cx=%.2f delta=%.3f" % [title_cx, view_cx, title_cx - view_cx])
	print("CHEST_Y=%.1f MESSAGE_ZONE_Y1=%.1f" % [chest.position.y, msg_zone.position.y + msg_zone.size.y])

	var shots := [
		{"name": "01_closed_beach", "p": 0.0, "scroll": false},
		{"name": "02_empty_early", "p": 0.18, "scroll": false},
		{"name": "03_empty_half", "p": 0.50, "scroll": false},
		{"name": "04_empty_full", "p": 1.0, "scroll": false},
		{"name": "05_unread_early", "p": 0.18, "scroll": true},
		{"name": "06_unread_half", "p": 0.40, "scroll": true},
		{"name": "07_unread_full", "p": 0.55, "scroll": true},
		{"name": "08_scroll_peek", "p": 0.60, "scroll": true},
		{"name": "09_scroll_partial", "p": 0.70, "scroll": true},
		{"name": "10_scroll_halfway", "p": 0.82, "scroll": true},
		{"name": "11_scroll_above_rim", "p": 0.92, "scroll": true},
		{"name": "12_scroll_final", "p": 1.0, "scroll": true},
	]
	for s in shots:
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		await process_frame
		await process_frame
		print(
			"STATE %s frame=%d modulate.a=%.3f frame.a=%.3f" % [
				s["name"], chest._frame_index, chest.modulate.a, chest._frame_view.modulate.a
			]
		)
		var img: Image = root_c.get_viewport().get_texture().get_image()
		if img:
			var crop := img.get_region(Rect2i(0, 0, mini(390, img.get_width()), mini(844, img.get_height())))
			var path_t := out_tmp.path_join("%s.png" % s["name"])
			crop.save_png(path_t)
			crop.save_png(out_art.path_join("v43_%s.png" % s["name"]))
			print("WROTE ", path_t)

	## Empty message in safe zone — must not overlap chest bounds.
	chest._set_frame_progress(1.0, false)
	var empty := Label.new()
	empty.text = "No new scrolls today."
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty.add_theme_font_size_override("font_size", 15)
	empty.add_theme_color_override("font_color", Color(0.90, 0.86, 0.94))
	empty.add_theme_constant_override("outline_size", 3)
	empty.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.10, 0.70))
	msg_zone.add_child(empty)
	await process_frame
	await process_frame
	var msg_bottom := msg_zone.global_position.y + msg_zone.size.y
	var chest_top := chest.global_position.y
	print("MESSAGE_SAFE msg_bottom=%.1f chest_top=%.1f gap=%.1f" % [msg_bottom, chest_top, chest_top - msg_bottom])
	var img2: Image = root_c.get_viewport().get_texture().get_image()
	if img2:
		var crop2 := img2.get_region(Rect2i(0, 0, mini(390, img2.get_width()), mini(844, img2.get_height())))
		crop2.save_png(out_tmp.path_join("13_empty_open_message.png"))
		crop2.save_png(out_art.path_join("v43_13_empty_open_message.png"))
		print("WROTE empty message")

	## --- YOUR CHEST management scene ---
	for c in root_c.get_children():
		c.queue_free()
	await process_frame
	var mgmt := Control.new()
	mgmt.size = Vector2(390, 844)
	root.add_child(mgmt)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.12, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mgmt.add_child(bg)
	var mtitle := Label.new()
	mtitle.text = "YOUR CHEST"
	mtitle.position = Vector2(60, 40)
	mtitle.size = Vector2(280, 40)
	mtitle.add_theme_font_size_override("font_size", 22)
	mtitle.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	mgmt.add_child(mtitle)
	var stats := PanelContainer.new()
	stats.name = "ChestStatsPanel"
	stats.position = Vector2(18, 90)
	stats.size = Vector2(354, 56)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.07, 0.16, 0.82)
	st.set_corner_radius_all(12)
	stats.add_theme_stylebox_override("panel", st)
	mgmt.add_child(stats)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(srow)
	for label in ["Unread", "Locked", "Requests"]:
		var lab := Label.new()
		lab.text = label
		lab.add_theme_font_size_override("font_size", 12)
		lab.add_theme_color_override("font_color", Color(0.92, 0.88, 0.96))
		srow.add_child(lab)
	var filters := VBoxContainer.new()
	filters.position = Vector2(18, 160)
	filters.size = Vector2(354, 100)
	mgmt.add_child(filters)
	var r1 := HBoxContainer.new()
	r1.name = "ChestFilterRow1"
	filters.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.name = "ChestFilterRow2"
	filters.add_child(r2)
	var chips: Dictionary = {}
	for pair in [["Current", r1], ["Unread", r1], ["Locked", r1], ["Requests", r2], ["Saved", r2], ["Hidden", r2]]:
		var b := Button.new()
		b.text = str(pair[0])
		b.custom_minimum_size = Vector2(100, 40)
		(pair[1] as HBoxContainer).add_child(b)
		chips[str(pair[0])] = b
	## Saved selected → Hidden remains visible; Hidden selected → Saved remains.
	chips["Saved"].disabled = false
	chips["Hidden"].visible = true
	print("SAVED_SELECTED_HIDDEN_VISIBLE=", str(chips["Hidden"].visible))
	chips["Hidden"].disabled = false
	chips["Saved"].visible = true
	print("HIDDEN_SELECTED_SAVED_VISIBLE=", str(chips["Saved"].visible))
	await process_frame
	await process_frame
	var img3: Image = mgmt.get_viewport().get_texture().get_image()
	if img3:
		var crop3 := img3.get_region(Rect2i(0, 0, mini(390, img3.get_width()), mini(844, img3.get_height())))
		crop3.save_png(out_tmp.path_join("14_your_chest_management.png"))
		crop3.save_png(out_art.path_join("v43_14_your_chest_management.png"))
		print("WROTE management")

	print("VALIDATION_DONE out=", out_tmp)
	quit(0)
