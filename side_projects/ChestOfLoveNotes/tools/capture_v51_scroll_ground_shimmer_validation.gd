extends SceneTree
## Headless visual validation for v51 horizontal scroll + water shimmer.
## Outputs are written under /tmp and /opt/cursor/artifacts — never committed.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v51/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v51_validation")

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

	## Advance shimmer animation a bit so capture shows the sheen layers.
	for _i in range(45):
		await process_frame

	var shots := [
		{"name": "01_main_chest_closed", "p": 0.0, "scroll": false},
		{"name": "02_open_mid", "p": 0.48, "scroll": false},
		{"name": "03_fully_open", "p": 1.0, "scroll": false},
		{"name": "04_scroll_hidden", "p": LoveNotesChest.SCROLL_REVEAL_START_PROGRESS, "scroll": true, "rise": 0.0},
		{"name": "05_scroll_first_peek", "p": 0.52, "scroll": true, "rise": 0.06},
		{"name": "06_scroll_25", "p": 0.66, "scroll": true, "rise": 0.28},
		{"name": "07_scroll_45", "p": 0.78, "scroll": true, "rise": 0.52},
		{"name": "08_scroll_60", "p": 0.90, "scroll": true, "rise": 0.74},
		{"name": "09_scroll_final", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "10_reward_hold", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "11_empty_open", "p": 1.0, "scroll": false},
		{"name": "12_ocean_shimmer", "p": 0.0, "scroll": false},
		{"name": "13_your_chest_placeholder", "p": 0.0, "scroll": false},
	]
	for s in shots:
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if bool(s["scroll"]):
			chest._enter_layered_open()
			if s.has("rise"):
				chest._set_scroll_rise_amount(float(s["rise"]))
			else:
				chest._set_scroll_rise_amount(0.0)
		if s["name"] == "10_reward_hold" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A
		if s["name"] == "05_scroll_first_peek" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_EMERGE_A
		if String(s["name"]).begins_with("06_") or String(s["name"]).begins_with("07_") \
				or String(s["name"]).begins_with("08_") or String(s["name"]).begins_with("09_"):
			if chest._glow_pulse:
				chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_EMERGE_A
		await process_frame
		await process_frame
		var img := root_c.get_viewport().get_texture().get_image()
		if img:
			var path := "%s/%s.png" % [out_dir, s["name"]]
			img.save_png(path)
			img.save_png("/opt/cursor/artifacts/chest_v51_validation/%s.png" % s["name"])
			print("WROTE ", path)
		var tex_path := ""
		if chest._frame_view and chest._frame_view.texture:
			tex_path = str(chest._frame_view.texture.resource_path)
		var scroll_path := ""
		if chest._scroll_view and chest._scroll_view.texture:
			scroll_path = str(chest._scroll_view.texture.resource_path)
		var glow_a := chest._glow_pulse.modulate.a if chest._glow_pulse else -1.0
		print(
			"STATE ", s["name"],
			" frame=", chest._frame_index,
			" layered=", chest._layered_open,
			" foot=", chest.foot_y_in_control(),
			" scroll_rise=", chest._scroll_rise,
			" scroll_size=", chest._scroll_view.size if chest._scroll_view else Vector2.ZERO,
			" scroll_rot=", chest._scroll_view.rotation if chest._scroll_view else -1.0,
			" glow_a=", glow_a,
			" shadow_y=", chest._shadow_view.position.y if chest._shadow_view else -1.0,
			" tex=", tex_path,
			" scroll_tex=", scroll_path
		)

	## Ocean shimmer band bounds (water only).
	print("WATER_TOP=", ChestEnvironment.WATER_TOP_FRAC)
	print("WATER_BOTTOM=", ChestEnvironment.WATER_BOTTOM_FRAC)
	print("GLISTEN_VISIBLE=", env._water_glisten != null and env._water_glisten.visible)
	print("GLISTEN_B_VISIBLE=", env._water_glisten_b != null and env._water_glisten_b.visible)
	print("GLISTEN_CLIP_Y=", env._water_clip.position.y if env._water_clip else -1.0)
	print("GLISTEN_CLIP_H=", env._water_clip.size.y if env._water_clip else -1.0)
	print("GLINT_COUNT=", env._glints.size())
	print("GLINT0_A=", env._glints[0].modulate.a if env._glints.size() else -1.0)
	print("GROUND=", ChestEnvironment.CHEST_GROUND_Y)
	print("FOOT_FRAC=", LoveNotesChest.CHEST_FOOT_Y_FRAC)
	print("SCROLL_PEEK=", LoveNotesChest.SCROLL_PEEK_ABOVE_RIM)
	print("SCROLL_FINAL=", LoveNotesChest.SCROLL_FINAL_ABOVE_RIM)
	print("SCROLL_OPENING_WIDTH_FRAC=", LoveNotesChest.SCROLL_OPENING_WIDTH_FRAC)
	print("SCROLL_NATIVE=", LoveNotesChest.SCROLL_NATIVE)
	print("SCROLL_EMERGE_SEC=", LoveNotesChest.SCROLL_EMERGE_SEC)
	print("SCROLL_POST_OPEN_BEAT_SEC=", LoveNotesChest.SCROLL_POST_OPEN_BEAT_SEC)
	print("REWARD_HOLD_SEC=", LoveNotesChest.REWARD_HOLD_SEC)
	print("GLOW_EMERGE_A=", LoveNotesChest.GLOW_EMERGE_A)
	print("GLOW_REWARD_HOLD_A=", LoveNotesChest.GLOW_REWARD_HOLD_A)
	print("CHEST_FRAMES=", LoveNotesChest.CHEST_FRAME_COUNT)
	print("SCROLL_LAYER=", LoveNotesChest.SCROLL_LAYER)
	print("ANIMATION_V2=1")
	print("HORIZONTAL_SCROLL=1")

	## Timed open cadence probe (empty).
	chest.apply_ready_idle_state()
	await process_frame
	var t0 := Time.get_ticks_msec()
	var last_idx := -1
	var switches: Array = []
	chest.play_open_animation(false, false)
	var guard := 0
	while chest.animating and guard < 240:
		await process_frame
		guard += 1
		if chest._frame_index != last_idx:
			var ms := Time.get_ticks_msec() - t0
			switches.append({"i": chest._frame_index, "ms": ms})
			last_idx = chest._frame_index
			print("FRAME_SWITCH i=", last_idx, " ms=", ms)
	print("OPEN_DURATION_MS=", Time.get_ticks_msec() - t0)
	print("FRAME_SWITCH_COUNT=", switches.size())

	## Empty retap — glow/particle only, no full replay.
	chest.chest_state = LoveNotesChest.ChestState.OPEN_EMPTY
	chest._open_amount = 1.0
	chest._set_frame_progress(1.0, false)
	var before_idx := chest._frame_index
	await chest.play_open_empty_pulse()
	print("EMPTY_RETAP_FRAME=", chest._frame_index, " before=", before_idx)

	## Rapid-tap guard.
	chest.animating = true
	chest.play_open_animation(false, true)
	print("RAPID_TAP_BLOCKED=", chest.animating)
	chest.animating = false

	## Full unread open with horizontal scroll timing probe.
	chest.apply_ready_idle_state()
	await process_frame
	var t1 := Time.get_ticks_msec()
	chest.play_open_animation(false, true)
	guard = 0
	var saw_scroll := false
	while chest.animating and guard < 400:
		await process_frame
		guard += 1
		if chest._scroll_rise > 0.01:
			if not saw_scroll:
				print("SCROLL_FIRST_VISIBLE_MS=", Time.get_ticks_msec() - t1, " rise=", chest._scroll_rise)
				saw_scroll = true
	print("UNREAD_OPEN_DURATION_MS=", Time.get_ticks_msec() - t1)
	print("FINAL_SCROLL_RISE=", chest._scroll_rise)
	print("FINAL_SCROLL_SIZE=", chest._scroll_view.size if chest._scroll_view else Vector2.ZERO)
	print("FINAL_SCROLL_ROT=", chest._scroll_view.rotation if chest._scroll_view else -1.0)

	quit(0)
