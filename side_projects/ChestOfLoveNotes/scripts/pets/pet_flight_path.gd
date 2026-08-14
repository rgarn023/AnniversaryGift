extends RefCounted
class_name PetFlightPath
## Soft curved flight path (quadratic / cubic Bezier) for future TAKEOFF→FLY→LAND.
## Production visuals stay disabled until PET_FLIGHT_VISUALS_READY.

var start: Vector2 = Vector2.ZERO
var control_a: Vector2 = Vector2.ZERO
var control_b: Vector2 = Vector2.ZERO
var destination: Vector2 = Vector2.ZERO
var use_cubic: bool = false
var progress: float = 0.0 ## 0..1
var landing_point: Vector2 = Vector2.ZERO
var last_safe_ground: Vector2 = Vector2.ZERO


func reset() -> void:
	start = Vector2.ZERO
	control_a = Vector2.ZERO
	control_b = Vector2.ZERO
	destination = Vector2.ZERO
	use_cubic = false
	progress = 0.0
	landing_point = Vector2.ZERO
	last_safe_ground = Vector2.ZERO


func configure_quadratic(p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	start = p0
	control_a = p1
	control_b = p1
	destination = p2
	use_cubic = false
	progress = 0.0
	landing_point = p2


func configure_cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> void:
	start = p0
	control_a = p1
	control_b = p2
	destination = p3
	use_cubic = true
	progress = 0.0
	landing_point = p3


func sample(t: float) -> Vector2:
	var u := clampf(t, 0.0, 1.0)
	if use_cubic:
		var omt := 1.0 - u
		return (
			omt * omt * omt * start
			+ 3.0 * omt * omt * u * control_a
			+ 3.0 * omt * u * u * control_b
			+ u * u * u * destination
		)
	## Quadratic: start → control_a → destination
	var o := 1.0 - u
	return o * o * start + 2.0 * o * u * control_a + u * u * destination


func current_point() -> Vector2:
	return sample(progress)


func advance(delta: float, duration_sec: float) -> float:
	if duration_sec <= 0.001:
		progress = 1.0
		return progress
	progress = clampf(progress + delta / duration_sec, 0.0, 1.0)
	return progress


func is_complete() -> bool:
	return progress >= 0.999


func to_debug_dict() -> Dictionary:
	return {
		"start": start,
		"control_a": control_a,
		"control_b": control_b,
		"destination": destination,
		"use_cubic": use_cubic,
		"progress": progress,
		"landing_point": landing_point,
		"last_safe_ground": last_safe_ground,
		"current": current_point(),
	}
