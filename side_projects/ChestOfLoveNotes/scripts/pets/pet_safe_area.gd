extends RefCounted
class_name PetSafeArea
## Derived pet roam / exclusion geometry for the CHEST environment.
## Adapts to viewport size; fractions from docs/PET_SAFE_AREA.md.
##
## Chest is a SOLID ground obstacle: destinations, path segments, and per-frame
## steps must not enter the expanded solid-body exclusion. Cross-screen travel
## uses upper-sand transit + left/right side detours (waypoint routing).

enum RoamRegion {
	LEFT,
	CENTER_LEFT,
	CENTER_RIGHT,
	RIGHT,
}

var viewport_size: Vector2 = Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
## Chest host rect in the same local space as PetActor (PetRuntimeRoot).
var chest_rect: Rect2 = Rect2()
var edge_margin: float = PetRuntimeConfig.EDGE_MARGIN_PX
var chest_exclusion_margin: float = PetRuntimeConfig.CHEST_EXCLUSION_MARGIN_PX
var pet_body_half: Vector2 = Vector2.ZERO
var pet_body_pad: float = PetRuntimeConfig.PET_CHEST_BODY_PAD_PX
var screen_edge_pad: float = PetRuntimeConfig.SCREEN_EDGE_PAD_PX
## Last plan telemetry (debug / tests — no production overlay).
var last_plan_debug: Dictionary = {}


func configure(vp_size: Vector2, chest_local_rect: Rect2) -> void:
	viewport_size = vp_size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
	chest_rect = chest_local_rect
	var scale := scale_factor()
	edge_margin = PetRuntimeConfig.EDGE_MARGIN_PX * scale
	screen_edge_pad = PetRuntimeConfig.SCREEN_EDGE_PAD_PX * scale
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


func pet_visual_extent_left() -> float:
	## Full visible body left of ground-anchor (canvas 40px × runtime scale).
	return PetRuntimeConfig.PET_VISUAL_EXTENT_LEFT_PX * PetRuntimeConfig.PET_RUNTIME_VISUAL_SCALE * scale_factor()


func pet_visual_extent_right() -> float:
	return PetRuntimeConfig.PET_VISUAL_EXTENT_RIGHT_PX * PetRuntimeConfig.PET_RUNTIME_VISUAL_SCALE * scale_factor()


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
	## Anchor min so leftmost visible pixels stay inside viewport + pad.
	return pet_visual_extent_left() + screen_edge_pad


func roam_x_max() -> float:
	## Anchor max so rightmost visible pixels stay inside viewport + pad.
	return viewport_size.x - pet_visual_extent_right() - screen_edge_pad


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


func chest_solid_rect() -> Rect2:
	## Opaque-ish chest body (not full transparent host). Seaward sand stays open.
	var host := chest_runtime_rect()
	var foot_y := host.position.y + host.size.y * LoveNotesChest.CHEST_FOOT_Y_FRAC
	var solid_h := minf(
		PetRuntimeConfig.CHEST_SOLID_HEIGHT_PX * scale_factor(),
		host.size.y * 0.55
	)
	var solid_w := host.size.x * PetRuntimeConfig.CHEST_SOLID_WIDTH_FRAC
	return Rect2(
		Vector2(host.get_center().x - solid_w * 0.5, foot_y - solid_h),
		Vector2(solid_w, solid_h)
	)


func chest_exclusion_rect() -> Rect2:
	## Expanded ground obstacle: solid chest + margin + pet body (lighter expand).
	var base := chest_solid_rect()
	var mx := chest_exclusion_margin + pet_body_half.x * PetRuntimeConfig.CHEST_EXCLUSION_HORIZONTAL_BODY_FACTOR
	var my := chest_exclusion_margin + pet_body_half.y * PetRuntimeConfig.CHEST_EXCLUSION_VERTICAL_BODY_FACTOR
	return Rect2(
		base.position.x - mx,
		base.position.y - my,
		base.size.x + mx * 2.0,
		base.size.y + my * 2.0
	)


func transit_y() -> float:
	## Midpoint of seaward sand corridor above the expanded chest obstacle.
	var ex := chest_exclusion_rect()
	var top_band := sand_y_min()
	var bottom_band := minf(ex.position.y - 4.0 * scale_factor(), sand_y_max())
	if bottom_band <= top_band + 2.0:
		## Degenerate: park just above exclusion if possible, else sand mid.
		return clampf(ex.position.y - 6.0 * scale_factor(), sand_y_min(), sand_y_max())
	return (top_band + bottom_band) * 0.5


func has_transit_corridor() -> bool:
	var ex := chest_exclusion_rect()
	return ex.position.y > sand_y_min() + 8.0 * scale_factor()


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


func path_segments_safe(from_pos: Vector2, waypoints: Array) -> bool:
	var prev := from_pos
	for w in waypoints:
		var p: Vector2 = w
		if not is_valid_roam_point(p):
			return false
		if segment_intersects_chest_exclusion(prev, p):
			return false
		prev = p
	return true


func is_valid_roam_point(point: Vector2) -> bool:
	## Epsilon so clamp_to_roam endpoints are accepted (float edges).
	const EPS := 0.05
	if point.x < roam_x_min() - EPS or point.x > roam_x_max() + EPS:
		return false
	if point.y < sand_y_min() - EPS or point.y > sand_y_max() + EPS:
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
		## Prefer seaward transit if still overlapping.
		if is_in_chest_exclusion(p):
			p.y = clampf(transit_y(), sand_y_min(), sand_y_max())
			p.x = clampf(p.x, roam_x_min(), roam_x_max())
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


func region_x_range(region: int) -> Vector2:
	## Inclusive-ish [min, max] X bands for balanced sampling.
	var mid := viewport_size.x * 0.5
	var ex := chest_exclusion_rect()
	var lo := roam_x_min()
	var hi := roam_x_max()
	## Side pockets beside obstacle; fall back to half-screen if pocket thin.
	var left_hi := maxf(lo + 4.0, minf(ex.position.x - 2.0, mid))
	var right_lo := minf(hi - 4.0, maxf(ex.end.x + 2.0, mid))
	match region:
		RoamRegion.LEFT:
			return Vector2(lo, left_hi)
		RoamRegion.CENTER_LEFT:
			return Vector2(lo, mid)
		RoamRegion.CENTER_RIGHT:
			return Vector2(mid, hi)
		RoamRegion.RIGHT:
			return Vector2(right_lo, hi)
		_:
			return Vector2(lo, hi)


func classify_region(point: Vector2) -> int:
	var mid := viewport_size.x * 0.5
	var ex := chest_exclusion_rect()
	if point.x < ex.position.x:
		return RoamRegion.LEFT
	if point.x > ex.end.x:
		return RoamRegion.RIGHT
	if point.x < mid:
		return RoamRegion.CENTER_LEFT
	return RoamRegion.CENTER_RIGHT


func plan_ground_path(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	## Deterministic waypoint routing around the chest obstacle.
	## Returns { ok, waypoints, route, length, segments_safe }.
	var dest := clamp_to_roam(to_pos)
	var empty: Array[Vector2] = []
	if not is_valid_roam_point(dest):
		last_plan_debug = {
			"ok": false,
			"route": "invalid_dest",
			"from": from_pos,
			"to": to_pos,
			"waypoints": empty,
		}
		return last_plan_debug
	if is_roam_path_clear(from_pos, dest):
		var direct: Array[Vector2] = [dest]
		last_plan_debug = {
			"ok": true,
			"route": "direct",
			"from": from_pos,
			"to": dest,
			"waypoints": direct,
			"length": from_pos.distance_to(dest),
			"segments_safe": true,
			"obstacle_intersects_direct": false,
		}
		return last_plan_debug

	var ex := chest_exclusion_rect()
	var gap := 10.0 * scale_factor()
	var ty := transit_y()
	var left_x := clampf(ex.position.x - gap, roam_x_min(), roam_x_max())
	var right_x := clampf(ex.end.x + gap, roam_x_min(), roam_x_max())

	## Candidate routes: upper transit, left side, right side (1–2 waypoints).
	var candidates: Array[Dictionary] = []

	## Upper transit (preferred for cross-screen).
	var u1 := clamp_to_roam(Vector2(from_pos.x, ty))
	var u2 := clamp_to_roam(Vector2(dest.x, ty))
	var u_mid := clamp_to_roam(Vector2(ex.get_center().x, ty))
	candidates.append({"route": "upper_two", "points": [u1, u2, dest]})
	candidates.append({"route": "upper_mid", "points": [u_mid, dest]})
	candidates.append({"route": "upper_dest_lane", "points": [u2, dest]})
	candidates.append({"route": "upper_start_lane", "points": [u1, dest]})

	## Left-side detour.
	var l1 := clamp_to_roam(Vector2(left_x, from_pos.y))
	var l2 := clamp_to_roam(Vector2(left_x, dest.y))
	var l_up := clamp_to_roam(Vector2(left_x, ty))
	candidates.append({"route": "left_side", "points": [l1, l2, dest]})
	candidates.append({"route": "left_upper", "points": [l_up, dest]})

	## Right-side detour.
	var r1 := clamp_to_roam(Vector2(right_x, from_pos.y))
	var r2 := clamp_to_roam(Vector2(right_x, dest.y))
	var r_up := clamp_to_roam(Vector2(right_x, ty))
	candidates.append({"route": "right_side", "points": [r1, r2, dest]})
	candidates.append({"route": "right_upper", "points": [r_up, dest]})

	## Combined: side → upper transit → side → dest (covers stubborn diagonals).
	candidates.append({"route": "left_then_upper", "points": [l_up, u2, dest]})
	candidates.append({"route": "right_then_upper", "points": [r_up, u2, dest]})

	var best: Dictionary = {}
	var best_len := INF
	for c in candidates:
		var pts: Array = c["points"]
		## Drop near-duplicate consecutive points.
		var cleaned: Array[Vector2] = []
		var prev := from_pos
		for raw in pts:
			var p: Vector2 = raw
			if prev.distance_to(p) < 1.5:
				continue
			cleaned.append(p)
			prev = p
		if cleaned.is_empty():
			continue
		## Ensure final dest present.
		if cleaned[cleaned.size() - 1].distance_to(dest) > 1.5:
			cleaned.append(dest)
		if not path_segments_safe(from_pos, cleaned):
			continue
		var length := 0.0
		prev = from_pos
		for p2 in cleaned:
			length += prev.distance_to(p2)
			prev = p2
		if length < best_len:
			best_len = length
			best = {
				"ok": true,
				"route": str(c["route"]),
				"from": from_pos,
				"to": dest,
				"waypoints": cleaned,
				"length": length,
				"segments_safe": true,
				"obstacle_intersects_direct": true,
				"left_x": left_x,
				"right_x": right_x,
				"transit_y": ty,
			}

	if best.is_empty():
		last_plan_debug = {
			"ok": false,
			"route": "none",
			"from": from_pos,
			"to": dest,
			"waypoints": empty,
			"obstacle_intersects_direct": true,
			"transit_y": ty,
		}
		return last_plan_debug
	last_plan_debug = best
	return best


func random_roam_target(rng: RandomNumberGenerator, from_pos: Variant = null) -> Vector2:
	## Region-balanced sampling. Saved/current position does NOT bias regions.
	## Cross-chest targets are accepted when a safe waypoint path exists.
	var origin: Variant = from_pos
	var origin_v := Vector2.ZERO
	var has_origin := origin != null and typeof(origin) == TYPE_VECTOR2
	if has_origin:
		origin_v = origin as Vector2

	var regions: Array[int] = [
		RoamRegion.LEFT,
		RoamRegion.CENTER_LEFT,
		RoamRegion.CENTER_RIGHT,
		RoamRegion.RIGHT,
	]
	## Occasionally force opposite half for cross-screen roam.
	var force_opposite := has_origin and rng.randf() < PetRuntimeConfig.ROAM_CROSS_SIDE_CHANCE
	if force_opposite:
		var mid := viewport_size.x * 0.5
		if origin_v.x <= mid:
			regions = [RoamRegion.RIGHT, RoamRegion.CENTER_RIGHT, RoamRegion.CENTER_LEFT, RoamRegion.LEFT]
		else:
			regions = [RoamRegion.LEFT, RoamRegion.CENTER_LEFT, RoamRegion.CENTER_RIGHT, RoamRegion.RIGHT]
	else:
		## Shuffle for balance (Fisher–Yates).
		for i in range(regions.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = regions[i]
			regions[i] = regions[j]
			regions[j] = tmp

	var min_travel := PetRuntimeConfig.ROAM_MIN_TRAVEL_PX * scale_factor()
	var roll := rng.randf()
	var prefer_short := roll < PetRuntimeConfig.ROAM_SHORT_CHANCE
	var prefer_medium := (not prefer_short) and roll < (PetRuntimeConfig.ROAM_SHORT_CHANCE + PetRuntimeConfig.ROAM_MEDIUM_CHANCE)

	for _attempt in range(96):
		var region: int = regions[_attempt % regions.size()]
		var xr := region_x_range(region)
		if xr.y <= xr.x + 1.0:
			continue
		var p := Vector2(
			rng.randf_range(xr.x, xr.y),
			rng.randf_range(sand_y_min(), sand_y_max())
		)
		p = clamp_to_roam(p)
		if not is_valid_roam_point(p):
			continue
		if has_origin:
			var dist := origin_v.distance_to(p)
			if prefer_short and dist > min_travel * 2.2:
				continue
			if prefer_medium and (dist < min_travel or dist > min_travel * 5.0):
				continue
			if (not prefer_short) and (not prefer_medium) and dist < min_travel * 1.5:
				## Long roam — require meaningful travel.
				if rng.randf() < 0.7:
					continue
			if dist < min_travel * 0.35:
				continue
			var plan := plan_ground_path(origin_v, p)
			if not bool(plan.get("ok", false)):
				continue
		return p

	## Fallback: same-side corridor (always path-clear to nearby sand).
	return _fallback_side_roam_target(rng, origin)


func _fallback_side_roam_target(rng: RandomNumberGenerator, origin: Variant = null) -> Vector2:
	var ex := chest_exclusion_rect()
	var mid := ex.get_center().x
	var prefer_left := true
	if origin != null and typeof(origin) == TYPE_VECTOR2:
		prefer_left = (origin as Vector2).x <= mid
	var y := rng.randf_range(sand_y_min(), sand_y_max())
	var candidates: Array[Vector2] = []
	## Slim corridors left/right of expanded exclusion + transit band.
	var left_x := minf(ex.position.x - 2.0, roam_x_max())
	var right_x := maxf(ex.end.x + 2.0, roam_x_min())
	left_x = clampf(left_x, roam_x_min(), roam_x_max())
	right_x = clampf(right_x, roam_x_min(), roam_x_max())
	candidates.append(Vector2(left_x, y))
	candidates.append(Vector2(right_x, y))
	candidates.append(Vector2(roam_x_min(), transit_y()))
	candidates.append(Vector2(roam_x_max(), transit_y()))
	if ex.position.x - roam_x_min() > 4.0:
		candidates.append(Vector2((roam_x_min() + ex.position.x) * 0.5, y))
	if roam_x_max() - ex.end.x > 4.0:
		candidates.append(Vector2((ex.end.x + roam_x_max()) * 0.5, y))
	if not prefer_left:
		candidates.reverse()
	for c in candidates:
		var p := clamp_to_roam(c)
		if not is_valid_roam_point(p):
			continue
		if origin != null and typeof(origin) == TYPE_VECTOR2:
			var plan := plan_ground_path(origin as Vector2, p)
			if not bool(plan.get("ok", false)):
				continue
		return p
	var edge_x := ex.position.x - 1.0 if prefer_left else ex.end.x + 1.0
	edge_x = clampf(edge_x, roam_x_min(), roam_x_max())
	var last := Vector2(edge_x, clampf(transit_y(), sand_y_min(), sand_y_max()))
	if is_in_chest_exclusion(last):
		last.x = roam_x_min() if prefer_left else roam_x_max()
		last.y = clampf(transit_y(), sand_y_min(), sand_y_max())
	return last


func chest_interaction_points() -> Array[Vector2]:
	## Safe beside-chest points — outside expanded exclusion, not over reward cavity.
	var ex := chest_exclusion_rect()
	## Prefer mid-side height; fall back toward transit if lower pocket is tight.
	var y_candidates: Array[float] = [
		clampf(ex.position.y + ex.size.y * 0.55, sand_y_min(), sand_y_max()),
		clampf(ex.position.y + ex.size.y * 0.72, sand_y_min(), sand_y_max()),
		clampf(transit_y(), sand_y_min(), sand_y_max()),
	]
	var gap := 14.0 * scale_factor()
	var out: Array[Vector2] = []
	for y in y_candidates:
		var left := Vector2(ex.position.x - gap, y)
		var right := Vector2(ex.end.x + gap, y)
		left.x = clampf(left.x, roam_x_min(), roam_x_max())
		right.x = clampf(right.x, roam_x_min(), roam_x_max())
		left = clamp_to_roam(left)
		right = clamp_to_roam(right)
		if is_valid_roam_point(left) and not out.has(left):
			## Keep only the leftmost-ish candidate once.
			var has_left := false
			for existing in out:
				if existing.x < viewport_size.x * 0.5:
					has_left = true
					break
			if not has_left:
				out.append(left)
		if is_valid_roam_point(right):
			var has_right := false
			for existing in out:
				if existing.x >= viewport_size.x * 0.5:
					has_right = true
					break
			if not has_right:
				out.append(right)
		if out.size() >= 2:
			break
	if out.is_empty():
		out.append(clamp_to_roam(Vector2(roam_x_min(), transit_y())))
		out.append(clamp_to_roam(Vector2(roam_x_max(), transit_y())))
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


## --- Flight zone (architecture; production gated) ---

func flight_zone_rect() -> Rect2:
	var pad_x := viewport_size.x * PetRuntimeConfig.FLIGHT_X_PAD_FRAC
	var y0 := viewport_size.y * PetRuntimeConfig.FLIGHT_Y_MIN_FRAC
	var y1 := viewport_size.y * PetRuntimeConfig.FLIGHT_Y_MAX_FRAC
	## Stay clear of title/message UI top band.
	y0 = maxf(y0, viewport_size.y * PetRuntimeConfig.UI_TOP_EXCLUDE_FRAC + 4.0)
	return Rect2(pad_x, y0, viewport_size.x - pad_x * 2.0, maxf(8.0, y1 - y0))


func is_in_flight_zone(point: Vector2) -> bool:
	return flight_zone_rect().has_point(point)


func clamp_to_flight_zone(point: Vector2) -> Vector2:
	var z := flight_zone_rect()
	## Inset slightly so Rect2.has_point (excludes far edges) still accepts.
	const INSET := 0.5
	return Vector2(
		clampf(point.x, z.position.x + INSET, z.end.x - INSET),
		clampf(point.y, z.position.y + INSET, z.end.y - INSET)
	)


func random_flight_control_point(rng: RandomNumberGenerator) -> Vector2:
	var z := flight_zone_rect()
	return Vector2(
		rng.randf_range(z.position.x, z.end.x),
		rng.randf_range(z.position.y, z.end.y)
	)


func random_landing_point(rng: RandomNumberGenerator) -> Vector2:
	## Safe sand landing — outside chest exclusion, on-screen, not under UI.
	for _i in range(48):
		var p := Vector2(
			rng.randf_range(roam_x_min(), roam_x_max()),
			rng.randf_range(sand_y_min(), sand_y_max())
		)
		if is_valid_roam_point(p):
			return p
	return default_spawn_position(rng)


func build_flight_path(from_ground: Vector2, rng: RandomNumberGenerator) -> PetFlightPath:
	var path := PetFlightPath.new()
	path.last_safe_ground = ensure_safe_position(from_ground, rng)
	var landing := random_landing_point(rng)
	var takeoff_lift := clamp_to_flight_zone(
		Vector2(from_ground.x, sand_y_min() - 20.0 * scale_factor())
	)
	var cruise := random_flight_control_point(rng)
	var approach := clamp_to_flight_zone(Vector2(landing.x, flight_zone_rect().end.y - 8.0))
	## Cubic Bezier through flight zone; LAND lerps approach → sand landing.
	path.configure_cubic(from_ground, takeoff_lift, cruise, approach)
	path.landing_point = landing
	path.last_safe_ground = path.last_safe_ground
	return path


func to_debug_dict() -> Dictionary:
	return {
		"viewport": viewport_size,
		"sand_y_min": sand_y_min(),
		"sand_y_max": sand_y_max(),
		"roam_x_min": roam_x_min(),
		"roam_x_max": roam_x_max(),
		"pet_visual_extent_left": pet_visual_extent_left(),
		"pet_visual_extent_right": pet_visual_extent_right(),
		"screen_edge_pad": screen_edge_pad,
		"chest_runtime_rect": chest_runtime_rect(),
		"chest_solid_rect": chest_solid_rect(),
		"chest_exclusion": chest_exclusion_rect(),
		"transit_y": transit_y(),
		"has_transit_corridor": has_transit_corridor(),
		"pet_body_half": pet_body_half,
		"pet_effective_collision_size": pet_effective_collision_size(),
		"edge_margin": edge_margin,
		"interaction_points": chest_interaction_points(),
		"flight_zone": flight_zone_rect(),
		"flight_enabled": PetRuntimeConfig.PET_FLIGHT_ENABLED,
		"flight_visuals_ready": PetRuntimeConfig.PET_FLIGHT_VISUALS_READY,
		"last_plan": last_plan_debug,
	}
