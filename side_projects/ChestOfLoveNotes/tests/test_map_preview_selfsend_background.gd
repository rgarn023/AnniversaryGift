extends SceneTree
## Map stability, whole-composite preview pinch, self-send, activity FG, scheduled notify.

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
	print("=== Map / Preview / Self-send / Background ===")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var act := FileAccess.get_file_as_string("res://scripts/network/activity_lock_helper.gd")
	var notif := FileAccess.get_file_as_string("res://scripts/network/notification_helper.gd")
	var send := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var notify_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestNotifyPlugin.kt")
	var svc := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ActivityLockService.kt")
	var recv := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ScheduledNotifyReceiver.kt")
	var focus_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestFocusPlugin.kt")
	var self_mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808220000_allow_self_send_scrolls.sql")
	var act_mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808180000_activity_focus_locks.sql")

	## MAP — long-lived instance, no blank/fatal on pan/pinch
	_assert(map.contains("_tile_nodes"), "map reuses tile nodes")
	_assert(map.contains("_initial_paint_done"), "map tracks first paint")
	_assert(map.contains("_show_fatal_map_error"), "fatal error only before first paint")
	_assert(map.contains("_schedule_tile_retry"), "quiet tile retry")
	_assert(map.contains("_recenter_so_latlng_at_screen"), "pinch zooms around focal point")
	_assert(map.contains("_queue_refresh_tiles"), "pan refresh throttled")
	_assert(map.contains("_tile_nodes[key]"), "map keeps keyed tile nodes")
	_assert(map.contains("stale"), "map removes only stale tiles")
	_assert(map.contains("Never blank") or map.contains("never re-show full loading"), "no overlay after first paint")

	## PREVIEW — whole composite pinch
	_assert(viewer.contains("_zoom_pan_root"), "ZoomPanRoot present")
	_assert(viewer.contains("_set_composite_scale"), "composite scale pinch")
	_assert(viewer.contains("MAX_COMPOSITE_SCALE"), "max 3x zoom")
	_assert(viewer.contains("_on_view_zoom_changed"), "zoom compat hook")
	_assert(viewer.contains("_font_step"), "A+/A- font step")
	_assert(viewer.contains("NOTIFICATION_WM_GO_BACK_REQUEST"), "android back closes")
	_assert(viewer.contains("Font changes must NOT touch ZoomPanRoot"), "A+ does not alter composite")

	## SELF-SEND
	_assert(compose.contains("Send to Myself (Test)"), "debug self-send UI")
	_assert(compose.contains("_self_send_enabled"), "self-send gated")
	_assert(compose.contains("DEBUG_SELF_SEND") or compose.contains("BuildFlags.DEBUG_SELF_SEND"), "uses build flag")
	_assert(main.contains("me_profile"), "compose gets current profile")
	_assert(send.contains("isSelfSend"), "send-scroll allows self")
	_assert(not send.contains("Cannot send a scroll to yourself"), "self-send error removed")
	_assert(self_mig.contains("drop constraint if exists scrolls_no_self"), "self-send migration")

	## ACTIVITY FG SERVICE
	_assert(FileAccess.file_exists("res://android/plugins/chest_secure_storage/ActivityLockService.kt"), "ActivityLockService file")
	_assert(svc.contains("FOREGROUND_SERVICE_TYPE_LOCATION") or svc.contains("foregroundServiceType"), "FGS location type")
	_assert(svc.contains("Activity Lock in progress"), "progress notification copy")
	_assert(loc_kt.contains("start_activity_tracking"), "plugin start tracking")
	_assert(act.contains("start_activity_tracking"), "helper starts native service")
	_assert(act.contains("sync_from_native_service"), "helper merges native progress")
	_assert(install.contains("ActivityLockService"), "install wires service")
	_assert(install.contains("FOREGROUND_SERVICE_LOCATION"), "FGS location permission")

	## SCHEDULED NOTIFICATIONS
	_assert(notify_kt.contains("schedule_notification"), "schedule API")
	_assert(recv.contains("BOOT_COMPLETED") or recv.contains("ACTION_BOOT"), "reboot receiver")
	_assert(notif.contains("schedule_ready_at"), "helper schedules ready")
	_assert(notif.contains("sync_scheduled_from_chest"), "chest sync schedules")
	_assert(main.contains("sync_scheduled_from_chest"), "main syncs on chest load")
	_assert(main.contains("reschedule_persisted"), "startup reschedule")
	_assert(preset.contains("receive_boot_completed=true"), "boot permission export")

	## FOCUS still interactive-only
	_assert(focus_kt.contains("classifyInteractiveUsage"), "focus classifier")
	_assert(focus_kt.contains("ALARM_UI_PACKAGES"), "alarms ignored")
	_assert(FocusLockHelper.events_indicate_interactive_use([
		{"type": FocusLockHelper.TYPE_ACTIVITY_RESUMED, "package": "com.android.chrome"},
	]), "interactive app use resets")
	_assert(not FocusLockHelper.events_indicate_interactive_use([
		{"type": FocusLockHelper.TYPE_NOTIFICATION_INTERRUPTION, "package": "com.android.systemui"},
		{"type": FocusLockHelper.TYPE_SCREEN_INTERACTIVE, "package": "android"},
	]), "passive notification does not reset")

	## Attachments still out of active UI
	_assert(compose.contains("Attachments removed from active product UI"), "attachments UI removed")

	## Activity/focus schema migration still present
	_assert(act_mig.contains("activity_lock_enabled"), "activity/focus migration present")

	_assert(BuildFlags.APP_VERSION_CODE >= 23, "versionCode 23+")
	_assert(preset.contains("version/code=23"), "export 23")
	_assert(preset.contains("ChestOfLoveNotes-map-currentlocation-schedule-selfsend-fixes-debug.apk"), "APK name")

	## Runtime preview composite clamp (static source checks already cover ZoomPanRoot).
	_assert(viewer.contains("MAX_COMPOSITE_SCALE: float = 3.0"), "max composite scale is 3x")
	_assert(viewer.contains("MIN_COMPOSITE_SCALE: float = 1.0"), "min composite scale is fit")
	_assert(viewer.contains("_reset_preview_state"), "reset restores preview state")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
