extends SceneTree
## Headless visual validation for v57 scroll mask cleanup.
## Confirms no CavityMaskHost / gray cavity rectangle; rear → scroll → front rim.
## Outputs under /tmp and /opt/cursor/artifacts — never committed.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v57/runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v57_validation")

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

	## Hierarchy audit — mask helpers must not exist / must not draw.
	var mask_host := chest.get_node_or_null("ChestAnimationRoot/ScrollCavityClip/CavityMaskHost")
	print("AUDIT mask_host=", mask_host)
	print("AUDIT scroll_parent=", chest._scroll_view.get_parent().name if chest._scroll_view else "?")
	print("AUDIT scroll_material=", chest._scroll_view.material if chest._scroll_view else null)
	print("AUDIT clip_children=", chest._scroll_clip.clip_children if chest._scroll_clip else -1)
	print("AUDIT clip_contents=", chest._scroll_clip.clip_contents if chest._scroll_clip else false)
	print(
		"AUDIT z_order frame=", chest._frame_view.z_index,
		" scroll=", chest._scroll_clip.z_index,
		" rim=", chest._rim_view.z_index,
		" glow=", chest._glow_pulse.z_index
	)

	var shots := [
		{"name": "01_fully_open_before_scroll", "p": 1.0, "scroll": false},
		{"name": "02_handoff_one_frame_before_reveal", "p": 1.0, "scroll": true, "rise": 0.0},
		{"name": "03_scroll_first_pixels", "p": 1.0, "scroll": true, "rise": 0.03 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "04_scroll_10", "p": 1.0, "scroll": true, "rise": 0.10 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "05_scroll_25", "p": 1.0, "scroll": true, "rise": 0.25 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "06_scroll_50", "p": 1.0, "scroll": true, "rise": 0.50 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "07_scroll_75", "p": 1.0, "scroll": true, "rise": 0.75 / LoveNotesChest.SCROLL_FINAL_ABOVE_RIM},
		{"name": "08_scroll_final_90", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "09_reward_hold", "p": 1.0, "scroll": true, "rise": 1.0},
		{"name": "10_empty_open", "p": 1.0, "scroll": false},
		{"name": "11_ocean_shimmer_regression", "p": 0.0, "scroll": false},
	]
	var handoff_img: Image = null
	var after_activate_img: Image = null
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
		await process_frame
		await process_frame
		var img := root_c.get_viewport().get_texture().get_image()
		if img:
			var path := "%s/%s.png" % [out_dir, s["name"]]
			img.save_png(path)
			img.save_png("/opt/cursor/artifacts/chest_v57_validation/%s.png" % s["name"])
			print("WROTE ", path)
			if s["name"] == "01_fully_open_before_scroll":
				handoff_img = img.duplicate()
			if s["name"] == "02_handoff_one_frame_before_reveal":
				after_activate_img = img.duplicate()
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
			" z_scroll=", chest._scroll_clip.z_index if chest._scroll_clip else -1,
			" z_rim=", chest._rim_view.z_index if chest._rim_view else -1,
			" parent=", chest._scroll_view.get_parent().name if chest._scroll_view else "?",
			" material=", chest._scroll_view.material != null if chest._scroll_view else false
		)

	## Frame-diff: fully-open vs layered-at-rise=0 (ignore scroll region below rim).
	## Large unexpected rectangular gray cavity change must not appear above the rim.
	if handoff_img != null and after_activate_img != null:
		var w := handoff_img.get_width()
		var h := handoff_img.get_height()
		var changed := 0
		var grayish := 0
		## Chest cavity band in viewport — approximate center of phone frame.
		var x0 := int(w * 0.28)
		var x1 := int(w * 0.72)
		var y0 := int(h * 0.42)
		var y1 := int(h * 0.62)
		for y in range(y0, y1):
			for x in range(x0, x1):
				var a := handoff_img.get_pixel(x, y)
				var b := after_activate_img.get_pixel(x, y)
				var dr := absf(a.r - b.r)
				var dg := absf(a.g - b.g)
				var db := absf(a.b - b.b)
				if dr + dg + db > 0.18:
					changed += 1
					## Gray-ish: low chroma, mid luminance.
					var mx := maxf(b.r, maxf(b.g, b.b))
					var mn := minf(b.r, minf(b.g, b.b))
					var lum := (b.r + b.g + b.b) / 3.0
					if (mx - mn) < 0.08 and lum > 0.25 and lum < 0.75:
						grayish += 1
		var area := maxi((x1 - x0) * (y1 - y0), 1)
		print("DIFF cavity_band changed=", changed, " grayish=", grayish, " area=", area,
			" changed_frac=", float(changed) / float(area),
			" gray_frac=", float(grayish) / float(area))
		## Soft gate — gray rectangle would light up a large mid-luma low-chroma band.
		if float(grayish) / float(area) > 0.08:
			print("FAIL: large grayish rectangular cavity delta detected")
			quit(1)
		else:
			print("PASS: no large gray cavity rectangle in handoff diff")

	## TOD regression smoke (day still correct).
	var day_pal := ChestEnvironment.tod_palette_at(11.783)
	print("TOD day phase=", day_pal["phase"], " star_a=", day_pal["star_a"])
	ChestEnvironment.debug_hour_override = -1.0
	env._apply_time_of_day(true)

	print("v57 validation complete")
	quit(0)
