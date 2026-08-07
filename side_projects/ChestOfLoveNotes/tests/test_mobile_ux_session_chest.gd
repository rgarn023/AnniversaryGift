extends SceneTree
## Headless contracts for mobile UX, accessibility, session restore hardening, chest frames.

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
	print("=== Mobile UX / Session / Chest Tests ===")
	AndroidSecureStore.enable_test_backend()
	_test_session_soft_fail_keeps_keystore()
	_test_persist_verified()
	_test_mobile_ui_scale()
	_test_logical_viewport()
	_test_chest_frames()
	_test_startup_charoite()
	_test_plugin_commit()
	_test_build_version()
	_test_anniversary_untouched()
	AndroidSecureStore.disable_test_backend()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_session_soft_fail_keeps_keystore() -> void:
	AndroidSecureStore.enable_test_backend()
	var tokens := SecureTokenService.new()
	tokens.set_keep_me_signed_in(true)
	tokens.set_session("access-a", "refresh-a", 9999999999)
	tokens.set_user("u1", "a@example.com", true)
	_assert(tokens.persist_if_needed(), "persist succeeds on test backend")
	_assert(AndroidSecureStore.has_session(), "ciphertext present")
	tokens.clear(false)
	_assert(AndroidSecureStore.has_session(), "soft clear keeps Keystore session")
	_assert(tokens.restore_from_secure_storage(), "can restore after soft clear")
	tokens.clear(true)
	_assert(not AndroidSecureStore.has_session(), "hard clear deletes Keystore session")
	var app_src := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	_assert(app_src.contains("refresh_soft_fail"), "restore soft-fail path present")
	_assert(app_src.contains("clear(false)"), "soft failures clear memory only")
	_assert(app_src.contains("persist_session_verified"), "verified persist helper present")


func _test_persist_verified() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("persist_session_verified"), "sign-in verifies Keystore persist")
	_assert(main_src.contains("Secure session persisted successfully"), "debug persist success toast")
	_assert(main_src.contains("CharoiteBoot"), "Charoite cold boot wired")
	_assert(not main_src.contains("Restoring secure session"), "no technical restore copy for users")
	_assert(main_src.contains("_log_secure_debug"), "debug secure YES/NO logging")
	_assert(main_src.contains("_add_bottom_nav"), "bottom navigation present")


func _test_mobile_ui_scale() -> void:
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.0), "Standard scale 1.0")
	_assert(MobileUi.font(18) == 18, "Standard body 18")
	MobileUi.set_text_size(MobileUi.TextSize.LARGE)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.2), "Large scale 1.20")
	_assert(MobileUi.font(18) == 22, "Large body 22")
	MobileUi.set_text_size(MobileUi.TextSize.EXTRA_LARGE)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.4), "Extra Large scale 1.40")
	_assert(MobileUi.font(18) == 25, "Extra Large body 25")
	_assert(MobileUi.TOUCH_MIN >= 48, "touch min 48")
	_assert(MobileUi.TOUCH_PRIMARY_H >= 56, "primary touch >= 56")
	MobileUi.set_reduced_motion(true)
	_assert(MobileUi.reduced_motion(), "Reduced Motion can enable")
	MobileUi.set_reduced_motion(false)
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	var ui_src := FileAccess.get_file_as_string("res://scripts/ui/mobile_ui.gd")
	_assert(ui_src.contains("Android system font-scale"), "documents Android font-scale limitation")
	_assert(not ui_src.contains(".scale ="), "does not apply node scale transforms for text")


func _test_logical_viewport() -> void:
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_assert(proj.contains("viewport_width=390"), "logical width 390")
	_assert(proj.contains("viewport_height=844"), "logical height 844")
	_assert(proj.contains('stretch/mode="canvas_items"'), "canvas_items stretch")
	_assert(proj.contains("charoite_boot_splash.png"), "Charoite boot splash configured")
	_assert(not proj.contains("viewport_width=1080"), "no longer 1080 logical width")


func _test_chest_frames() -> void:
	for f in [
		"opening_frames/frame_00_closed.png",
		"opening_frames/frame_01_open10.png",
		"opening_frames/frame_02_open25.png",
		"opening_frames/frame_03_ajar.png",
		"opening_frames/frame_04_half.png",
		"opening_frames/frame_05_open.png",
	]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % f), "frame exists: " + f)
	var chest_src := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest_src.contains("FRAME_KEYS"), "multi-frame keys present")
	_assert(chest_src.contains("opening_frames"), "uses curated opening_frames path")
	_assert(chest_src.contains("frame_00_closed.png"), "closed frame wired")
	_assert(chest_src.contains("play_close_animation"), "close animation present")
	_assert(chest_src.contains("TRANS_CUBIC"), "non-linear timing")
	_assert(not chest_src.contains("chest_open_90.png"), "black-bg 90% frame removed from playback")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("play_open_animation(state.reduced_motion)"), "main uses full open")


func _test_startup_charoite() -> void:
	_assert(FileAccess.file_exists("res://assets/art/charoite_boot_splash.png"), "Charoite splash asset")
	_assert(FileAccess.file_exists("res://assets/art/brand/charoite_games_wordmark.png"), "Charoite wordmark")
	_assert(FileAccess.file_exists("res://scripts/ui/charoite_boot.gd"), "CharoiteBoot script")
	var boot_src := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	_assert(boot_src.contains("MIN_DURATION_SEC := 5.0"), "boot minimum 5 seconds")
	_assert(not boot_src.to_lower().contains("chest_closed"), "boot scene has no chest art")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("Text Size"), "Text Size setting in Profile")
	_assert(main_src.contains("Reduced Motion"), "Reduced Motion setting in Profile")
	_assert(main_src.contains("Unread"), "summary Unread label")
	_assert(main_src.contains("Your Chest"), "Your Chest label")


func _test_plugin_commit() -> void:
	var kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestSecureStoragePlugin.kt")
	_assert(kt.contains(".commit()"), "SharedPreferences uses commit for durability")
	_assert(not kt.contains(".apply()"), "no async apply for session writes")
	_assert(kt.contains("ChestOfLoveNotesSessionKey"), "Keystore alias present")


func _test_build_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE >= 7, "versionCode >= 7")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("ChestOfLoveNotes-mobile-native-complete-fix-debug.apk"), "export APK name")
	_assert(preset.contains("version/code=7"), "export versionCode 7")
	_assert(BuildFlags.PRIVATE_ONBOARDING_BUILD == true, "private onboarding still enabled")


func _test_anniversary_untouched() -> void:
	var f := FileAccess.open("/workspace/export_presets.cfg", FileAccess.READ)
	_assert(f != null, "Anniversary Gift export_presets present")
	if f:
		var text := f.get_as_text()
		f.close()
		_assert(text.contains("anniversarygift") or text.contains("AnniversaryGift"), "AG export remains")
		_assert(not text.contains("chestoflovenotes"), "AG not rewritten to COLN")
