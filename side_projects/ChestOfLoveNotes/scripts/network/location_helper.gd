extends RefCounted
class_name LocationHelper
## Battery-conscious device location for Location Lock.
## Permission is requested only when Compose/Open explicitly needs a GPS fix.
## Place search does NOT use this helper.

const PLUGIN_NAME := "ChestLocation"
const DEFAULT_RADIUS_M := 500
const MIN_RADIUS_M := 1
const MAX_RADIUS_M := 10000
const SMALL_RADIUS_WARN_M := 50
## Optional quick shortcuts only — not the sole radius control.
const RADIUS_OPTIONS: Array[int] = [25, 100, 250, 500, 1000]
const PERM_FINE := "android.permission.ACCESS_FINE_LOCATION"
const PERM_COARSE := "android.permission.ACCESS_COARSE_LOCATION"
const MAX_ACCEPTABLE_ACCURACY_M := 200.0

## Desktop / headless mock (never used to falsely unlock online scrolls).
const MOCK_LAT := 33.4484
const MOCK_LNG := -112.0740


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
	if Engine.has_singleton(PLUGIN_NAME):
		return Engine.get_singleton(PLUGIN_NAME)
	return null


static func permission_status() -> String:
	if OS.get_name() != "Android":
		return "unsupported"
	var p = _plugin()
	if p != null and p.has_method("has_location_permission") and bool(p.has_location_permission()):
		return "granted"
	var granted := OS.get_granted_permissions()
	if granted.has(PERM_FINE) or granted.has(PERM_COARSE):
		return "granted"
	return "denied"


static func request_permission_if_needed() -> String:
	## Never call during app launch — only from Location Lock configure / open.
	if OS.get_name() != "Android":
		return "unsupported"
	if permission_status() == "granted":
		return "granted"
	OS.request_permissions()
	return permission_status()


static func get_current_fix(require_accuracy: bool = true) -> Dictionary:
	if OS.get_name() != "Android":
		return {
			"ok": true,
			"lat": MOCK_LAT,
			"lng": MOCK_LNG,
			"accuracy_m": 25.0,
			"mock": true,
		}
	if permission_status() != "granted":
		return {
			"ok": false,
			"error": "Location access is needed only to verify whether you're near the unlock location.",
			"denied": true,
		}
	var p = _plugin()
	if p == null or not p.has_method("get_last_known_location"):
		return {
			"ok": false,
			"error": "Turn on Location Services to verify this scroll.",
			"unavailable": true,
		}
	var raw := str(p.get_last_known_location())
	var parts := raw.split("|")
	if parts.is_empty():
		return {"ok": false, "error": "We couldn't verify your location. Try again.", "unavailable": true}
	if parts[0] == "ok" and parts.size() >= 4:
		var accuracy := float(parts[3])
		if require_accuracy and accuracy > 0.0 and accuracy > MAX_ACCEPTABLE_ACCURACY_M:
			return {
				"ok": false,
				"error": "Location accuracy is too low right now. Try again outdoors.",
				"inaccurate": true,
				"accuracy_m": accuracy,
			}
		return {
			"ok": true,
			"lat": float(parts[1]),
			"lng": float(parts[2]),
			"accuracy_m": accuracy,
			"mock": false,
		}
	var code := str(parts[2]) if parts.size() >= 3 else "unavailable"
	var msg := str(parts[1]) if parts.size() >= 2 else "We couldn't verify your location. Try again."
	if code == "disabled":
		msg = "Turn on Location Services to verify this scroll."
	elif code == "denied":
		msg = "Location access is needed only to verify whether you're near the unlock location."
	return {
		"ok": false,
		"error": msg,
		"denied": code == "denied",
		"disabled": code == "disabled",
		"unavailable": code == "unavailable",
	}


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
			## Do not unlock when reported GPS uncertainty is worse than the lock radius.
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
	## Magic Password is verified at open time (never OR'd with location/time).
	if bool(item.get("has_password", false)) or bool(item.get("has_magic_password", false)):
		if not bool(item.get("password_ok", false)):
			reasons.append("password")
	return {"ok": reasons.is_empty(), "reasons": reasons}
