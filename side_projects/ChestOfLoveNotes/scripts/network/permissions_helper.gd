extends RefCounted
class_name PermissionsHelper
## First-run + Profile permission status for Notifications / Location / Camera.
## Queries Android runtime state only — never stores fake Allowed/Not Allowed flags.
## Requests use Godot's OS.request_permission (real system dialogs) with plugin UI-thread fallback.

const PREF_SETUP_DONE := "coln_permissions_setup_done_v1"
const PERM_NOTIFY := "android.permission.POST_NOTIFICATIONS"
const PERM_FINE := "android.permission.ACCESS_FINE_LOCATION"
const PERM_COARSE := "android.permission.ACCESS_COARSE_LOCATION"
const PERM_CAMERA := "android.permission.CAMERA"


static func setup_completed() -> bool:
	return bool(_cfg().get_value("permissions", "setup_done", false))


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


static func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[COLN-PERM] %s" % msg)


static func _mark_asked(key: String) -> void:
	var c := _cfg()
	c.set_value("asked", key, true)
	c.save(_cfg_path())


static func _was_asked(key: String) -> bool:
	return bool(_cfg().get_value("asked", key, false))


static func _android_granted(perm: String) -> bool:
	if OS.get_name() != "Android":
		return true
	var granted := OS.get_granted_permissions()
	return granted.has(perm)


static func notification_allowed() -> bool:
	if OS.get_name() != "Android":
		return true
	## Prefer plugin (handles API < 33 via NotificationManager).
	var p = Engine.get_singleton("ChestNotify") if Engine.has_singleton("ChestNotify") else null
	if p != null and p.has_method("has_notification_permission"):
		return bool(p.has_notification_permission())
	return _android_granted(PERM_NOTIFY)


static func location_allowed() -> bool:
	## Coarse OR fine counts as Allowed for general app use.
	if OS.get_name() != "Android":
		return true
	var p = Engine.get_singleton("ChestLocation") if Engine.has_singleton("ChestLocation") else null
	if p != null and p.has_method("has_location_permission"):
		return bool(p.has_location_permission())
	return _android_granted(PERM_FINE) or _android_granted(PERM_COARSE)


static func camera_allowed() -> bool:
	if OS.get_name() != "Android":
		return true
	var p = Engine.get_singleton("ChestQr") if Engine.has_singleton("ChestQr") else null
	if p != null and p.has_method("has_camera_permission"):
		return bool(p.has_camera_permission())
	return _android_granted(PERM_CAMERA)


static func status_label(allowed: bool) -> String:
	return "Allowed" if allowed else "Not Allowed"


static func needs_settings(kind: String) -> bool:
	## After a prior ask + still denied + Android won't show a dialog again.
	if OS.get_name() != "Android":
		return false
	match kind:
		"notifications":
			if notification_allowed():
				return false
			if not _was_asked("notifications"):
				return false
			return not _can_request_again(PERM_NOTIFY)
		"location":
			if location_allowed():
				return false
			if not _was_asked("location"):
				return false
			return not _can_request_again(PERM_FINE) and not _can_request_again(PERM_COARSE)
		"camera":
			if camera_allowed():
				return false
			if not _was_asked("camera"):
				return false
			return not _can_request_again(PERM_CAMERA)
		_:
			return false


static func _can_request_again(perm: String) -> bool:
	## Plugin reports shouldShowRequestPermissionRationale / ActivityCompat path.
	var p = Engine.get_singleton("ChestNotify") if Engine.has_singleton("ChestNotify") else null
	if p != null and p.has_method("can_request_permission"):
		return bool(p.can_request_permission(perm))
	## Unknown → allow another OS.request_permission attempt.
	return true


static func request_notifications() -> Dictionary:
	## Returns {requested:bool, allowed:bool, needs_settings:bool}
	if OS.get_name() != "Android":
		return {"requested": false, "allowed": true, "needs_settings": false}
	if notification_allowed():
		_log("permission notifications result=true (already granted)")
		return {"requested": false, "allowed": true, "needs_settings": false}
	if needs_settings("notifications"):
		_log("permission notifications permanently denied → settings")
		return {"requested": false, "allowed": false, "needs_settings": true}
	_log("permission notifications requested")
	_mark_asked("notifications")
	var requested := false
	## Godot native path — shows the system dialog when declared in export preset.
	if OS.has_method("request_permission"):
		OS.request_permission(PERM_NOTIFY)
		requested = true
	var p = Engine.get_singleton("ChestNotify") if Engine.has_singleton("ChestNotify") else null
	if p != null and p.has_method("request_notification_permission"):
		## UI-thread fallback if Godot path is unavailable on this build.
		p.request_notification_permission()
		requested = true
	return {"requested": requested, "allowed": notification_allowed(), "needs_settings": false}


static func request_location() -> Dictionary:
	if OS.get_name() != "Android":
		return {"requested": false, "allowed": true, "needs_settings": false}
	if location_allowed():
		_log("permission location result=granted (already)")
		return {"requested": false, "allowed": true, "needs_settings": false}
	if needs_settings("location"):
		_log("permission location permanently denied → settings")
		return {"requested": false, "allowed": false, "needs_settings": true}
	_log("permission location requested")
	_mark_asked("location")
	var requested := false
	if OS.has_method("request_permission"):
		## Request fine; Android presents the foreground location chooser (precise/approx).
		OS.request_permission(PERM_FINE)
		OS.request_permission(PERM_COARSE)
		requested = true
	var p = Engine.get_singleton("ChestLocation") if Engine.has_singleton("ChestLocation") else null
	if p != null and p.has_method("request_location_permission"):
		p.request_location_permission()
		requested = true
	return {"requested": requested, "allowed": location_allowed(), "needs_settings": false}


static func request_camera() -> Dictionary:
	if OS.get_name() != "Android":
		return {"requested": false, "allowed": true, "needs_settings": false}
	if camera_allowed():
		_log("permission camera result=true (already granted)")
		return {"requested": false, "allowed": true, "needs_settings": false}
	if needs_settings("camera"):
		_log("permission camera permanently denied → settings")
		return {"requested": false, "allowed": false, "needs_settings": true}
	_log("permission camera requested")
	_mark_asked("camera")
	var requested := false
	if OS.has_method("request_permission"):
		OS.request_permission(PERM_CAMERA)
		requested = true
	var p = Engine.get_singleton("ChestQr") if Engine.has_singleton("ChestQr") else null
	if p != null and p.has_method("request_camera_permission"):
		p.request_camera_permission()
		requested = true
	return {"requested": requested, "allowed": camera_allowed(), "needs_settings": false}


static func open_app_settings() -> void:
	_log("open app settings")
	var p = Engine.get_singleton("ChestQr") if Engine.has_singleton("ChestQr") else null
	if p != null and p.has_method("open_app_settings"):
		if bool(p.open_app_settings()):
			return
	var n = Engine.get_singleton("ChestNotify") if Engine.has_singleton("ChestNotify") else null
	if n != null and n.has_method("open_app_settings"):
		if bool(n.open_app_settings()):
			return
	if n != null and n.has_method("open_app_notification_settings"):
		n.open_app_notification_settings()


static func snapshot() -> Dictionary:
	return {
		"notifications": notification_allowed(),
		"location": location_allowed(),
		"camera": camera_allowed(),
	}


static func log_resume_refresh() -> void:
	var s := snapshot()
	_log(
		"permission state refreshed on resume n=%s l=%s c=%s"
		% [str(s.notifications), str(s.location), str(s.camera)]
	)
