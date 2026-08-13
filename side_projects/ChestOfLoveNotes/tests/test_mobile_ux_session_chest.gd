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
	_assert(app_src.contains("silent"), "silent restore reasons present")
	_assert(app_src.contains("await_ready"), "waits for Android secure plugin readiness")
	_assert(app_src.contains("persist_session_verified"), "verified persist helper present")
	_assert(app_src.contains("membership_soft_fail_continued") or app_src.contains("membership_soft_fail"), "soft membership path present")
	_assert(not app_src.contains('session_restore_message = "Could not verify your account'), "no false verify toast message")
	_assert(app_src.contains("refresh_invalid"), "resume hard refresh invalid path present")
	_assert(app_src.contains("forbidden"), "cold restore checks membership forbidden before sign-out")
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(auth_src.contains("_last_refresh_result"), "refresh waiters keep leader soft/hard result")


func _test_persist_verified() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("persist_session_verified"), "sign-in verifies Keystore persist")
	_assert(not main_src.contains("Secure session persisted successfully"), "no fake persist-success toast")
	_assert(main_src.contains("CharoiteBoot"), "Charoite cold boot wired")
	_assert(main_src.contains('restore.get("silent"'), "startup restore silence gate")
	_assert(main_src.contains("play_open_empty_pulse") or main_src.contains("No new scrolls today"), "empty chest open feedback")
	_assert(not main_src.contains("opened=%d"), "no debug opened= sent status")
	_assert(main_src.contains("_format_sent_status"), "human sent status helper")
	_assert(main_src.contains("Signing In…") or main_src.contains("◌"), "sign-in spinner present")
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
	_assert(MobileUi.SIZE_NAV_LABEL >= 14 and MobileUi.SIZE_NAV_LABEL <= 16, "nav label readable size")
	_assert(MobileUi.TOUCH_PRIMARY_H >= 52 and MobileUi.TOUCH_PRIMARY_H <= 56, "primary button 52–56")
	_assert(MobileUi.INPUT_H >= 48 and MobileUi.INPUT_H <= 52, "input height 48–52")
	_assert(MobileUi.TOUCH_NAV_H >= 68 and MobileUi.TOUCH_NAV_H <= 80, "nav height touch-friendly")
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
	_assert(ui_src.contains("follow_focus = false"), "follow_focus disabled globally")
	_assert(ui_src.contains("SCROLL_MODE_SHOW_NEVER"), "scrollbars hidden")
	_assert(ui_src.contains("wire_keyboard_avoidance"), "shared keyboard avoidance")
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
	_assert(
		FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_00.png")
		or FileAccess.file_exists("res://assets/art/chest/chest_closed.png"),
		"chest production art present"
	)
	var chest_src := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(not chest_src.contains("FRAME_KEYS"), "static pose keyframe table removed")
	_assert(
		chest_src.contains("assets/art/chest/frames/")
		or chest_src.contains("FRAME_FILES")
		or chest_src.contains("chest_closed.png"),
		"frame sequence wired"
	)
	_assert(
		chest_src.contains("_set_frame_progress") or chest_src.contains("_show_frame_progress"),
		"frame progress open"
	)
	_assert(chest_src.contains("preload_assets"), "chest preload present")
	_assert(chest_src.contains("play_empty_feedback"), "empty-chest helper present")
	_assert(chest_src.contains("play_open_empty_pulse"), "empty open pulse present")
	_assert(
		chest_src.contains("SCROLL_REVEAL_START_INDEX") or chest_src.contains("_emerge_scroll"),
		"scroll emergence path present"
	)
	_assert(chest_src.contains("play_close_animation"), "close animation present")
	_assert(chest_src.contains("TRANS_CUBIC") or chest_src.contains("_ease_open_curve"), "non-linear timing")
	_assert(chest_src.contains("_apply_root_offset") or chest_src.contains("_anticipation_y"), "fixed base / tiny anticipation without whole-chest zoom")
	_assert(not chest_src.contains("chest_open_90.png"), "black-bg 90% frame removed from playback")
	_assert(not chest_src.contains("var _latch"), "detached latch overlay removed")
	_assert(not chest_src.contains("var _lock"), "detached lock overlay removed")
	_assert(not chest_src.contains("chest_latch.png"), "latch texture not wired")
	_assert(not chest_src.contains("chest_lock.png"), "lock texture not wired")
	_assert(chest_src.contains("CLOSING"), "closing state present")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("play_open_animation(state.reduced_motion"), "main uses cinematic open")
	_assert(main_src.contains("var chest_w := 252") or main_src.contains("var chest_side := 252"), "main chest display ~252")
	_assert(main_src.contains("chest_h := 326") or main_src.contains("chest_h := 292"), "taller chest host")
	_assert(main_src.contains("No new scrolls today"), "empty open message present")
	_assert(main_src.contains("_begin_nav_transition"), "prepared page transitions")
	_assert(
		main_src.contains("Hidden from Sent history")
		or main_src.contains("Scroll hidden"),
		"sent hide uses snackbar text"
	)
	_assert(main_src.contains("_add_inventory_filter_rows"), "shared chest filter rows")
	_assert(main_src.contains('_add_inventory_filter_rows(root, "saved")'), "Saved keeps Hidden sibling")
	_assert(main_src.contains("_dismiss_toast_if_visible"), "dismiss toast before chest reward")
	_assert(main_src.contains("_hide_sent_with_undo"), "sent hide undo path")
	_assert(main_src.contains("No sent scrolls yet"), "sent empty state present")
	_assert(main_src.contains("scroll_rolled.png"), "sent empty uses vector scroll icon")
	_assert(main_src.contains("Signing In…"), "sign-in loading label present")
	_assert(main_src.contains("SHOW_ONBOARDING_BANNER") or main_src.contains("BuildFlags.SHOW_ONBOARDING_BANNER"), "onboarding banner gated off")


func _test_startup_charoite() -> void:
	_assert(FileAccess.file_exists("res://assets/branding/charoite_system_splash_dark.png"), "dark splash asset")
	_assert(FileAccess.file_exists("res://assets/branding/charoite_games_cg_logo.png"), "official CG logo packaged")
	_assert(FileAccess.file_exists("res://scripts/ui/charoite_boot.gd"), "CharoiteBoot script")
	var boot_src := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	_assert(boot_src.contains("MIN_VISIBLE_SEC := 4.0"), "boot minimum visible ~4.0 seconds")
	_assert(boot_src.contains("mark_app_ready"), "boot waits for app-ready gate")
	_assert(boot_src.contains("FADE_OUT_SEC := 0.20"), "short fade-out into app")
	_assert(boot_src.contains("splash_frames"), "approved animated CG frames")
	_assert(boot_src.contains("splash_still.png"), "reduced-motion still CG frame")
	_assert(not boot_src.contains('_label.text = "Charoite Games"'), "no duplicate text label")
	_assert(not boot_src.contains("var _label"), "no studio text Label node")
	_assert(not boot_src.to_lower().contains("chest_closed"), "boot scene has no chest art")
	_assert(not boot_src.contains("charoite_boot_splash.png"), "PRESENTS splash not used in CharoiteBoot")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("mark_app_ready"), "main marks boot ready after restore")
	_assert(main_src.contains("Text Size"), "Text Size setting in Profile")
	_assert(main_src.contains("Reduced Motion"), "Reduced Motion setting in Profile")
	_assert(main_src.contains("Unread"), "summary Unread label")
	_assert(main_src.contains("YOUR CHEST") or main_src.contains("Your Chest"), "Your Chest management heading")
	_assert(main_src.contains("SHOW_ONBOARDING_BANNER"), "onboarding banner flag referenced")
	_assert(not main_src.contains('_banner.text = "Private Onboarding Build"'), "Private Onboarding banner text removed")


func _test_plugin_commit() -> void:
	var kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestSecureStoragePlugin.kt")
	_assert(kt.contains(".commit()"), "SharedPreferences uses commit for durability")
	_assert(not kt.contains(".apply()"), "no async apply for session writes")
	_assert(kt.contains("ChestOfLoveNotesSessionKey"), "Keystore alias present")


func _test_build_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE >= 26, "versionCode >= 24")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(
		preset.contains("ChestOfLoveNotes-v47-chest-clean-transition-debug.apk") or preset.contains("v46-chest-geometry-grounding-debug.apk") or preset.contains("ChestOfLoveNotes-v45-chest-grounding-scroll-fix-debug.apk") or preset.contains("ChestOfLoveNotes-v44-chest-render-scroll-beach-polish-debug.apk")
		or preset.contains("ChestOfLoveNotes-v40-chest-smoothing-hidden-fix-debug.apk")
		or preset.contains("ChestOfLoveNotes-v39-chest-polish-debug.apk")
		or preset.contains("ChestOfLoveNotes-fantasy-sheet-chest-debug.apk")
		or preset.contains("ChestOfLoveNotes-game-quality-chest-disconnect-fix-debug.apk")
		or preset.contains("splash-timing-chest-animation-fix-debug.apk"),
		"export APK name"
	)
	_assert(preset.contains("version/code=47") or preset.contains("version/code=46") or preset.contains("version/code=45") or preset.contains("version/code=42") or preset.contains("version/code=41") or preset.contains("version/code=40") or preset.contains("version/code=39") or preset.contains("version/code=37") or preset.contains("version/code=33") or preset.contains("version/code=32"), "export versionCode recent")
	_assert(BuildFlags.PRIVATE_ONBOARDING_BUILD == true, "private onboarding still enabled")
	_assert(BuildFlags.SHOW_ONBOARDING_BANNER == false, "onboarding banner hidden in APKs")
	_assert(FileAccess.file_exists("res://assets/icons/app_icon_1024.png"), "app icon present")
	_assert(FileAccess.file_exists("res://assets/icons/adaptive_foreground.png"), "adaptive foreground present")
	var icon_readme := FileAccess.get_file_as_string("res://assets/icons/README_ICON.txt")
	_assert(icon_readme.contains("must NOT use the Charoite Games CG logo"), "icon readme forbids CG logo")


func _test_resume_gate() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("if not _startup_done"), "resume ignored until startup done")
	_assert(main_src.contains("_resume_inflight"), "resume single-flight coalesces FOCUS_IN+RESUMED")
	_assert(main_src.contains("membership_soft_fail") or main_src.contains("play_open_empty_pulse"), "soft membership / empty chest paths")
	_assert(main_src.contains("Vector2(354") or main_src.contains("modal_w := 354"), "modals sized for 390 viewport")
	_assert(main_src.contains("Preview Chest Scroll Open"), "debug chest scroll preview path")
	var app_src := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	_assert(app_src.contains("user_soft_fail_continued"), "soft user fail does not wipe session")
	_assert(app_src.contains("email_confirmed_persisted") or app_src.contains("user_soft_fail_continued"), "restore soft-fail email guard")
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
