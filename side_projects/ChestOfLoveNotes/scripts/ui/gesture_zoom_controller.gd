class_name GestureZoomController
extends RefCounted

## Pinch / magnify / wheel zoom helper that cooperates with vertical scrolling.

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
	_pinching = false
	_last_distance = 0.0
	_touch_positions.clear()
	current_scale = clampf(default_scale, min_scale, max_scale)
	zoom_changed.emit(current_scale)


func is_pinching() -> bool:
	return _pinching


func handle_input(event: InputEvent) -> bool:
	# Desktop / emulator: ctrl + mouse wheel
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.ctrl_pressed or mb.meta_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				adjust(1.08)
				return true
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				adjust(0.92)
				return true

	# Some Android devices emit magnify gestures
	if event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		# factor is typically near 1.0
		var factor: float = mag.factor
		if factor > 0.0:
			set_scale(current_scale * clampf(factor, 0.85, 1.15))
			return true

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_positions[touch.index] = touch.position
		else:
			_touch_positions.erase(touch.index)
			if _touch_positions.size() < 2:
				_pinching = false
				_last_distance = 0.0
		# Do not consume single taps; only multi-touch pinches.
		return _touch_positions.size() >= 2

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touch_positions[drag.index] = drag.position
		if _touch_positions.size() >= 2:
			var keys: Array = _touch_positions.keys()
			keys.sort()
			var a: Vector2 = _touch_positions[keys[0]]
			var b: Vector2 = _touch_positions[keys[1]]
			var dist: float = a.distance_to(b)
			if dist < 8.0:
				return true
			if not _pinching:
				_pinching = true
				_last_distance = dist
				return true
			if _last_distance > 0.0:
				var ratio: float = dist / _last_distance
				ratio = clampf(ratio, 0.90, 1.10)
				set_scale(current_scale * ratio)
			_last_distance = dist
			return true
	return false
