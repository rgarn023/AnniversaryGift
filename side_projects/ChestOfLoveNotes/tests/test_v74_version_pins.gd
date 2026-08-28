extends SceneTree
## v74 version + release-gate pins.

var _passed := 0
var _failed := 0


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % msg)
	else:
		_failed += 1
		print("FAIL: %s" % msg)


func _init() -> void:
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	var gate := FileAccess.get_file_as_string("res://android/signing/LAST_RELEASED_VERSION_CODE").strip_edges()
	var ci := FileAccess.get_file_as_string("res://tools/ci_export_android_artifacts.sh")
	var wf := ""
	if FileAccess.file_exists("res://../../.github/workflows/build-chest-of-love-notes-android.yml"):
		wf = FileAccess.get_file_as_string("res://../../.github/workflows/build-chest-of-love-notes-android.yml")

	_assert(BuildFlags.APP_VERSION_CODE == 74, "BuildFlags versionCode 74")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.74-auth-recovery-google-signin", "BuildFlags versionName")
	_assert(flags.contains("APP_VERSION_CODE := 74"), "flags source 74")
	_assert(preset.contains("version/code=74"), "export versionCode 74")
	_assert(preset.contains("0.1.74-auth-recovery-google-signin"), "export versionName")
	_assert(preset.contains("154659_cursor_under4mb.gif"), "splash GIF excluded")
	_assert(proj.contains("0.1.74-auth-recovery-google-signin"), "project.godot version")
	_assert(gate == "72", "LAST_RELEASED_VERSION_CODE remains 72")
	_assert(ci.contains('APK_NAME="ChestOfLoveNotes-v${VERSION_CODE}-arm64-release.apk"'), "CI APK name uses VERSION_CODE")
	_assert(ci.contains("GATE_PIN"), "CI version-aware gate")
	_assert(not ci.contains('APK_NAME="ChestOfLoveNotes-v72-arm64-release.apk"'), "CI not hard-pinned to v72 APK name")
	if not wf.is_empty():
		_assert(wf.contains("ChestOfLoveNotes-v74-APK"), "workflow APK artifact name")
		_assert(wf.contains("tools/ci_export_android_artifacts.sh"), "workflow uses version-aware script")
		_assert(wf.contains('LAST_RELEASED_VERSION_CODE)" = "72"'), "workflow keeps gate at 72")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
