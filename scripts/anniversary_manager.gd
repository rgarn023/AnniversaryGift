class_name AnniversaryManager
extends RefCounted

## Core unlock / archive / final-gift logic for Anniversary Gift.

signal state_changed
signal catchup_queue_changed(queue: Array)

const MESSAGES_PATH := "res://data/messages.json"
const FINAL_DATE := "2026-08-13"

var date_service: DateService
var save_service: SaveService

var messages: Array[Dictionary] = []
var state: Dictionary = {}
var developer_mode: bool = false
var catchup_queue: Array[String] = []


func _init(p_date_service: DateService = null, p_save_service: SaveService = null) -> void:
	date_service = p_date_service if p_date_service != null else DateService.new()
	save_service = p_save_service if p_save_service != null else SaveService.new()
	_load_messages()
	reload_progress()


func _load_messages() -> void:
	messages.clear()
	if not FileAccess.file_exists(MESSAGES_PATH):
		push_warning("AnniversaryManager: missing messages.json")
		return
	var file := FileAccess.open(MESSAGES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Variant = (parsed as Dictionary).get("messages", [])
	if typeof(arr) != TYPE_ARRAY:
		return
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY:
			messages.append((item as Dictionary).duplicate(true))


func reload_progress() -> void:
	state = save_service.load_state(developer_mode)
	refresh_unlocks()


func enter_developer_mode() -> void:
	developer_mode = true
	date_service.set_developer_active(true)
	state = save_service.load_state(true)
	refresh_unlocks()
	state_changed.emit()


func exit_developer_mode() -> void:
	developer_mode = false
	date_service.set_developer_active(false)
	date_service.clear_simulated_date()
	state = save_service.load_state(false)
	refresh_unlocks()
	state_changed.emit()


func persist() -> void:
	save_service.save_state(state, developer_mode)


func get_message_for_date(iso_date: String) -> Dictionary:
	for msg in messages:
		if str(msg.get("date", "")) == iso_date:
			return msg
	return {}


func get_all_dates() -> PackedStringArray:
	return DateService.ALL_DATES


func get_effective_date() -> String:
	return date_service.get_effective_date()


func get_unlock_date() -> String:
	## Normal mode uses max(device date, latest legitimate). Developer uses simulated/effective only.
	var effective: String = get_effective_date()
	if developer_mode:
		return effective
	var latest: String = str(state.get("latest_legitimate_date", ""))
	return DateService.max_date(effective, latest)


func refresh_unlocks() -> void:
	var unlock_date: String = get_unlock_date()
	if not developer_mode:
		var device_date: String = date_service.get_device_date()
		var latest: String = str(state.get("latest_legitimate_date", ""))
		var new_latest: String = DateService.max_date(latest, device_date)
		if new_latest != latest:
			state["latest_legitimate_date"] = new_latest
			persist()
	_rebuild_catchup_queue(unlock_date)
	state_changed.emit()


func get_unlocked_dates() -> Array[String]:
	var unlock_date: String = get_unlock_date()
	var result: Array[String] = []
	for d in DateService.ALL_DATES:
		if d <= unlock_date:
			result.append(d)
	# Once opened/viewed, never relock — include them even if unlock_date moves back in edge cases.
	for d in state.get("opened_chest_dates", []):
		var ds := str(d)
		if DateService.ALL_DATES.has(ds) and not result.has(ds):
			result.append(ds)
	for d in state.get("viewed_scroll_dates", []):
		var ds2 := str(d)
		if DateService.ALL_DATES.has(ds2) and not result.has(ds2):
			result.append(ds2)
	result.sort()
	return result


func is_date_unlocked(iso_date: String) -> bool:
	return get_unlocked_dates().has(iso_date)


func is_chest_opened(iso_date: String) -> bool:
	return state.get("opened_chest_dates", []).has(iso_date)


func is_scroll_viewed(iso_date: String) -> bool:
	return state.get("viewed_scroll_dates", []).has(iso_date)


func mark_chest_opened(iso_date: String) -> void:
	var opened: Array = state.get("opened_chest_dates", [])
	if not opened.has(iso_date):
		opened.append(iso_date)
		opened.sort()
		state["opened_chest_dates"] = opened
	if iso_date == FINAL_DATE:
		# First-stage open of final chest is the message.
		pass
	persist()
	_rebuild_catchup_queue(get_unlock_date())
	state_changed.emit()


func mark_scroll_viewed(iso_date: String) -> void:
	var viewed: Array = state.get("viewed_scroll_dates", [])
	if not viewed.has(iso_date):
		viewed.append(iso_date)
		viewed.sort()
		state["viewed_scroll_dates"] = viewed
	if iso_date == FINAL_DATE:
		state["final_message_viewed"] = true
	persist()
	_rebuild_catchup_queue(get_unlock_date())
	state_changed.emit()


func mark_final_gift_opened() -> void:
	state["final_gift_opened"] = true
	persist()
	state_changed.emit()


func is_final_message_viewed() -> bool:
	return bool(state.get("final_message_viewed", false)) or is_scroll_viewed(FINAL_DATE)


func is_final_gift_ready() -> bool:
	return is_final_message_viewed()


func is_final_gift_opened() -> bool:
	return bool(state.get("final_gift_opened", false))


func get_archived_dates() -> Array[String]:
	var result: Array[String] = []
	for d in state.get("viewed_scroll_dates", []):
		result.append(str(d))
	result.sort()
	return result


func get_next_chest_date() -> String:
	if catchup_queue.is_empty():
		# Final gift state remains available on main screen.
		if is_final_gift_ready():
			return FINAL_DATE
		return ""
	return catchup_queue[0]


func _rebuild_catchup_queue(unlock_date: String) -> void:
	catchup_queue.clear()
	if unlock_date < DateService.START_DATE:
		catchup_queue_changed.emit(catchup_queue.duplicate())
		return
	for d in DateService.ALL_DATES:
		if d > unlock_date:
			break
		if not is_chest_opened(d) or not is_scroll_viewed(d):
			# Need to open chest / view message.
			if d == FINAL_DATE and is_scroll_viewed(d):
				continue
			catchup_queue.append(d)
	catchup_queue_changed.emit(catchup_queue.duplicate())


func get_prestart_message() -> String:
	return "Your anniversary surprise begins August 6."


func is_before_start() -> bool:
	return get_unlock_date() < DateService.START_DATE


func get_text_scale() -> float:
	return float(state.get("message_text_scale", 1.0))


func set_text_scale(scale: float) -> void:
	state["message_text_scale"] = clampf(scale, 0.8, 2.2)
	persist()


func is_reduced_motion() -> bool:
	return bool(state.get("reduced_motion", false))


func set_reduced_motion(enabled: bool) -> void:
	state["reduced_motion"] = enabled
	persist()
	state_changed.emit()


func is_sound_enabled() -> bool:
	return bool(state.get("sound_enabled", true))


func set_sound_enabled(enabled: bool) -> void:
	state["sound_enabled"] = enabled
	persist()


# ---------- Developer helpers ----------

func developer_reset_progress() -> void:
	state = save_service.reset_state(true)
	_rebuild_catchup_queue(get_unlock_date())
	state_changed.emit()


func developer_mark_chest_unopened(iso_date: String) -> void:
	var opened: Array = state.get("opened_chest_dates", [])
	opened.erase(iso_date)
	state["opened_chest_dates"] = opened
	if iso_date == FINAL_DATE:
		state["final_message_viewed"] = false
		state["final_gift_opened"] = false
	persist()
	_rebuild_catchup_queue(get_unlock_date())
	state_changed.emit()


func developer_mark_scroll_unread(iso_date: String) -> void:
	var viewed: Array = state.get("viewed_scroll_dates", [])
	viewed.erase(iso_date)
	state["viewed_scroll_dates"] = viewed
	if iso_date == FINAL_DATE:
		state["final_message_viewed"] = false
	persist()
	_rebuild_catchup_queue(get_unlock_date())
	state_changed.emit()


func developer_unlock_all() -> void:
	date_service.set_simulated_date("2026-08-14")
	refresh_unlocks()


func developer_set_date(iso_date: String) -> void:
	date_service.set_simulated_date(iso_date)
	refresh_unlocks()
