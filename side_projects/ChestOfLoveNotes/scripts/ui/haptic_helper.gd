class_name HapticHelper
extends RefCounted

## Light Android haptic feedback wrapper. Safe no-op elsewhere.


static func light_tap() -> void:
	_vibrate(12)


static func lock_release() -> void:
	_vibrate(24)


static func scroll_land() -> void:
	_vibrate(18)


static func _vibrate(duration_ms: int) -> void:
	if not OS.has_feature("android"):
		return
	# Godot Input.vibrate_handheld is available on mobile exports.
	Input.vibrate_handheld(duration_ms)
