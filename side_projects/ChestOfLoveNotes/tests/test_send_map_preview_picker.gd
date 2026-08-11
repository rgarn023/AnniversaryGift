extends SceneTree
## Send validation, map bootstrap, composite preview, photo picker.

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
	print("=== Send / Map / Preview / Picker ===")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var media := FileAccess.get_file_as_string("res://scripts/network/media_picker_helper.gd")
	var plugin := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestMediaPlugin.kt")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")

	_assert(compose.contains("func validate_compose_draft()"), "central validate_compose_draft")
	_assert(compose.contains("Ready to send"), "ready to send label")
	_assert(compose.contains("compose_validation valid="), "validation debug log")
	_assert(compose.contains("_pw2_syncing"), "password confirm sync guard")
	_assert(compose.contains("as_utc - bias_min * 60"), "timezone-aware unlock unix")
	_assert(compose.contains("Attachments removed from active product UI") or compose.contains("MediaPickerHelper"), "attachments dormant / media helper available")
	_assert(compose.contains("\"Required\" if pw_on else \"Not required\""), "ready check password status only")
	_assert(not compose.contains("print(\"password=\""), "no password value logging")

	_assert(map.contains("func _bootstrap_map_after_layout"), "map layout bootstrap exists")
	_assert(map.contains("Loading map…") or map.contains("Loading map"), "loading overlay copy")
	_assert(map.contains("Couldn't load the map."), "map error state")
	_assert(map.contains("Search for a place instead"), "map search fallback action")
	_assert(map.contains("_layout_ready = true"), "layout ready gate")

	_assert(viewer.contains("_zoom_pan_root"), "composite ZoomPanRoot")
	_assert(viewer.contains("Reset"), "reset control")
	_assert(viewer.contains("_on_view_zoom_changed"), "pinch -> composite zoom")
	_assert(viewer.contains("Font changes must NOT touch ZoomPanRoot"), "font zoom isolation")
	_assert(viewer.contains("NOTIFICATION_WM_GO_BACK_REQUEST"), "android back closes preview")
	_assert(viewer.contains("_content_rect"), "parchment content rect")

	_assert(media.contains("ChestMedia"), "MediaPickerHelper targets ChestMedia")
	_assert(plugin.contains("ACTION_PICK_IMAGES"), "Android Photo Picker intent")
	_assert(plugin.contains("image/jpeg"), "image mime filtering")
	_assert(plugin.contains("EXTRA_PICK_IMAGES_MAX"), "multi-select when supported")
	_assert(install.contains("ChestMediaPlugin.kt"), "install script copies media plugin")
	_assert(install.contains("ChestMedia") and install.contains("ChestMediaPlugin"), "manifest registers ChestMedia")

	_assert(BuildFlags.APP_VERSION_CODE >= 26, "versionCode 26+")
	_assert(preset.contains("version/code=26"), "export preset versionCode 26")

	## Runtime: timezone helper math sanity via Compose unlock conversion contract.
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var now_local := Time.get_datetime_dict_from_system(false)
	var as_utc := int(Time.get_unix_time_from_datetime_dict({
		"year": int(now_local.year),
		"month": int(now_local.month),
		"day": int(now_local.day),
		"hour": int(now_local.hour),
		"minute": int(now_local.minute),
		"second": int(now_local.second),
	}))
	var local_unix := as_utc - bias * 60
	var sys_unix := int(Time.get_unix_time_from_system())
	_assert(absi(local_unix - sys_unix) < 120, "local wall-clock conversion within 2 minutes")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
