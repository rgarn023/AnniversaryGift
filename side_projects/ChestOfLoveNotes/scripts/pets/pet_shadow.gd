extends Node2D
class_name PetShadowDraw
## Soft runtime ellipse under the pet. No baked shadow texture.
## Drawn in PetVisual local space (canvas px); PetVisual scale applies.

## Approximate foot ellipse in 128×128 canvas space.
var radius_x: float = 26.0
var radius_y: float = 9.0
var base_alpha: float = 0.30
## 0 = grounded, 1 = peak hop lift (subtle alpha/scale response only).
var hop_lift: float = 0.0


func _draw() -> void:
	var lift := clampf(hop_lift, 0.0, 1.0)
	var a := base_alpha * (1.0 - lift * 0.22)
	var rx := radius_x * (1.0 + lift * 0.06)
	var ry := radius_y * (1.0 - lift * 0.12)
	## Layered translucent ellipses — soft falloff, no hard outline.
	var layers := [
		[1.00, a * 0.22],
		[0.78, a * 0.34],
		[0.55, a * 0.42],
		[0.32, a * 0.28],
	]
	for layer in layers:
		var scale_mul: float = float(layer[0])
		var alpha: float = float(layer[1])
		## Native CanvasItem.draw_ellipse(center, major, minor, color, filled, width, antialiased)
		draw_ellipse(Vector2.ZERO, rx * scale_mul, ry * scale_mul, Color(0.05, 0.04, 0.03, alpha), true, -1.0, true)


func set_hop_lift(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if absf(next - hop_lift) < 0.01:
		return
	hop_lift = next
	queue_redraw()
