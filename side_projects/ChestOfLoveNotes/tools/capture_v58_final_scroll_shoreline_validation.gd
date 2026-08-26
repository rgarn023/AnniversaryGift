extends SceneTree
## Headless visual validation for v58 final scroll + shoreline polish.
## Reports scroll local/global transforms, rim edge, X bias, buried start,
## and shoreline mask clipping. Outputs under /tmp and /opt/cursor/artifacts.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v58/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v58_validation")

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
	ChestEnvironment.debug_hour_override = 11.783
	env._apply_time_of_day(true)
	await process_frame
	await process_frame

	for _i in range(50):
		await process_frame

	print("CONST CAVITY_CENTER=", LoveNotesChest.CAVITY_CENTER_CANVAS_X)
	print("CONST SCROLL_X_BIAS=", LoveNotesChest.SCROLL_X_BIAS_CANVAS)
	print("CONST CAVITY_RIM=", LoveNotesChest.CAVITY_RIM_CANVAS_Y)
	print("CONST SCROLL_START=", LoveNotesChest.SCROLL_START_ABOVE_RIM)
	print("CONST SCROLL_PEEK=", LoveNotesChest.SCROLL_PEEK_ABOVE_RIM)
	print("CONST SCROLL_FINAL=", LoveNotesChest.SCROLL_FINAL_ABOVE_RIM)
	print("CONST SCROLL_CONTENT_TOP_PAD=", LoveNotesChest.SCROLL_CONTENT_TOP_PAD)
	print("CONST SCROLL_CONTENT_BOTTOM_PAD=", LoveNotesChest.SCROLL_CONTENT_BOTTOM_PAD)
	print("CONST WATER_TOP=", ChestEnvironment.WATER_TOP_FRAC)
	print("CONST WATER_BOTTOM=", ChestEnvironment.WATER_BOTTOM_FRAC)
	print("AUDIT mask_host=", chest.get_node_or_null("ChestAnimationRoot/ScrollCavityClip/CavityMaskHost"))
	print("AUDIT scroll_parent=", chest._scroll_view.get_parent().name if chest._scroll_view else "?")
	print("AUDIT scroll_clip_children=", chest._scroll_clip.clip_children if chest._scroll_clip else -1)
	print("AUDIT water_clip_children=", env._water_clip.clip_children if env._water_clip else -1)
	print("AUDIT water_clip_is_tex=", env._water_clip is TextureRect)
	print("AUDIT water_mask_tex=", (env._water_clip as TextureRect).texture != null if env._water_clip is TextureRect else false)
	print(
		"AUDIT z_order frame=", chest._frame_view.z_index,
		" scroll=", chest._scroll_clip.z_index,
		" rim=", chest._rim_view.z_index,
		" glow=", chest._glow_pulse.z_index
	)
	print(
		"WATER_LAYOUT clip_pos=", env._water_clip.position,
		" clip_size=", env._water_clip.size,
		" tint_pos=", env._ocean_tint.position,
		" tint_size=", env._ocean_tint.size,
		" glisten_pos=", env._water_glisten.position,
		" glisten_size=", env._water_glisten.size
	)

	var shots := [
		{"name": "01_fully_open_before_scroll", "p": 1.0, "scroll": false},
		{"name": "02_scroll_fully_hidden", "p": 1.0, "scroll": true, "rise": 0.0},
		{"name": "03_scroll_first_pixels", "p": 1.0, "scroll": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.03)},
		{"name": "04_scroll_10", "p": 1.0, "scroll": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.10)},
		{"name": "05_scroll_25", "p": 1.0, "scroll": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.25)},
		{"name": "06_scroll_50", "p": 1.0, "scroll": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.50)},
		{"name": "07_scroll_75", "p": 1.0, "scroll": true, "rise": LoveNotesChest.scroll_rise_for_above_rim(0.75)},
		{"name": "08_scroll_final_90", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "09_reward_hold", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "10_empty_open", "p": 1.0, "scroll": false},
		{"name": "11_ocean_shimmer_shoreline", "p": 0.0, "scroll": false},
	]
	var xs: Array[float] = []
	for s in shots:
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if bool(s["scroll"]):
			chest._enter_layered_open()
			if s.has("rise"):
				chest._set_scroll_rise_amount(float(s["rise"]))
			else:
				chest._set_scroll_rise_amount(0.0)
		if s["name"] == "09_reward_hold" and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A
		if String(s["name"]).begins_with("03_") or String(s["name"]).begins_with("04_") \
				or String(s["name"]).begins_with("05_") or String(s["name"]).begins_with("06_") \
				or String(s["name"]).begins_with("07_") or String(s["name"]).begins_with("08_"):
			if chest._glow_pulse:
				chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_EMERGE_A
		## Advance shimmer for shoreline shot.
		if s["name"] == "11_ocean_shimmer_shoreline":
			for _j in range(90):
				env._process(0.016)
				await process_frame
		await process_frame
		await process_frame
		var img := root_c.get_viewport().get_texture().get_image()
		if img:
			var path := "%s/%s.png" % [out_dir, s["name"]]
			img.save_png(path)
			img.save_png("/opt/cursor/artifacts/chest_v58_validation/%s.png" % s["name"])
			print("WROTE ", path)
		var rim_y := chest._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * chest._anchor_rect.size.y
		var st := chest._scroll_clip.position.y + chest._scroll_view.position.y if chest._scroll_view else -1.0
		var sx := chest._scroll_clip.position.x + chest._scroll_view.position.x if chest._scroll_view else -1.0
		var sh := chest._scroll_view.size.y if chest._scroll_view else 0.0
		var sw := chest._scroll_view.size.x if chest._scroll_view else 0.0
		var content_frac := 1.0 - LoveNotesChest.SCROLL_CONTENT_TOP_PAD - LoveNotesChest.SCROLL_CONTENT_BOTTOM_PAD
		var content_h := sh * content_frac
		var content_top := st + sh * LoveNotesChest.SCROLL_CONTENT_TOP_PAD
		var above := (rim_y - content_top) / maxf(content_h, 0.01) if bool(s["scroll"]) else -1.0
		var local_pos := chest._scroll_view.position if chest._scroll_view else Vector2.ZERO
		var global_pos := chest._scroll_view.global_position if chest._scroll_view else Vector2.ZERO
		var scroll_cx := sx + sw * 0.5
		xs.append(scroll_cx)
		var geom_cx := chest._anchor_rect.position.x + (LoveNotesChest.CAVITY_CENTER_CANVAS_X / LoveNotesChest.FRAME_CANVAS.x) * chest._anchor_rect.size.x
		var target_cx := chest._anchor_rect.position.x + (
			(LoveNotesChest.CAVITY_CENTER_CANVAS_X + LoveNotesChest.SCROLL_X_BIAS_CANVAS) / LoveNotesChest.FRAME_CANVAS.x
		) * chest._anchor_rect.size.x
		print(
			"STATE ", s["name"],
			" rise=", chest._scroll_rise,
			" above_rim_content=", above,
			" content_top=", content_top,
			" scroll_local=", local_pos,
			" scroll_global=", global_pos,
			" scroll_size=", Vector2(sw, sh),
			" rim_y=", rim_y,
			" scroll_cx=", scroll_cx,
			" geom_cx=", geom_cx,
			" target_cx=", target_cx,
			" x_bias_px=", scroll_cx - geom_cx,
			" parent=", chest._scroll_view.get_parent().name if chest._scroll_view else "?",
			" z_scroll=", chest._scroll_clip.z_index,
			" z_rim=", chest._rim_view.z_index,
			" clip_children=", chest._scroll_clip.clip_children,
			" material=", chest._scroll_view.material != null if chest._scroll_view else false
		)

	## X consistency across reveal path (hidden through final).
	var xmin: float = float(xs[1])
	var xmax: float = float(xs[1])
	for i in range(1, 9):
		var v: float = float(xs[i])
		xmin = minf(xmin, v)
		xmax = maxf(xmax, v)
	print("X_PATH min=", xmin, " max=", xmax, " spread=", xmax - xmin)
	if xmax - xmin > 1.5:
		print("FAIL: scroll X not consistent across reveal")
		quit(1)
	else:
		print("PASS: scroll X consistent across reveal")

	## Shoreline sand-band must not be strongly cyan-boosted vs beach alone.
	## Sample mid/right shore bump region in the shimmer shot.
	var shore_img := Image.load_from_file("%s/11_ocean_shimmer_shoreline.png" % out_dir)
	if shore_img:
		var w := shore_img.get_width()
		var h := shore_img.get_height()
		var blueish := 0
		var samples := 0
		## Sand bump ~x 0.55-0.70, yfrac ~0.55-0.58 (dry sand above shoreline mask).
		for y in range(int(h * 0.555), int(h * 0.585)):
			for x in range(int(w * 0.55), int(w * 0.72)):
				var c := shore_img.get_pixel(x, y)
				samples += 1
				## Strong cyan/blue cast relative to warm sand.
				if c.b > c.r + 0.08 and c.b > c.g + 0.02 and c.b > 0.35:
					blueish += 1
		var frac := float(blueish) / float(maxi(samples, 1))
		print("SHORE_SAND blueish=", blueish, " samples=", samples, " frac=", frac)
		if frac > 0.08:
			print("FAIL: blue water tint still bleeding onto sand band")
			quit(1)
		else:
			print("PASS: no significant blue bleed on dry sand band")

	var day_pal := ChestEnvironment.tod_palette_at(11.783)
	print("TOD day phase=", day_pal["phase"], " star_a=", day_pal["star_a"])
	ChestEnvironment.debug_hour_override = -1.0
	env._apply_time_of_day(true)

	print("v58 validation complete")
	quit(0)
