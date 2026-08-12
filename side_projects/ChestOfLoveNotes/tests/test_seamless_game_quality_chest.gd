extends SceneTree
## v38: Fantasy sheet chest — locked base-aligned frames from authoritative sprite sheets.

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
	print("=== Fantasy sheet chest animation (v38) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")

	_assert(chest.contains("Fantasy sheet chest"), "sheet architecture")
	_assert(chest.contains("assets/art/chest/frames/"), "production frame dir")
	_assert(chest.contains("EMPTY_DIR"), "empty sequence dir")
	_assert(chest.contains("SCROLL_DIR"), "scroll sequence dir")
	_assert(chest.contains("_set_frame_progress"), "frame progress driver")
	_assert(chest.contains("SpriteFrames"), "SpriteFrames prepared")
	_assert(chest.contains("SCROLL_REVEAL_START_INDEX"), "scroll starts after open")
	_assert(chest.contains("OPEN_DURATION_SEC := 1.00"), "open ~1.0s")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 0.68"), "scroll emerge duration")
	_assert(chest.contains("_ease_open_curve"), "quality easing")
	_assert(chest.contains("OPEN_WAITING_FOR_SCROLL"), "waiting state")
	_assert(chest.contains("OPEN_SCROLL_EMERGING"), "emerging state")
	_assert(chest.contains("play_open_empty_pulse"), "empty retap pulse")
	_assert(chest.contains("if animating"), "guards overlapping anim")
	_assert(not chest.contains("HINGE_CANVAS"), "old hinge path removed")
	_assert(not chest.contains("chest_body_planted.png"), "old planted body unused")
	_assert(not chest.contains("LID_OPEN_ANGLE"), "old lid angle removed")
	_assert(not chest.contains("_lid.rotation"), "no procedural lid rotation")
	_assert(not chest.contains('scale.y =') and not chest.contains('"scale:y"'), "no scale.y squash")
	_assert(not chest.contains("_cinematic_zoom"), "no cinematic zoom")
	_assert(chest.contains("preload_assets"), "preload")
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads")
	_assert(main.contains("No new scrolls today."), "empty copy")
	_assert(main.contains("OPEN_EMPTY"), "retap handles OPEN_EMPTY")
	_assert(main.contains("play_open_empty_pulse"), "retap pulse wired")
	_assert(boot.contains("MIN_VISIBLE_SEC := 2.0"), "splash min 2s untouched")

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
	for i in range(10):
		_assert(
			FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_%02d.png" % i),
			"empty frame %02d" % i
		)
	for i in range(13):
		_assert(
			FileAccess.file_exists("res://assets/art/chest/frames/scroll/scroll_%02d.png" % i),
			"scroll frame %02d" % i
		)

	_assert(flags.contains("APP_VERSION_CODE := 38"), "versionCode 38")
	_assert(preset.contains("version/code=38"), "export 38")
	_assert(preset.contains("fantasy-sheet-chest-debug.apk"), "APK name")
	## Fantasy APK must remain ignored (GitHub 100MB); do not force-add via !build/ exception.
	_assert(gitignore.contains("*.apk"), "apks ignored by default")
	_assert(
		not gitignore.contains("!build/ChestOfLoveNotes-fantasy-sheet-chest-debug.apk"),
		"fantasy APK gitignore exception removed"
	)
	_assert(export_sh.contains("fantasy-sheet-chest-debug.apk"), "export default")
	_assert(chest.contains("func play_open_animation"), "open API")
	_assert(chest.contains("func play_open_empty_pulse"), "pulse API")

	## Runtime: preload + pose snaps for representative states.
	LoveNotesChest.preload_assets()
	var node := LoveNotesChest.new()
	root.add_child(node)
	node.size = Vector2(320, 320)
	await process_frame
	_assert(node._empty_frames.size() == 10, "empty frames loaded")
	_assert(node._scroll_frames.size() == 13, "scroll frames loaded")

	var states := [
		{"name": "closed", "p": 0.0, "scroll": false},
		{"name": "early_opening", "p": 0.22, "scroll": false},
		{"name": "half_open", "p": 0.48, "scroll": false},
		{"name": "fully_open", "p": 1.0, "scroll": false},
		## Scroll reveal is gated until eased >= 0.62 (after chest is substantially open).
		{"name": "scroll_begin", "p": 0.72, "scroll": true},
		{"name": "scroll_halfway", "p": 0.86, "scroll": true},
		{"name": "scroll_full", "p": 1.0, "scroll": true},
	]
	var out_dir := "res://../.cursor_tmp_chest_validate"
	## Write under user:// for headless reliability.
	var user_dir := "user://chest_validate_v38"
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("chest_validate_v38"))
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
				var path := OS.get_user_data_dir().path_join("chest_validate_v38/%s.png" % s["name"])
				img.save_png(path)
				print("WROTE ", path)
		_assert(node._frame_index >= 0, "state %s frame index" % s["name"])

	## Rapid-tap guard
	node.animating = true
	var blocked := true
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
