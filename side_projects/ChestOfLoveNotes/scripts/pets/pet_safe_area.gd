extends RefCounted
class_name PetSafeArea
## Derived pet roam / exclusion geometry for the CHEST environment.
## Adapts to viewport size; fractions from docs/PET_SAFE_AREA.md.

var viewport_size: Vector2 = Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
## Chest host rect in the same local space as PetActor (PetRuntimeRoot).
var chest_rect: Rect2 = Rect2()
var edge_margin: float = PetRuntimeConfig.EDGE_MARGIN_PX
var chest_exclusion_margin: float = PetRuntimeConfig.CHEST_EXCLUSION_MARGIN_PX


func configure(vp_size: Vector2, chest_local_rect: Rect2) -> void:
	viewport_size = vp_size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
	chest_rect = chest_local_rect
	var scale := scale_factor()
	edge_margin = PetRuntimeConfig.EDGE_MARGIN_PX * scale
	chest_exclusion_margin = PetRuntimeConfig.CHEST_EXCLUSION_MARGIN_PX * scale


func scale_factor() -> float:
	## Prefer height scale; pets move on a tall phone canvas.
	return maxf(0.5, viewport_size.y / PetRuntimeConfig.DESIGN_HEIGHT)


func move_speed() -> float:
	return PetRuntimeConfig.MOVE_SPEED_PX_PER_SEC * scale_factor()


func sand_y_min() -> float:
	var water := viewport_size.y * PetRuntimeConfig.WATER_BOTTOM_FRAC + 8.0 * scale_factor()
	var ui_top := viewport_size.y * PetRuntimeConfig.UI_TOP_EXCLUDE_FRAC
	return maxf(water, ui_top)


func sand_y_max() -> float:
	## Above bottom nav; leave a little room above chest foot for normal roam.
	var nav_top := viewport_size.y * (1.0 - PetRuntimeConfig.UI_BOTTOM_NAV_FRAC) - edge_margin
	var chest_foot := viewport_size.y * PetRuntimeConfig.CHEST_GROUND_Y
	## Normal roam stays at/above foot line minus a small pad so paws stay on sand.
	var foot_cap := chest_foot - 6.0 * scale_factor()
	return minf(nav_top, foot_cap)


func roam_x_min() -> float:
	return edge_margin


func roam_x_max() -> float:
	return viewport_size.x - edge_margin


func chest_exclusion_rect() -> Rect2:
	if chest_rect.size.x <= 0.0 or chest_rect.size.y <= 0.0:
		## Fallback centered chest using design fractions.
		var cw := 252.0 * (viewport_size.x / PetRuntimeConfig.DESIGN_WIDTH)
		var ch := 326.0 * scale_factor()
		var foot_y := viewport_size.y * PetRuntimeConfig.CHEST_GROUND_Y
		var foot_frac := LoveNotesChest.CHEST_FOOT_Y_FRAC
		var top := foot_y - ch * foot_frac
		var left := (viewport_size.x - cw) * 0.5
		chest_rect = Rect2(left, top, cw, ch)
	var m := chest_exclusion_margin
	return Rect2(
		chest_rect.position.x - m,
		chest_rect.position.y - m,
		chest_rect.size.x + m * 2.0,
		chest_rect.size.y + m * 2.0
	)


func is_in_ocean(point: Vector2) -> bool:
	return point.y < viewport_size.y * PetRuntimeConfig.WATER_BOTTOM_FRAC


func is_in_ui_exclusion(point: Vector2) -> bool:
	if point.y < viewport_size.y * PetRuntimeConfig.UI_TOP_EXCLUDE_FRAC:
		return true
	if point.y > viewport_size.y * (1.0 - PetRuntimeConfig.UI_BOTTOM_NAV_FRAC):
		return true
	return false


func is_in_chest_exclusion(point: Vector2) -> bool:
	return chest_exclusion_rect().has_point(point)


func is_valid_roam_point(point: Vector2) -> bool:
	if point.x < roam_x_min() or point.x > roam_x_max():
		return false
	if point.y < sand_y_min() or point.y > sand_y_max():
		return false
	if is_in_ocean(point):
		return false
	if is_in_ui_exclusion(point):
		return false
	if is_in_chest_exclusion(point):
		return false
	return true


func clamp_to_roam(point: Vector2) -> Vector2:
	var p := point
	p.x = clampf(p.x, roam_x_min(), roam_x_max())
	p.y = clampf(p.y, sand_y_min(), sand_y_max())
	if is_in_chest_exclusion(p):
		## Push horizontally away from chest center.
		var ex := chest_exclusion_rect()
		var mid := ex.position.x + ex.size.x * 0.5
		if p.x <= mid:
			p.x = ex.position.x - 1.0
		else:
			p.x = ex.end.x + 1.0
		p.x = clampf(p.x, roam_x_min(), roam_x_max())
		p.y = clampf(p.y, sand_y_min(), sand_y_max())
	return p


func random_roam_target(rng: RandomNumberGenerator) -> Vector2:
	## Rejection sample; fall back to clamped point if needed.
	for _i in range(48):
		var p := Vector2(
			rng.randf_range(roam_x_min(), roam_x_max()),
			rng.randf_range(sand_y_min(), sand_y_max())
		)
		if is_valid_roam_point(p):
			return p
	return clamp_to_roam(Vector2(
		rng.randf_range(roam_x_min(), roam_x_max()),
		rng.randf_range(sand_y_min(), sand_y_max())
	))


func chest_interaction_points() -> Array[Vector2]:
	## Safe beside-chest points — not over the reward/center cavity.
	var ex := chest_exclusion_rect()
	var y := clampf(
		ex.position.y + ex.size.y * 0.72,
		sand_y_min(),
		sand_y_max()
	)
	var left := Vector2(ex.position.x - 18.0 * scale_factor(), y)
	var right := Vector2(ex.end.x + 18.0 * scale_factor(), y)
	left.x = clampf(left.x, roam_x_min(), roam_x_max())
	right.x = clampf(right.x, roam_x_min(), roam_x_max())
	## Prefer points outside the exclusion core.
	var out: Array[Vector2] = []
	if not is_in_chest_exclusion(left) and not is_in_ocean(left) and not is_in_ui_exclusion(left):
		out.append(left)
	if not is_in_chest_exclusion(right) and not is_in_ocean(right) and not is_in_ui_exclusion(right):
		out.append(right)
	if out.is_empty():
		## Last resort: clamped sides even if slightly near exclusion edge.
		out.append(clamp_to_roam(left))
		out.append(clamp_to_roam(right))
	return out


func random_chest_interaction_target(rng: RandomNumberGenerator) -> Vector2:
	var pts := chest_interaction_points()
	if pts.is_empty():
		return clamp_to_roam(Vector2(viewport_size.x * 0.5, sand_y_max()))
	return pts[rng.randi_range(0, pts.size() - 1)]


func default_spawn_position(rng: RandomNumberGenerator = null) -> Vector2:
	## Start on open sand left of chest.
	var ex := chest_exclusion_rect()
	var p := Vector2(ex.position.x - 36.0 * scale_factor(), sand_y_min() + (sand_y_max() - sand_y_min()) * 0.55)
	p = clamp_to_roam(p)
	if rng != null and not is_valid_roam_point(p):
		return random_roam_target(rng)
	return p


func to_debug_dict() -> Dictionary:
	return {
		"viewport": viewport_size,
		"sand_y_min": sand_y_min(),
		"sand_y_max": sand_y_max(),
		"roam_x_min": roam_x_min(),
		"roam_x_max": roam_x_max(),
		"chest_exclusion": chest_exclusion_rect(),
		"edge_margin": edge_margin,
		"interaction_points": chest_interaction_points(),
	}
