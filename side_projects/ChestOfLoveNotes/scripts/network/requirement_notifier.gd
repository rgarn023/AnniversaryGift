extends RefCounted
class_name RequirementNotifier
## Central lock-requirement transition notifier (false → true once).
## Notifications report state; open-scroll remains authoritative.

const DEDUPE_PATH := "user://coln_req_notify_dedupe.json"

var _seen: Dictionary = {} ## key -> true


func _init() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(DEDUPE_PATH):
		_seen = {}
		return
	var txt := FileAccess.get_file_as_string(DEDUPE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		_seen = parsed
	else:
		_seen = {}


func _save() -> void:
	var f := FileAccess.open(DEDUPE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_seen))


func _claim(key: String) -> bool:
	if key.is_empty() or _seen.has(key):
		return false
	_seen[key] = true
	_save()
	return true


func clear_for_scroll(scroll_id: String) -> void:
	var prefix := scroll_id + "|"
	var drop: Array = []
	for k in _seen.keys():
		if str(k).begins_with(prefix):
			drop.append(k)
	for d in drop:
		_seen.erase(d)
	_save()


func evaluate_item(item: Dictionary, now_unix: int = -1) -> void:
	## Call after chest refresh / lock progress updates.
	if now_unix < 0:
		now_unix = int(Time.get_unix_time_from_system())
	var sid := str(item.get("id", item.get("scroll_id", "")))
	if sid.is_empty():
		return
	if bool(item.get("is_opened", false)) or bool(item.get("is_read", false)):
		clear_for_scroll(sid)
		return

	var unlock_unix := int(item.get("unlock_at_unix", item.get("unlock_unix", 0)))
	if unlock_unix <= 0:
		var unlock_at := str(item.get("unlock_at", ""))
		if not unlock_at.is_empty():
			unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))

	var time_ok := unlock_unix <= 0 or unlock_unix <= now_unix
	var loc_enabled := bool(item.get("has_location_lock", false))
	var loc_ok := (not loc_enabled) or bool(item.get("location_requirement_met", false))
	var act_enabled := bool(item.get("activity_lock_enabled", false))
	var act_ok := (not act_enabled) or bool(item.get("activity_completed", false)) or str(item.get("activity_completed_at", "")) != ""
	var focus_enabled := bool(item.get("focus_lock_enabled", false))
	var focus_ok := (not focus_enabled) or bool(item.get("focus_completed", false)) or str(item.get("focus_completed_at", "")) != ""
	var pw_enabled := bool(item.get("has_password", false)) or bool(item.get("has_magic_password", false))
	## Password is only "complete" after successful open verification — never notify as complete here.
	var pw_ok := not pw_enabled

	if time_ok and unlock_unix > 0 and _claim("%s|time" % sid):
		_notify_partial_or_ready(sid, "Time Lock complete", time_ok and loc_ok and act_ok and focus_ok and pw_ok, "time")
	if loc_enabled and loc_ok and _claim("%s|location" % sid):
		_notify_partial_or_ready(sid, "Location Lock complete", time_ok and loc_ok and act_ok and focus_ok and pw_ok, "location")
	if act_enabled and act_ok and _claim("%s|activity" % sid):
		NotificationHelper.notify_activity_complete()
		if time_ok and loc_ok and act_ok and focus_ok and pw_ok and _claim("%s|ready" % sid):
			_notify_ready(sid)
	if focus_enabled and focus_ok and _claim("%s|focus" % sid):
		var all_ready := time_ok and loc_ok and act_ok and focus_ok and pw_ok
		NotificationHelper.notify_focus_complete(all_ready)
		if all_ready and _claim("%s|ready" % sid):
			_notify_ready(sid)

	## All non-password locks complete → ready (password still at open).
	if time_ok and loc_ok and act_ok and focus_ok and not pw_enabled:
		if _claim("%s|ready" % sid):
			_notify_ready(sid)


func _notify_partial_or_ready(scroll_id: String, title: String, all_ok: bool, kind: String) -> void:
	if all_ok:
		if _claim("%s|ready" % scroll_id):
			_notify_ready(scroll_id)
		return
	var body := "A scroll's %s requirement is now complete. Other locks remain." % kind
	if kind == "time":
		body = "A scroll's time requirement is now complete. Other locks remain."
	NotificationHelper.show("scheduled_ready", title, body, "chest:%s" % scroll_id, 1200 + int(absi(hash(scroll_id + kind)) % 80))


func _notify_ready(scroll_id: String) -> void:
	NotificationHelper.show(
		"scheduled_ready",
		"Your scroll is ready to open.",
		"All unlock requirements are complete.",
		"chest:%s" % scroll_id,
		1300 + int(absi(hash(scroll_id)) % 80)
	)


func evaluate_chest_items(items: Array) -> void:
	for it in items:
		if typeof(it) == TYPE_DICTIONARY:
			evaluate_item(it)
