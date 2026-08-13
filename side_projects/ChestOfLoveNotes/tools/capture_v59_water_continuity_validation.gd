extends SceneTree
## Headless water continuity validation for v59 recovery.
## Confirms single rectangular water clip (no shoreline mask bands),
## shimmer still visible, and no strong blue tint on dry sand.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/chest_audit_v59/water"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/chest_v59_water")

	ChestEnvironment.preload_assets()

	var root_c := Control.new()
	root_c.size = Vector2(390, 844)
	root.add_child(root_c)

	var env := ChestEnvironment.new()
	env.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_c.add_child(env)
	ChestEnvironment.debug_hour_override = 11.783
	env._apply_time_of_day(true)
	await process_frame
	await process_frame

	print("CONST WATER_TOP=", ChestEnvironment.WATER_TOP_FRAC)
	print("CONST WATER_BOTTOM=", ChestEnvironment.WATER_BOTTOM_FRAC)
	print("AUDIT water_clip_type=", env._water_clip.get_class() if env._water_clip else "?")
	print("AUDIT water_is_texture_rect=", env._water_clip is TextureRect)
	print("AUDIT water_clip_contents=", env._water_clip.clip_contents if env._water_clip else false)
	print("AUDIT water_clip_children=", env._water_clip.clip_children if env._water_clip else -1)
	print(
		"WATER_LAYOUT clip_pos=", env._water_clip.position,
		" clip_size=", env._water_clip.size,
		" tint_pos=", env._ocean_tint.position,
		" tint_size=", env._ocean_tint.size,
		" glisten_pos=", env._water_glisten.position,
		" glisten_size=", env._water_glisten.size,
		" glisten_b_pos=", env._water_glisten_b.position if env._water_glisten_b else Vector2.ZERO
	)
	print("AUDIT glint_count=", env._glints.size())
	print("AUDIT glisten_visible=", env._water_glisten != null and env._water_glisten.visible)
	print("AUDIT glisten_b_visible=", env._water_glisten_b != null and env._water_glisten_b.visible)

	if env._water_clip is TextureRect:
		print("FAIL: water clip must be plain Control, not TextureRect mask")
		quit(1)
	if env._water_clip == null or not env._water_clip.clip_contents:
		print("FAIL: water clip must use clip_contents")
		quit(1)
	if env._water_clip.clip_children == CanvasItem.CLIP_CHILDREN_ONLY:
		print("FAIL: shoreline CLIP_CHILDREN_ONLY must remain disabled")
		quit(1)

	## Advance shimmer so capture shows sheen.
	for _j in range(90):
		env._process(0.016)
		await process_frame
	await process_frame
	await process_frame

	var img := root_c.get_viewport().get_texture().get_image()
	if img == null:
		print("FAIL: no viewport image")
		quit(1)
	var path := "%s/01_ocean_shimmer_continuous.png" % out_dir
	img.save_png(path)
	img.save_png("/opt/cursor/artifacts/chest_v59_water/01_ocean_shimmer_continuous.png")
	print("WROTE ", path)

	var w := img.get_width()
	var h := img.get_height()
	var y0 := int(h * ChestEnvironment.WATER_TOP_FRAC)
	var y1 := int(h * ChestEnvironment.WATER_BOTTOM_FRAC)
	## Column-mean luminance in water band — large adjacent jumps ⇒ vertical bands.
	var means: Array[float] = []
	for x in range(w):
		var s := 0.0
		var n := 0
		for y in range(y0, y1):
			var c := img.get_pixel(x, y)
			s += (c.r + c.g + c.b) / 3.0
			n += 1
		means.append(s / float(maxi(n, 1)))
	var diffs: Array[float] = []
	var big_jumps := 0
	for i in range(means.size() - 1):
		var d: float = absf(float(means[i]) - float(means[i + 1]))
		diffs.append(d)
		if d > 0.045:
			big_jumps += 1
	var avg_diff := 0.0
	var max_diff := 0.0
	for d in diffs:
		avg_diff += d
		max_diff = maxf(max_diff, d)
	avg_diff /= float(maxi(diffs.size(), 1))
	print("WATER_BANDING avg_adj=", avg_diff, " max_adj=", max_diff, " big_jumps=", big_jumps)
	if max_diff > 0.12 or big_jumps > 18:
		print("FAIL: vertical water bands / tiled sections detected")
		quit(1)
	else:
		print("PASS: ocean luminance continuous (no vertical bands)")

	## Dry sand below water bottom must not show strong cyan water tint.
	var blueish := 0
	var samples := 0
	for y in range(int(h * 0.575), int(h * 0.620)):
		for x in range(int(w * 0.50), int(w * 0.78)):
			var c := img.get_pixel(x, y)
			samples += 1
			if c.b > c.r + 0.08 and c.b > c.g + 0.02 and c.b > 0.35:
				blueish += 1
	var frac := float(blueish) / float(maxi(samples, 1))
	print("DRY_SAND blueish=", blueish, " samples=", samples, " frac=", frac)
	if frac > 0.08:
		print("FAIL: blue water tint bleeding onto sand")
		quit(1)
	else:
		print("PASS: no significant blue bleed on dry sand")

	## Shimmer still visible: water midband should include brighter glint pixels
	## than the local mean (subtle sheen — not over-bright).
	var sum_lum := 0.0
	var water_samples := 0
	var lums: Array[float] = []
	for y in range(y0 + 2, y1 - 2):
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			lums.append(lum)
			sum_lum += lum
			water_samples += 1
	var mean_lum := sum_lum / float(maxi(water_samples, 1))
	var bright := 0
	var max_lum := 0.0
	for lum in lums:
		max_lum = maxf(max_lum, lum)
		if lum > mean_lum + 0.08:
			bright += 1
	var bright_frac := float(bright) / float(maxi(water_samples, 1))
	print(
		"SHIMMER bright=", bright,
		" samples=", water_samples,
		" frac=", bright_frac,
		" mean=", mean_lum,
		" max=", max_lum
	)
	if bright < 8 or max_lum < mean_lum + 0.05:
		print("FAIL: shimmer not visible in water band")
		quit(1)
	else:
		print("PASS: shimmer visible in water band")

	## Confirm children remain parented under one water clip.
	var parent_ok := true
	if env._ocean_tint.get_parent() != env._water_clip:
		parent_ok = false
	if env._water_glisten.get_parent() != env._water_clip:
		parent_ok = false
	if env._water_glisten_b.get_parent() != env._water_clip:
		parent_ok = false
	for g in env._glints:
		if g.get_parent() != env._water_clip:
			parent_ok = false
	print("AUDIT single_water_parent=", parent_ok)
	if not parent_ok:
		print("FAIL: shimmer nodes not under single water clip")
		quit(1)
	else:
		print("PASS: shimmer clipped to one continuous water region")

	ChestEnvironment.debug_hour_override = -1.0
	env._apply_time_of_day(true)
	print("v59 water continuity validation complete")
	quit(0)
