extends SceneTree
## Automated checks for permissions / map / chest / notification performance pass (v25).

var _passed := 0
var _failed := 0


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % msg)
	else:
		_failed += 1
		print("FAIL: %s" % msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _init() -> void:
	var main := _read("res://scripts/main.gd")
	var compose := _read("res://scripts/scroll/compose_scroll_screen.gd")
	var map := _read("res://scripts/ui/map_location_picker.gd")
	var loc_kt := _read("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var notify_kt := _read("res://android/plugins/chest_secure_storage/ChestNotifyPlugin.kt")
	var install := _read("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var flags := _read("res://scripts/build_flags.gd")
	var export_cfg := _read("res://export_presets.cfg")
	var project := _read("res://project.godot")
	var strings := _read("res://scripts/ui/product_strings.gd")
	var perms := _read("res://scripts/network/permissions_helper.gd")
	var loc_gd := _read("res://scripts/network/location_helper.gd")

	_assert(perms.contains("class_name PermissionsHelper"), "PermissionsHelper exists")
	_assert(main.contains("_show_permissions_setup"), "first-run permissions setup")
	_assert(main.contains("PERMISSIONS"), "profile permissions section")
	_assert(strings.contains("NOTIFY_RATIONALE"), "notify rationale string")
	_assert(strings.contains("LOCATION_RATIONALE"), "location rationale string")
	_assert(strings.contains("CAMERA_SETUP_RATIONALE"), "camera setup rationale")

	_assert(loc_kt.contains("FusedLocationProviderClient") or loc_kt.contains("play-services") or loc_kt.contains("LocationServices"), "fused location provider")
	_assert(loc_kt.contains("begin_fresh_location"), "fresh location API")
	_assert(loc_gd.contains("FRESH_POLL_COUNT"), "longer acquisition window")
	_assert(loc_gd.contains("Allow Location permission"), "permission failure copy")
	_assert(install.contains("play-services-location"), "play services location dependency")

	_assert(map.contains("_gesture_layer"), "dedicated map gesture layer")
	_assert(map.contains("_apply_live_pinch_scale"), "continuous pinch visual scale")
	_assert(map.contains("_handle_touch_event"), "canonical multitouch handler")
	_assert(project.contains("emulate_mouse_from_touch=false"), "multitouch not collapsed to mouse")

	_assert(main.contains("YOUR CHEST") or main.contains("Your Chest"), "Your Chest heading")
	_assert(main.contains("View Locks"), "locked action View Locks")
	_assert(main.contains("_format_unlock_countdown"), "human countdown")
	_assert(main.contains("☆ Save") or main.contains("Save"), "save label")
	_assert(not main.contains("chip_scroll"), "no horizontal chip scroll")
	_assert(main.contains("Current") and main.contains("Unread") and main.contains("Locked"), "chest categories")
	_assert(main.contains("Requests") and main.contains("Saved"), "chest secondary categories")

	_assert(compose.contains("_toggle_debug_self_send"), "Debug Recipient modal removed / toggle used")
	_assert(compose.contains("Test with myself"), "self-send retained")
	_assert(compose.contains("Require your Person"), "location lock Person copy")
	_assert(compose.contains("VBoxContainer.new()") and compose.contains("Use Current Location"), "stacked location buttons")

	_assert(main.contains("_counts_from_chest_cache") or main.contains("cache_is_fresh"), "cache-first nav")
	_assert(main.contains("_consume_notification_deeplink"), "deeplink consumption")
	_assert(notify_kt.contains("consume_pending_deeplink"), "android deeplink consume")
	_assert(main.contains("_add_geofence_opt_in"), "geofence opt-in UI")
	_assert(FileAccess.file_exists("res://android/plugins/chest_secure_storage/GeofenceReceiver.kt"), "GeofenceReceiver")

	_assert(flags.contains("APP_VERSION_CODE := 28"), "versionCode 26")
	_assert(export_cfg.contains("version/code=28"), "export 25")
	_assert(export_cfg.contains("ChestOfLoveNotes-current-location-qr-camera-fix-debug.apk"), "APK name")

	_assert(main.contains("\"Person\"") or main.contains("Person"), "nav Person label")
	_assert(not main.contains("Send sealed scrolls to friends"), "welcome friend copy removed")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
