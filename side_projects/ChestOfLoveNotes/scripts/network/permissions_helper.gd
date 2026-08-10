extends RefCounted
class_name PermissionsHelper
## First-run + Profile permission status for Notifications / Location / Camera.
## Does NOT request Usage Access, background location, or exact alarms.

const PREF_SETUP_DONE := "coln_permissions_setup_done_v1"
const PREF_NOTIFY_ASKED := "coln_notify_permission_asked"


static func setup_completed() -> bool:
	return bool(ProjectSettings.get_setting("coln/" + PREF_SETUP_DONE, false)) \
		or _cfg().get_value("permissions", "setup_done", false)


static func mark_setup_completed() -> void:
	var c := _cfg()
	c.set_value("permissions", "setup_done", true)
	c.save(_cfg_path())


static func _cfg_path() -> String:
	return "user://coln_permissions.cfg"


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(_cfg_path())
	return c


static func notification_allowed() -> bool:
	return NotificationHelper.has_permission()


static func location_allowed() -> bool:
	return LocationHelper.permission_status() == "granted" or LocationHelper.permission_status() == "unsupported"


static func camera_allowed() -> bool:
	if OS.get_name() != "Android":
		return true
	var p = Engine.get_singleton("ChestQr") if Engine.has_singleton("ChestQr") else null
	if p != null and p.has_method("has_camera_permission"):
		return bool(p.has_camera_permission())
	var granted := OS.get_granted_permissions()
	return granted.has("android.permission.CAMERA")


static func status_label(allowed: bool) -> String:
	return "Allowed" if allowed else "Not Allowed"


static func request_notifications() -> void:
	NotificationHelper.request_permission_contextual(true)


static func request_location() -> void:
	LocationHelper.request_permission_if_needed()


static func request_camera() -> void:
	if OS.get_name() != "Android":
		return
	var p = Engine.get_singleton("ChestQr") if Engine.has_singleton("ChestQr") else null
	if p != null and p.has_method("request_camera_permission"):
		p.request_camera_permission()
	else:
		OS.request_permissions()


static func open_app_settings() -> void:
	var p = Engine.get_singleton("ChestQr") if Engine.has_singleton("ChestQr") else null
	if p != null and p.has_method("open_app_settings"):
		p.open_app_settings()
		return
	var n = Engine.get_singleton("ChestNotify") if Engine.has_singleton("ChestNotify") else null
	if n != null and n.has_method("open_app_notification_settings"):
		n.open_app_notification_settings()
