extends SceneTree
## v32: Splash min-visible 2.0s + chest opening polish (no scale/squash/ghost).

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
	print("=== Splash timing + chest animation fix (v32) ===")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")

	## SPLASH — timing only; approved artwork untouched
	_assert(boot.contains("MIN_VISIBLE_SEC := 2.0"), "min visible 2.0s")
	_assert(boot.contains("FADE_OUT_SEC := 0.20"), "fade out ~200ms")
	_assert(boot.contains("func mark_app_ready"), "app-ready gate")
	_assert(boot.contains("visible_elapsed >= MIN_VISIBLE_SEC and _app_ready"), "min time AND ready")
	_assert(boot.contains("splash_frames_meta.json"), "uses approved frame meta")
	_assert(boot.contains("splash_still.png"), "reduced-motion still")
	_assert(not boot.contains("MIN_DURATION_SEC := 1.75"), "old 1.75 constant removed")
	_assert(main.contains("mark_app_ready"), "main wires app-ready after restore")
	_assert(FileAccess.file_exists("res://assets/branding/splash_frames_meta.json"), "frame meta packaged")
	_assert(FileAccess.file_exists("res://assets/branding/splash_still.png"), "still frame packaged")

	## CHEST — frame-based, no whole-chest scale open, no squash
	_assert(chest.contains("FRAME_FILES"), "authored frame list")
	_assert(chest.contains("chest_closed.png"), "closed plate")
	_assert(chest.contains("chest_open.png"), "open plate")
	_assert(chest.contains("OPEN_DURATION_SEC := 0.95"), "open ~0.95s")
	_assert(chest.contains("OPEN_SCROLL_EMERGING"), "scroll-emerging state")
	_assert(chest.contains("sfx_open_start"), "sound hook open start")
	_assert(chest.contains("sfx_fully_open"), "sound hook fully open")
	_assert(chest.contains("sfx_scroll_emerge"), "sound hook scroll")
	_assert(chest.contains("play_open_empty_pulse"), "empty retap pulse")
	_assert(chest.contains("_anticipation_y"), "tiny Y anticipation")
	_assert(not chest.contains("_cinematic_zoom"), "cinematic zoom removed")
	_assert(not chest.contains("_apply_centered_zoom"), "centered zoom helper removed")
	_assert(not chest.contains("scale.y"), "no scale.y squash")
	_assert(chest.contains("preload_assets"), "chest assets preloaded")
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads chest")
	_assert(main.contains("No new scrolls today."), "empty message")
	_assert(main.contains("play_open_empty_pulse"), "retap uses pulse")
	_assert(main.contains("play_open_animation(state.reduced_motion, has_new)"), "scroll only when new")

	## Frame assets present (same-canvas plates)
	for fname in [
		"chest_closed.png",
		"chest_open_10.png",
		"chest_open_25.png",
		"chest_ajar.png",
		"chest_half.png",
		"chest_open.png",
	]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % fname), "asset %s" % fname)

	## VERSION / APK
	_assert(BuildFlags.APP_VERSION_CODE >= 32, "BuildFlags >= 32")
	_assert(preset.contains("version/code="), "export has versionCode")
	_assert(
		gitignore.contains("splash-timing-chest-animation-fix-debug.apk")
		or gitignore.contains("game-quality-chest-disconnect-fix-debug.apk"),
		"gitignore allows debug APK"
	)

	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
