extends SceneTree
## Headless visual validation for v47 PATH B — not committed output.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v47/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)

	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()

	var root_c := Control.new()
	root_c.size = Vector2(390, 844)
	root.add_child(root_c)

	var env := ChestEnvironment.new()
	env.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_c.add_child(env)

	var chest := LoveNotesChest.new()
	var chest_w := 252.0
	var chest_h := 326.0
	chest.custom_minimum_size = Vector2(chest_w, chest_h)
	chest.size = Vector2(chest_w, chest_h)
	var ground_y := ChestEnvironment.CHEST_GROUND_Y
	var foot_in_host := LoveNotesChest.CHEST_FOOT_Y_FRAC
	chest.set_anchors_preset(Control.PRESET_CENTER)
	chest.anchor_left = 0.5
	chest.anchor_right = 0.5
	chest.anchor_top = ground_y
	chest.anchor_bottom = ground_y
	chest.offset_left = -chest_w * 0.5
	chest.offset_right = chest_w * 0.5
	chest.offset_top = -chest_h * foot_in_host
	chest.offset_bottom = chest_h * (1.0 - foot_in_host)
	chest.z_index = 5
	root_c.add_child(chest)
	chest.configure(LoveNotesChest.ChestState.READY, false)
	await process_frame
	await process_frame

	var shots := [
		{"name": "closed", "p": 0.0, "scroll": false},
		{"name": "flare_closed", "p": 0.35, "scroll": false},
		{"name": "open", "p": 1.0, "scroll": false},
		{"name": "scroll_hidden", "p": 0.40, "scroll": true},
		{"name": "scroll_peek", "p": 0.50, "scroll": true},
		{"name": "scroll_25", "p": 0.62, "scroll": true},
		{"name": "scroll_50", "p": 0.78, "scroll": true},
		{"name": "scroll_70", "p": 0.90, "scroll": true},
		{"name": "scroll_final", "p": 1.0, "scroll": true},
	]
	for s in shots:
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if bool(s["scroll"]) and float(s["p"]) >= LoveNotesChest.SCROLL_REVEAL_START_PROGRESS:
			## Map combined progress into readable rise amounts for stills.
			var t_scroll := (float(s["p"]) - LoveNotesChest.SCROLL_REVEAL_START_PROGRESS) / (1.0 - LoveNotesChest.SCROLL_REVEAL_START_PROGRESS)
			chest._set_scroll_rise_amount(t_scroll)
		await process_frame
		await process_frame
		var img := root_c.get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/%s.png" % [out_dir, s["name"]])
			print("WROTE ", out_dir, "/", s["name"], ".png")
		print(
			"STATE ", s["name"],
			" frame=", chest._frame_index,
			" foot=", chest.foot_y_in_control(),
			" shadow_top=", chest._shadow_view.position.y if chest._shadow_view else -1.0,
			" ground=", ChestEnvironment.CHEST_GROUND_Y,
			" scroll_rise=", chest._scroll_rise,
			" opaque=", chest._frame_view.modulate.a
		)

	## Close crop of chest base for grounding proof.
	chest._set_frame_progress(0.0, false)
	await process_frame
	var full := root_c.get_viewport().get_texture().get_image()
	if full:
		var foot_screen_y := int(chest.global_position.y + chest.foot_y_in_control())
		var cx := int(chest.global_position.x + chest.size.x * 0.5)
		var y0 := clampi(foot_screen_y - 90, 0, full.get_height() - 1)
		var y1 := clampi(foot_screen_y + 70, 0, full.get_height())
		var x0 := clampi(cx - 120, 0, full.get_width() - 1)
		var x1 := clampi(cx + 120, 0, full.get_width())
		var crop := full.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
		crop.save_png("%s/ground_contact_close.png" % out_dir)
		print("WROTE ground_contact_close.png foot_screen_y=", foot_screen_y)

	print("GROUND=", ChestEnvironment.CHEST_GROUND_Y)
	print("FOOT_FRAC=", LoveNotesChest.CHEST_FOOT_Y_FRAC)
	print("EMPTY_FRAMES=", LoveNotesChest.EMPTY_FRAME_COUNT)
	print("PATH_B=1")
	quit(0)
