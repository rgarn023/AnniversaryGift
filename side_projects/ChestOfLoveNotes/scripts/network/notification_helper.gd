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


static func request_permission_contextual(force: bool = false) -> void:
	## Call from first-run Permissions Setup or after a user-relevant moment.
	if OS.get_name() != "Android":
		return
	if has_permission():
		ensure_channels()
		return
	if not force and bool(ProjectSettings.get_setting(PREF_ASKED, false)):
		return
	ProjectSettings.set_setting(PREF_ASKED, true)
	var p = _plugin()
	if p != null and p.has_method("request_notification_permission"):
		p.request_notification_permission()
	ensure_channels()


static func consume_pending_deeplink() -> String:
	var p = _plugin()
	if p != null and p.has_method("consume_pending_deeplink"):
		return str(p.consume_pending_deeplink())
	return ""


static func peek_pending_deeplink() -> String:
	var p = _plugin()
	if p != null and p.has_method("peek_pending_deeplink"):
		return str(p.peek_pending_deeplink())
	return ""


static func push_token_placeholder() -> String:
	## No FCM client plugin wired yet — returns empty so registration no-ops.
	return get_push_token()


static func get_push_token() -> String:
	var p = _plugin()
	if p != null and p.has_method("get_push_token"):
		return str(p.get_push_token()).strip_edges()
	return ""


static func show(channel: String, title: String, body: String, deep_link: String = "chest", notif_id: int = 1001) -> void:
	var p = _plugin()
	if p == null or not p.has_method("show_notification"):
		return
	if not has_permission() and OS.get_name() == "Android":
		return
	p.show_notification(channel, title, body, deep_link, notif_id)


static func notify_new_scroll(from_name: String, scroll_id: String = "") -> void:
	var who := from_name.strip_edges()
	var title := "New Scroll"
	var body := "You received a new scroll." if who.is_empty() else "You received a new scroll from %s." % who
	var link := "chest" if scroll_id.is_empty() else "chest:%s" % scroll_id
	show("new_scroll", title, body, link, 1101)


static func notify_connection_request(from_name: String) -> void:
	var who := from_name.strip_edges()
	if who.is_empty():
		who = "Someone"
	show("connections", "%s wants to connect with you." % who, ProductStrings.CONNECTION_REQUEST, "person", 1201)


static func notify_scheduled_ready(scroll_id: String = "") -> void:
	var link := "chest" if scroll_id.is_empty() else "chest:%s" % scroll_id
	show("scheduled_ready", "Your scroll is ready to open.", "A scroll's requirements are complete.", link, 1102)


static func schedule_ready_at(unlock_unix: int, scroll_id: String) -> void:
	## Schedule for unlock time while app may be closed (AlarmManager inexact).
	var p = _plugin()
	if p == null:
		return
	ensure_channels()
	var notif_id := 200000 + int(absi(hash(str(scroll_id))) % 50000)
	var trigger_ms := int(unlock_unix) * 1000
	var link := "chest:%s" % scroll_id
	if p.has_method("schedule_notification"):
		p.schedule_notification(
			"scheduled_ready",
			"Scroll ready",
			"A scroll is now available to open.",
			link,
			notif_id,
			trigger_ms
		)
	elif trigger_ms <= int(Time.get_unix_time_from_system()) * 1000 + 2000:
		show("scheduled_ready", "Scroll ready", "A scroll is now available to open.", link, notif_id)


static func cancel_scheduled_ready(scroll_id: String) -> void:
	var p = _plugin()
	if p == null:
		return
	var notif_id := 200000 + int(absi(hash(str(scroll_id))) % 50000)
	if p.has_method("cancel_scheduled_notification"):
		p.cancel_scheduled_notification(notif_id)
	elif p.has_method("cancel_notification"):
		p.cancel_notification(notif_id)


static func reschedule_persisted() -> void:
	var p = _plugin()
	if p != null and p.has_method("reschedule_persisted_notifications"):
		p.reschedule_persisted_notifications()


static func sync_scheduled_from_chest(items: Array) -> void:
	## Register/cancel scheduled-ready alarms from incoming chest scrolls.
	var now_u := int(Time.get_unix_time_from_system())
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = it
		var sid := str(item.get("id", ""))
		if sid.is_empty():
			continue
		if bool(item.get("opened", false)) or bool(item.get("is_opened", false)):
			cancel_scheduled_ready(sid)
			continue
		var unlock := int(item.get("unlock_at_unix", item.get("unlock_unix", 0)))
		if unlock <= 0:
			continue
		if unlock <= now_u:
			## Already eligible — do not leave a stale future alarm.
			cancel_scheduled_ready(sid)
			continue
		schedule_ready_at(unlock, sid)


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
