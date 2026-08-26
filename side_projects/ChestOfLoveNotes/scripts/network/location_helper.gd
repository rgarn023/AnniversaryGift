extends RefCounted
class_name LocationHelper
## Battery-conscious device location for Location Lock.
## Uses Android Fused Location via ChestLocationPlugin when available.
## Permission is requested only when Compose/Open/permissions-setup explicitly needs it.
##
## Success for "Use Current Location" = valid latitude/longitude.
## Reverse geocoding is optional display polish (handled by Compose).

const PLUGIN_NAME := "ChestLocation"
const DEFAULT_RADIUS_M := 500
const MIN_RADIUS_M := 1
const MAX_RADIUS_M := 10000
const SMALL_RADIUS_WARN_M := 50
## Optional quick shortcuts only — not the sole radius control.
const RADIUS_OPTIONS: Array[int] = [25, 100, 250, 500, 1000]
const PERM_FINE := "android.permission.ACCESS_FINE_LOCATION"
const PERM_COARSE := "android.permission.ACCESS_COARSE_LOCATION"
## Sensible threshold for Location Lock *selection* — not unlock evaluation.
const MAX_ACCEPTABLE_ACCURACY_M := 500.0
## Accept recent fused/cached fixes for selection.
const MAX_FIX_AGE_MS := 180000
## ~45s fused acquisition window (matches native FRESH_TIMEOUT_MS).
const FRESH_POLL_COUNT := 120
const FRESH_POLL_INTERVAL_SEC := 0.4

## Desktop / headless mock (never used to falsely unlock online scrolls).
const MOCK_LAT := 33.4484
const MOCK_LNG := -112.0740

## Ignore stale polls/timeouts from a superseded Current Location attempt.
static var _active_request_token: int = 0

## Canonical Current Location diagnostics (no coordinates). Shared by Compose + Android Diagnostics.
static var last_request_state: String = "Idle" ## Idle / Requesting / Success / Failed
static var last_native_request: String = "Not Started" ## Started / Not Started
static var last_callback: String = "Not Received" ## Received / Not Received
static var last_failure_stage: String = "None" ## None / Permission / Services / Bridge / Request / Callback / Invalid Fix / Timeout


static func reset_request_diagnostics() -> void:
	last_request_state = "Idle"
	last_native_request = "Not Started"
	last_callback = "Not Received"
	last_failure_stage = "None"


static func request_diagnostics_snapshot() -> Dictionary:
	return {
		"location_request_state": last_request_state,
		"last_native_request": last_native_request,
		"last_callback": last_callback,
		"last_failure_stage": last_failure_stage,
		"location_bridge": "Available" if bridge_available() else "Missing",
		"location_services": "On" if location_services_enabled() else "Off",
	}


static func haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
	var r := 6371000.0
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lng2 - lng1)
	var a := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return r * 2.0 * atan2(sqrt(a), sqrt(maxf(0.0, 1.0 - a)))


static func within_radius(lat: float, lng: float, target_lat: float, target_lng: float, radius_m: int) -> bool:
	if radius_m <= 0:
		return false
	return haversine_m(lat, lng, target_lat, target_lng) <= float(radius_m)


static func format_radius(meters: int) -> String:
	if meters >= 1000:
		var km := float(meters) / 1000.0
		if is_equal_approx(km, floor(km)):
			return "%d km" % int(km)
		return "%.1f km" % km
	return "%d m" % meters


static func format_distance_away(meters: float) -> String:
	if meters < 1000.0:
		return "about %d m away" % int(round(meters))
	return "about %.1f km away" % (meters / 1000.0)


static func _plugin():
	return NativePluginUtil.get_singleton(PLUGIN_NAME)


static func _plugin_method(method: String) -> bool:
	## Canonical capability check — never rely on has_method alone for Android JNI.
	return NativePluginUtil.method_available(PLUGIN_NAME, method)


static func _call_plugin(method: String, args: Array = []) -> Variant:
	return NativePluginUtil.call_method(PLUGIN_NAME, method, args)


static func bridge_available() -> bool:
	## ONE canonical Location bridge check used by Diagnostics and Compose.
	var p = _plugin()
	if p == null:
		return false
	if OS.get_name() == "Android":
		## Singleton registration proves ChestLocationPlugin is packaged.
		## Probe a known method when has_method works; otherwise trust the singleton.
		if p.has_method("location_plugin_available"):
			return bool(p.call("location_plugin_available"))
		return true
	return (
		_plugin_method("location_plugin_available")
		or _plugin_method("begin_fresh_location")
		or _plugin_method("get_last_known_location")
	)


static func is_available() -> bool:
	return bridge_available()


static func services_enabled() -> bool:
	return location_services_enabled()


static func request_current_location(require_accuracy: bool = true) -> Dictionary:
	## Canonical entry used by Compose Use Current Location.
	return await get_fresh_fix(require_accuracy)


static func _await_plugin_ready(max_waits: int = 12) -> Variant:
	## Runtime registration can lag briefly after resume — wait before declaring missing.
	var p = _plugin()
	if p != null:
		return p
	var tree := Engine.get_main_loop() as SceneTree
	for _i in range(max_waits):
		if tree != null:
			await tree.create_timer(0.05).timeout
		p = _plugin()
		if p != null:
			return p
	return null


static func _log(msg: String) -> void:
	## Targeted Current Location diagnostics (debug builds only; not shown in UI).
	if OS.is_debug_build():
		print("[COLN-LOC] %s" % msg)


static func _bridge_missing_error() -> Dictionary:
	last_request_state = "Failed"
	last_failure_stage = "Bridge"
	_log("LOCATION BRIDGE MISSING")
	_log("provider_initialized=false")
	_log("provider_type=missing")
	_log("accepted=false")
	_log("rejection_reason=LOCATION_BRIDGE_MISSING")
	var msg := "We couldn't determine your location. Try again."
	if OS.is_debug_build():
		msg = "LOCATION BRIDGE MISSING"
	return {
		"ok": false,
		"error": msg,
		"unavailable": true,
		"bridge_missing": true,
	}


static func permission_status() -> String:
	if OS.get_name() != "Android":
		return "unsupported"
	if _plugin_method("has_location_permission"):
		var ok: Variant = _call_plugin("has_location_permission")
		if bool(ok):
			return "granted"
	var granted := OS.get_granted_permissions()
	if granted.has(PERM_FINE) or granted.has(PERM_COARSE):
		return "granted"
	return "denied"


static func location_services_enabled() -> bool:
	## Live Android Location Services query via ChestLocation.is_location_enabled().
	## Do NOT infer from permission, cache, prior failure, or bridge presence.
	if OS.get_name() != "Android":
		return true
	var p = _plugin()
	if p == null:
		return true
	if _plugin_method("is_location_enabled"):
		return bool(_call_plugin("is_location_enabled"))
	## Plugin present but method unknown — avoid false Off (Diagnostics bug).
	return true


static func request_permission_if_needed() -> String:
	## Never call during app launch — only from Location Lock / permissions setup.
	if OS.get_name() != "Android":
		return "unsupported"
	if permission_status() == "granted":
		return "granted"
	if OS.has_method("request_permission"):
		OS.request_permission(PERM_FINE)
		OS.request_permission(PERM_COARSE)
	if _plugin_method("request_location_permission"):
		_call_plugin("request_location_permission")
	return permission_status()


static func dump_diagnostics() -> void:
	if _plugin_method("location_diagnostics"):
		_log(str(_call_plugin("location_diagnostics")))
	else:
		_log("plugin_missing perm=%s enabled=%s" % [permission_status(), location_services_enabled()])


static func _coords_valid(lat: float, lng: float) -> bool:
	if not is_finite(lat) or not is_finite(lng):
		return false
	if is_equal_approx(lat, 0.0) and is_equal_approx(lng, 0.0):
		return false
	if lat < -90.0 or lat > 90.0 or lng < -180.0 or lng > 180.0:
		return false
	return true


static func _parse_fix_raw(raw: String, require_accuracy: bool, max_age_ms: int = -1) -> Dictionary:
	var parts := raw.split("|")
	if parts.is_empty():
		return {"ok": false, "error": "We couldn't determine your location. Try again.", "unavailable": true}
	if parts[0] == "ok" and parts.size() >= 4:
		var lat := float(parts[1])
		var lng := float(parts[2])
		var accuracy := float(parts[3])
		var age_ms := int(parts[4]) if parts.size() >= 5 and str(parts[4]).is_valid_int() else -1
		var source := str(parts[5]) if parts.size() >= 6 else "device"
		_log("latitude=%s" % ("valid" if _coords_valid(lat, lng) else "invalid"))
		_log("longitude=%s" % ("valid" if _coords_valid(lat, lng) else "invalid"))
		_log("accuracy=%s" % accuracy)
		_log("location_age=%s" % (float(age_ms) / 1000.0 if age_ms >= 0 else -1))
		if not _coords_valid(lat, lng):
			_log("accepted=false")
			_log("rejection_reason=invalid_coordinates")
			return {
				"ok": false,
				"error": "We couldn't determine your location. Try again.",
				"unavailable": true,
			}
		if max_age_ms >= 0 and age_ms >= 0 and age_ms > max_age_ms:
			_log("accepted=false")
			_log("rejection_reason=stale_fix")
			return {
				"ok": false,
				"error": "We couldn't determine your location. Try again.",
				"stale": true,
				"age_ms": age_ms,
			}
		var accuracy_note := ""
		if accuracy > 0.0 and accuracy > 25.0:
			accuracy_note = "Approximate accuracy: %d m" % int(round(accuracy))
		if require_accuracy and accuracy > 0.0 and accuracy > MAX_ACCEPTABLE_ACCURACY_M:
			_log("accepted=false")
			_log("rejection_reason=accuracy_too_low")
			return {
				"ok": false,
				"error": "Your location accuracy is too low. Try again.",
				"inaccurate": true,
				"accuracy_m": accuracy,
			}
		_log("accepted=true")
		_log("rejection_reason=")
		return {
			"ok": true,
			"lat": lat,
			"lng": lng,
			"accuracy_m": accuracy,
			"age_ms": age_ms,
			"mock": false,
			"source": source,
			"accuracy_note": accuracy_note,
		}
	var code := str(parts[2]) if parts.size() >= 3 else "unavailable"
	var msg := str(parts[1]) if parts.size() >= 2 else "We couldn't determine your location. Try again."
	if code == "disabled":
		msg = "Turn on Location Services to use your current location."
	elif code == "denied":
		msg = "Allow Location permission to use your current location."
	elif code == "timeout":
		msg = "We couldn't determine your location. Try again."
	elif code == "pending":
		msg = "Getting your location…"
	return {
		"ok": false,
		"error": msg,
		"denied": code == "denied",
		"disabled": code == "disabled",
		"pending": code == "pending",
		"unavailable": code == "unavailable" or code == "timeout",
		"timeout": code == "timeout",
	}


static func get_current_fix(require_accuracy: bool = true) -> Dictionary:
	## Synchronous peek — last-known only. Fresh fused acquisition uses get_fresh_fix().
	if OS.get_name() != "Android":
		return {
			"ok": true,
			"lat": MOCK_LAT,
			"lng": MOCK_LNG,
			"accuracy_m": 25.0,
			"age_ms": 0,
			"mock": true,
			"source": "mock",
		}
	if permission_status() != "granted":
		return {
			"ok": false,
			"error": "Allow Location permission to use your current location.",
			"denied": true,
		}
	if not location_services_enabled():
		return {
			"ok": false,
			"error": "Turn on Location Services to use your current location.",
			"disabled": true,
		}
	if not bridge_available() or not _plugin_method("get_last_known_location"):
		return _bridge_missing_error()
	return _parse_fix_raw(str(_call_plugin("get_last_known_location")), require_accuracy)


static func get_fresh_fix(require_accuracy: bool = true) -> Dictionary:
	## Obtain a fresh fused location fix. Coordinates success is independent of reverse geocode.
	## State: Idle → Requesting → Success | Failed (diagnostics). Token supersedes stale timeouts.
	if OS.get_name() != "Android":
		last_request_state = "Success"
		last_native_request = "Started"
		last_callback = "Received"
		last_failure_stage = "None"
		return get_current_fix(require_accuracy)
	_active_request_token += 1
	var my_token := _active_request_token
	last_request_state = "Requesting"
	last_native_request = "Not Started"
	last_callback = "Not Received"
	last_failure_stage = "None"
	_log("current_location_requested")
	_log("state=Requesting")
	var p = await _await_plugin_ready()
	var fine := false
	var coarse := false
	if _plugin_method("has_fine_location_permission"):
		fine = bool(_call_plugin("has_fine_location_permission"))
	else:
		fine = OS.get_granted_permissions().has(PERM_FINE)
	if _plugin_method("has_coarse_location_permission"):
		coarse = bool(_call_plugin("has_coarse_location_permission"))
	else:
		coarse = OS.get_granted_permissions().has(PERM_COARSE)
	_log("permission_fine=%s" % fine)
	_log("permission_coarse=%s" % coarse)
	_log("location_services=%s" % location_services_enabled())
	_log("Engine.has_singleton(ChestLocation)=%s" % Engine.has_singleton(PLUGIN_NAME))
	dump_diagnostics()
	if permission_status() != "granted":
		last_request_state = "Failed"
		last_failure_stage = "Permission"
		_log("provider_initialized=false")
		_log("accepted=false")
		_log("rejection_reason=permission_denied")
		_log("state=Failed")
		return {
			"ok": false,
			"error": "Allow Location permission to use your current location.",
			"denied": true,
		}
	if not location_services_enabled():
		last_request_state = "Failed"
		last_failure_stage = "Services"
		_log("provider_initialized=false")
		_log("accepted=false")
		_log("rejection_reason=location_services_off")
		_log("state=Failed")
		return {
			"ok": false,
			"error": "Turn on Location Services to use your current location.",
			"disabled": true,
		}
	if p == null or not bridge_available():
		last_request_state = "Failed"
		last_failure_stage = "Bridge"
		_log("state=Failed")
		return _bridge_missing_error()
	_log("provider_initialized=true")
	_log("provider_type=ChestLocation/fused")
	var settled: Dictionary = {}
	var success_latched := false
	## begin/poll are always present on packaged ChestLocation — do not gate on has_method.
	if _plugin_method("begin_fresh_location") and _plugin_method("poll_fresh_location"):
		if not bool(_call_plugin("begin_fresh_location")):
			last_request_state = "Failed"
			last_failure_stage = "Request"
			last_native_request = "Not Started"
			_log("location_request_started=false")
			_log("accepted=false")
			_log("rejection_reason=begin_failed")
			_log("state=Failed")
			if not location_services_enabled():
				last_failure_stage = "Services"
				return {
					"ok": false,
					"error": "Turn on Location Services to use your current location.",
					"disabled": true,
				}
			return {
				"ok": false,
				"error": "We couldn't determine your location. Try again.",
				"unavailable": true,
			}
		last_native_request = "Started"
		_log("location_request_started")
		var tree := Engine.get_main_loop() as SceneTree
		for _i in range(FRESH_POLL_COUNT):
			if my_token != _active_request_token:
				_log("accepted=false")
				_log("rejection_reason=superseded_request")
				_log("state=Failed")
				return {"ok": false, "error": "We couldn't determine your location. Try again.", "unavailable": true}
			if tree != null:
				await tree.create_timer(FRESH_POLL_INTERVAL_SEC).timeout
			if success_latched and bool(settled.get("ok", false)):
				last_request_state = "Success"
				last_failure_stage = "None"
				_log("state=SUCCESS")
				return settled
			var raw := str(_call_plugin("poll_fresh_location"))
			if raw.begins_with("ok|"):
				last_callback = "Received"
				_log("callback_received")
				_log("state=COORDINATES_RECEIVED")
				var parsed_ok := _parse_fix_raw(raw, require_accuracy, MAX_FIX_AGE_MS)
				if bool(parsed_ok.get("ok", false)):
					settled = parsed_ok
					success_latched = true
					## Cancel native timeout / listeners — stale timeout must not overwrite success.
					if _plugin_method("cancel_fresh_location"):
						_call_plugin("cancel_fresh_location")
					last_request_state = "Success"
					last_failure_stage = "None"
					_log("state=SUCCESS")
					return settled
				last_failure_stage = "Invalid Fix"
				## Keep listening for a better/fresher point.
				continue
			if raw.contains("|pending"):
				continue
			## Timeout/error from poll — ignore if we already accepted coords.
			if success_latched:
				_log("timeout_fired after success — ignored")
				last_request_state = "Success"
				last_failure_stage = "None"
				_log("state=SUCCESS")
				return settled
			_log("timeout_fired")
			break
		if _plugin_method("cancel_fresh_location"):
			_call_plugin("cancel_fresh_location")
		if my_token != _active_request_token:
			_log("state=Failed")
			return {"ok": false, "error": "We couldn't determine your location. Try again.", "unavailable": true}
		if success_latched and bool(settled.get("ok", false)):
			last_request_state = "Success"
			last_failure_stage = "None"
			_log("state=SUCCESS")
			return settled
		var last_raw := ""
		if _plugin_method("get_last_known_location"):
			last_raw = str(_call_plugin("get_last_known_location"))
		var last := _parse_fix_raw(last_raw, require_accuracy, MAX_FIX_AGE_MS)
		if bool(last.get("ok", false)):
			last["source"] = "recent_cached"
			last_callback = "Received"
			last_request_state = "Success"
			last_failure_stage = "None"
			_log("callback_received")
			_log("accepted=true")
			_log("rejection_reason=")
			_log("state=SUCCESS")
			return last
		last_request_state = "Failed"
		last_failure_stage = "Timeout"
		_log("accepted=false")
		_log("rejection_reason=timeout_no_fix")
		_log("state=Failed")
		return {
			"ok": false,
			"error": "We couldn't determine your location. Try again.",
			"unavailable": true,
			"timeout": true,
		}
	## Prefer begin/poll only — do not use blocking request_fresh_location on the UI thread.
	last_request_state = "Failed"
	last_failure_stage = "Bridge"
	_log("accepted=false")
	_log("rejection_reason=no_fresh_api")
	_log("state=Failed")
	return {
		"ok": false,
		"error": "We couldn't determine your location. Try again.",
		"unavailable": true,
		"bridge_missing": true,
	}


static func register_geofence(scroll_id: String, lat: float, lng: float, radius_m: float) -> bool:
	if not _plugin_method("register_scroll_geofence"):
		return false
	return bool(_call_plugin("register_scroll_geofence", [scroll_id, lat, lng, radius_m]))


static func remove_geofence(scroll_id: String) -> bool:
	if not _plugin_method("remove_scroll_geofence"):
		return false
	return bool(_call_plugin("remove_scroll_geofence", [scroll_id]))


static func clear_all_geofences() -> bool:
	if not _plugin_method("clear_all_geofences"):
		return false
	return bool(_call_plugin("clear_all_geofences"))


static func has_background_location_permission() -> bool:
	if _plugin_method("has_background_location_permission"):
		return bool(_call_plugin("has_background_location_permission"))
	return permission_status() == "granted"


static func request_background_location_permission() -> bool:
	if _plugin_method("request_background_location_permission"):
		return bool(_call_plugin("request_background_location_permission"))
	return false


static func format_lock_summary(location_name: String, has_schedule: bool, schedule_label: String, radius_m: int = DEFAULT_RADIUS_M) -> String:
	var place := location_name.strip_edges()
	if place.is_empty():
		place = "a set place"
	var near := "Near %s (within %s)" % [place, format_radius(radius_m)]
	if has_schedule:
		return "%s · %s" % [near, schedule_label]
	return near


static func evaluate_unlock_requirements(item: Dictionary, now_unix: int, fix: Dictionary = {}) -> Dictionary:
	## Central AND of active requirements. Fail closed on location errors.
	var reasons: PackedStringArray = PackedStringArray()
	var unlock_unix := int(item.get("unlock_at_unix", item.get("unlock_unix", 0)))
	if unlock_unix <= 0:
		var unlock_at := str(item.get("unlock_at", ""))
		if not unlock_at.is_empty():
			unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))
	if unlock_unix > now_unix:
		reasons.append("time")
	if bool(item.get("has_location_lock", false)):
		var tlat := float(item.get("location_lat", NAN))
		var tlng := float(item.get("location_lng", NAN))
		var radius := int(item.get("location_radius_m", DEFAULT_RADIUS_M))
		if not is_finite(tlat) or not is_finite(tlng):
			reasons.append("location_unconfigured")
		elif not bool(fix.get("ok", false)):
			reasons.append("location_unavailable")
		else:
			var accuracy := float(fix.get("accuracy_m", 0.0))
			if accuracy > 0.0 and accuracy > float(maxi(radius, 1)):
				reasons.append("location_accuracy")
				return {
					"ok": false,
					"reasons": reasons,
					"distance_m": -1.0,
					"message": "Location accuracy is too low for this small unlock radius. Try again outdoors.",
				}
			var dist := haversine_m(float(fix.get("lat")), float(fix.get("lng")), tlat, tlng)
			if dist > float(radius):
				reasons.append("location_far")
				return {
					"ok": false,
					"reasons": reasons,
					"distance_m": dist,
					"message": "You're %s from the unlock location." % format_distance_away(dist),
				}
	if bool(item.get("has_password", false)) or bool(item.get("has_magic_password", false)):
		if not bool(item.get("password_ok", false)):
			reasons.append("password")
	return {"ok": reasons.is_empty(), "reasons": reasons}
