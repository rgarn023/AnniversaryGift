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
	_test_chest_frames()
	_test_startup_copy()
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
	# Soft clear keeps Keystore
	tokens.clear(false)
	_assert(AndroidSecureStore.has_session(), "soft clear keeps Keystore session")
	_assert(tokens.restore_from_secure_storage(), "can restore after soft clear")
	# Hard clear removes
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
	_assert(main_src.contains("Opening your chest"), "user-facing startup copy")
	_assert(not main_src.contains("Restoring secure session"), "no technical restore copy for users")
	_assert(main_src.contains("_log_secure_debug"), "debug secure YES/NO logging")
	_assert(main_src.contains("_add_bottom_nav"), "bottom navigation present")


func _test_mobile_ui_scale() -> void:
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.0), "Standard scale 1.0")
	_assert(MobileUi.font(20) == 20, "Standard body 20")
	MobileUi.set_text_size(MobileUi.TextSize.LARGE)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.2), "Large scale 1.20")
	_assert(MobileUi.font(20) == 24, "Large body 24")
	MobileUi.set_text_size(MobileUi.TextSize.EXTRA_LARGE)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.4), "Extra Large scale 1.40")
	_assert(MobileUi.font(20) == 28, "Extra Large body 28")
	_assert(MobileUi.TOUCH_MIN >= 48, "touch min 48")
	_assert(MobileUi.TOUCH_PRIMARY_H >= 56, "primary touch >= 56")
	MobileUi.set_reduced_motion(true)
	_assert(MobileUi.reduced_motion(), "Reduced Motion can enable")
	MobileUi.set_reduced_motion(false)
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	var ui_src := FileAccess.get_file_as_string("res://scripts/ui/mobile_ui.gd")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(ui_src.contains("Android system font-scale"), "documents Android font-scale limitation")
	_assert(not ui_src.contains(".scale ="), "does not apply node scale transforms for text")
	_assert(ui_src.contains("autowrap: bool = false"), "labels default to no autowrap")
	_assert(main_src.contains("OVERRUN_TRIM_ELLIPSIS"), "title uses ellipsis not vertical wrap")
	_assert(main_src.contains("area.x * 0.52"), "chest sized to usable width")


func _test_chest_frames() -> void:
	for f in [
		"chest_closed.png", "chest_open_10.png", "chest_open_25.png", "chest_ajar.png",
		"chest_open_50.png", "chest_half.png", "chest_open_75.png", "chest_open_90.png",
		"chest_open.png",
	]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % f), "frame exists: " + f)
	var chest_src := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest_src.contains("FRAME_KEYS"), "multi-frame keys present")
	_assert(chest_src.contains("chest_open_10.png"), "10% frame wired")
	_assert(chest_src.contains("chest_open_90.png"), "90% frame wired")
	_assert(chest_src.contains("play_close_animation"), "close animation present")
	_assert(chest_src.contains("TRANS_CUBIC"), "non-linear timing")
	_assert(main_uses_full_open(), "main chest uses full open (not always short)")


func main_uses_full_open() -> bool:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	return main_src.contains("play_open_animation(state.reduced_motion)")


func _test_startup_copy() -> void:
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
	_assert(BuildFlags.APP_VERSION_CODE >= 5, "versionCode >= 5")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("ChestOfLoveNotes-mobile-accessibility-session-chest-debug.apk"), "export APK name")
	_assert(preset.contains("version/code=5"), "export versionCode 5")
	_assert(BuildFlags.PRIVATE_ONBOARDING_BUILD == true, "private onboarding still enabled")


func _test_anniversary_untouched() -> void:
	var f := FileAccess.open("/workspace/export_presets.cfg", FileAccess.READ)
	_assert(f != null, "Anniversary Gift export_presets present")
	if f:
		var text := f.get_as_text()
		f.close()
		_assert(text.contains("anniversarygift") or text.contains("AnniversaryGift"), "AG export remains")
		_assert(not text.contains("chestoflovenotes"), "AG not rewritten to COLN")
