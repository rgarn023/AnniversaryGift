extends SceneTree
## Fixed preview, map pinch, activity/focus locks, attachments hidden.

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
	print("=== Preview / Activity / Focus / Notifications ===")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808180000_activity_focus_locks.sql")
	var send := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")

	_assert(viewer.contains("_zoom_pan_root"), "preview ZoomPanRoot")
	_assert(viewer.contains("_on_view_zoom_changed"), "preview composite zoom handler")
	_assert(viewer.contains("_content_rect"), "fixed content rect")
	_assert(viewer.contains("_font_step"), "font step A+/A-")
	_assert(viewer.contains("Reset"), "reset control")
	_assert(viewer.contains("NOTIFICATION_WM_GO_BACK_REQUEST"), "android back")
	_assert(viewer.contains("set_attachments"), "attachments ignored in preview")

	_assert(map.contains("_handle_map_pinch"), "map pinch zoom")
	_assert(map.contains("_bootstrap_map_after_layout"), "map first-paint bootstrap preserved")
	_assert(map.contains("_set_zoom_level"), "map +/- zoom helper")
	_assert(map.contains("_initial_paint_done"), "map one-instance after first paint")
	_assert(map.contains("_tile_nodes"), "map reuses tiles")

	_assert(compose.contains("_build_activity_card"), "activity lock card")
	_assert(compose.contains("_build_focus_card"), "focus lock card")
	_assert(compose.contains("Attachments removed from active product UI"), "attachments UI removed")
	_assert(compose.contains("activity_lock_enabled"), "activity in draft")
	_assert(compose.contains("focus_lock_enabled"), "focus in draft")
	_assert(compose.contains("Set Activity distance to at least 1 km."), "activity validation")
	_assert(compose.contains("Set Focus time between 1 and 24 hours."), "focus validation")

	_assert(mig.contains("activity_lock_enabled"), "migration activity")
	_assert(mig.contains("focus_lock_enabled"), "migration focus")
	_assert(mig.contains("activity_distance_km"), "migration progress fields")
	_assert(send.contains("activity_target_km"), "send-scroll activity")
	_assert(send.contains("focus_duration_hours"), "send-scroll focus")

	_assert(FileAccess.file_exists("res://android/plugins/chest_secure_storage/ChestFocusPlugin.kt"), "ChestFocus plugin")
	_assert(FileAccess.file_exists("res://android/plugins/chest_secure_storage/ChestNotifyPlugin.kt"), "ChestNotify plugin")
	_assert(FileAccess.file_exists("res://scripts/network/activity_lock_helper.gd"), "activity helper")
	_assert(FileAccess.file_exists("res://scripts/network/focus_lock_helper.gd"), "focus helper")
	_assert(FileAccess.file_exists("res://scripts/network/scroll_lock_evaluator.gd"), "central evaluator")
	_assert(FileAccess.file_exists("res://scripts/network/notification_helper.gd"), "notification helper")

	_assert(main.contains("ScrollLockEvaluator.evaluate"), "main uses central evaluator")
	_assert(main.contains("Start Challenge"), "activity start button")
	_assert(main.contains("Begin Focus Time") or main.contains("Start Focus Again"), "focus start button")
	_assert(main.contains("NotificationHelper"), "notifications wired")

	## Activity distance cumulative + jitter filter (spaced timestamps = realistic travel).
	var t0 := int(Time.get_unix_time_from_system()) - 600
	ActivityLockHelper.reset_challenge("test-scroll")
	ActivityLockHelper.start_challenge("test-scroll", 1.0, 37.0, -77.0)
	var st0: Dictionary = ActivityLockHelper.get_progress("test-scroll")
	st0["last_unix"] = t0
	var all0 := {"test-scroll": st0}
	## rewrite start timestamp via apply after adjusting store through helpers
	ActivityLockHelper.reset_challenge("test-scroll")
	var boot := ActivityLockHelper.start_challenge("test-scroll", 1.0, 37.0, -77.0)
	## Force older last_unix by applying a no-op tiny move then large moves with time.
	var lat := 37.0
	var lng := -77.0
	ActivityLockHelper.apply_sample("test-scroll", lat, lng, 10.0, t0)
	## ~0.5 km east over 120s
	lng = -77.0 + (500.0 / 111320.0) / cos(deg_to_rad(37.0))
	ActivityLockHelper.apply_sample("test-scroll", lat, lng, 10.0, t0 + 120)
	var p1: Dictionary = ActivityLockHelper.get_progress("test-scroll")
	_assert(float(p1.get("distance_km", 0.0)) > 0.4 and float(p1.get("distance_km", 0.0)) < 0.7, "activity ~0.5km segment")
	_assert(not ActivityLockHelper.is_complete("test-scroll", 1.0), "activity still locked at 0.5")
	## another ~0.6 km over next 120s
	lng += (600.0 / 111320.0) / cos(deg_to_rad(37.0))
	ActivityLockHelper.apply_sample("test-scroll", lat, lng, 10.0, t0 + 240)
	_assert(ActivityLockHelper.is_complete("test-scroll", 1.0), "activity complete after ~1.1km")
	## jitter while stationary should not explode distance
	var before := float(ActivityLockHelper.get_progress("test-scroll").get("distance_km", 0.0))
	for i in range(5):
		ActivityLockHelper.apply_sample("test-scroll", lat + 0.000001 * float(i), lng, 10.0, t0 + 250 + i)
	var after := float(ActivityLockHelper.get_progress("test-scroll").get("distance_km", 0.0))
	_assert(after - before < 0.05, "GPS jitter filtered")

	## Loop route counts cumulative
	ActivityLockHelper.reset_challenge("loop")
	ActivityLockHelper.start_challenge("loop", 2.0, 37.0, -77.0)
	var a_lng := -77.0
	var b_lng := -77.0 + (800.0 / 111320.0) / cos(deg_to_rad(37.0))
	ActivityLockHelper.apply_sample("loop", 37.0, a_lng, 10.0, t0)
	ActivityLockHelper.apply_sample("loop", 37.0, b_lng, 10.0, t0 + 180)
	ActivityLockHelper.apply_sample("loop", 37.0, a_lng, 10.0, t0 + 360)
	var loop_d := float(ActivityLockHelper.get_progress("loop").get("distance_km", 0.0))
	_assert(loop_d > 1.4, "loop route accumulates out+back")

	## Focus helper
	FocusLockHelper.debug_short_seconds = 1
	FocusLockHelper.begin_focus("focus-1", 1)
	OS.delay_msec(1100)
	var fr := FocusLockHelper.evaluate("focus-1")
	_assert(str(fr.get("status", "")) == "complete", "focus completes after short debug duration")
	FocusLockHelper.debug_short_seconds = 0

	_test_focus_interactive_classifier()

	_assert(ActivityLockHelper.parse_km_text("2.5").ok, "parse 2.5 km")
	_assert(not bool(ActivityLockHelper.parse_km_text("0.5").ok), "reject <1 km")
	_assert(FocusLockHelper.parse_hours_text("3").ok, "parse 3 hours")
	_assert(not bool(FocusLockHelper.parse_hours_text("48").ok), "reject >24 hours")

	var ev := ScrollLockEvaluator.evaluate({
		"id": "x",
		"unlock_at_unix": int(Time.get_unix_time_from_system()) - 10,
		"has_location_lock": false,
		"activity_lock_enabled": false,
		"focus_lock_enabled": false,
		"has_password": false,
	})
	_assert(bool(ev.get("ok", false)), "evaluator all-inactive locks pass")

	_assert(BuildFlags.APP_VERSION_CODE >= 24, "versionCode 24+")
	_assert(preset.contains("version/code=24"), "export 24")
	_assert(preset.contains("ChestOfLoveNotes-my-person-qr-notifications-debug.apk"), "APK name")
	var focus_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestFocusPlugin.kt")
	_assert(focus_kt.contains("classifyInteractiveUsage"), "Android classifier present")
	_assert(focus_kt.contains("NOTIFICATION_INTERRUPTION") or focus_kt.contains("TYPE_NOTIFICATION_INTERRUPTION"), "notif events ignored in plugin")
	_assert(focus_kt.contains("selfPackage"), "own package ignored in classifier")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _ev(type: int, pkg: String) -> Dictionary:
	return {"type": type, "package": pkg}


func _test_focus_interactive_classifier() -> void:
	## Passive: notifications / wake / sync / music / our app / lock glance / unanswered call / alarms.
	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
		_ev(FocusLockHelper.TYPE_NOTIFICATION_INTERRUPTION, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_NOTIFICATION_SEEN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_SCREEN_NON_INTERACTIVE, "android"),
	]), "passive notifications do not interrupt")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
		_ev(FocusLockHelper.TYPE_KEYGUARD_SHOWN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_USER_INTERACTION, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_SCREEN_NON_INTERACTIVE, "android"),
	]), "lock-screen time check does not interrupt")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_FOREGROUND_SERVICE_START, "com.spotify.music"),
		_ev(FocusLockHelper.TYPE_STANDBY_BUCKET_CHANGED, "com.spotify.music"),
	]), "background music/sync does not interrupt")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, FocusLockHelper.SELF_PACKAGE),
		_ev(FocusLockHelper.TYPE_NOTIFICATION_INTERRUPTION, FocusLockHelper.SELF_PACKAGE),
		_ev(FocusLockHelper.TYPE_USER_INTERACTION, FocusLockHelper.SELF_PACKAGE),
	]), "Chest of Love Notes events never sabotage Focus")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_KEYGUARD_SHOWN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.samsung.android.incallui"),
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
	]), "unanswered incoming call does not interrupt")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_KEYGUARD_SHOWN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
	]), "systemui while locked does not interrupt")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
		_ev(FocusLockHelper.TYPE_KEYGUARD_SHOWN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.sec.android.app.clockpackage"),
		_ev(FocusLockHelper.TYPE_SCREEN_NON_INTERACTIVE, "android"),
	]), "alarm merely firing while locked does not interrupt")

	_assert(not FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.google.android.deskclock"),
		_ev(FocusLockHelper.TYPE_MOVE_TO_FOREGROUND, "com.android.deskclock"),
		_ev(FocusLockHelper.TYPE_SCREEN_NON_INTERACTIVE, "android"),
	]), "alarm merely firing while unlocked does not interrupt")

	## Active: unlock+use, app switch, tap notification into app, answer/place call.
	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "android"),
		_ev(FocusLockHelper.TYPE_KEYGUARD_HIDDEN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.instagram.android"),
	]), "unlock then open app interrupts")

	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.android.chrome"),
	]), "already-unlocked app foreground interrupts")

	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_NOTIFICATION_INTERRUPTION, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_USER_INTERACTION, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.whatsapp"),
	]), "tapping notification into app interrupts")

	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_KEYGUARD_SHOWN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_KEYGUARD_HIDDEN, "com.android.systemui"),
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.samsung.android.incallui"),
	]), "answering a call after unlock interrupts")

	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.google.android.dialer"),
		_ev(FocusLockHelper.TYPE_USER_INTERACTION, "com.google.android.dialer"),
	]), "placing a call while unlocked interrupts")

	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_USER_INTERACTION, "com.android.chrome"),
	]), "user interaction in another app interrupts")

	_assert(FocusLockHelper.events_indicate_interactive_use([
		_ev(FocusLockHelper.TYPE_ACTIVITY_RESUMED, "com.google.android.deskclock"),
		_ev(FocusLockHelper.TYPE_USER_INTERACTION, "com.google.android.deskclock"),
	]), "dismissing an alarm (user interaction) interrupts")
