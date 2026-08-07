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
	_test_resume_gate()
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
	_assert(app_src.contains("membership_soft_fail"), "resume soft membership path present")
	_assert(app_src.contains("refresh_invalid"), "resume hard refresh invalid path present")


func _test_persist_verified() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("persist_session_verified"), "sign-in verifies Keystore persist")
	_assert(main_src.contains("Secure session persisted successfully"), "debug persist success toast")
	_assert(main_src.contains("CharoiteBoot"), "Charoite cold boot wired")
	_assert(not main_src.contains("Restoring secure session"), "no technical restore copy for users")
	_assert(main_src.contains("_log_secure_debug"), "debug secure YES/NO logging")
	_assert(main_src.contains("_add_bottom_nav"), "bottom navigation present")
	_assert(main_src.contains("_startup_done"), "startup gate for resume")
	_assert(main_src.contains("_settings_long_value_card"), "profile long-value layout")
	_assert(main_src.contains("configure_scroll") or main_src.contains("_wire_scroll"), "touch scroll wiring")


func _test_mobile_ui_scale() -> void:
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.0), "Standard scale 1.0")
	_assert(MobileUi.font(17) == 17, "Standard body 17")
	_assert(MobileUi.SIZE_APP_TITLE >= 24 and MobileUi.SIZE_APP_TITLE <= 28, "app title in 24–28")
	_assert(MobileUi.SIZE_SCREEN_TITLE >= 22 and MobileUi.SIZE_SCREEN_TITLE <= 26, "screen title in 22–26")
	_assert(MobileUi.SIZE_BODY >= 16 and MobileUi.SIZE_BODY <= 18, "body in 16–18")
	_assert(MobileUi.SIZE_NAV_LABEL >= 12 and MobileUi.SIZE_NAV_LABEL <= 14, "nav label in 12–14")
	_assert(MobileUi.TOUCH_PRIMARY_H >= 52 and MobileUi.TOUCH_PRIMARY_H <= 56, "primary button 52–56")
	_assert(MobileUi.INPUT_H >= 48 and MobileUi.INPUT_H <= 52, "input height 48–52")
	_assert(MobileUi.TOUCH_NAV_H >= 64 and MobileUi.TOUCH_NAV_H <= 72, "nav height 64–72")
	MobileUi.set_text_size(MobileUi.TextSize.LARGE)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.2), "Large scale 1.20")
	_assert(MobileUi.font(17) == 20, "Large body 20")
	MobileUi.set_text_size(MobileUi.TextSize.EXTRA_LARGE)
	_assert(is_equal_approx(MobileUi.scale_factor(), 1.4), "Extra Large scale 1.40")
	_assert(MobileUi.font(17) == 24, "Extra Large body 24")
	_assert(MobileUi.TOUCH_MIN >= 48, "touch min 48")
	MobileUi.set_reduced_motion(true)
	_assert(MobileUi.reduced_motion(), "Reduced Motion can enable")
	MobileUi.set_reduced_motion(false)
	MobileUi.set_text_size(MobileUi.TextSize.STANDARD)
	var ui_src := FileAccess.get_file_as_string("res://scripts/ui/mobile_ui.gd")
	_assert(ui_src.contains("Android system font-scale"), "documents Android font-scale limitation")
	_assert(ui_src.contains("configure_scroll"), "scroll helper present")
	_assert(ui_src.contains("_pass_drag_through"), "touch drag pass-through present")
	_assert(not ui_src.contains("Control.scale"), "does not apply Control.scale for text")


func _test_logical_viewport() -> void:
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_assert(proj.contains("viewport_width=390"), "logical width 390")
	_assert(proj.contains("viewport_height=844"), "logical height 844")
	_assert(proj.contains('stretch/mode="canvas_items"'), "canvas_items stretch")
	_assert(proj.contains("charoite_system_splash_dark.png"), "dark system splash configured")
	_assert(not proj.contains("viewport_width=1080"), "no longer 1080 logical width")
	_assert(not proj.contains("charoite_boot_splash.png"), "PRESENTS splash removed from boot_splash")


func _test_chest_frames() -> void:
	for f in ["chest_closed.png", "chest_open.png"]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % f), "frame exists: " + f)
	var chest_src := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest_src.contains("FRAME_KEYS"), "multi-frame keys present")
	_assert(chest_src.contains("chest_closed.png"), "closed frame wired")
	_assert(chest_src.contains("chest_open.png"), "open frame wired")
	_assert(chest_src.contains("play_close_animation"), "close animation present")
	_assert(chest_src.contains("TRANS_CUBIC"), "non-linear timing")
	_assert(not chest_src.contains("chest_open_90.png"), "black-bg 90% frame removed from playback")
	_assert(not chest_src.contains("_latch"), "detached latch overlay removed")
	_assert(not chest_src.contains("_lock"), "detached lock overlay removed")
	_assert(chest_src.contains("CLOSING"), "closing state present")
	_assert(chest_src.contains("FRAME_SIZE := Vector2(220"), "balanced chest footprint")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("play_open_animation(state.reduced_motion)"), "main uses full open")
	_assert(main_src.contains("var chest_side := 220"), "main chest display ~220")


func _test_startup_charoite() -> void:
	_assert(FileAccess.file_exists("res://assets/branding/charoite_system_splash_dark.png"), "dark splash asset")
	_assert(FileAccess.file_exists("res://scripts/ui/charoite_boot.gd"), "CharoiteBoot script")
	var boot_src := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	_assert(boot_src.contains("MIN_DURATION_SEC := 5.0"), "boot minimum 5 seconds")
	_assert(boot_src.contains("charoite_games_cg_logo.png"), "official CG logo path preferred")
	_assert(not boot_src.contains("Charoite Games Presents"), "no Presents copy")
	_assert(not boot_src.contains('_label.text = "Charoite Games"'), "no duplicate text label")
	_assert(not boot_src.to_lower().contains("chest_closed"), "boot scene has no chest art")
	_assert(not boot_src.contains("charoite_boot_splash.png"), "PRESENTS splash not used in CharoiteBoot")
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
	_assert(BuildFlags.APP_VERSION_CODE >= 8, "versionCode >= 8")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("ChestOfLoveNotes-mobile-correction-complete-debug.apk"), "export APK name")
	_assert(preset.contains("version/code=8"), "export versionCode 8")
	_assert(BuildFlags.PRIVATE_ONBOARDING_BUILD == true, "private onboarding still enabled")


func _test_resume_gate() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("if not _startup_done"), "resume ignored until startup done")
	_assert(main_src.contains("membership_soft_fail"), "soft membership does not force login")
	var mem_src := FileAccess.get_file_as_string("res://scripts/network/membership_service.gd")
	_assert(mem_src.contains("_claim_inflight"), "membership single-flight")
	_assert(mem_src.contains("_claim_membership_inner"), "membership claim does not clear at start")


func _test_anniversary_untouched() -> void:
	var f := FileAccess.open("/workspace/export_presets.cfg", FileAccess.READ)
	_assert(f != null, "Anniversary Gift export_presets present")
	if f:
		var text := f.get_as_text()
		_assert(text.contains("com.charoitegames.anniversarygift") or text.contains("Anniversary"), "Anniversary Gift preset intact")
		f.close()
