extends RefCounted
class_name ActivityLockHelper
## Activity Lock: cumulative distance after explicit Start Challenge.
## Progress is persisted locally; optional last-fix kept for segment math only.

const MIN_KM := 1.0
const MAX_KM := 100.0
const DEFAULT_KM := 5.0
const PRESETS_KM: Array[float] = [1.0, 2.0, 5.0, 10.0, 25.0]
const STORE_PATH := "user://coln_activity_challenges.json"
## Ignore segments shorter than this (GPS jitter while stationary).
const MIN_SEGMENT_M := 12.0
const MAX_ACCURACY_M := 50.0
const MAX_SPEED_M_S := 55.0 ## ~200 km/h — reject teleport jumps

static var _debug_force_km: float = -1.0


static func clamp_km(v: float) -> float:
	return clampf(v, MIN_KM, MAX_KM)


static func parse_km_text(text: String) -> Dictionary:
	var t := text.strip_edges().to_lower().replace("km", "").replace(",", ".").strip_edges()
	if t.is_empty() or not t.is_valid_float():
		return {"ok": false, "error": "Enter a distance of at least 1 km."}
	var v := float(t)
	if v < MIN_KM:
		return {"ok": false, "error": "Set Activity distance to at least 1 km."}
	if v > MAX_KM:
		return {"ok": false, "error": "Activity distance can be at most 100 km."}
	return {"ok": true, "value": clamp_km(v)}


static func format_km(km: float) -> String:
	if is_equal_approx(km, floor(km)):
		return "%d km" % int(km)
	return "%.1f km" % km


static func _load_all() -> Dictionary:
	if not FileAccess.file_exists(STORE_PATH):
		return {}
	var f := FileAccess.open(STORE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_as_text()
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


static func _save_all(data: Dictionary) -> void:
	var f := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))


static func get_progress(scroll_id: String) -> Dictionary:
	sync_from_native_service(scroll_id)
	var all := _load_all()
	var key := str(scroll_id)
	if not all.has(key) or typeof(all[key]) != TYPE_DICTIONARY:
		return {
			"started": false,
			"distance_km": 0.0,
			"completed": false,
			"target_km": 0.0,
		}
	return (all[key] as Dictionary).duplicate(true)


static func _location_plugin():
	if Engine.has_singleton("ChestLocation"):
		return Engine.get_singleton("ChestLocation")
	return null


static func start_challenge(scroll_id: String, target_km: float, start_lat: float, start_lng: float) -> Dictionary:
	var all := _load_all()
	var state := {
		"started": true,
		"started_unix": int(Time.get_unix_time_from_system()),
		"target_km": clamp_km(target_km),
		"distance_km": 0.0,
		"completed": false,
		"last_lat": start_lat,
		"last_lng": start_lng,
		"last_unix": int(Time.get_unix_time_from_system()),
		"service_active": false,
	}
	all[str(scroll_id)] = state
	_save_all(all)
	## Android foreground service keeps accumulating while app is backgrounded/screen off.
	var p = _location_plugin()
	if p != null and p.has_method("start_activity_tracking"):
		var ok := bool(p.start_activity_tracking(str(scroll_id), clamp_km(target_km), start_lat, start_lng))
		state["service_active"] = ok
		all[str(scroll_id)] = state
		_save_all(all)
	return state


static func reset_challenge(scroll_id: String) -> void:
	var all := _load_all()
	all.erase(str(scroll_id))
	_save_all(all)
	var p = _location_plugin()
	if p != null and p.has_method("stop_activity_tracking"):
		p.stop_activity_tracking()


static func sync_from_native_service(scroll_id: String = "") -> Dictionary:
	## Merge foreground-service progress into local JSON (no route trail).
	var p = _location_plugin()
	if p == null or not p.has_method("activity_tracking_snapshot"):
		return {}
	var raw := str(p.activity_tracking_snapshot())
	if raw.is_empty() or raw == "{}":
		return {}
	var native = JSON.parse_string(raw)
	if typeof(native) != TYPE_DICTIONARY:
		return {}
	var sid := str(native.get("scroll_id", ""))
	if sid.is_empty():
		return {}
	if not scroll_id.is_empty() and sid != str(scroll_id):
		return native
	var all := _load_all()
	var local: Dictionary = all.get(sid, {}) if typeof(all.get(sid, {})) == TYPE_DICTIONARY else {}
	if local.is_empty():
		local = {
			"started": bool(native.get("started", false)),
			"target_km": float(native.get("target_km", DEFAULT_KM)),
			"distance_km": 0.0,
			"completed": false,
		}
	local["started"] = bool(native.get("started", local.get("started", false)))
	local["target_km"] = float(native.get("target_km", local.get("target_km", DEFAULT_KM)))
	local["distance_km"] = maxf(float(local.get("distance_km", 0.0)), float(native.get("distance_km", 0.0)))
	local["completed"] = bool(native.get("completed", false)) or bool(local.get("completed", false))
	if native.has("last_lat") and native.get("last_lat") != null:
		local["last_lat"] = float(native.get("last_lat"))
	if native.has("last_lng") and native.get("last_lng") != null:
		local["last_lng"] = float(native.get("last_lng"))
	if native.has("last_unix"):
		local["last_unix"] = int(native.get("last_unix"))
	local["service_active"] = bool(native.get("service_active", false))
	all[sid] = local
	_save_all(all)
	if bool(local.get("completed", false)) and p.has_method("stop_activity_tracking"):
		p.stop_activity_tracking()
	return local


static func apply_sample(scroll_id: String, lat: float, lng: float, accuracy_m: float = 25.0, sample_unix: int = -1) -> Dictionary:
	var all := _load_all()
	var key := str(scroll_id)
	if not all.has(key) or typeof(all[key]) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Challenge not started"}
	var state: Dictionary = (all[key] as Dictionary).duplicate(true)
	if bool(state.get("completed", false)):
		return {"ok": true, "state": state}
	if accuracy_m > MAX_ACCURACY_M and accuracy_m > 0.0:
		return {"ok": true, "state": state, "ignored": "accuracy"}
	if not is_finite(lat) or not is_finite(lng):
		return {"ok": true, "state": state, "ignored": "coords"}
	var last_lat := float(state.get("last_lat", NAN))
	var last_lng := float(state.get("last_lng", NAN))
	var now_u := sample_unix if sample_unix > 0 else int(Time.get_unix_time_from_system())
	if is_finite(last_lat) and is_finite(last_lng):
		var seg_m := LocationHelper.haversine_m(last_lat, last_lng, lat, lng)
		var dt := maxi(1, now_u - int(state.get("last_unix", now_u)))
		var speed := seg_m / float(dt)
		if seg_m >= MIN_SEGMENT_M and speed <= MAX_SPEED_M_S:
			var add_km := seg_m / 1000.0
			state["distance_km"] = float(state.get("distance_km", 0.0)) + add_km
	state["last_lat"] = lat
	state["last_lng"] = lng
	state["last_unix"] = now_u
	var target := float(state.get("target_km", DEFAULT_KM))
	if _debug_force_km >= 0.0:
		state["distance_km"] = _debug_force_km
	if float(state.get("distance_km", 0.0)) + 0.001 >= target:
		state["completed"] = true
		state["completed_unix"] = now_u
	all[key] = state
	_save_all(all)
	return {"ok": true, "state": state}


static func is_complete(scroll_id: String, target_km: float) -> bool:
	var p := get_progress(scroll_id)
	if bool(p.get("completed", false)):
		return true
	return float(p.get("distance_km", 0.0)) + 0.001 >= clamp_km(target_km) and bool(p.get("started", false))


static func clear_all_for_sign_out() -> void:
	var p = _location_plugin()
	if p != null and p.has_method("clear_activity_tracking_state"):
		p.clear_activity_tracking_state()
	elif p != null and p.has_method("stop_activity_tracking"):
		p.stop_activity_tracking()
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(STORE_PATH)
