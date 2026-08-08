extends RefCounted
class_name FocusLockHelper
## Focus Lock: uninterrupted non-interactive phone period after Begin Focus Time.
## Usage verification is local via ChestFocus / Usage Access — no app history uploaded.

const MIN_HOURS := 1
const MAX_HOURS := 24
const DEFAULT_HOURS := 3
const PRESETS_HOURS: Array[int] = [1, 2, 4, 8, 12, 24]
const STORE_PATH := "user://coln_focus_challenges.json"
const PLUGIN_NAME := "ChestFocus"
## Tests may set this > 0 to shorten duration. Production must leave at 0.
static var debug_short_seconds: int = 0


static func clamp_hours(h: int) -> int:
	return clampi(h, MIN_HOURS, MAX_HOURS)


static func parse_hours_text(text: String) -> Dictionary:
	var t := text.strip_edges().to_lower().replace("hours", "").replace("hour", "").replace("hr", "").replace("h", "").strip_edges()
	if t.is_empty() or not t.is_valid_float():
		return {"ok": false, "error": "Set Focus time between 1 and 24 hours."}
	var v := int(round(float(t)))
	if v < MIN_HOURS or v > MAX_HOURS:
		return {"ok": false, "error": "Set Focus time between 1 and 24 hours."}
	return {"ok": true, "value": clamp_hours(v)}


static func format_hours(h: int) -> String:
	if h == 1:
		return "1 hour"
	return "%d hours" % h


static func required_seconds(hours: int) -> int:
	if debug_short_seconds > 0 and OS.is_debug_build():
		return debug_short_seconds
	return clamp_hours(hours) * 3600


static func _plugin():
	if Engine.has_singleton(PLUGIN_NAME):
		return Engine.get_singleton(PLUGIN_NAME)
	return null


static func usage_access_granted() -> bool:
	if OS.get_name() != "Android":
		return true ## Desktop/headless: treat as granted for compose tests.
	var p = _plugin()
	if p != null and p.has_method("has_usage_access"):
		return bool(p.has_usage_access())
	return false


static func open_usage_access_settings() -> void:
	var p = _plugin()
	if p != null and p.has_method("open_usage_access_settings"):
		p.open_usage_access_settings()


static func _load_all() -> Dictionary:
	if not FileAccess.file_exists(STORE_PATH):
		return {}
	var f := FileAccess.open(STORE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


static func _save_all(data: Dictionary) -> void:
	var f := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))


static func get_progress(scroll_id: String) -> Dictionary:
	var all := _load_all()
	var key := str(scroll_id)
	if not all.has(key) or typeof(all[key]) != TYPE_DICTIONARY:
		return {"started": false, "completed": false, "interrupted": false, "hours": 0}
	return (all[key] as Dictionary).duplicate(true)


static func begin_focus(scroll_id: String, hours: int) -> Dictionary:
	var all := _load_all()
	var state := {
		"started": true,
		"interrupted": false,
		"completed": false,
		"hours": clamp_hours(hours),
		"started_unix": int(Time.get_unix_time_from_system()),
		"started_elapsed_msec": Time.get_ticks_msec(),
		"boot_id": _boot_token(),
	}
	all[str(scroll_id)] = state
	_save_all(all)
	return state


static func restart_focus(scroll_id: String, hours: int) -> Dictionary:
	return begin_focus(scroll_id, hours)


static func _boot_token() -> String:
	## Soft reboot detector — if Android exposes boot time via plugin, prefer that.
	var p = _plugin()
	if p != null and p.has_method("boot_elapsed_realtime"):
		return str(p.boot_elapsed_realtime())
	return "unknown"


static func evaluate(scroll_id: String) -> Dictionary:
	## Check whether focus interval completed uninterrupted.
	var all := _load_all()
	var key := str(scroll_id)
	if not all.has(key) or typeof(all[key]) != TYPE_DICTIONARY:
		return {"ok": false, "status": "not_started"}
	var state: Dictionary = (all[key] as Dictionary).duplicate(true)
	if bool(state.get("completed", false)):
		return {"ok": true, "status": "complete", "state": state}
	if not bool(state.get("started", false)):
		return {"ok": false, "status": "not_started", "state": state}
	if str(state.get("boot_id", "")) != _boot_token() and str(state.get("boot_id", "")) != "unknown":
		state["interrupted"] = true
		state["started"] = false
		all[key] = state
		_save_all(all)
		return {"ok": false, "status": "reboot_reset", "state": state, "message": "Focus interrupted. Start again when you're ready."}
	var hours := int(state.get("hours", DEFAULT_HOURS))
	var need := required_seconds(hours)
	var started := int(state.get("started_unix", 0))
	var now_u := int(Time.get_unix_time_from_system())
	var elapsed := now_u - started
	if OS.get_name() == "Android":
		var p = _plugin()
		if p == null or not usage_access_granted():
			return {"ok": false, "status": "usage_denied", "state": state, "message": "Focus Lock needs Usage Access to verify an uninterrupted period."}
		if p.has_method("had_interactive_usage_since"):
			var used := bool(p.had_interactive_usage_since(started * 1000))
			if used:
				state["interrupted"] = true
				state["started"] = false
				state["interrupted_unix"] = now_u
				all[key] = state
				_save_all(all)
				return {"ok": false, "status": "interrupted", "state": state, "message": "Focus interrupted. Start again when you're ready."}
	else:
		## Headless/desktop: complete when wall time elapsed (for automated tests).
		pass
	if elapsed >= need:
		state["completed"] = true
		state["completed_unix"] = now_u
		all[key] = state
		_save_all(all)
		return {"ok": true, "status": "complete", "state": state}
	return {
		"ok": false,
		"status": "in_progress",
		"state": state,
		"elapsed_sec": elapsed,
		"needed_sec": need,
		"remaining_sec": maxi(0, need - elapsed),
	}


static func is_complete(scroll_id: String) -> bool:
	var r := evaluate(scroll_id)
	return bool(r.get("ok", false)) and str(r.get("status", "")) == "complete"


static func clear_all_for_sign_out() -> void:
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(STORE_PATH)
