class_name GestureZoomController
extends RefCounted

## Pinch-to-zoom helper that cooperates with vertical scrolling.

signal zoom_changed(scale: float)

var min_scale: float = 0.8
var max_scale: float = 2.2
var current_scale: float = 1.0
var _pinching: bool = false
var _last_distance: float = 0.0
var _touch_positions: Dictionary = {}


func set_scale(value: float) -> void:
	var clamped: float = clampf(value, min_scale, max_scale)
	if not is_equal_approx(clamped, current_scale):
		current_scale = clamped
		zoom_changed.emit(current_scale)


func adjust(factor: float) -> void:
	set_scale(current_scale * factor)


func reset(default_scale: float = 1.0) -> void:
	set_scale(default_scale)


func is_pinching() -> bool:
	return _pinching


func handle_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_positions[touch.index] = touch.position
		else:
			_touch_positions.erase(touch.index)
			if _touch_positions.size() < 2:
				_pinching = false
				_last_distance = 0.0
		return false

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touch_positions[drag.index] = drag.position
		if _touch_positions.size() >= 2:
			var keys: Array = _touch_positions.keys()
			keys.sort()
			var a: Vector2 = _touch_positions[keys[0]]
			var b: Vector2 = _touch_positions[keys[1]]
			var dist: float = a.distance_to(b)
			if not _pinching:
				_pinching = true
				_last_distance = dist
				return true
			if _last_distance > 0.0:
				var ratio: float = dist / _last_distance
				# Soften extreme jumps.
				ratio = clampf(ratio, 0.92, 1.08)
				set_scale(current_scale * ratio)
			_last_distance = dist
			return true
	return false
