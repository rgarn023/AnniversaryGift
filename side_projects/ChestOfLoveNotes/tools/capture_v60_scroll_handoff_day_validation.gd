extends SceneTree
## Headless visual validation for v60 scroll handoff + day fix.
## Checks: layered chest match pose, scroll visible while buried, rise steps,
## front-rim occlusion geometry, and 15:34 DAY (no moon/stars).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v60/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v60_validation")

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

	print("CONST CAVITY_RIM=", LoveNotesChest.CAVITY_RIM_CANVAS_Y)
	print("CONST SCROLL_START=", LoveNotesChest.SCROLL_START_ABOVE_RIM)
	print("CONST SCROLL_PEEK=", LoveNotesChest.SCROLL_PEEK_ABOVE_RIM)
	print("CONST SCROLL_FINAL=", LoveNotesChest.SCROLL_FINAL_ABOVE_RIM)
	print("CONST CHEST_GROUND=", ChestEnvironment.CHEST_GROUND_Y)
	print("AUDIT z_order frame=", chest._frame_view.z_index,
		" scroll=", chest._scroll_clip.z_index,
		" rim=", chest._rim_view.z_index,
		" glow=", chest._glow_pulse.z_index)
	print("AUDIT open_back_modulate_at_ready=", chest._frame_view.modulate)

	## TOD audit at 15:34
	var pal1534 := ChestEnvironment.tod_palette_at(15.566)
	print("TOD 15:34 phase=", pal1534["phase"],
		" star_a=", pal1534["star_a"],
		" sky_top=", pal1534["sky_top"],
		" sky_horizon=", pal1534["sky_horizon"],
		" blend=", pal1534["blend"])
	print("TOD stars_visible=", env._stars.visible, " stars_a=", env._stars.modulate.a)

	var local_h := ChestEnvironment.local_hour_frac()
	var bias_h := ChestEnvironment.local_hour_frac_via_bias()
	var sys := Time.get_datetime_dict_from_system()
	var utc := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()))
	print("TIME API=Time.get_datetime_dict_from_system local_h=", local_h,
		" bias_h=", bias_h,
		" sys=", sys.get("hour"), ":", sys.get("minute"),
		" utc=", utc.get("hour"), ":", utc.get("minute"),
		" bias_min=", ChestEnvironment.local_timezone_bias_minutes(),
		" debug_override=", ChestEnvironment.debug_hour_override)

	for tod_h in [4.0, 6.5, 10.0, 15.566, 18.5, 21.0]:
		var p := ChestEnvironment.tod_palette_at(tod_h)
		print("TOD_CASE h=", tod_h, " phase=", p["phase"], " star_a=", p["star_a"],
			" sky_top_a=", (p["sky_top"] as Color).a,
			" horizon=", p["sky_horizon"])

	var shots := [
		{"name": "01_fully_open_before_scroll", "p": 1.0, "scroll": false},
		{"name": "02_layered_open_no_scroll", "layered_only": true},
		{"name": "03_scroll_visible_buried", "arm_buried": true},
		{"name": "04_scroll_first_5", "arm_buried": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.05)},
		{"name": "05_scroll_10", "arm_buried": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.10)},
		{"name": "06_scroll_25", "arm_buried": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.25)},
		{"name": "07_scroll_50", "arm_buried": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.50)},
		{"name": "08_scroll_75", "arm_buried": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.75)},
		{"name": "09_scroll_final", "arm_buried": true, "rise": 1.0},
		{"name": "10_reward_hold", "arm_buried": true, "rise": 1.0},
		{"name": "11_empty_open", "p": 1.0, "scroll": false},
		{"name": "12_ocean_day_1534", "p": 0.0, "scroll": false},
	]
	var fail := 0
	for s in shots:
		if s.get("layered_only", false):
			chest._exit_layered_open()
			chest._show_frame_index(12)
			chest._enter_layered_open()
			chest._scroll_rise = 0.0
			chest._place_scroll_and_rim()
			chest._set_scroll_layers_visible(true)
			if chest._scroll_clip:
				chest._scroll_clip.visible = false ## no scroll for composite check
		elif s.get("arm_buried", false):
			chest._arm_scroll_hidden_behind_lip()
			if s.has("rise"):
				chest._set_scroll_rise_amount(float(s["rise"]))
		else:
			chest._set_frame_progress(float(s.get("p", 0.0)), bool(s.get("scroll", false)))
		if s["name"] == "10_reward_hold" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A
		await process_frame
		await process_frame
		var vp_tex := root_c.get_viewport().get_texture()
		if vp_tex != null:
			var img := vp_tex.get_image()
			if img:
				img.save_png("%s/%s.png" % [out_dir, s["name"]])
				img.save_png("/opt/cursor/artifacts/chest_v60_validation/%s.png" % s["name"])
				print("WROTE ", s["name"])

		var rim_y := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
		var st := chest._scroll_clip.position.y + chest._scroll_view.position.y if chest._scroll_view else -1.0
		var sh := chest._scroll_view.size.y if chest._scroll_view else 0.0
		var content_frac := 1.0 - LoveNotesChest.SCROLL_CONTENT_TOP_PAD - LoveNotesChest.SCROLL_CONTENT_BOTTOM_PAD
		var content_h := sh * content_frac
		var content_top := st + sh * LoveNotesChest.SCROLL_CONTENT_TOP_PAD
		var above := (rim_y - content_top) / maxf(content_h, 0.01) if sh > 0.0 else -1.0
		print(
			"SHOT ", s["name"],
			" rise=", chest._scroll_rise,
			" layered=", chest._layered_open,
			" scroll_vis=", chest._scroll_clip.visible if chest._scroll_clip else false,
			" rim_vis=", chest._rim_view.visible if chest._rim_view else false,
			" back_mod=", chest._frame_view.modulate if chest._frame_view else Color(),
			" content_top=", content_top,
			" rim_y=", rim_y,
			" above=", above,
			" z_scroll=", chest._scroll_clip.z_index if chest._scroll_clip else -1,
			" z_rim=", chest._rim_view.z_index if chest._rim_view else -1
		)

	## Gates
	chest._arm_scroll_hidden_behind_lip()
	await process_frame
	if not chest._scroll_clip.visible:
		print("FAIL: scroll not visible while buried")
		fail += 1
	else:
		print("PASS: scroll visible while buried")
	var rim_y2 := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
	var st2 := chest._scroll_clip.position.y + chest._scroll_view.position.y
	var sh2 := chest._scroll_view.size.y
	var content_frac2 := 1.0 - LoveNotesChest.SCROLL_CONTENT_TOP_PAD - LoveNotesChest.SCROLL_CONTENT_BOTTOM_PAD
	var content_top2 := st2 + sh2 * LoveNotesChest.SCROLL_CONTENT_TOP_PAD
	var above2 := (rim_y2 - content_top2) / maxf(sh2 * content_frac2, 0.01)
	if above2 > 0.02:
		print("FAIL: buried start not fully behind lip above=", above2)
		fail += 1
	else:
		print("PASS: buried start fully behind front lip above=", above2)
	var mod := chest._frame_view.modulate
	if absf(mod.r - 1.0) > 0.001 or absf(mod.g - 1.0) > 0.001 or absf(mod.b - 1.0) > 0.001 or absf(mod.a - 1.0) > 0.001:
		print("FAIL: open-back modulate not neutral at handoff ", mod)
		fail += 1
	else:
		print("PASS: open-back modulate neutral at handoff")
	if chest._scroll_clip.z_index <= chest._frame_view.z_index or chest._rim_view.z_index <= chest._scroll_clip.z_index:
		print("FAIL: draw order")
		fail += 1
	else:
		print("PASS: draw order rear < scroll < rim")

	## Final exposure
	chest._set_scroll_rise_amount(1.0)
	await process_frame
	var stf := chest._scroll_clip.position.y + chest._scroll_view.position.y
	var shf := chest._scroll_view.size.y
	var ctopf := stf + shf * LoveNotesChest.SCROLL_CONTENT_TOP_PAD
	var abovef := (rim_y2 - ctopf) / maxf(shf * content_frac2, 0.01)
	if abovef < 0.80 or abovef > 0.90:
		print("FAIL: final exposure ", abovef)
		fail += 1
	else:
		print("PASS: final exposure ", abovef)

	## 15:34 DAY gate
	if str(pal1534["phase"]) != "day":
		print("FAIL: 15:34 phase not day")
		fail += 1
	else:
		print("PASS: 15:34 is DAY")
	if float(pal1534["star_a"]) > 0.001 or env._stars.visible:
		print("FAIL: 15:34 moon/stars not hidden")
		fail += 1
	else:
		print("PASS: 15:34 moon/stars hidden")
	var hz := pal1534["sky_horizon"] as Color
	if hz.b < hz.r * 0.90:
		print("FAIL: 15:34 horizon too sunset-like ", hz)
		fail += 1
	else:
		print("PASS: 15:34 horizon daytime blue-dominant")

	ChestEnvironment.debug_hour_override = -1.0
	print("FAILS=", fail)
	print("v60 scroll handoff + day validation complete")
	quit(1 if fail > 0 else 0)
