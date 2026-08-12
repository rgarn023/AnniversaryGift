extends SceneTree
## Headless visual validation for v42 one-chest + beach layout.
## Writes PNGs under /tmp/coln_v42_validate/.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_tmp := "/tmp/coln_v42_validate"
	DirAccess.make_dir_recursive_absolute(out_tmp)

	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()

	var root_c := Control.new()
	root_c.size = Vector2(390, 844)
	root.add_child(root_c)

	var env := ChestEnvironment.new()
	env.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	env.size = Vector2(390, 844)
	root_c.add_child(env)

	## Header hierarchy: title row + refresh + stats + filters.
	var header := Control.new()
	header.position = Vector2(18, 40)
	header.size = Vector2(354, 52)
	root_c.add_child(header)
	var title := Label.new()
	title.text = "CHEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.10, 0.72))
	header.add_child(title)
	var refresh := Button.new()
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

	var stats := PanelContainer.new()
	stats.position = Vector2(18, 98)
	stats.size = Vector2(354, 56)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.07, 0.16, 0.82)
	st.set_corner_radius_all(12)
	stats.add_theme_stylebox_override("panel", st)
	root_c.add_child(stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(row)
	for label in ["Unread", "Locked", "Requests"]:
		var lab := Label.new()
		lab.text = label
		lab.add_theme_font_size_override("font_size", 12)
		lab.add_theme_color_override("font_color", Color(0.92, 0.88, 0.96))
		row.add_child(lab)

	var filters := HBoxContainer.new()
	filters.position = Vector2(18, 162)
	filters.size = Vector2(354, 40)
	root_c.add_child(filters)
	for label in ["Saved", "Hidden"]:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(100, 40)
		filters.add_child(b)

	var chest := LoveNotesChest.new()
	chest.position = Vector2(69, 300)
	chest.size = Vector2(252, 326)
	chest.clip_contents = false
	root_c.add_child(chest)
	await process_frame

	var title_cx := title.global_position.x + title.size.x * 0.5
	var view_cx := header.global_position.x + header.size.x * 0.5
	print("TITLE_CENTER title_cx=%.2f view_cx=%.2f delta=%.3f" % [title_cx, view_cx, title_cx - view_cx])
	print("REFRESH_BOUNDS y0=%.1f y1=%.1f header_h=%.1f" % [
		refresh.global_position.y, refresh.global_position.y + refresh.size.y, header.size.y
	])
	print("STATS_BOUNDS y0=%.1f" % stats.global_position.y)

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
		var img: Image = root_c.get_viewport().get_texture().get_image()
		if img:
			var crop := img.get_region(Rect2i(0, 0, mini(390, img.get_width()), mini(844, img.get_height())))
			var path_t := out_tmp.path_join("%s.png" % s["name"])
			crop.save_png(path_t)
			print("WROTE ", path_t, " frame=", chest._frame_index)

	## Reward hold / empty message
	chest._set_frame_progress(1.0, false)
	var empty := Label.new()
	empty.text = "No new scrolls today."
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.position = Vector2(40, 640)
	empty.size = Vector2(310, 36)
	empty.add_theme_font_size_override("font_size", 15)
	empty.add_theme_color_override("font_color", Color(0.90, 0.86, 0.94))
	empty.add_theme_constant_override("outline_size", 3)
	empty.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.10, 0.70))
	root_c.add_child(empty)
	await process_frame
	await process_frame
	var img2: Image = root_c.get_viewport().get_texture().get_image()
	if img2:
		var crop2 := img2.get_region(Rect2i(0, 0, mini(390, img2.get_width()), mini(844, img2.get_height())))
		crop2.save_png(out_tmp.path_join("13_empty_open_message.png"))
		print("WROTE empty message")

	print("VALIDATION_DONE out=", out_tmp)
	quit(0)
