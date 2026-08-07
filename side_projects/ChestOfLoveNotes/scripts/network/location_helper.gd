extends RefCounted
class_name LocationHelper
## Battery-conscious location access for Location Lock.
## Permission is requested only when Compose/Open explicitly needs a fix.

const PLUGIN_NAME := "ChestLocation"
const DEFAULT_RADIUS_M := 500
const PERM_FINE := "android.permission.ACCESS_FINE_LOCATION"
const PERM_COARSE := "android.permission.ACCESS_COARSE_LOCATION"

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
	return r * 2.0 * atan2(sqrt(a), sqrt(maxi(0.0, 1.0 - a)))


static func within_radius(lat: float, lng: float, target_lat: float, target_lng: float, radius_m: int) -> bool:
	if radius_m <= 0:
		return false
	return haversine_m(lat, lng, target_lat, target_lng) <= float(radius_m)


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


static func get_current_fix() -> Dictionary:
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
			"error": "Location permission is required for Location Lock.",
			"denied": true,
		}
	var p = _plugin()
	if p == null or not p.has_method("get_last_known_location"):
		return {
			"ok": false,
			"error": "Location services are unavailable on this device.",
			"unavailable": true,
		}
	var raw := str(p.get_last_known_location())
	var parts := raw.split("|")
	if parts.is_empty():
		return {"ok": false, "error": "Location is temporarily unavailable.", "unavailable": true}
	if parts[0] == "ok" and parts.size() >= 4:
		return {
			"ok": true,
			"lat": float(parts[1]),
			"lng": float(parts[2]),
			"accuracy_m": float(parts[3]),
			"mock": false,
		}
	var code := str(parts[2]) if parts.size() >= 3 else "unavailable"
	var msg := str(parts[1]) if parts.size() >= 2 else "Location is temporarily unavailable."
	return {
		"ok": false,
		"error": msg,
		"denied": code == "denied",
		"disabled": code == "disabled",
		"unavailable": code == "unavailable",
	}


static func format_lock_summary(location_name: String, has_schedule: bool, schedule_label: String) -> String:
	var place := location_name.strip_edges()
	if place.is_empty():
		place = "a set place"
	if has_schedule:
		return "Near %s · %s" % [place, schedule_label]
	return "Near %s" % place
