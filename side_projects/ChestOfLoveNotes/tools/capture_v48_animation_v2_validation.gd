extends SceneTree
## Headless visual validation for v48 animation_v2 — outputs not committed.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v48/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v48_validation")

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

	## Exact required visual states (frame-by-frame + scroll stages).
	var shots := [
		{"name": "01_closed", "p": 0.0, "scroll": false},
		{"name": "02_open_08", "p": 0.08, "scroll": false},
		{"name": "03_open_17", "p": 0.16, "scroll": false},
		{"name": "04_open_25", "p": 0.24, "scroll": false},
		{"name": "05_open_33", "p": 0.32, "scroll": false},
		{"name": "06_open_42", "p": 0.40, "scroll": false},
		{"name": "07_open_50", "p": 0.48, "scroll": false},
		{"name": "08_open_58", "p": 0.56, "scroll": false},
		{"name": "09_open_67", "p": 0.64, "scroll": false},
		{"name": "10_open_75", "p": 0.72, "scroll": false},
		{"name": "11_open_83", "p": 0.80, "scroll": false},
		{"name": "12_open_92", "p": 0.90, "scroll": false},
		{"name": "13_fully_open", "p": 1.0, "scroll": false},
		{"name": "14_scroll_hidden", "p": LoveNotesChest.SCROLL_REVEAL_START_PROGRESS, "scroll": true},
		{"name": "15_scroll_peek", "p": 0.55, "scroll": true},
		{"name": "16_scroll_25", "p": 0.66, "scroll": true},
		{"name": "17_scroll_50", "p": 0.78, "scroll": true},
		{"name": "18_scroll_70", "p": 0.90, "scroll": true},
		{"name": "19_scroll_final", "p": 1.0, "scroll": true},
		{"name": "20_reward_hold", "p": 1.0, "scroll": true},
		{"name": "21_empty_fully_open", "p": 1.0, "scroll": false},
	]
	for s in shots:
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if bool(s["scroll"]) and float(s["p"]) > LoveNotesChest.SCROLL_REVEAL_START_PROGRESS + 0.001:
			var t_scroll := (float(s["p"]) - LoveNotesChest.SCROLL_REVEAL_START_PROGRESS) / (1.0 - LoveNotesChest.SCROLL_REVEAL_START_PROGRESS)
			chest._set_scroll_rise_amount(clampf(t_scroll, 0.0, 1.0))
		elif bool(s["scroll"]):
			chest._enter_layered_open()
			chest._set_scroll_rise_amount(0.0)
		if s["name"] == "20_reward_hold" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A
		await process_frame
		await process_frame
		var img := root_c.get_viewport().get_texture().get_image()
		if img:
			var path := "%s/%s.png" % [out_dir, s["name"]]
			img.save_png(path)
			img.save_png("/opt/cursor/artifacts/chest_v48_validation/%s.png" % s["name"])
			print("WROTE ", path)
		var tex_path := ""
		if chest._frame_view and chest._frame_view.texture:
			tex_path = str(chest._frame_view.texture.resource_path)
		print(
			"STATE ", s["name"],
			" frame=", chest._frame_index,
			" layered=", chest._layered_open,
			" foot=", chest.foot_y_in_control(),
			" scroll_rise=", chest._scroll_rise,
			" opaque=", chest._frame_view.modulate.a if chest._frame_view else -1.0,
			" tex=", tex_path
		)

	## Timed open cadence probe (empty) — measure discrete frame changes.
	chest.apply_ready_idle_state()
	await process_frame
	var t0 := Time.get_ticks_msec()
	var last_idx := -1
	var switches: Array = []
	chest.play_open_animation(false, false)
	## Poll until finished or timeout.
	var guard := 0
	while chest.animating and guard < 240:
		await process_frame
		guard += 1
		if chest._frame_index != last_idx:
			var ms := Time.get_ticks_msec() - t0
			switches.append({"i": chest._frame_index, "ms": ms})
			last_idx = chest._frame_index
			print("FRAME_SWITCH i=", last_idx, " ms=", ms)
	var open_ms := Time.get_ticks_msec() - t0
	print("OPEN_DURATION_MS=", open_ms)
	print("FRAME_SWITCH_COUNT=", switches.size())
	print("GROUND=", ChestEnvironment.CHEST_GROUND_Y)
	print("FOOT_FRAC=", LoveNotesChest.CHEST_FOOT_Y_FRAC)
	print("CHEST_FRAMES=", LoveNotesChest.CHEST_FRAME_COUNT)
	print("OPEN_DURATION_SEC=", LoveNotesChest.OPEN_DURATION_SEC)
	print("ANIMATION_V2=1")
	quit(0)
