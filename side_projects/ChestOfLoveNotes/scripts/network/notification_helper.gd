extends RefCounted
class_name NotificationHelper
## Thin wrapper around ChestNotify Android plugin.

const PLUGIN_NAME := "ChestNotify"
const PREF_ASKED := "coln_notify_permission_asked"


static func _plugin():
	if Engine.has_singleton(PLUGIN_NAME):
		return Engine.get_singleton(PLUGIN_NAME)
	return null


static func available() -> bool:
	return _plugin() != null


static func ensure_channels() -> void:
	var p = _plugin()
	if p != null and p.has_method("ensure_channels"):
		p.ensure_channels()


static func has_permission() -> bool:
	if OS.get_name() != "Android":
		return false
	var p = _plugin()
	if p != null and p.has_method("has_notification_permission"):
		return bool(p.has_notification_permission())
	return false


static func request_permission_contextual() -> void:
	## Call only after a user-relevant moment (e.g. first send / first received scroll).
	if OS.get_name() != "Android":
		return
	if has_permission():
		ensure_channels()
		return
	if bool(ProjectSettings.get_setting(PREF_ASKED, false)):
		return
	ProjectSettings.set_setting(PREF_ASKED, true)
	var p = _plugin()
	if p != null and p.has_method("request_notification_permission"):
		p.request_notification_permission()
	ensure_channels()


static func show(channel: String, title: String, body: String, deep_link: String = "chest", notif_id: int = 1001) -> void:
	var p = _plugin()
	if p == null or not p.has_method("show_notification"):
		return
	if not has_permission() and OS.get_name() == "Android":
		return
	p.show_notification(channel, title, body, deep_link, notif_id)


static func notify_new_scroll(from_name: String) -> void:
	var who := from_name.strip_edges()
	var title := "New scroll"
	var body := "You received a new scroll." if who.is_empty() else "You received a new scroll from %s." % who
	show("new_scroll", title, body, "chest", 1101)


static func notify_scheduled_ready() -> void:
	show("scheduled_ready", "Scroll ready", "A scroll is now available to open.", "chest", 1102)


static func notify_activity_progress(current_km: float, target_km: float) -> void:
	show(
		"activity",
		"Activity Lock in progress",
		"%.1f / %s" % [current_km, ActivityLockHelper.format_km(target_km)],
		"activity",
		1201
	)


static func notify_activity_complete() -> void:
	show("activity", "Activity Lock complete", "Activity Lock complete.", "chest", 1202)


static func notify_focus_complete(all_ready: bool) -> void:
	if all_ready:
		show("focus", "Focus complete", "Focus complete — your scroll is ready.", "chest", 1301)
	else:
		show("focus", "Focus complete", "Focus complete — one more lock remains.", "chest", 1301)
