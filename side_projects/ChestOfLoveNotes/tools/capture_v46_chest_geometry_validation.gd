extends SceneTree
## Headless visual validation montage for v46 geometry + grounding + scroll.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()
	var env := ChestEnvironment.new()
	env.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	env.size = Vector2(390, 844)
	root.add_child(env)
	var chest := LoveNotesChest.new()
	chest.size = Vector2(252, 326)
	chest.position = Vector2(69, 844 * ChestEnvironment.CHEST_GROUND_Y - 326 * LoveNotesChest.CHEST_FOOT_Y_FRAC)
	root.add_child(chest)
	await process_frame
	chest._layout_frames()
	await process_frame

	var out_dir := "/tmp/chest_audit/v46_runtime"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shots := [
		{"name": "01_closed", "p": 0.0, "scroll": false, "badge": true},
		{"name": "02_early_crack", "p": 0.22, "scroll": false, "badge": false},
		{"name": "03_early_open", "p": 0.42, "scroll": false, "badge": false},
		{"name": "04_half_open", "p": 0.70, "scroll": false, "badge": false},
		{"name": "05_fully_open", "p": 1.0, "scroll": false, "badge": false},
		{"name": "06_open_glow", "p": 1.0, "scroll": false, "badge": false, "glow": true},
		{"name": "07_empty_hold", "p": 1.0, "scroll": false, "badge": false, "empty_msg": true},
		{"name": "08_scroll_hidden", "p": 0.50, "scroll": true, "badge": false},
		{"name": "09_scroll_peek", "p": 0.56, "scroll": true, "badge": false},
		{"name": "10_scroll_25", "p": 0.68, "scroll": true, "badge": false},
		{"name": "11_scroll_50", "p": 0.80, "scroll": true, "badge": false},
		{"name": "12_scroll_70", "p": 0.90, "scroll": true, "badge": false},
		{"name": "13_scroll_final", "p": 1.0, "scroll": true, "badge": false},
		{"name": "14_reward_hold", "p": 1.0, "scroll": true, "badge": false},
	]
	for s in shots:
		chest.set_unread_badge(3 if bool(s.get("badge", false)) else 0)
		chest._set_badge_suppressed(not bool(s.get("badge", false)))
		chest._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		if bool(s.get("glow", false)) and chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_SETTLE_A
		elif chest._glow_pulse:
			chest._glow_pulse.modulate.a = LoveNotesChest.GLOW_REWARD_HOLD_A if bool(s["scroll"]) else 0.0
		await process_frame
		await process_frame
		var img: Image = get_root().get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/%s.png" % [out_dir, str(s["name"])])
			print("WROTE ", s["name"])
	print("FOOT_Y=", chest.foot_y_in_control())
	print("SHADOW_Y=", chest._shadow_view.position.y, " H=", chest._shadow_view.size.y)
	print("GROUND=", ChestEnvironment.CHEST_GROUND_Y)
	print("DONE")
	quit(0)
