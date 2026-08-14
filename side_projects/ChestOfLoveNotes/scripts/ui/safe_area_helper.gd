extends RefCounted
class_name SafeAreaHelper
## Converts DisplayServer safe-area into MarginContainer theme margins
## in viewport/logical coordinates.


static func apply_to_margin(margin: MarginContainer, extra_h: int = 22, extra_top: int = 16, extra_bottom: int = 16) -> void:
	if margin == null:
		return
	var insets := display_insets_viewport()
	margin.add_theme_constant_override("margin_left", int(insets.x) + extra_h)
	margin.add_theme_constant_override("margin_top", int(insets.y) + extra_top)
	margin.add_theme_constant_override("margin_right", int(insets.z) + extra_h)
	margin.add_theme_constant_override("margin_bottom", int(insets.w) + extra_bottom)


static func display_insets_viewport() -> Vector4:
	## Returns left, top, right, bottom insets in viewport coordinates.
	var vp := Vector2.ZERO
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		vp = (tree as SceneTree).root.get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1080, 2400)

	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return Vector4(0, 0, 0, 0)

	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win_pos: Vector2i = DisplayServer.window_get_position()
	var left := maxi(0, safe.position.x - win_pos.x)
	var top := maxi(0, safe.position.y - win_pos.y)
	var right := maxi(0, (win_pos.x + int(win_size.x)) - (safe.position.x + safe.size.x))
	var bottom := maxi(0, (win_pos.y + int(win_size.y)) - (safe.position.y + safe.size.y))

	var sx := vp.x / win_size.x
	var sy := vp.y / win_size.y
	return Vector4(left * sx, top * sy, right * sx, bottom * sy)


static func keyboard_height_viewport() -> float:
	# Headless / desktop display servers may not implement virtual keyboard.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var kb := float(DisplayServer.virtual_keyboard_get_height())
	if kb <= 0.0:
		return 0.0
	var vp := Vector2.ZERO
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		vp = (tree as SceneTree).root.get_visible_rect().size
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.y <= 0.0 or vp.y <= 0.0:
		return kb
	return kb * (vp.y / win_size.y)
