extends SceneTree
## v41: Beach chest polish — scale-stable frames, raised scroll, centered title, default beach.

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
	print("=== Beach chest polish (v41) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env_script := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var prep := FileAccess.get_file_as_string("res://tools/prepare_chest_animation_frames.py")
	var beach_prep := FileAccess.get_file_as_string("res://tools/prepare_default_beach_environment.py")

	_assert(chest.contains("Fantasy sheet chest"), "sheet architecture")
	_assert(chest.contains("FRAME_CANVAS := Vector2(384, 496)"), "taller canvas 384x496")
	_assert(chest.contains("EMPTY_FRAME_COUNT := 13"), "13 empty frames")
	_assert(chest.contains("SCROLL_FRAME_COUNT := 13"), "13 scroll frames")
	_assert(chest.contains("SCROLL_REVEAL_START_INDEX := 8"), "scroll starts after open")
	_assert(chest.contains("OPEN_DURATION_SEC := 1.36"), "open ~1.36s")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 1.08"), "scroll emerge duration")
	_assert(chest.contains("REWARD_HOLD_SEC := 0.40"), "reward hold before note")
	_assert(chest.contains("EMPHASIS_SCALE := 1.003"), "tiny settle scale only")
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
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads chest")
	_assert(main.contains("ChestEnvironment.preload_assets"), "main preloads beach env")
	_assert(main.contains("ChestEnvironment.new()"), "chest screen mounts environment")
	_assert(main.contains("ENV_DEFAULT_BEACH"), "default_beach id")
	_assert(main.contains("No new scrolls today."), "empty copy")
	_assert(main.contains("_add_inventory_filter_rows"), "shared filter rows")
	_assert(main.contains('_add_inventory_filter_rows(root, "saved")'), "Saved uses full filter set")
	_assert(main.contains('["hidden", "Hidden", row2]'), "Hidden chip in shared filters")
	_assert(main.contains("_dismiss_toast_if_visible"), "toast dismiss on chest open")
	_assert(main.contains("_fill_inventory_list_deferred"), "deferred loading flash")
	_assert(main.contains("chest_h := 326"), "taller chest host")
	_assert(main.contains("-chest_h * 0.18"), "chest grounded toward sand")
	_assert(main.contains("Title centered on the viewport"), "viewport-centered CHEST title")
	_assert(main.contains("PRESET_CENTER_RIGHT"), "refresh stays right-anchored")
	_assert(not main.contains("header.add_child(MobileUi.make_page_title(\"Chest\""), "title not HBox-centered")
	_assert(boot.contains("MIN_VISIBLE_SEC := 4.0"), "splash min 4s")
	_assert(prep.contains("CANVAS_H = 496"), "prep taller canvas")
	_assert(prep.contains("BASE_Y = 367"), "foot lock absolute")
	_assert(prep.contains("normalize_body_scale"), "body scale normalization")
	_assert(prep.contains("extract_scroll_layer"), "parchment scroll layer")
	_assert(prep.contains("compose_scroll_rise"), "raised scroll composites")
	_assert(prep.contains("empty_picks = [0, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]"), "clean empty picks only")
	_assert(prep.contains("cell_top_clipped"), "rejects damaged top cells")
	_assert(prep.contains("(-40, \"scroll_fully\")"), "final scroll rise dy")
	_assert(beach_prep.contains("default_beach.png"), "beach generator output")
	_assert(env_script.contains("ENV_DEFAULT_BEACH"), "environment id constant")
	_assert(env_script.contains("apply_environment"), "swappable environment API")
	_assert(not env_script.contains("BillingClient") and not env_script.contains("in_app_purchase"), "no store implementation")

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
	_assert(FileAccess.file_exists("res://assets/art/chest/scroll_rolled.png"), "scroll layer asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_front_rim.png"), "front rim asset")
	_assert(
		FileAccess.file_exists("res://assets/art/background/environments/default_beach.png"),
		"default beach environment art"
	)
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

	_assert(flags.contains("APP_VERSION_CODE := 41"), "versionCode 41")
	_assert(preset.contains("version/code=41"), "export 41")
	_assert(preset.contains("0.1.41-beach-chest-polish"), "version name")
	_assert(preset.contains("v41-beach-chest-polish-debug.apk"), "APK name")
	_assert(gitignore.contains("*.apk"), "apks ignored by default")
	_assert(export_sh.contains("v41-beach-chest-polish-debug.apk"), "export default")

	## Runtime: preload + pose snaps for representative states.
	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()
	var node := LoveNotesChest.new()
	root.add_child(node)
	node.size = Vector2(252, 326)
	var env := ChestEnvironment.new()
	root.add_child(env)
	env.size = Vector2(390, 844)
	await process_frame
	_assert(node._empty_frames.size() == 13, "empty frames loaded")
	_assert(node._scroll_frames.size() == 13, "scroll frames loaded")
	_assert(env._bg != null and env._bg.texture != null, "beach texture loaded")
	_assert(env.environment_id == ChestEnvironment.ENV_DEFAULT_BEACH, "default beach id active")

	var states := [
		{"name": "closed", "p": 0.0, "scroll": false},
		{"name": "early_open", "p": 0.18, "scroll": false},
		{"name": "quarter_open", "p": 0.32, "scroll": false},
		{"name": "half_open", "p": 0.50, "scroll": false},
		{"name": "late_open", "p": 0.78, "scroll": false},
		{"name": "fully_open", "p": 1.0, "scroll": false},
		{"name": "scroll_peek", "p": 0.58, "scroll": true},
		{"name": "scroll_partial", "p": 0.68, "scroll": true},
		{"name": "scroll_halfway", "p": 0.82, "scroll": true},
		{"name": "scroll_mostly", "p": 0.92, "scroll": true},
		{"name": "scroll_fully", "p": 1.0, "scroll": true},
	]
	var validate_dir := OS.get_user_data_dir().path_join("chest_validate_v41")
	DirAccess.make_dir_recursive_absolute(validate_dir)
	var prev_body_span := -1.0
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
				var w := img.get_width()
				var h := img.get_height()
				var top_hits := 0
				for x in range(w):
					if img.get_pixel(x, 0).a > 0.15 or img.get_pixel(x, mini(1, h - 1)).a > 0.15:
						top_hits += 1
				_assert(top_hits == 0, "state %s no top-edge opacity" % s["name"])
				## Approximate lower-body width stability (not lid flare).
				var y0 := int(h * 0.55)
				var min_x := w
				var max_x := 0
				for y in range(y0, h):
					for x in range(w):
						if img.get_pixel(x, y).a > 0.15:
							min_x = mini(min_x, x)
							max_x = maxi(max_x, x)
				if max_x > min_x:
					var span := float(max_x - min_x + 1)
					if prev_body_span > 0.0 and not bool(s["scroll"]):
						var drift := absf(span - prev_body_span) / prev_body_span
						_assert(drift < 0.06, "state %s body width stable (drift=%.3f)" % [s["name"], drift])
					if not bool(s["scroll"]):
						prev_body_span = span
				var path := validate_dir.path_join("%s.png" % s["name"])
				img.save_png(path)
				print("WROTE ", path)
		_assert(node._frame_index >= 0, "state %s frame index" % s["name"])

	## Scroll final frame should sit on the raised reward pose (index 12).
	node._set_frame_progress(1.0, true)
	await process_frame
	_assert(node._frame_index == 12, "final scroll frame index 12")

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

	## Title centering helper: overlay title center == viewport center for sample widths.
	for vw in [360, 390, 412]:
		var header := Control.new()
		header.size = Vector2(vw, 48)
		root.add_child(header)
		var title := Label.new()
		title.text = "Chest"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		header.add_child(title)
		var refresh := Button.new()
		refresh.custom_minimum_size = Vector2(48, 48)
		refresh.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		refresh.anchor_left = 1.0
		refresh.anchor_right = 1.0
		refresh.offset_left = -48
		refresh.offset_right = 0
		header.add_child(refresh)
		await process_frame
		var title_center_x := title.global_position.x + title.size.x * 0.5
		var view_center_x := header.global_position.x + header.size.x * 0.5
		_assert(absf(title_center_x - view_center_x) < 1.0, "title center == viewport center @%d" % vw)
		header.queue_free()

	node.queue_free()
	env.queue_free()
	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
