extends SceneTree
## v73 Android notification reliability static checks.

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
	var helper := _read("res://scripts/network/notification_helper.gd")
	var perms := _read("res://scripts/network/permissions_helper.gd")
	var events := _read("res://scripts/network/chest_event_notifier.gd")
	var main := _read("res://scripts/main.gd")
	var notify_kt := _read("res://android/plugins/chest_secure_storage/ChestNotifyPlugin.kt")
	var sched_kt := _read("res://android/plugins/chest_secure_storage/ScheduledNotifyReceiver.kt")
	var geo_kt := _read("res://android/plugins/chest_secure_storage/GeofenceReceiver.kt")
	var install := _read("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var icon_xml := _read("res://android/plugins/chest_secure_storage/res/drawable/ic_coln_notification.xml")
	var preset := _read("res://export_presets.cfg")

	_assert(preset.contains("permissions/post_notifications=true"), "export declares POST_NOTIFICATIONS")
	_assert(install.contains("POST_NOTIFICATIONS"), "install script injects POST_NOTIFICATIONS")
	_assert(install.contains("ic_coln_notification"), "install copies notify icon")
	_assert(not icon_xml.is_empty(), "custom notification icon drawable present")

	_assert(notify_kt.contains("POST_NOTIFICATIONS"), "plugin references POST_NOTIFICATIONS")
	_assert(notify_kt.contains("resolveSmallIcon") or notify_kt.contains("ic_coln_notification"), "custom/small icon resolver")
	_assert(not notify_kt.contains("ic_dialog_info"), "plugin no longer uses generic dialog icon")
	_assert(notify_kt.contains("open_app_notification_settings"), "open notification settings API")
	_assert(notify_kt.contains("has_notification_permission"), "permission query API")
	_assert(notify_kt.contains("request_notification_permission"), "runtime request API")
	_assert(notify_kt.contains("ensure_channels"), "channel ensure API")
	_assert(notify_kt.contains("coln_scrolls"), "stable scrolls channel id")
	_assert(notify_kt.contains("coln_connections"), "stable connections channel id")

	_assert(sched_kt.contains("ChestNotifyPlugin.CH_SCROLLS"), "scheduled receiver uses stable scrolls channel")
	_assert(not sched_kt.contains('CH_READY = "coln_scheduled_ready"'), "legacy scheduled channel id removed")
	_assert(sched_kt.contains("POST_NOTIFICATIONS"), "scheduled fire checks permission")
	_assert(not sched_kt.contains("ic_dialog_info"), "scheduled no generic dialog icon")

	_assert(geo_kt.contains("ChestNotifyPlugin.CH_SCROLLS") or geo_kt.contains("CH_ID = ChestNotifyPlugin"), "geofence channel aligned")
	_assert(not geo_kt.contains("ic_dialog_info"), "geofence no generic dialog icon")

	_assert(helper.contains("PREF_PATH"), "permission-asked persists via ConfigFile")
	_assert(helper.contains("open_notification_settings"), "helper opens notification settings")
	_assert(helper.contains("1401"), "activity progress id distinct from connections")
	_assert(helper.contains("notify_connection_request"), "connection trigger preserved")
	_assert(helper.contains("notify_new_scroll"), "new scroll trigger preserved")
	_assert(helper.contains("request_permission_contextual"), "contextual permission request")

	_assert(events.contains("seeded"), "chest event seed avoids historical spam")
	_assert(events.contains("notify_new_scroll"), "chest events fire new scroll")
	_assert(events.contains("notify_connection_request"), "chest events fire connection")
	_assert(main.contains("ChestEventNotifier"), "main wires chest event notifier")
	_assert(main.contains("Open Notification Settings"), "settings CTA for denied notifications")
	_assert(perms.contains("open_notification_settings"), "PermissionsHelper notification settings")
	_assert(perms.contains("Disabled / permission required") or perms.contains("Enabled"), "Enabled/Disabled status labels")

	## Dedupe still present for requirement transitions.
	var reqn := _read("res://scripts/network/requirement_notifier.gd")
	_assert(reqn.contains("_claim"), "requirement notifier dedupe intact")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
