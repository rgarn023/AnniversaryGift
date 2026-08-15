class_name SaveService
extends RefCounted

## Atomic JSON save/load for normal and developer progress.

const SAVE_VERSION := 1
const NORMAL_PATH := "user://anniversary_progress.json"
const DEVELOPER_PATH := "user://anniversary_developer_progress.json"


static func default_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"opened_chest_dates": [],
		"viewed_scroll_dates": [],
		"latest_legitimate_date": "",
		"final_message_viewed": false,
		"final_gift_opened": false,
		"message_text_scale": 1.0,
		"reduced_motion": false,
		"sound_enabled": true,
	}


func load_state(developer_mode: bool = false) -> Dictionary:
	var path: String = DEVELOPER_PATH if developer_mode else NORMAL_PATH
	if not FileAccess.file_exists(path):
		return default_state()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveService: unable to open %s" % path)
		return default_state()
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_backup_corrupt(path, text)
		return default_state()
	return _sanitize(parsed as Dictionary)


func save_state(state: Dictionary, developer_mode: bool = false) -> bool:
	var path: String = DEVELOPER_PATH if developer_mode else NORMAL_PATH
	var sanitized: Dictionary = _sanitize(state)
	sanitized["version"] = SAVE_VERSION
	var json_text: String = JSON.stringify(sanitized, "\t")
	var tmp_path: String = path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveService: unable to write %s" % tmp_path)
		return false
	file.store_string(json_text)
	file.close()
	# Atomic replace where supported.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_err: Error = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		# Fallback copy.
		var src := FileAccess.open(tmp_path, FileAccess.READ)
		var dst := FileAccess.open(path, FileAccess.WRITE)
		if src == null or dst == null:
			push_warning("SaveService: atomic rename failed for %s" % path)
			return false
		dst.store_string(src.get_as_text())
		src.close()
		dst.close()
		DirAccess.remove_absolute(tmp_path)
	return true


func reset_state(developer_mode: bool = false) -> Dictionary:
	var state: Dictionary = default_state()
	save_state(state, developer_mode)
	return state


func _sanitize(raw: Dictionary) -> Dictionary:
	var state: Dictionary = default_state()
	state["opened_chest_dates"] = _to_string_array(raw.get("opened_chest_dates", []))
	state["viewed_scroll_dates"] = _to_string_array(raw.get("viewed_scroll_dates", []))
	state["latest_legitimate_date"] = str(raw.get("latest_legitimate_date", ""))
	state["final_message_viewed"] = bool(raw.get("final_message_viewed", false))
	state["final_gift_opened"] = bool(raw.get("final_gift_opened", false))
	state["message_text_scale"] = clampf(float(raw.get("message_text_scale", 1.0)), 0.8, 2.2)
	state["reduced_motion"] = bool(raw.get("reduced_motion", false))
	state["sound_enabled"] = bool(raw.get("sound_enabled", true))
	state["version"] = int(raw.get("version", SAVE_VERSION))
	return state


func _to_string_array(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		var s := str(item)
		if not s.is_empty() and not result.has(s):
			result.append(s)
	result.sort()
	return result


func _backup_corrupt(path: String, text: String) -> void:
	var backup: String = path + ".corrupt.%d.bak" % int(Time.get_unix_time_from_system())
	var file := FileAccess.open(backup, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
	push_warning("SaveService: backed up corrupt save to %s" % backup)
