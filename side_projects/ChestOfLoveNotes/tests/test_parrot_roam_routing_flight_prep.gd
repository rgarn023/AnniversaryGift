extends SceneTree
## v68 — Full-width parrot roam routing + flight architecture (flight disabled).

var _passed: int = 0
var _failed: int = 0
var _dist_left_pct: float = 0.0
var _dist_right_pct: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _run() -> void:
	print("=== v68 parrot roam routing + flight prep ===")
	_test_version()
	_test_flight_flags()
	_test_edge_padding_and_bounds()
	_test_transit_corridor()
	_test_left_to_right_routing()
	_test_right_to_left_routing()
	_test_detour_routes()
	_test_diagonal_and_segments()
	_test_tunneling_and_edges()
	_test_distribution()
	_test_saved_position_does_not_lock_side()
	_test_interaction_from_both_sides()
	_test_actor_path_following()
	_test_flight_architecture()
	_test_manifest_flight_contract()
	_test_regressions()
	print("DIST left_pct=%.1f right_pct=%.1f" % [_dist_left_pct, _dist_right_pct])
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _make_area(vp: Vector2 = Vector2(390, 844)) -> PetSafeArea:
	var area := PetSafeArea.new()
	var chest_w := 252.0 * (vp.x / 390.0)
	var chest_h := 326.0 * (vp.y / 844.0)
	var foot := vp.y * PetRuntimeConfig.CHEST_GROUND_Y
	var top := foot - chest_h * LoveNotesChest.CHEST_FOOT_Y_FRAC
	var left := (vp.x - chest_w) * 0.5
	area.configure(vp, Rect2(left, top, chest_w, chest_h))
	return area


func _make_actor(seed: int = 42, vp: Vector2 = Vector2(390, 844)) -> PetActor:
	var scene := load("res://scenes/pets/PetActor.tscn") as PackedScene
	var actor := scene.instantiate() as PetActor
	get_root().add_child(actor)
	var def := PetDefinition.new()
	def.id = "parrot"
	def.display_name = "Parrot"
	def.unlock_type = PetDefinition.UNLOCK_FREE
	def.default_unlocked = true
	def.asset_root = "res://assets/pets/parrot/"
	actor.setup_from_definition(def)
	var chest_w := 252.0 * (vp.x / 390.0)
	var chest_h := 326.0 * (vp.y / 844.0)
	var foot_y := vp.y * PetRuntimeConfig.CHEST_GROUND_Y
	var top := foot_y - chest_h * LoveNotesChest.CHEST_FOOT_Y_FRAC
	var left := (vp.x - chest_w) * 0.5
	actor.configure_runtime(vp, Rect2(left, top, chest_w, chest_h), seed)
	return actor


func _simulate_path(actor: PetActor, max_frames: int = 400) -> bool:
	## Drive ROAM until IDLE or timeout. Returns true if never entered chest.
	var ok := true
	for _f in range(max_frames):
		if actor.state != PetState.Kind.ROAM and actor.state != PetState.Kind.CHEST_INTERACTION:
			break
		var before := actor.position
		actor._process(0.05)
		if actor.safe_area.is_in_chest_exclusion(actor.position):
			ok = false
			break
		if before.distance_to(actor.position) > 0.5 \
			and actor.safe_area.segment_intersects_chest_exclusion(before, actor.position):
			ok = false
			break
	return ok


func _test_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE == 70, "versionCode 70")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.70-pet-store-gifting", "versionName 70")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("version/code=70"), "export versionCode 70")
	_assert(preset.contains("0.1.70-pet-store-gifting"), "export versionName 70")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_assert(proj.contains("0.1.70-pet-store-gifting"), "project.godot version")


func _test_flight_flags() -> void:
	_assert(PetRuntimeConfig.PET_FLIGHT_ENABLED == false, "PET_FLIGHT_ENABLED false")
	_assert(PetRuntimeConfig.PET_FLIGHT_VISUALS_READY == false, "PET_FLIGHT_VISUALS_READY false")
	_assert(PetRuntimeConfig.flight_visuals_allowed() == false, "flight visuals not allowed")
	PetRuntimeConfig.set_flight_test_mode(false)
	_assert(PetRuntimeConfig.flight_behavior_allowed() == false, "flight behavior off by default")


func _test_edge_padding_and_bounds() -> void:
	var area := _make_area()
	_assert(area.roam_x_min() > area.pet_visual_extent_left(), "left margin includes body+pad")
	_assert(area.roam_x_max() < area.viewport_size.x - area.pet_visual_extent_right(), "right margin includes body+pad")
	_assert(area.roam_x_min() >= area.pet_visual_extent_left() + area.screen_edge_pad - 0.1, "left = extent+pad")
	## Anchor at roam_x_min → leftmost pixel >= pad (>0).
	var leftmost := area.roam_x_min() - area.pet_visual_extent_left()
	var rightmost := area.roam_x_max() + area.pet_visual_extent_right()
	_assert(leftmost >= area.screen_edge_pad - 0.1, "leftmost pixels inside viewport pad")
	_assert(rightmost <= area.viewport_size.x - area.screen_edge_pad + 0.1, "rightmost pixels inside viewport pad")
	_assert(leftmost > 0.0, "never clips left edge (x>0)")
	_assert(rightmost < area.viewport_size.x, "never clips right edge")


func _test_transit_corridor() -> void:
	var area := _make_area()
	_assert(area.has_transit_corridor(), "seaward transit corridor exists")
	var ex := area.chest_exclusion_rect()
	_assert(ex.position.y > area.sand_y_min(), "exclusion top below sand_y_min")
	var ty := area.transit_y()
	_assert(ty >= area.sand_y_min() - 0.1 and ty < ex.position.y, "transit_y in open band")
	## Crossing at transit_y across chest X must be clear.
	var a := Vector2(area.roam_x_min() + 2.0, ty)
	var b := Vector2(area.roam_x_max() - 2.0, ty)
	a = area.clamp_to_roam(a)
	b = area.clamp_to_roam(b)
	_assert(area.is_valid_roam_point(a), "transit left valid")
	_assert(area.is_valid_roam_point(b), "transit right valid")
	_assert(not area.segment_intersects_chest_exclusion(a, b), "transit lane does not cross obstacle")


func _test_left_to_right_routing() -> void:
	var area := _make_area()
	var ex := area.chest_exclusion_rect()
	var left := area.clamp_to_roam(Vector2(minf(ex.position.x - 20.0, area.roam_x_min() + 12.0), area.sand_y_max() - 12.0))
	if not area.is_valid_roam_point(left):
		left = area.clamp_to_roam(Vector2(area.roam_x_min() + 6.0, area.transit_y()))
	var right := area.clamp_to_roam(Vector2(maxf(ex.end.x + 20.0, area.roam_x_max() - 12.0), area.sand_y_max() - 12.0))
	if not area.is_valid_roam_point(right):
		right = area.clamp_to_roam(Vector2(area.roam_x_max() - 6.0, area.transit_y()))
	_assert(area.is_valid_roam_point(left), "spawn left valid")
	_assert(area.is_valid_roam_point(right), "target right valid")
	_assert(area.segment_intersects_chest_exclusion(left, right), "straight L→R blocked by chest")
	var plan := area.plan_ground_path(left, right)
	_assert(bool(plan.get("ok", false)), "L→R plan ok")
	_assert(area.path_segments_safe(left, plan.get("waypoints", [])), "L→R segments safe")
	_assert(str(plan.get("route", "")).contains("upper") or str(plan.get("route", "")).contains("left") \
		or str(plan.get("route", "")).contains("right"), "L→R uses detour route")


func _test_right_to_left_routing() -> void:
	var area := _make_area()
	var ex := area.chest_exclusion_rect()
	var right := area.clamp_to_roam(Vector2(maxf(ex.end.x + 20.0, area.roam_x_max() - 12.0), area.sand_y_max() - 12.0))
	if not area.is_valid_roam_point(right):
		right = area.clamp_to_roam(Vector2(area.roam_x_max() - 6.0, area.transit_y()))
	var left := area.clamp_to_roam(Vector2(minf(ex.position.x - 20.0, area.roam_x_min() + 12.0), area.sand_y_max() - 12.0))
	if not area.is_valid_roam_point(left):
		left = area.clamp_to_roam(Vector2(area.roam_x_min() + 6.0, area.transit_y()))
	_assert(area.is_valid_roam_point(left) and area.is_valid_roam_point(right), "R↔L endpoints valid")
	_assert(area.segment_intersects_chest_exclusion(right, left), "straight R→L blocked")
	var plan := area.plan_ground_path(right, left)
	_assert(bool(plan.get("ok", false)), "R→L plan ok")
	_assert(area.path_segments_safe(right, plan.get("waypoints", [])), "R→L segments safe")


func _test_detour_routes() -> void:
	var area := _make_area()
	var ex := area.chest_exclusion_rect()
	var left := area.clamp_to_roam(Vector2(ex.position.x - 25.0, area.sand_y_max() - 8.0))
	var right := area.clamp_to_roam(Vector2(ex.end.x + 25.0, area.sand_y_max() - 8.0))
	var plan := area.plan_ground_path(left, right)
	_assert(bool(plan.get("ok", false)), "detour plan ok")
	var route := str(plan.get("route", ""))
	print("DETOUR_ROUTE=", route, " len=", plan.get("length", 0))
	## Chest directly between — plan must not be direct.
	_assert(route != "direct", "chest-between uses non-direct route")
	## Left and right detour candidates are considered (debug fields).
	_assert(plan.has("transit_y") or route.contains("upper") or route.contains("left") or route.contains("right"), "route choice recorded")


func _test_diagonal_and_segments() -> void:
	var area := _make_area()
	var ex := area.chest_exclusion_rect()
	var dl := area.clamp_to_roam(Vector2(ex.position.x - 40.0, area.sand_y_min() + 8.0))
	var dr := area.clamp_to_roam(Vector2(ex.end.x + 40.0, area.sand_y_max() - 8.0))
	if area.segment_intersects_chest_exclusion(dl, dr):
		var plan := area.plan_ground_path(dl, dr)
		_assert(bool(plan.get("ok", false)), "diagonal cross-chest plan ok")
		_assert(area.path_segments_safe(dl, plan.get("waypoints", [])), "diagonal segments safe")
	else:
		_assert(true, "diagonal already clear (skip)")


func _test_tunneling_and_edges() -> void:
	var actor := _make_actor(11)
	var ex := actor.safe_area.chest_exclusion_rect()
	var left := actor.safe_area.clamp_to_roam(Vector2(ex.position.x - 28.0, (actor.safe_area.sand_y_min() + actor.safe_area.sand_y_max()) * 0.55))
	actor.position = left
	## Aim through chest with huge delta — must not tunnel.
	actor.target_position = actor.safe_area.clamp_to_roam(Vector2(ex.end.x + 28.0, left.y))
	actor._path_waypoints.clear()
	actor._planned_destination = actor.target_position
	actor.transition_to(PetState.Kind.ROAM)
	actor._tick_move_toward(10.0, true)
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.position), "high-delta no chest entry")
	## Edge clip: force roam extremes.
	actor.position = Vector2(actor.safe_area.roam_x_min(), actor.safe_area.transit_y())
	var left_pix := actor.position.x - actor.safe_area.pet_visual_extent_left()
	_assert(left_pix >= actor.safe_area.screen_edge_pad - 0.5, "left extreme no clip")
	actor.position = Vector2(actor.safe_area.roam_x_max(), actor.safe_area.transit_y())
	var right_pix := actor.position.x + actor.safe_area.pet_visual_extent_right()
	_assert(right_pix <= actor.safe_area.viewport_size.x - actor.safe_area.screen_edge_pad + 0.5, "right extreme no clip")
	actor.queue_free()


func _test_distribution() -> void:
	var area := _make_area()
	var mid := area.viewport_size.x * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260814
	var left_hits := 0
	var right_hits := 0
	var n := 400
	## Sample without origin bias first.
	for _i in range(n):
		var t := area.random_roam_target(rng)
		if t.x < mid:
			left_hits += 1
		else:
			right_hits += 1
	_dist_left_pct = 100.0 * float(left_hits) / float(n)
	_dist_right_pct = 100.0 * float(right_hits) / float(n)
	_assert(_dist_left_pct > 15.0, "left-half targets >15%% (got %.1f)" % _dist_left_pct)
	_assert(_dist_right_pct > 15.0, "right-half targets >15%% (got %.1f)" % _dist_right_pct)
	_assert(_dist_left_pct < 85.0, "not 90%%+ left bias")
	_assert(_dist_right_pct < 85.0, "not 90%%+ right bias")

	## From LEFT origin — must still reach right half often via routing.
	var ex := area.chest_exclusion_rect()
	var origin_left := area.clamp_to_roam(Vector2(ex.position.x - 20.0, area.transit_y() + 20.0))
	var reach_right := 0
	var reach_left := 0
	for _i in range(120):
		var t2 := area.random_roam_target(rng, origin_left)
		var plan := area.plan_ground_path(origin_left, t2)
		_assert(bool(plan.get("ok", false)), "from-left target has safe plan")
		if t2.x > mid:
			reach_right += 1
		else:
			reach_left += 1
	_assert(reach_right > 10, "saved/current left still allows right-side travel (%d)" % reach_right)

	var origin_right := area.clamp_to_roam(Vector2(ex.end.x + 20.0, area.transit_y() + 20.0))
	var reach_left2 := 0
	for _i in range(120):
		var t3 := area.random_roam_target(rng, origin_right)
		var plan3 := area.plan_ground_path(origin_right, t3)
		_assert(bool(plan3.get("ok", false)), "from-right target has safe plan")
		if t3.x < mid:
			reach_left2 += 1
	_assert(reach_left2 > 10, "saved/current right still allows left-side travel (%d)" % reach_left2)

	## Full route simulation reachability.
	var actor := _make_actor(99)
	actor.position = origin_left
	actor.force_roam_to_for_test(origin_right)
	_assert(actor.state == PetState.Kind.ROAM, "forced L→R roam")
	_assert(_simulate_path(actor, 500), "simulate L→R no chest cross")
	_assert(actor.position.x > mid - 5.0 or actor._planned_destination.x > mid, "reached/aimed right half")
	actor.position = origin_right
	actor.force_roam_to_for_test(origin_left)
	_assert(_simulate_path(actor, 500), "simulate R→L no chest cross")
	actor.queue_free()


func _test_saved_position_does_not_lock_side() -> void:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var mgr := PetManager.new()
	mgr.bootstrap()
	var area := _make_area()
	var left_world := area.clamp_to_roam(Vector2(area.roam_x_min() + 10.0, area.transit_y()))
	if not area.is_valid_roam_point(left_world):
		left_world = area.default_spawn_position(null)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(left_world, area.viewport_size), true)
	var restored := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_runtime_rect(), null)
	_assert(restored.x < area.viewport_size.x * 0.5, "restore starts left")
	## After restore, target generation must still sample right.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var right_hits := 0
	for _i in range(100):
		var t := area.random_roam_target(rng, restored)
		if t.x > area.viewport_size.x * 0.5:
			right_hits += 1
	_assert(right_hits > 8, "after saved-left restore, right targets still appear (%d)" % right_hits)


func _test_interaction_from_both_sides() -> void:
	var area := _make_area()
	var pts := area.chest_interaction_points()
	_assert(pts.size() >= 2, "left+right interaction points")
	var left_pt := pts[0]
	var right_pt := pts[1] if pts.size() > 1 else pts[0]
	## From opposite sides.
	var start_left := area.clamp_to_roam(Vector2(area.roam_x_min() + 4.0, area.transit_y()))
	var start_right := area.clamp_to_roam(Vector2(area.roam_x_max() - 4.0, area.transit_y()))
	var plan_lr := area.plan_ground_path(start_left, right_pt)
	var plan_rl := area.plan_ground_path(start_right, left_pt)
	_assert(bool(plan_lr.get("ok", false)), "interaction reachable from left→right point")
	_assert(bool(plan_rl.get("ok", false)), "interaction reachable from right→left point")
	_assert(area.path_segments_safe(start_left, plan_lr.get("waypoints", [])), "L interaction segments safe")
	_assert(area.path_segments_safe(start_right, plan_rl.get("waypoints", [])), "R interaction segments safe")

	var actor := _make_actor(21)
	actor.position = start_right
	actor._begin_chest_interaction()
	_assert(actor.state == PetState.Kind.CHEST_INTERACTION, "chest interaction state")
	_assert(_simulate_path(actor, 500), "interaction approach no chest cross")
	actor.queue_free()


func _test_actor_path_following() -> void:
	var actor := _make_actor(33)
	var snap := actor.get_debug_snapshot()
	_assert(snap.has("path_waypoints"), "debug exposes waypoints")
	_assert(snap.has("active_route"), "debug exposes route")
	_assert(snap.has("flight_eligibility"), "debug exposes flight eligibility")
	_assert(snap.has("flight_zone"), "debug exposes flight zone")
	var ex := actor.safe_area.chest_exclusion_rect()
	var left := actor.safe_area.clamp_to_roam(Vector2(ex.position.x - 22.0, actor.safe_area.sand_y_max() - 10.0))
	var right := actor.safe_area.clamp_to_roam(Vector2(ex.end.x + 22.0, actor.safe_area.sand_y_max() - 10.0))
	actor.position = left
	actor.force_roam_to_for_test(right)
	_assert(actor._path_waypoints.size() >= 1, "actor has waypoints")
	_assert(_simulate_path(actor, 600), "actor path follow no chest")
	actor.queue_free()


func _test_flight_architecture() -> void:
	## Production remains disabled.
	_assert(PetRuntimeConfig.PET_FLIGHT_ENABLED == false, "prod flight still false")
	PetRuntimeConfig.set_flight_test_mode(true)
	_assert(PetRuntimeConfig.flight_behavior_allowed(), "test mode allows flight logic")
	_assert(not PetRuntimeConfig.flight_visuals_allowed(), "test mode still no flight visuals")

	var actor := _make_actor(77)
	var ground := actor.position
	actor.force_state_for_test(PetState.Kind.TAKEOFF)
	_assert(actor.state == PetState.Kind.TAKEOFF, "TAKEOFF enterable under test flag")
	_assert(actor._flight_path != null, "flight path generated")
	var zone := actor.safe_area.flight_zone_rect()
	_assert(zone.size.x > 0.0 and zone.size.y > 0.0, "flight zone non-empty")
	## Advance through takeoff → fly samples stay in zone / not UI.
	for _f in range(40):
		if actor.state != PetState.Kind.TAKEOFF:
			break
		actor._process(0.05)
	_assert(actor.state == PetState.Kind.FLY or actor.state == PetState.Kind.LAND or actor.state == PetState.Kind.TAKEOFF, "progressed flight")
	if actor._flight_path != null:
		for t_i in range(11):
			var t := float(t_i) / 10.0
			var p := actor._flight_path.sample(t)
			## Cruise samples should be clampable into flight zone (path may start on sand).
			if t >= 0.25 and t <= 0.85:
				var c := actor.safe_area.clamp_to_flight_zone(p)
				_assert(actor.safe_area.is_in_flight_zone(c), "flight sample clampable to zone t=%.1f" % t)
				_assert(not actor.safe_area.is_in_ui_exclusion(c), "flight avoids UI t=%.1f" % t)
	var landing := actor._intended_landing
	_assert(actor.safe_area.is_valid_roam_point(landing), "landing is safe sand")
	_assert(not actor.safe_area.is_in_chest_exclusion(landing), "landing outside chest")

	## Midair must not persist as ground position.
	if actor.state == PetState.Kind.FLY or actor.state == PetState.Kind.TAKEOFF:
		var midair := actor.position
		var persist := actor.get_persistable_world_position()
		_assert(actor.safe_area.is_valid_roam_point(persist), "persistable is ground-safe")
		_assert(persist.y >= actor.safe_area.sand_y_min() - 1.0, "persistable on/near sand")
		## If currently midair above sand, persist should differ toward ground.
		if midair.y < actor.safe_area.sand_y_min() - 5.0:
			_assert(persist.y > midair.y - 1.0, "does not persist raw midair y")

	## Reward cancels flight.
	actor.force_state_for_test(PetState.Kind.FLY)
	actor.pause_for_reward()
	_assert(actor.paused, "reward pauses")
	_assert(not PetState.is_flight_state(actor.state), "reward cancels flight state")
	_assert(actor.safe_area.is_valid_roam_point(actor.position) or actor.reward_hide_requested, "reward leaves ground-safe pos")
	actor.resume_after_reward()
	_assert(actor.state == PetState.Kind.IDLE, "resume IDLE on ground")
	_assert(not PetState.is_flight_state(actor.state), "no flight after resume")
	_assert(actor.safe_area.is_valid_roam_point(actor.position), "resume ground valid")

	## Without test mode, TAKEOFF must not engage from idle production path.
	PetRuntimeConfig.set_flight_test_mode(false)
	actor._begin_idle()
	actor._state_timer = 0.0
	## Force many idle decisions — flight must not start while disabled.
	var flew := false
	for _i in range(30):
		actor._tick_idle(10.0)
		if PetState.is_flight_state(actor.state):
			flew = true
			break
		if actor.state != PetState.Kind.IDLE:
			actor._begin_idle()
			actor._state_timer = 0.0
	_assert(not flew, "production idle never enters flight while disabled")
	actor.queue_free()
	PetRuntimeConfig.set_flight_test_mode(false)


func _test_manifest_flight_contract() -> void:
	var raw := FileAccess.get_file_as_string("res://assets/pets/parrot/parrot_animation_manifest.json")
	var m: Dictionary = JSON.parse_string(raw)
	_assert(str(m.get("status", "")) == "ARTWORK_READY", "ground package ARTWORK_READY")
	_assert(bool(m.get("flight_artwork_ready", true)) == false, "flight_artwork_ready false")
	_assert(bool(m.get("flight_enabled", true)) == false, "flight_enabled false in manifest")
	var by_name := {}
	for a in m.get("animations", []):
		by_name[str(a.get("name", ""))] = a
	for name in ["idle", "move", "chest_interaction", "tap_reaction"]:
		_assert(by_name.has(name), "ground anim %s present" % name)
		_assert(str(by_name[name].get("status", "")) == "artwork_ready", "%s artwork_ready" % name)
	for name in ["takeoff", "fly", "land"]:
		_assert(by_name.has(name), "flight anim %s listed" % name)
		_assert(str(by_name[name].get("status", "")) == "awaiting_artwork", "%s awaiting_artwork" % name)
	_assert(DirAccess.open("res://assets/pets/parrot/takeoff") != null, "takeoff folder")
	_assert(DirAccess.open("res://assets/pets/parrot/fly") != null, "fly folder")
	_assert(DirAccess.open("res://assets/pets/parrot/land") != null, "land folder")
	## Loader must stay ground-ready despite missing flight PNGs.
	var loader := PetAnimationLoader.new()
	loader.load_parrot_manifest()
	_assert(loader.artwork_ready == true, "loader artwork_ready despite awaiting flight")
	_assert(loader.flight_artwork_ready == false, "loader flight_artwork_ready false")
	_assert(loader.animation_name_for_visual_state("fly") == "idle", "fly visual falls back to idle")


func _test_regressions() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "chest opening intact")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "baked scroll intact")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "ground intact")
	_assert(env.contains("default_beach"), "beach intact")
	_assert(main.contains("_build_profile_pets_section"), "profile pets section intact")
	_assert(friends.contains("disconnect_my_person"), "backend disconnect untouched")
	_assert(not main.contains("BillingClient"), "no billing")
	## Profile selector regression (logic only).
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var mgr := PetManager.new()
	mgr.bootstrap()
	mgr.grant_pet_from_claim("parrot", false)
	_assert(mgr.select_profile_pet("off"), "profile off works")
	_assert(mgr.get_profile_pet_selection() == "off", "selection off")
	_assert(mgr.select_profile_pet("parrot"), "profile parrot works")
	_assert(mgr.get_profile_pet_selection() == "parrot", "selection parrot")
