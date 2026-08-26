extends RefCounted
class_name ChestEventNotifier
## Local (in-app refresh) notifications for newly arrived scrolls / connection requests.
## Seeds existing chest items on first sync so upgrade/reinstall does not spam history.
## Dedupe keys persist under user:// so the same event does not re-notify.

const DEDUPE_PATH := "user://coln_chest_event_notify_dedupe.json"

var _seen: Dictionary = {} ## key -> true
var _seeded: bool = false


func _init() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(DEDUPE_PATH):
		_seen = {}
		_seeded = false
		return
	var txt := FileAccess.get_file_as_string(DEDUPE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		_seen = {}
		_seeded = false
		return
	var d: Dictionary = parsed
	_seeded = bool(d.get("seeded", false))
	var keys: Variant = d.get("keys", {})
	if typeof(keys) == TYPE_DICTIONARY:
		_seen = keys
	elif typeof(keys) == TYPE_ARRAY:
		_seen = {}
		for k in keys:
			_seen[str(k)] = true
	else:
		_seen = {}


func _save() -> void:
	var f := FileAccess.open(DEDUPE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"seeded": _seeded, "keys": _seen}))


func _claim(key: String) -> bool:
	if key.is_empty() or _seen.has(key):
		return false
	_seen[key] = true
	_save()
	return true


func _remember(key: String) -> void:
	if key.is_empty() or _seen.has(key):
		return
	_seen[key] = true


func evaluate_chest(scrolls: Array, requests: Array) -> void:
	## First successful chest payload: remember current ids without notifying.
	if not _seeded:
		for s in scrolls:
			if typeof(s) == TYPE_DICTIONARY:
				var sid := str((s as Dictionary).get("id", ""))
				if not sid.is_empty():
					_remember("scroll|%s" % sid)
		for r in requests:
			if typeof(r) == TYPE_DICTIONARY:
				var rid := str((r as Dictionary).get("id", ""))
				if not rid.is_empty():
					_remember("request|%s" % rid)
		_seeded = true
		_save()
		return

	for s in scrolls:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = s
		var sid := str(item.get("id", ""))
		if sid.is_empty():
			continue
		if bool(item.get("is_opened", false)) or bool(item.get("opened", false)):
			_remember("scroll|%s" % sid)
			continue
		## Permission must be ready BEFORE claim — otherwise the first event is lost.
		if not NotificationHelper.prepare_contextual_notification():
			continue
		if not _claim("scroll|%s" % sid):
			continue
		var sender: Dictionary = item.get("sender", {}) if typeof(item.get("sender")) == TYPE_DICTIONARY else {}
		var from_name := IdentityHelper.display_name_from_profile(
			sender,
			IdentityHelper.safe_label(str(item.get("sender_display_name", "")), "")
		)
		NotificationHelper.notify_new_scroll(from_name, sid)

	for r in requests:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var req: Dictionary = r
		var rid := str(req.get("id", ""))
		if rid.is_empty():
			continue
		## Permission must be ready BEFORE claim — otherwise the first event is lost.
		if not NotificationHelper.prepare_contextual_notification():
			continue
		if not _claim("request|%s" % rid):
			continue
		var sender2: Dictionary = req.get("sender", {}) if typeof(req.get("sender")) == TYPE_DICTIONARY else {}
		var who := IdentityHelper.display_name_from_profile(sender2, "Someone")
		NotificationHelper.notify_connection_request(who, rid)
