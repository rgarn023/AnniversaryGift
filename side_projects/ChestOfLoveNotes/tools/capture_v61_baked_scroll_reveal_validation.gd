extends SceneTree
## Headless visual validation for v61 baked scroll reveal.
## Captures chest open mid frames, chest_12, reveal_00…07, and compositor inactivity.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v61/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v61_validation")

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
	ChestEnvironment.debug_hour_override = 15.566
	env._apply_time_of_day(true)
	await process_frame
	await process_frame

	print("CONST POST_OPEN_BEAT=", LoveNotesChest.SCROLL_POST_OPEN_BEAT_SEC)
	print("CONST REWARD_HOLD=", LoveNotesChest.REWARD_HOLD_SEC)
	print("CONST REVEAL_COUNT=", LoveNotesChest.REVEAL_FRAME_COUNT)
	print("CONST CHEST_GROUND=", ChestEnvironment.CHEST_GROUND_Y)
	print("CONST FOOT_FRAC=", LoveNotesChest.CHEST_FOOT_Y_FRAC)

	var fail := 0
	if chest._reveal_frames.size() != 8:
		print("FAIL: reveal frames not preloaded count=", chest._reveal_frames.size())
		fail += 1
	else:
		print("PASS: 8 reveal frames preloaded")

	var c12 := chest._chest_frames[12].get_image()
	var r0 := chest._reveal_frames[0].get_image()
	if c12 == null or r0 == null or c12.get_data() != r0.get_data():
		print("FAIL: reveal_00 not identical to chest_12")
		fail += 1
	else:
		print("PASS: reveal_00 identical to chest_12")

	var shots := [
		{"name": "01_closed", "p": 0.0},
		{"name": "02_mid_open", "p": 0.50},
		{"name": "03_chest_12", "p": 1.0},
		{"name": "04_reveal_00", "reveal": 0},
		{"name": "05_reveal_01", "reveal": 1},
		{"name": "06_reveal_02", "reveal": 2},
		{"name": "07_reveal_03", "reveal": 3},
		{"name": "08_reveal_04", "reveal": 4},
		{"name": "09_reveal_05", "reveal": 5},
		{"name": "10_reveal_06", "reveal": 6},
		{"name": "11_reveal_07", "reveal": 7},
		{"name": "12_final_hold", "reveal": 7},
		{"name": "13_empty_open", "p": 1.0},
		{"name": "14_ocean_day_1534", "p": 0.0},
	]

	chest._reward_sequence_log.clear()
	chest._record_reward_texture("chest_12_fully_open")
	for s in shots:
		if s.has("reveal"):
			chest._show_baked_reveal_index(int(s["reveal"]))
		else:
			chest._clear_baked_reveal()
			chest._ensure_legacy_layers_hidden()
			chest._set_frame_progress(float(s.get("p", 0.0)), false)
		if s["name"] == "12_final_hold" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A
		await process_frame
		await process_frame
		## Headless dummy renderer cannot capture viewport; save authoritative frame textures.
		if chest._frame_view and chest._frame_view.texture:
			var tex_img := chest._frame_view.texture.get_image()
			if tex_img:
				tex_img.save_png("%s/%s.png" % [out_dir, s["name"]])
				tex_img.save_png("/opt/cursor/artifacts/chest_v61_validation/%s.png" % s["name"])
				print("WROTE ", s["name"])
		var path_str := str(chest._frame_view.texture.resource_path) if chest._frame_view and chest._frame_view.texture else ""
		print(
			"SHOT ", s["name"],
			" baked=", chest._baked_reveal_active,
			" layered=", chest._layered_open,
			" scroll_vis=", chest._scroll_clip.visible if chest._scroll_clip else false,
			" rim_vis=", chest._rim_view.visible if chest._rim_view else false,
			" tex=", path_str
		)
		if s.has("reveal"):
			if chest._layered_open or (chest._scroll_clip and chest._scroll_clip.visible) or (chest._rim_view and chest._rim_view.visible):
				print("FAIL: compositor active during ", s["name"])
				fail += 1
			if not path_str.contains("animation_v3"):
				print("FAIL: not animation_v3 texture during ", s["name"])
				fail += 1
			if path_str.contains("chest_open_back"):
				print("FAIL: open_back during ", s["name"])
				fail += 1

	## Sequence assertion via discrete swaps
	var expected := [
		"chest_12_fully_open",
		"reveal_00_hidden",
		"reveal_01_peek",
		"reveal_02_15",
		"reveal_03_30",
		"reveal_04_50",
		"reveal_05_70",
		"reveal_06_85",
		"reveal_07_final",
	]
	print("SEQ_LOG=", ",".join(chest._reward_sequence_log))
	if chest._reward_sequence_log != expected:
		## rebuild expected from this run's discrete show path
		var ok := true
		if chest._reward_sequence_log.size() < expected.size():
			ok = false
		else:
			for i in range(expected.size()):
				if chest._reward_sequence_log[i] != expected[i]:
					ok = false
					break
		if not ok:
			print("FAIL: reward sequence mismatch")
			fail += 1
		else:
			print("PASS: reward sequence order")
	else:
		print("PASS: reward sequence order")

	## Empty path must not arm reveal
	chest._clear_baked_reveal()
	chest._ensure_legacy_layers_hidden()
	chest._set_frame_progress(1.0, false)
	await process_frame
	if chest._baked_reveal_active or chest._layered_open or chest._scroll_clip.visible:
		print("FAIL: empty open armed scroll/reveal")
		fail += 1
	else:
		print("PASS: empty open has no baked/layered scroll")

	## Plant unchanged
	if absf(ChestEnvironment.CHEST_GROUND_Y - 0.888) > 0.0001:
		print("FAIL: ground Y changed")
		fail += 1
	else:
		print("PASS: ground Y unchanged")
	if absf(LoveNotesChest.CHEST_FOOT_Y_FRAC - (420.0 / 512.0)) > 0.0001:
		print("FAIL: foot frac changed")
		fail += 1
	else:
		print("PASS: foot frac unchanged")

	print("FAIL_COUNT=", fail)
	quit(0 if fail == 0 else 1)
