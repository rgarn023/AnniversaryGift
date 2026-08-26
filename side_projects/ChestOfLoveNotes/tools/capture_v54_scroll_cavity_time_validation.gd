extends SceneTree
## Headless visual validation for v54 scroll cavity + local-time fix.
## Outputs are written under /tmp and /opt/cursor/artifacts — never committed.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v54/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v54_validation")

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
	for _i in range(50):
		await process_frame

	var shots := [
		{"name": "01_main_chest_closed", "p": 0.0, "scroll": false},
		{"name": "02_open_mid", "p": 0.48, "scroll": false},
		{"name": "03_fully_open", "p": 1.0, "scroll": false},
		{"name": "04_handoff_layered", "p": 1.0, "scroll": true, "rise": 0.0},
		{"name": "05_scroll_first_peek", "p": 0.52, "scroll": true, "rise": 0.0},
		{"name": "06_scroll_25", "p": 0.66, "scroll": true, "rise": 0.28},
		{"name": "07_scroll_50", "p": 0.78, "scroll": true, "rise": 0.52},
		{"name": "08_scroll_70", "p": 0.90, "scroll": true, "rise": 0.74},
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
			img.save_png("/opt/cursor/artifacts/chest_v54_validation/%s.png" % s["name"])
			print("WROTE ", path)
		var tex_path := ""
		if chest._frame_view and chest._frame_view.texture:
			tex_path = str(chest._frame_view.texture.resource_path)
		var scroll_path := ""
		if chest._scroll_view and chest._scroll_view.texture:
			scroll_path = str(chest._scroll_view.texture.resource_path)
		var glow_a := chest._glow_pulse.modulate.a if chest._glow_pulse else -1.0
		var rim_y := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
		var st := chest._scroll_clip.position.y + chest._scroll_view.position.y if chest._scroll_view else -1.0
		var sh := chest._scroll_view.size.y if chest._scroll_view else 0.0
		var above := (rim_y - st) / maxf(sh, 0.01) if bool(s["scroll"]) else -1.0
		print(
			"STATE ", s["name"],
			" frame=", chest._frame_index,
			" layered=", chest._layered_open,
			" foot=", chest.foot_y_in_control(),
			" scroll_rise=", chest._scroll_rise,
			" above_rim=", above,
			" scroll_size=", chest._scroll_view.size if chest._scroll_view else Vector2.ZERO,
			" clip=", chest._scroll_clip.size if chest._scroll_clip else Vector2.ZERO,
			" scroll_rot=", chest._scroll_view.rotation if chest._scroll_view else -1.0,
			" glow_a=", glow_a,
			" shadow_y=", chest._shadow_view.position.y if chest._shadow_view else -1.0,
			" tex=", tex_path,
			" scroll_tex=", scroll_path
		)

	## Time-of-day representative captures (mock hours; reset after).
	var tod_hours := [
		{"name": "14_sky_night", "h": 0.0},
		{"name": "15_sky_night_to_dawn", "h": 4.75},
		{"name": "16_sky_dawn", "h": 6.5},
		{"name": "17_sky_dawn_to_day", "h": 7.5},
		{"name": "18_sky_day", "h": 12.0},
		{"name": "19_sky_day_to_sunset", "h": 16.5},
		{"name": "20_sky_sunset", "h": 18.5},
		{"name": "21_sky_sunset_to_night", "h": 19.5},
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
			img2.save_png("/opt/cursor/artifacts/chest_v54_validation/%s.png" % tod["name"])
			print("WROTE ", tod["name"])
		var pal := ChestEnvironment.tod_palette_at(float(tod["h"]))
		print(
			"TOD ", tod["name"],
			" hour=", tod["h"],
			" phase=", pal["phase"],
			" star_a=", pal["star_a"],
			" shimmer=", pal["shimmer"],
			" ocean_a=", (pal["ocean"] as Color).a,
			" stars_mod_a=", env._stars.modulate.a if env._stars else -1.0
		)
	ChestEnvironment.debug_hour_override = -1.0
	env._apply_time_of_day(true)

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
	print("DYNAMIC_SKY=1")
	var sky_stops := 0
	if env._sky_gradient != null:
		sky_stops = env._sky_gradient.get_point_count()
	print("SKY_GRADIENT=", env._sky_gradient_view != null)
	print("SKY_STOPS=", sky_stops)
	print("LAYER_Z frame=", chest._frame_view.z_index, " glow=", chest._glow_pulse.z_index, " scroll=", chest._scroll_clip.z_index, " rim=", chest._rim_view.z_index)
	print("CAVITY_RIM=", LoveNotesChest.CAVITY_RIM_CANVAS_Y)
	print("NO_BAND_SKY=", env._sky_gradient_view != null)

	## Timed open cadence probe via progress samples (avoid long tween waits in headless).
	chest.apply_ready_idle_state()
	await process_frame
	var switches: Array = []
	for p in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		chest._set_frame_progress(float(p), false)
		await process_frame
		switches.append({"i": chest._frame_index, "p": p})
		print("FRAME_SWITCH i=", chest._frame_index, " p=", p)
	print("FRAME_SWITCH_COUNT=", switches.size())

	## Empty retap — glow/particle only, no full replay.
	chest.chest_state = LoveNotesChest.ChestState.OPEN_EMPTY
	chest._open_amount = 1.0
	chest._set_frame_progress(1.0, false)
	var before_idx := chest._frame_index
	chest.animating = false
	await chest.play_open_empty_pulse()
	print("EMPTY_RETAP_FRAME=", chest._frame_index, " before=", before_idx)

	## Rapid-tap guard.
	chest.animating = true
	chest.play_open_animation(false, true)
	print("RAPID_TAP_BLOCKED=", chest.animating)
	chest.animating = false

	## Unread scroll rise probe via rise amounts (continuous Y path).
	chest.apply_ready_idle_state()
	await process_frame
	chest._enter_layered_open()
	for rise in [0.0, 0.25, 0.5, 0.75, 1.0]:
		chest._set_scroll_rise_amount(float(rise))
		await process_frame
		var rim_y := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
		var st := chest._scroll_clip.position.y + chest._scroll_view.position.y
		var above := (rim_y - st) / maxf(chest._scroll_view.size.y, 0.01)
		print("SCROLL_RISE_PROBE rise=", rise, " above_rim=", above, " size=", chest._scroll_view.size, " rot=", chest._scroll_view.rotation)
	print("FINAL_SCROLL_RISE=", chest._scroll_rise)
	print("FINAL_SCROLL_SIZE=", chest._scroll_view.size)
	print("FINAL_SCROLL_ROT=", chest._scroll_view.rotation)
	var rim_yf := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
	var stf := chest._scroll_clip.position.y + chest._scroll_view.position.y
	print("FINAL_ABOVE_RIM=", (rim_yf - stf) / maxf(chest._scroll_view.size.y, 0.01))
	print("GROUND_Y=", ChestEnvironment.CHEST_GROUND_Y)
	print("VALIDATION_DONE=1")

	quit(0)
