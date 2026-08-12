extends SceneTree
## v36: Seamless layered hinged chest (not plate slideshow).

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
	print("=== Seamless game-quality chest (v36) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")

	_assert(chest.contains("continuous hinged lid") or chest.contains("Seamless layered"), "layered continuous architecture")
	_assert(chest.contains("chest_lid.png"), "lid asset")
	_assert(chest.contains("chest_body_planted.png"), "planted body")
	_assert(chest.contains("chest_front_lip.png"), "front rim")
	_assert(chest.contains("chest_inner_glow.png"), "glow")
	_assert(chest.contains("chest_interior.png"), "interior")
	_assert(chest.contains("HINGE_CANVAS"), "rear hinge pivot")
	_assert(chest.contains("LID_OPEN_ANGLE"), "lid angle")
	_assert(chest.contains("_lid.rotation"), "lid rotation driven")
	_assert(chest.contains("pivot_offset"), "hinge via pivot")
	_assert(chest.contains("OPEN_DURATION_SEC := 1.00"), "open ~1.0s")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 0.68"), "scroll emerge duration")
	_assert(chest.contains("_ease_open_curve"), "quality easing")
	_assert(chest.contains("OPEN_WAITING_FOR_SCROLL"), "waiting state")
	_assert(chest.contains("OPEN_SCROLL_EMERGING"), "emerging state")
	_assert(chest.contains("play_open_empty_pulse"), "empty retap pulse")
	_assert(chest.contains("_extra_scroll_a"), "multi-scroll edge hint")
	_assert(chest.contains("clip_contents = true"), "scroll occlusion clip")
	_assert(not chest.contains("FRAME_FILES"), "no plate slideshow list")
	_assert(not chest.contains("_frame_plate"), "no frame plate swapper")
	_assert(not chest.contains("_set_frame_index"), "no discrete frame index")
	_assert(not chest.contains('scale.y =') and not chest.contains('"scale:y"'), "no scale.y squash")
	_assert(not chest.contains("_cinematic_zoom"), "no cinematic zoom")
	_assert(chest.contains("preload_assets"), "preload")
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads")
	_assert(main.contains("No new scrolls today."), "empty copy")
	_assert(main.contains("OPEN_EMPTY"), "retap handles OPEN_EMPTY")
	_assert(main.contains("play_open_empty_pulse"), "retap pulse wired")

	for fname in [
		"chest_lid.png",
		"chest_body_planted.png",
		"chest_front_lip.png",
		"chest_inner_glow.png",
		"chest_interior.png",
		"chest_contact_shadow.png",
	]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % fname), "asset %s" % fname)
	_assert(FileAccess.file_exists("res://assets/art/scroll/scroll_rolled.png"), "scroll rolled")

	_assert(flags.contains("APP_VERSION_CODE := 36"), "versionCode 36")
	_assert(preset.contains("version/code=36"), "export 36")
	_assert(preset.contains("seamless-game-quality-chest-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-seamless-game-quality-chest-debug.apk"), "gitignore")
	_assert(export_sh.contains("seamless-game-quality-chest-debug.apk"), "export default")

	## Static API / constant checks (no SceneTree await — keeps headless -s reliable).
	_assert(chest.contains("func play_open_animation"), "open API")
	_assert(chest.contains("func play_open_empty_pulse"), "pulse API")
	_assert(chest.contains("LID_OPEN_ANGLE := -1.18"), "open angle constant")
	_assert(chest.contains("_lid_angle = lerpf(0.0, LID_OPEN_ANGLE, eased)"), "continuous angle lerp")
	_assert(chest.contains("if animating") and chest.contains("return"), "guards overlapping anim")

	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
