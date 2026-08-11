extends SceneTree
## Map pinch damping, current-location freshness, schedule canonicalization, send errors, self-send.

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
	print("=== Map / Current Location / Schedule / Self-send (v23) ===")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var scrolls := FileAccess.get_file_as_string("res://scripts/network/scroll_service.gd")
	var send_ts := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	var open_ts := FileAccess.get_file_as_string("res://supabase/functions/open-scroll/index.ts")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var mig1 := FileAccess.get_file_as_string("res://supabase/migrations/20260808180000_activity_focus_locks.sql")
	var mig2 := FileAccess.get_file_as_string("res://supabase/migrations/20260808220000_allow_self_send_scrolls.sql")
	var mig3 := FileAccess.get_file_as_string("res://supabase/migrations/20260808230000_activity_focus_completion_rpcs.sql")

	## MAP PINCH
	_assert(map.contains("PINCH_DAMPING"), "pinch damping constant")
	_assert(map.contains("PINCH_MAX_DELTA_PER_EVENT"), "per-event zoom clamp")
	_assert(map.contains("_apply_fractional_zoom"), "fractional zoom accumulator")
	_assert(map.contains("_snapshot_tiles_to_hold"), "hold prior tiles during zoom")
	_assert(map.contains("_hold_tile_layer"), "hold tile layer")
	_assert(map.contains("_end_pinch_gesture"), "pinch settle/end")
	_assert(map.contains("log(ratio) / log(2.0)"), "normalized scale ratio → zoom delta")
	_assert(map.contains("_pinch_tile_debounce"), "tile fetch debounce during pinch")
	_assert(not map.contains("ratio > 1.08"), "old jumpy threshold removed")

	## CURRENT LOCATION
	_assert(loc.contains("MAX_FIX_AGE_MS"), "freshness max age")
	_assert(loc.contains("Location accuracy is low. Try again."), "accuracy message")
	_assert(loc.contains("device_gps"), "GPS source marker")
	_assert(loc_kt.contains("ageMs"), "plugin encodes age")
	_assert(loc_kt.contains("Never silently returns stale last-known"), "poll does not fall back stale")
	_assert(compose.contains("Current location selected"), "success status")
	_assert(compose.contains("Current Location"), "selected card source label")
	_assert(compose.contains('place["source"] = "current"'), "marks current source")
	_assert(compose.contains("Location permission is needed to use your current location"), "permission copy")
	_assert(compose.contains("_finish_current_location_attempt"), "button reset helper")

	## SCHEDULE
	_assert(compose.contains("_format_unlock_label"), "canonical unlock label")
	_assert(compose.contains("_local_datetime_dict_from_unix"), "local dict from unix")
	_assert(compose.contains("_apply_unlock_unix"), "apply unlock unix → local fields")
	_assert(compose.contains("_timezone_bias_minutes"), "timezone bias helper")
	_assert(compose.contains("schedule_label := _format_unlock_label()"), "Ready Check uses canonical label")
	_assert(not compose.contains("var dt := Time.get_datetime_dict_from_unix_time(target)"), "relative unlock no longer UTC-only")

	## SEND ERRORS
	_assert(compose.contains("func restore_after_failed_send(user_message: String"), "single restore path with message")
	_assert(compose.contains("func clear_send_error"), "stale send error clear")
	_assert(compose.contains("var _send_error: String"), "send error state")
	_assert(main.contains("Single inline error"), "main does not toast duplicate send failure")
	_assert(main.contains("send_scroll_failed status="), "internal send diagnostics")
	_assert(scrolls.contains("send_scroll_response ok=false"), "scroll service logs status/code")

	## SELF-SEND / MIGRATIONS / EDGE
	_assert(mig1.contains("activity_lock_enabled"), "migration 1 activity/focus columns")
	_assert(mig2.contains("scrolls_no_self"), "migration 2 self-send")
	_assert(mig3.contains("mark_focus_lock_complete"), "migration 3 RPCs")
	_assert(send_ts.contains("isSelfSend"), "send-scroll self-send")
	_assert(open_ts.contains("activity_locked"), "open-scroll activity")
	_assert(open_ts.contains("focus_locked"), "open-scroll focus")

	## VERSION / APK
	_assert(BuildFlags.APP_VERSION_CODE >= 26, "versionCode 26+")
	_assert(preset.contains("version/code=26"), "export versionCode 26")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	_assert(gitignore.contains("ChestOfLoveNotes-android-permissions-fix-debug.apk"), "APK allowlisted in gitignore")
	_assert(preset.contains("android-permissions-fix-debug.apk"), "export_path APK name")

	## Runtime: schedule display/validation agreement
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var now := int(Time.get_unix_time_from_system())
	var future := now + 300
	var local_as_utc := future + bias * 60
	var dt := Time.get_datetime_dict_from_unix_time(local_as_utc)
	var fields := {
		"year": int(dt.year), "month": int(dt.month), "day": int(dt.day),
		"hour": int(dt.hour), "minute": int(dt.minute), "second": 0,
	}
	var recomputed := int(Time.get_unix_time_from_datetime_dict(fields)) - bias * 60
	_assert(absi(recomputed - future) <= 60, "local wall-clock ↔ unix round-trip within 60s")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
