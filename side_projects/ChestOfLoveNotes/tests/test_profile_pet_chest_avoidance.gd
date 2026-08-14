extends SceneTree
## v64 — Profile pet selector + chest avoidance (segment, step, spawn, resume).

var _passed: int = 0
var _failed: int = 0


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
	print("=== v64 Profile pet + chest avoidance ===")
	_test_version()
	_test_profile_pet_persistence()
	_test_profile_ui_wiring()
	_test_spawn_counts()
	_test_chest_exclusion_geometry()
	_test_target_and_segment_rejection()
	_test_movement_step_and_tunneling()
	_test_spawn_and_resume_correction()
	_test_interaction_points_safe()
	_test_left_right_roam()
	_test_randomized_path_simulation()
	_test_regressions()
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


func _test_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE == 67, "versionCode 67")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.67-profile-pet-persistence-fix", "versionName 67")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("version/code=67"), "export versionCode 67")
	_assert(preset.contains("0.1.67-profile-pet-persistence-fix"), "export versionName 67")


func _test_profile_pet_persistence() -> void:
	## Clean slate.
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)

	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(mgr.is_owned("parrot"), "parrot owned by default")
	_assert(mgr.pet_enabled == true, "pets enabled by default")
	_assert(mgr.active_pet_id == "parrot", "active parrot")
	_assert(mgr.get_profile_pet_selection() == "parrot", "UI selection Parrot")
	_assert(mgr.should_spawn_on_chest(), "spawn when Parrot on")

	## 1. Parrot → Off
	_assert(mgr.select_profile_pet("off"), "select Off")
	_assert(mgr.pet_enabled == false, "pet_enabled false")
	_assert(mgr.active_pet_id == "parrot", "active_pet preserved while Off")
	_assert(mgr.is_owned("parrot"), "ownership preserved while Off")
	_assert(mgr.get_profile_pet_selection() == "off", "UI selection Off")
	_assert(not mgr.should_spawn_on_chest(), "no spawn when Off")

	## 2. Off persists reload
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.pet_enabled == false, "Off persists")
	_assert(mgr2.active_pet_id == "parrot", "active parrot persists while Off")
	_assert(mgr2.is_owned("parrot"), "owned persists while Off")
	_assert(mgr2.get_profile_pet_selection() == "off", "UI Off after reload")

	## 3. Off → Parrot
	_assert(mgr2.select_profile_pet("parrot"), "select Parrot")
	_assert(mgr2.pet_enabled == true, "enabled again")
	_assert(mgr2.active_pet_id == "parrot", "active parrot")
	_assert(mgr2.get_profile_pet_selection() == "parrot", "UI Parrot")
	_assert(mgr2.should_spawn_on_chest(), "spawn when Parrot")

	## 4. Parrot persists reload
	var mgr3 := PetManager.new()
	mgr3.bootstrap()
	_assert(mgr3.pet_enabled == true, "Parrot enabled persists")
	_assert(mgr3.get_profile_pet_selection() == "parrot", "UI Parrot after reload")

	## Invalid active while enabled → safe fallback
	var cfg := ConfigFile.new()
	cfg.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg.set_value("active", "id", "not_a_real_pet")
	cfg.set_value("settings", "pet_enabled", true)
	cfg.save(PetManager.PERSIST_PATH)
	var mgr4 := PetManager.new()
	mgr4.bootstrap()
	_assert(mgr4.active_pet_id == "parrot", "invalid active falls back to parrot")
	_assert(mgr4.is_owned("parrot"), "ownership retained")


func _test_profile_ui_wiring() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("_build_profile_pets_section"), "pets section builder")
	_assert(main.contains('sec.text = "Pets"'), "Pets section label")
	_assert(main.contains("select_profile_pet"), "select API wired")
	_assert(main.contains("never mounted from"), "diagnostics removed note")
	var profile_fn_start := main.find("func _show_profile()")
	var profile_fn_end := main.find("func _show_diagnostics()")
	_assert(profile_fn_start >= 0 and profile_fn_end > profile_fn_start, "profile funcs")
	var profile_body := main.substr(profile_fn_start, profile_fn_end - profile_fn_start)
	_assert(not profile_body.contains("_build_android_diagnostics_panel"), "no Android Diagnostics on Profile")
	_assert(profile_body.contains("_build_profile_pets_section"), "Pets on Profile")
	## No empty diagnostics call left that would leave a gap — section simply absent.
	_assert(not profile_body.contains("col.add_child(_build_android_diagnostics_panel())"), "no diagnostics add_child")
	_assert(main.contains("_build_android_diagnostics_panel"), "diagnostics helper kept internally")
	_assert(not main.contains("BillingClient"), "no billing")
	_assert(not main.contains("PetCollectionScreen"), "no pet collection")
	_assert(not main.contains("Pet Shop"), "no pet shop")


func _test_spawn_counts() -> void:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var env := Node2D.new()
	env.name = "ChestEnvironment"
	get_root().add_child(env)
	var mgr := PetManager.new()
	mgr.bootstrap()
	var root := mgr.ensure_pet_runtime_root(env)

	mgr.select_profile_pet("off")
	_assert(mgr.spawn_active_pet(root) == null, "spawn null when Off")
	_assert(mgr.count_actors_under(env) == 0, "PetActor count Off = 0")

	mgr.select_profile_pet("parrot")
	var a1 := mgr.spawn_active_pet(root)
	_assert(a1 != null, "spawn when On")
	_assert(mgr.count_actors_under(env) == 1, "PetActor count On = 1")
	mgr.spawn_active_pet(root)
	mgr.spawn_active_pet(root)
	_assert(mgr.count_actors_under(env) == 1, "duplicate spawn protection")
	mgr.despawn_active_pet()
	env.queue_free()


func _test_chest_exclusion_geometry() -> void:
	var area := _make_area()
	var raw := area.chest_runtime_rect()
	var ex := area.chest_exclusion_rect()
	_assert(raw.size.x > 0.0 and raw.size.y > 0.0, "runtime chest rect non-empty")
	_assert(ex.size.x > raw.size.x, "exclusion wider than chest")
	_assert(ex.size.y > raw.size.y, "exclusion taller than chest")
	var body := area.pet_effective_collision_size()
	_assert(body.x > 20.0 and body.y > 20.0, "pet collision size accounts for body")
	## Expansion ≈ margin + half body on each side.
	var grow_x := (ex.size.x - raw.size.x) * 0.5
	_assert(grow_x >= area.chest_exclusion_margin + area.pet_body_half.x - 0.5, "Minkowski X expand")
	var dbg := area.to_debug_dict()
	_assert(dbg.has("chest_runtime_rect"), "debug runtime rect")
	_assert(dbg.has("chest_exclusion"), "debug exclusion")
	_assert(dbg.has("pet_effective_collision_size"), "debug pet size")


func _test_target_and_segment_rejection() -> void:
	var area := _make_area()
	var ex := area.chest_exclusion_rect()
	var inside := ex.get_center()
	_assert(area.is_in_chest_exclusion(inside), "center inside exclusion")
	_assert(not area.is_valid_roam_point(inside), "target inside rejected")

	var left := Vector2(ex.position.x - 40.0, clampf(ex.get_center().y, area.sand_y_min(), area.sand_y_max()))
	var right := Vector2(ex.end.x + 40.0, left.y)
	left = area.clamp_to_roam(left)
	right = area.clamp_to_roam(right)
	_assert(area.is_valid_roam_point(left), "left side valid")
	_assert(area.is_valid_roam_point(right), "right side valid")
	_assert(area.segment_intersects_chest_exclusion(left, right), "L→R segment crosses chest")
	_assert(area.segment_intersects_chest_exclusion(right, left), "R→L segment crosses chest")
	_assert(not area.is_roam_path_clear(left, right), "L→R path rejected")
	_assert(not area.is_roam_path_clear(right, left), "R→L path rejected")

	## Diagonal crossing.
	var dl := Vector2(ex.position.x - 50.0, area.sand_y_min() + 4.0)
	var dr := Vector2(ex.end.x + 50.0, area.sand_y_max() - 4.0)
	dl = area.clamp_to_roam(dl)
	dr = area.clamp_to_roam(dr)
	## If both ends outside, diagonal through chest body must be detected.
	if not area.is_in_chest_exclusion(dl) and not area.is_in_chest_exclusion(dr):
		_assert(area.segment_intersects_chest_exclusion(dl, dr), "diagonal crossing detected")
		_assert(not area.is_roam_path_clear(dl, dr), "diagonal path rejected")

	## random_roam_target with from_pos never returns a crossing path.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(80):
		var t := area.random_roam_target(rng, left)
		_assert(area.is_valid_roam_point(t), "roam target valid i=%d" % i)
		_assert(area.is_roam_path_clear(left, t), "roam path clear from left i=%d" % i)
	for i in range(80):
		var t2 := area.random_roam_target(rng, right)
		_assert(area.is_valid_roam_point(t2), "roam target valid from right i=%d" % i)
		_assert(area.is_roam_path_clear(right, t2), "roam path clear from right i=%d" % i)


func _test_movement_step_and_tunneling() -> void:
	var actor := _make_actor(9)
	var ex := actor.safe_area.chest_exclusion_rect()
	var left := actor.safe_area.clamp_to_roam(Vector2(ex.position.x - 30.0, (actor.safe_area.sand_y_min() + actor.safe_area.sand_y_max()) * 0.5))
	actor.position = left
	## Aim through chest — step must not enter.
	actor.target_position = actor.safe_area.clamp_to_roam(Vector2(ex.end.x + 30.0, left.y))
	actor.transition_to(PetState.Kind.ROAM)
	var entered := false
	for _f in range(40):
		actor._tick_move_toward(0.05, true)
		if actor.safe_area.is_in_chest_exclusion(actor.position):
			entered = true
			break
	_assert(not entered, "per-frame step cannot enter exclusion")
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.position), "position outside after blocked step")

	## High-delta tunneling attempt.
	actor.position = left
	var far := actor.safe_area.clamp_to_roam(Vector2(ex.end.x + 40.0, left.y))
	actor.target_position = far
	actor.transition_to(PetState.Kind.ROAM)
	## Huge delta — one step would leap across chest.
	actor._tick_move_toward(10.0, true)
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.position), "high-delta cannot tunnel into chest")
	_assert(
		not actor.safe_area.segment_intersects_chest_exclusion(left, actor.position)
		or actor.position.distance_to(left) < 1.0
		or actor.state == PetState.Kind.IDLE,
		"high-delta aborts or stays same-side"
	)
	actor.queue_free()


func _test_spawn_and_resume_correction() -> void:
	var actor := _make_actor(3)
	var ex := actor.safe_area.chest_exclusion_rect()
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.position), "spawn outside chest")
	_assert(actor.safe_area.is_valid_roam_point(actor.position), "spawn is valid roam")

	## Force unsafe point then ensure_safe_position.
	var bad := ex.get_center()
	var fixed := actor.safe_area.ensure_safe_position(bad, actor.rng)
	_assert(not actor.safe_area.is_in_chest_exclusion(fixed), "spawn-inside corrected")
	_assert(actor.safe_area.is_valid_roam_point(fixed), "corrected spawn valid")

	## Resume-after-reward with unsafe stale position.
	actor.position = bad
	actor.pause_for_reward()
	actor.resume_after_reward()
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.position), "resume corrects unsafe point")
	_assert(actor.state == PetState.Kind.IDLE, "resume IDLE")
	actor.queue_free()


func _test_interaction_points_safe() -> void:
	var area := _make_area()
	var pts := area.chest_interaction_points()
	_assert(pts.size() >= 1, "interaction points exist")
	for p in pts:
		_assert(not area.is_in_chest_exclusion(p), "interaction outside exclusion")
		_assert(not area.is_in_ocean(p), "interaction not ocean")
		_assert(not area.is_in_ui_exclusion(p), "interaction not UI")
	var actor := _make_actor(7)
	actor.force_state_for_test(PetState.Kind.CHEST_INTERACTION)
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.target_position), "interaction target outside")
	actor.queue_free()


func _test_left_right_roam() -> void:
	var area := _make_area()
	var ex := area.chest_exclusion_rect()
	var mid := ex.get_center().x
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var left_hits := 0
	var right_hits := 0
	for _i in range(100):
		var t := area.random_roam_target(rng)
		if t.x < mid:
			left_hits += 1
		else:
			right_hits += 1
	_assert(left_hits > 10, "can roam left of chest")
	_assert(right_hits > 10, "can roam right of chest")


func _test_randomized_path_simulation() -> void:
	var actor := _make_actor(55)
	var crossed := 0
	var samples := 0
	for i in range(120):
		actor._begin_roam()
		var start := actor.position
		var dest := actor.target_position
		samples += 1
		if actor.safe_area.segment_intersects_chest_exclusion(start, dest):
			crossed += 1
		## Simulate several frames along accepted path.
		for _f in range(30):
			if actor.state != PetState.Kind.ROAM:
				break
			var before := actor.position
			actor._process(0.05)
			if actor.safe_area.is_in_chest_exclusion(actor.position):
				crossed += 1
			if actor.safe_area.segment_intersects_chest_exclusion(before, actor.position) \
				and before.distance_to(actor.position) > 0.5:
				## Moving along a previously clear path should not suddenly cross.
				crossed += 1
		## Force idle so next roam starts fresh.
		if actor.state == PetState.Kind.ROAM:
			actor.position = actor.target_position
			actor._begin_idle()
	_assert(crossed == 0, "no ROAM path/step crosses chest (%d samples)" % samples)
	actor.queue_free()


func _test_regressions() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "chest opening intact")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "baked scroll intact")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "ground intact")
	_assert(env.contains("default_beach"), "beach intact")
	_assert(env.contains("WATER_BOTTOM_FRAC"), "water intact")
	_assert(main.contains("YOUR CHEST"), "Saved/Hidden hierarchy intact")
	_assert(main.contains("CharoiteBoot") or FileAccess.file_exists("res://scenes/CharoiteBoot.tscn"), "splash intact")
	_assert(friends.contains("disconnect_my_person"), "backend disconnect untouched")
	_assert(not main.contains("BillingClient"), "no billing")
	## Parrot animations unchanged (manifest still ARTWORK_READY).
	var raw := FileAccess.get_file_as_string("res://assets/pets/parrot/parrot_animation_manifest.json")
	var m: Dictionary = JSON.parse_string(raw)
	_assert(str(m.get("status", "")) == "ARTWORK_READY", "parrot artwork ready unchanged")
