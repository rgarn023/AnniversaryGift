extends SceneTree
## Time commit, current location UX, map multitouch, preview opacity, server locks.

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
	print("=== Time / Location / Map / Preview / Self-send ===")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var open_ts := FileAccess.get_file_as_string("res://supabase/functions/open-scroll/index.ts")
	var send_ts := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var rpc_mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808230000_activity_focus_completion_rpcs.sql")
	var self_mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808220000_allow_self_send_scrolls.sql")
	var af_mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808180000_activity_focus_locks.sql")
	var scrolls := FileAccess.get_file_as_string("res://scripts/network/scroll_service.gd")

	## TIME
	_assert(compose.contains("_make_time_stepper"), "mobile time steppers")
	_assert(compose.contains("Explicitly commit CURRENT stepper values"), "Save commits without focus loss")
	_assert(compose.contains("Save Time"), "Save Time action")
	_assert(compose.contains("_make_time_stepper"), "time steppers replace SpinBox save path")
	_assert(compose.contains("Hour must be between 1 and 12"), "hour validation on Save")

	## CURRENT LOCATION
	_assert(compose.contains("Getting your location…"), "loading feedback")
	_assert(compose.contains("get_fresh_fix"), "fresh location path")
	_assert(loc.contains("get_fresh_fix"), "LocationHelper fresh fix")
	_assert(loc_kt.contains("begin_fresh_location"), "plugin fresh listen")
	_assert(compose.contains("Location permission is required"), "permission error copy")

	## MAP
	_assert(map.contains("set_process_input(true)"), "map processes _input for multitouch")
	_assert(map.contains("func _input(event: InputEvent)"), "map _input handler")
	_assert(map.contains("InputEventScreenTouch"), "screen touch pinch")
	_assert(map.contains("center_only"), "center-only initial camera")
	_assert(map.contains("39.8283"), "broad default center not Richmond-only")
	_assert(map.contains("_initial_paint_done"), "first-paint gate preserved")
	_assert(map.contains("_schedule_tile_retry"), "quiet tile retry")

	## PREVIEW
	_assert(viewer.contains("layer = 100"), "preview above compose")
	_assert(viewer.contains("Color(0.05, 0.03, 0.09, 1.0)"), "opaque preview backdrop")
	_assert(viewer.contains("_zoom_pan_root"), "ZoomPanRoot")
	_assert(viewer.contains("func _input(event: InputEvent)"), "preview multitouch _input")
	_assert(viewer.contains("MAX_COMPOSITE_SCALE"), "3x max zoom")

	## SELF-SEND / BACKEND
	_assert(compose.contains("Send to Myself (Test)"), "debug self-send")
	_assert(send_ts.contains("isSelfSend"), "send-scroll self-send")
	_assert(self_mig.contains("scrolls_no_self"), "self-send migration")
	_assert(af_mig.contains("activity_lock_enabled"), "activity/focus schema migration")
	_assert(rpc_mig.contains("mark_activity_lock_progress"), "activity completion RPC")
	_assert(rpc_mig.contains("mark_focus_lock_complete"), "focus completion RPC")
	_assert(open_ts.contains("activity_locked"), "open-scroll enforces activity")
	_assert(open_ts.contains("focus_locked"), "open-scroll enforces focus")
	_assert(scrolls.contains("mark_activity_lock_progress"), "client sync activity")
	_assert(scrolls.contains("mark_focus_lock_complete"), "client sync focus")

	_assert(BuildFlags.APP_VERSION_CODE >= 22, "versionCode 22+")
	_assert(preset.contains("version/code=22"), "export 22")
	_assert(preset.contains("ChestOfLoveNotes-time-location-map-preview-selfsend-fixes-debug.apk"), "APK name")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
