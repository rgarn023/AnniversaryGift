extends SceneTree
## Headless visual validation for v56 scroll origin + top sky + local-time fix.
## Outputs are written under /tmp and /opt/cursor/artifacts — never committed.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v56/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v56_validation")

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
	## Scroll geometry validation uses a forced DAY sky so baked dusk/moon in
	## beach art cannot confuse rear-wall / top-strip inspection. TOD suite
	## below resets the override and exercises real phases.
	ChestEnvironment.debug_hour_override = 11.783
	env._apply_time_of_day(true)
	await process_frame
	await process_frame

	for _i in range(50):
		await process_frame

	var shots := [
		{"name": "01_main_chest_closed", "p": 0.0, "scroll": false},
		{"name": "02_open_mid", "p": 0.48, "scroll": false},
		{"name": "03_fully_open", "p": 1.0, "scroll": false},
		{"name": "04_handoff_layered_hidden", "p": 1.0, "scroll": true, "rise": 0.0},
		{"name": "05_scroll_first_peek", "p": 1.0, "scroll": true, "rise": LoveNotesChest.SCROLL_PEEK_ABOVE_RIM / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "06_scroll_10", "p": 1.0, "scroll": true, "rise": 0.10 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "07_scroll_25", "p": 1.0, "scroll": true, "rise": 0.25 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "08_scroll_50", "p": 1.0, "scroll": true, "rise": 0.50 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "09_scroll_75", "p": 1.0, "scroll": true, "rise": 0.75 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "10_scroll_final", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "11_reward_hold", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "12_empty_open", "p": 1.0, "scroll": false},
		{"name": "13_ocean_shimmer", "p": 0.0, "scroll": false},
	]
	for s in shots:
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if bool(s["scroll"]):
			chest._enter_layered_open()
			if s.has("rise"):
				chest._set_scroll_rise_amount(float(s["rise"]))
			else:
				chest._set_scroll_rise_amount(0.0)
		if s["name"] == "11_reward_hold" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A
		if String(s["name"]).begins_with("05_") or String(s["name"]).begins_with("06_") \
				or String(s["name"]).begins_with("07_") or String(s["name"]).begins_with("08_") \
				or String(s["name"]).begins_with("09_") or String(s["name"]).begins_with("10_"):
			if chest._glow_pulse:
				chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_EMERGE_A
		await process_frame
		await process_frame
		var img := root_c.get_viewport().get_texture().get_image()
		if img:
			var path := "%s/%s.png" % [out_dir, s["name"]]
			img.save_png(path)
			img.save_png("/opt/cursor/artifacts/chest_v56_validation/%s.png" % s["name"])
			print("WROTE ", path)
		var rim_y := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
		var st := chest._scroll_clip.position.y + chest._scroll_view.position.y if chest._scroll_view else -1.0
		var sh := chest._scroll_view.size.y if chest._scroll_view else 0.0
		var above := (rim_y - st) / maxf(sh, 0.01) if bool(s["scroll"]) else -1.0
		var local_pos := chest._scroll_view.position if chest._scroll_view else Vector2.ZERO
		var global_pos := chest._scroll_view.global_position if chest._scroll_view else Vector2.ZERO
		print(
			"STATE ", s["name"],
			" frame=", chest._frame_index,
			" layered=", chest._layered_open,
			" foot=", chest.foot_y_in_control(),
			" scroll_rise=", chest._scroll_rise,
			" above_rim=", above,
			" scroll_local=", local_pos,
			" scroll_global=", global_pos,
			" rim_y=", rim_y,
			" scroll_size=", chest._scroll_view.size if chest._scroll_view else Vector2.ZERO,
			" z_scroll=", chest._scroll_clip.z_index if chest._scroll_clip else -1,
			" z_rim=", chest._rim_view.z_index if chest._rim_view else -1,
			" z_frame=", chest._frame_view.z_index if chest._frame_view else -1,
			" clip_children=", chest._cavity_mask_host.clip_children if chest._cavity_mask_host else -1,
			" parent=", chest._scroll_view.get_parent().name if chest._scroll_view else "?"
		)

	## Time-of-day representative captures (mock hours; reset after).
	var tod_hours := [
		{"name": "14_sky_night_0400", "h": 4.0},
		{"name": "15_sky_dawn_0630", "h": 6.5},
		{"name": "16_sky_day_1147", "h": 11.783},
		{"name": "17_sky_day_1200", "h": 12.0},
		{"name": "18_sky_sunset_1830", "h": 18.5},
		{"name": "19_sky_night_2100", "h": 21.0},
	]
	chest._set_frame_progress(0.0, false)
	for tod in tod_hours:
		ChestEnvironment.debug_hour_override = float(tod["h"])
		env._apply_time_of_day(true)
		for _j in range(20):
			await process_frame
		var img2 := root_c.get_viewport().get_texture().get_image()
		if img2:
			img2.save_png("%s/%s.png" % [out_dir, tod["name"]])
			img2.save_png("/opt/cursor/artifacts/chest_v56_validation/%s.png" % tod["name"])
			print("WROTE ", tod["name"])
		var pal := ChestEnvironment.tod_palette_at(float(tod["h"]))
		print(
			"TOD ", tod["name"],
			" hour=", tod["h"],
			" phase=", pal["phase"],
			" star_a=", pal["star_a"],
			" sky_top_a=", (pal["sky_top"] as Color).a,
			" base_fill=", env._base_fill.color if env._base_fill else Color(),
			" stars_vis=", env._stars.visible if env._stars else false,
			" stars_mod_a=", env._stars.modulate.a if env._stars else -1.0
		)
	ChestEnvironment.debug_hour_override = -1.0
	env._apply_time_of_day(true)

	print("LOCAL_HOUR=", ChestEnvironment.local_hour_frac())
	print("LOCAL_VIA_BIAS=", ChestEnvironment.local_hour_frac_via_bias())
	print("TZ_BIAS=", ChestEnvironment.local_timezone_bias_minutes())
	print("SYS_DICT=", Time.get_datetime_dict_from_system())
	print("UTC_DICT=", Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system())))
	print("DEBUG_OVERRIDE=", ChestEnvironment.debug_hour_override)
	print("SCROLL_START=", LoveNotesChest.SCROLL_START_ABOVE_RIM)
	print("SCROLL_PEEK=", LoveNotesChest.SCROLL_PEEK_ABOVE_RIM)
	print("SCROLL_FINAL=", LoveNotesChest.SCROLL_FINAL_ABOVE_RIM)
	print("CAVITY_RIM=", LoveNotesChest.CAVITY_RIM_CANVAS_Y)
	print("GROUND_Y=", ChestEnvironment.CHEST_GROUND_Y)
	print("TOP_SHADE=", env.get_node_or_null("TopReadabilityShade") != null)
	print("VALIDATION_DONE=1")
	quit(0)
