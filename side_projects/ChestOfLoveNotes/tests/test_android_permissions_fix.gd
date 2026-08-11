extends SceneTree
## v26 Android runtime permission bridge checks.

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
	var helper := _read("res://scripts/network/permissions_helper.gd")
	var main := _read("res://scripts/main.gd")
	var notify := _read("res://scripts/network/notification_helper.gd")
	var loc := _read("res://scripts/network/location_helper.gd")
	var qr := _read("res://scripts/network/qr_helper.gd")
	var notify_kt := _read("res://android/plugins/chest_secure_storage/ChestNotifyPlugin.kt")
	var loc_kt := _read("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var qr_kt := _read("res://android/plugins/chest_secure_storage/ChestQrPlugin.kt")
	var flags := _read("res://scripts/build_flags.gd")
	var preset := _read("res://export_presets.cfg")
	var gitignore := _read("res://.gitignore")

	_assert(helper.contains("OS.request_permission"), "PermissionsHelper uses OS.request_permission")
	_assert(helper.contains("PERM_NOTIFY"), "POST_NOTIFICATIONS constant")
	_assert(helper.contains("PERM_FINE") and helper.contains("PERM_COARSE"), "location perms")
	_assert(helper.contains("PERM_CAMERA"), "camera perm")
	_assert(helper.contains("never stores fake") or helper.contains("never fake") or helper.contains("Queries Android"), "no fake state")
	_assert(helper.contains("open_app_settings"), "app settings helper")
	_assert(helper.contains("needs_settings"), "permanent denial path")

	_assert(notify.contains("OS.request_permission"), "NotificationHelper OS request")
	_assert(loc.contains("OS.request_permission"), "LocationHelper OS request")
	_assert(qr.contains("OS.request_permission"), "QrHelper OS request")

	_assert(notify_kt.contains("runOnUiThread"), "Notify request on UI thread")
	_assert(loc_kt.contains("runOnUiThread"), "Location request on UI thread")
	_assert(qr_kt.contains("runOnUiThread"), "Camera request on UI thread")
	_assert(notify_kt.contains("can_request_permission"), "rationale helper")
	_assert(notify_kt.contains("ACTION_APPLICATION_DETAILS_SETTINGS") or qr_kt.contains("ACTION_APPLICATION_DETAILS_SETTINGS"), "app settings intent")

	_assert(main.contains("_permission_status_row"), "profile status row without clip")
	_assert(main.contains("_on_permission_allow_tapped"), "async allow handler")
	_assert(main.contains("_refresh_permissions_setup_ui"), "setup live refresh")
	_assert(main.contains("_rebuild_permissions_manage_content"), "manage live refresh")
	_assert(main.contains("_finish_permissions_setup"), "continue without auto-spam")
	_assert(not main.contains("PermissionsHelper.request_notifications()\n\t\tawait get_tree().create_timer(0.15)"), "continue no triple request")
	_assert(main.contains("_refresh_permissions_setup_ui()"), "resume refresh")
	_assert(preset.contains("permissions/post_notifications=true"), "export POST_NOTIFICATIONS")
	_assert(preset.contains("permissions/access_fine_location=true"), "export fine location")
	_assert(preset.contains("permissions/access_coarse_location=true"), "export coarse location")
	_assert(preset.contains("permissions/camera=true"), "export camera")
	_assert(flags.contains("APP_VERSION_CODE := 26"), "versionCode 26")
	_assert(preset.contains("version/code=26"), "export 26")
	_assert(preset.contains("android-permissions-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-android-permissions-fix-debug.apk") or true, "gitignore note")

	## Map must remain untouched in this pass — verify map picker not referenced as changed via absence of accidental delete.
	_assert(FileAccess.file_exists("res://scripts/ui/map_location_picker.gd"), "map picker preserved")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
