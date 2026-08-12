extends SceneTree
## v40: Chest smoothing + Hidden filter fix — no top-clipped source poses.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _run() -> void:
	print("=== Chest smoothing + Hidden fix (v40) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var prep := FileAccess.get_file_as_string("res://tools/prepare_chest_animation_frames.py")

	_assert(chest.contains("Fantasy sheet chest"), "sheet architecture")
	_assert(chest.contains("FRAME_CANVAS := Vector2(384, 496)"), "taller canvas 384x496")
	_assert(chest.contains("EMPTY_FRAME_COUNT := 13"), "13 empty frames")
	_assert(chest.contains("SCROLL_FRAME_COUNT := 13"), "13 scroll frames")
	_assert(chest.contains("SCROLL_REVEAL_START_INDEX := 8"), "scroll starts after open")
	_assert(chest.contains("OPEN_DURATION_SEC := 1.28"), "open ~1.28s")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 0.96"), "scroll emerge duration")
	_assert(chest.contains("REWARD_HOLD_SEC := 0.40"), "reward hold before note")
	_assert(chest.contains("_set_badge_suppressed"), "badge hidden during reward")
	_assert(chest.contains("soft_glow_pulse.png"), "soft radial glow")
	_assert(not chest.contains("ColorRect.new()"), "no rectangular ColorRect glow")
	_assert(chest.contains("_ease_open_curve"), "quality easing")
	_assert(chest.contains("_frame_index_from_progress"), "variable frame timing")
	_assert(chest.contains("play_open_empty_pulse"), "empty retap pulse")
	_assert(chest.contains("if animating"), "guards overlapping anim")
	_assert(not chest.contains("HINGE_CANVAS"), "old hinge path removed")
	_assert(not chest.contains("LID_OPEN_ANGLE"), "old lid angle removed")
	_assert(not chest.contains("_lid.rotation"), "no procedural lid rotation")
	_assert(not chest.contains('scale.y =') and not chest.contains('"scale:y"'), "no scale.y squash")
	_assert(chest.contains("preload_assets"), "preload")
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads")
	_assert(main.contains("No new scrolls today."), "empty copy")
	_assert(main.contains("_add_inventory_filter_rows"), "shared filter rows")
	_assert(main.contains('_add_inventory_filter_rows(root, "saved")'), "Saved uses full filter set")
	_assert(main.contains('["hidden", "Hidden", row2]'), "Hidden chip in shared filters")
	_assert(main.contains("_dismiss_toast_if_visible"), "toast dismiss on chest open")
	_assert(main.contains("_fill_inventory_list_deferred"), "deferred loading flash")
	_assert(main.contains("chest_h := 326"), "taller chest host")
	_assert(boot.contains("MIN_VISIBLE_SEC := 4.0"), "splash min 4s")
	_assert(prep.contains("CANVAS_H = 496"), "prep taller canvas")
	_assert(prep.contains("BASE_Y = 367"), "foot lock absolute")
	_assert(prep.contains("empty_picks = [0, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]"), "clean empty picks only")
	_assert(prep.contains("cell_top_clipped"), "rejects damaged top cells")
	_assert(prep.contains("progressive_scroll_reveal"), "scroll reveal layer")

	_assert(
		FileAccess.file_exists(
			"res://assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png"
		),
		"glowing source sheet"
	)
	_assert(
		FileAccess.file_exists(
			"res://assets/chest/animation/magical_treasure_chest_animation_sheet.png"
		),
		"magical source sheet"
	)
	_assert(FileAccess.file_exists("res://assets/art/chest/soft_glow_pulse.png"), "soft glow asset")
	for i in range(13):
		_assert(
			FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_%02d.png" % i),
			"empty frame %02d" % i
		)
		_assert(
			FileAccess.file_exists("res://assets/art/chest/frames/scroll/scroll_%02d.png" % i),
			"scroll frame %02d" % i
		)
	_assert(not FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_13.png"), "no empty_13")

	_assert(flags.contains("APP_VERSION_CODE := 40"), "versionCode 40")
	_assert(preset.contains("version/code=40"), "export 40")
	_assert(preset.contains("0.1.40-chest-smoothing-hidden-fix"), "version name")
	_assert(preset.contains("v40-chest-smoothing-hidden-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("*.apk"), "apks ignored by default")
	_assert(export_sh.contains("v40-chest-smoothing-hidden-fix-debug.apk"), "export default")

	## Runtime: preload + pose snaps for representative states.
	LoveNotesChest.preload_assets()
	var node := LoveNotesChest.new()
	root.add_child(node)
	node.size = Vector2(252, 326)
	await process_frame
	_assert(node._empty_frames.size() == 13, "empty frames loaded")
	_assert(node._scroll_frames.size() == 13, "scroll frames loaded")

	var states := [
		{"name": "closed", "p": 0.0, "scroll": false},
		{"name": "early_open", "p": 0.18, "scroll": false},
		{"name": "quarter_open", "p": 0.32, "scroll": false},
		{"name": "half_open", "p": 0.50, "scroll": false},
		{"name": "late_open", "p": 0.78, "scroll": false},
		{"name": "fully_open", "p": 1.0, "scroll": false},
		{"name": "scroll_peek", "p": 0.60, "scroll": true},
		{"name": "scroll_partial", "p": 0.70, "scroll": true},
		{"name": "scroll_halfway", "p": 0.82, "scroll": true},
		{"name": "scroll_mostly", "p": 0.92, "scroll": true},
		{"name": "scroll_fully", "p": 1.0, "scroll": true},
	]
	var validate_dir := OS.get_user_data_dir().path_join("chest_validate_v40")
	DirAccess.make_dir_recursive_absolute(validate_dir)
	for s in states:
		node._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		await process_frame
		var tex: Texture2D = node._frame_view.texture
		_assert(tex != null, "state %s has texture" % s["name"])
		_assert(not str(tex.resource_path).contains("chest_body_planted"), "state %s not old body" % s["name"])
		_assert(not str(tex.resource_path).contains("chest_lid.png"), "state %s not old lid" % s["name"])
		if tex is ImageTexture or tex is CompressedTexture2D:
			var img: Image = tex.get_image()
			if img:
				## No opaque pixels on the top canvas edge (runtime clipping of tips).
				var w := img.get_width()
				var top_hits := 0
				for x in range(w):
					if img.get_pixel(x, 0).a > 0.15 or img.get_pixel(x, mini(1, img.get_height() - 1)).a > 0.15:
						top_hits += 1
				_assert(top_hits == 0, "state %s no top-edge opacity" % s["name"])
				var path := validate_dir.path_join("%s.png" % s["name"])
				img.save_png(path)
				print("WROTE ", path)
		_assert(node._frame_index >= 0, "state %s frame index" % s["name"])

	## Badge suppressed while reward animation is active.
	node.set_unread_badge(3)
	node._set_badge_suppressed(true)
	_assert(node._badge.visible == false, "badge hidden during animation")
	node._set_badge_suppressed(false)
	_assert(node._badge.visible == true, "badge restored after animation")

	## Rapid-tap guard
	node.animating = true
	node.play_open_animation(false, false)
	_assert(node.animating == true, "rapid tap blocked while animating")
	node.animating = false
	node.chest_state = LoveNotesChest.ChestState.OPEN_EMPTY
	node._open_amount = 1.0
	await node.play_open_empty_pulse()
	_assert(node.chest_state == LoveNotesChest.ChestState.OPEN_EMPTY, "pulse keeps OPEN_EMPTY")

	node.queue_free()
	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
