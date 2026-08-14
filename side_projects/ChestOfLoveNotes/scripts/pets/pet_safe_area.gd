extends RefCounted
class_name PetSafeArea
## Derived pet roam / exclusion geometry for the CHEST environment.
## Adapts to viewport size; fractions from docs/PET_SAFE_AREA.md.
##
## Chest is a SOLID obstacle for normal ROAM: destination, path segment, and
## per-frame steps must not enter the pet-body-expanded exclusion rect.

var viewport_size: Vector2 = Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
## Chest host rect in the same local space as PetActor (PetRuntimeRoot).
var chest_rect: Rect2 = Rect2()
var edge_margin: float = PetRuntimeConfig.EDGE_MARGIN_PX
var chest_exclusion_margin: float = PetRuntimeConfig.CHEST_EXCLUSION_MARGIN_PX
var pet_body_half: Vector2 = Vector2.ZERO
var pet_body_pad: float = PetRuntimeConfig.PET_CHEST_BODY_PAD_PX


func configure(vp_size: Vector2, chest_local_rect: Rect2) -> void:
	viewport_size = vp_size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
	chest_rect = chest_local_rect
	var scale := scale_factor()
	edge_margin = PetRuntimeConfig.EDGE_MARGIN_PX * scale
	chest_exclusion_margin = PetRuntimeConfig.CHEST_EXCLUSION_MARGIN_PX * scale
	pet_body_pad = PetRuntimeConfig.PET_CHEST_BODY_PAD_PX * scale
	## Minkowski half-extents from visible parrot body (design → screen).
	var visual := PetRuntimeConfig.PET_RUNTIME_VISUAL_SCALE * scale
	pet_body_half = Vector2(
		PetRuntimeConfig.TAP_HITBOX_BODY_W_PX * 0.5 * visual + pet_body_pad,
		PetRuntimeConfig.TAP_HITBOX_BODY_H_PX * 0.5 * visual + pet_body_pad
	)


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


func chest_runtime_rect() -> Rect2:
	## Actual chest host/runtime bounds (no pet inflate). Falls back to design geometry.
	if chest_rect.size.x > 0.0 and chest_rect.size.y > 0.0:
		return chest_rect
	var cw := 252.0 * (viewport_size.x / PetRuntimeConfig.DESIGN_WIDTH)
	var ch := 326.0 * scale_factor()
	var foot_y := viewport_size.y * PetRuntimeConfig.CHEST_GROUND_Y
	var foot_frac := LoveNotesChest.CHEST_FOOT_Y_FRAC
	var top := foot_y - ch * foot_frac
	var left := (viewport_size.x - cw) * 0.5
	chest_rect = Rect2(left, top, cw, ch)
	return chest_rect


func chest_exclusion_rect() -> Rect2:
	## Expanded obstacle: raw chest + safety margin + half pet visual body (Minkowski).
	var base := chest_runtime_rect()
	var mx := chest_exclusion_margin + pet_body_half.x
	var my := chest_exclusion_margin + pet_body_half.y
	return Rect2(
		base.position.x - mx,
		base.position.y - my,
		base.size.x + mx * 2.0,
		base.size.y + my * 2.0
	)


func pet_effective_collision_size() -> Vector2:
	## Full effective body size used for expansion (2 * half).
	return pet_body_half * 2.0


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


func segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	## True if the open/closed segment a→b intersects the filled rectangle.
	if rect.has_point(a) or rect.has_point(b):
		return true
	## Empty / degenerate segment.
	if a.distance_squared_to(b) < 0.0001:
		return rect.has_point(a)
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for i in range(4):
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


func segment_intersects_chest_exclusion(a: Vector2, b: Vector2) -> bool:
	return segment_intersects_rect(a, b, chest_exclusion_rect())


func is_roam_path_clear(from_pos: Vector2, to_pos: Vector2) -> bool:
	## Both endpoints valid AND straight segment does not cross expanded chest.
	if not is_valid_roam_point(to_pos):
		return false
	if segment_intersects_chest_exclusion(from_pos, to_pos):
		return false
	return true


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
		## Push horizontally away from chest center onto open sand.
		var ex := chest_exclusion_rect()
		var mid := ex.position.x + ex.size.x * 0.5
		if p.x <= mid:
			p.x = ex.position.x - 1.0
		else:
			p.x = ex.end.x + 1.0
		p.x = clampf(p.x, roam_x_min(), roam_x_max())
		p.y = clampf(p.y, sand_y_min(), sand_y_max())
		## If still overlapping (narrow viewport), try vertical nudge below exclusion.
		if is_in_chest_exclusion(p):
			p.y = minf(ex.end.y + 1.0, sand_y_max())
			p.y = clampf(p.y, sand_y_min(), sand_y_max())
		if is_in_chest_exclusion(p):
			## Last resort: park at nearest side mid-sand.
			p = Vector2(
				ex.position.x - 1.0 if p.x <= mid else ex.end.x + 1.0,
				clampf((sand_y_min() + sand_y_max()) * 0.5, sand_y_min(), sand_y_max())
			)
			p.x = clampf(p.x, roam_x_min(), roam_x_max())
	return p


func ensure_safe_position(point: Vector2, rng: RandomNumberGenerator = null) -> Vector2:
	## Spawn / resume / fallback — never leave the pet overlapping the chest body.
	if is_valid_roam_point(point):
		return point
	var fixed := clamp_to_roam(point)
	if is_valid_roam_point(fixed):
		return fixed
	if rng != null:
		return random_roam_target(rng)
	## Deterministic left-of-chest sand fallback.
	return default_spawn_position(null)


func random_roam_target(rng: RandomNumberGenerator, from_pos: Variant = null) -> Vector2:
	## Rejection sample; optionally reject targets whose segment from from_pos crosses chest.
	var origin: Variant = from_pos
	for _i in range(64):
		var p := Vector2(
			rng.randf_range(roam_x_min(), roam_x_max()),
			rng.randf_range(sand_y_min(), sand_y_max())
		)
		if not is_valid_roam_point(p):
			continue
		if origin != null and typeof(origin) == TYPE_VECTOR2:
			if not is_roam_path_clear(origin as Vector2, p):
				continue
		return p
	## Fallback: guaranteed same-side sand corridor (never inside chest).
	return _fallback_side_roam_target(rng, origin)


func _fallback_side_roam_target(rng: RandomNumberGenerator, origin: Variant = null) -> Vector2:
	var ex := chest_exclusion_rect()
	var mid := ex.get_center().x
	var prefer_left := true
	if origin != null and typeof(origin) == TYPE_VECTOR2:
		prefer_left = (origin as Vector2).x <= mid
	var y := rng.randf_range(sand_y_min(), sand_y_max())
	var candidates: Array[Vector2] = []
	## Slim corridors left/right of expanded exclusion.
	var left_x := minf(ex.position.x - 2.0, roam_x_max())
	var right_x := maxf(ex.end.x + 2.0, roam_x_min())
	left_x = clampf(left_x, roam_x_min(), roam_x_max())
	right_x = clampf(right_x, roam_x_min(), roam_x_max())
	candidates.append(Vector2(left_x, y))
	candidates.append(Vector2(right_x, y))
	## Also try corridor midpoints.
	if ex.position.x - roam_x_min() > 4.0:
		candidates.append(Vector2((roam_x_min() + ex.position.x) * 0.5, y))
	if roam_x_max() - ex.end.x > 4.0:
		candidates.append(Vector2((ex.end.x + roam_x_max()) * 0.5, y))
	## Prefer requested side first.
	if not prefer_left:
		candidates.reverse()
	for c in candidates:
		var p := clamp_to_roam(c)
		if not is_valid_roam_point(p):
			continue
		if origin != null and typeof(origin) == TYPE_VECTOR2:
			if not is_roam_path_clear(origin as Vector2, p):
				continue
		return p
	## Absolute last resort: park just outside exclusion on preferred side.
	var edge_x := ex.position.x - 1.0 if prefer_left else ex.end.x + 1.0
	edge_x = clampf(edge_x, roam_x_min(), roam_x_max())
	var last := Vector2(edge_x, clampf(y, sand_y_min(), sand_y_max()))
	if is_in_chest_exclusion(last):
		## Nudge further out.
		last.x = roam_x_min() if prefer_left else roam_x_max()
	return last


func chest_interaction_points() -> Array[Vector2]:
	## Safe beside-chest points — outside expanded exclusion, not over reward cavity.
	var ex := chest_exclusion_rect()
	var y := clampf(
		ex.position.y + ex.size.y * 0.72,
		sand_y_min(),
		sand_y_max()
	)
	## Keep a small visual gap outside the expanded obstacle for nuzzle/rub.
	var gap := 14.0 * scale_factor()
	var left := Vector2(ex.position.x - gap, y)
	var right := Vector2(ex.end.x + gap, y)
	left.x = clampf(left.x, roam_x_min(), roam_x_max())
	right.x = clampf(right.x, roam_x_min(), roam_x_max())
	var out: Array[Vector2] = []
	if not is_in_chest_exclusion(left) and not is_in_ocean(left) and not is_in_ui_exclusion(left):
		out.append(left)
	if not is_in_chest_exclusion(right) and not is_in_ocean(right) and not is_in_ui_exclusion(right):
		out.append(right)
	if out.is_empty():
		## Last resort: clamp sides — still must sit outside exclusion if possible.
		var l2 := clamp_to_roam(left)
		var r2 := clamp_to_roam(right)
		if not is_in_chest_exclusion(l2):
			out.append(l2)
		if not is_in_chest_exclusion(r2):
			out.append(r2)
		if out.is_empty():
			out.append(l2)
			out.append(r2)
	return out


func random_chest_interaction_target(rng: RandomNumberGenerator) -> Vector2:
	var pts := chest_interaction_points()
	if pts.is_empty():
		return clamp_to_roam(Vector2(viewport_size.x * 0.5, sand_y_max()))
	return pts[rng.randi_range(0, pts.size() - 1)]


func default_spawn_position(rng: RandomNumberGenerator = null) -> Vector2:
	## Start on open sand left of chest — never inside expanded exclusion.
	var ex := chest_exclusion_rect()
	var p := Vector2(
		ex.position.x - 36.0 * scale_factor(),
		sand_y_min() + (sand_y_max() - sand_y_min()) * 0.55
	)
	p = ensure_safe_position(p, rng)
	return p


func candidate_step_blocked(from_pos: Vector2, candidate: Vector2) -> bool:
	## Per-frame / high-delta guard: do not enter or tunnel through chest.
	if is_in_chest_exclusion(candidate):
		return true
	if segment_intersects_chest_exclusion(from_pos, candidate):
		return true
	return false


func to_debug_dict() -> Dictionary:
	return {
		"viewport": viewport_size,
		"sand_y_min": sand_y_min(),
		"sand_y_max": sand_y_max(),
		"roam_x_min": roam_x_min(),
		"roam_x_max": roam_x_max(),
		"chest_runtime_rect": chest_runtime_rect(),
		"chest_exclusion": chest_exclusion_rect(),
		"pet_body_half": pet_body_half,
		"pet_effective_collision_size": pet_effective_collision_size(),
		"edge_margin": edge_margin,
		"interaction_points": chest_interaction_points(),
	}
