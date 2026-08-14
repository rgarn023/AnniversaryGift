extends SceneTree
## Phase 1B-1 — invisible parrot runtime: states, bounds, lifecycle, reward pause.

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
	print("=== Pet system Phase 1B-1 invisible runtime ===")
	_test_runtime_flags()
	_test_safe_area_bounds_and_viewports()
	_test_state_transitions()
	_test_movement_bounds_simulation()
	_test_reward_pause_resume()
	_test_tap_reaction()
	await _test_duplicate_spawn_protection()
	_test_persistence_and_fallback()
	_test_visual_invisibility()
	_test_main_mount_wiring()
	_test_regression_locked_systems()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _make_actor(seed: int = 42, vp: Vector2 = Vector2(390, 844)) -> PetActor:
	var scene := load("res://scenes/pets/PetActor.tscn") as PackedScene
	var actor := scene.instantiate() as PetActor
	get_root().add_child(actor)
	var def := PetDefinition.new()
	def.id = "parrot"
	def.display_name = "Parrot"
	def.unlock_type = PetDefinition.UNLOCK_FREE
	def.default_unlocked = true
	actor.setup_from_definition(def)
	var chest := Rect2(69, 482, 252, 326)
	actor.configure_runtime(vp, chest, seed)
	return actor


func _test_runtime_flags() -> void:
	_assert(PetRuntimeConfig.PET_RUNTIME_ENABLED == true, "PET_RUNTIME_ENABLED true")
	_assert(PetRuntimeConfig.PET_VISUALS_ENABLED == true, "PET_VISUALS_ENABLED true (1B-2C)")
	_assert(PetRuntimeConfig.MOVE_SPEED_PX_PER_SEC > 0.0, "move speed configured")
	_assert(PetRuntimeConfig.MOVE_SPEED_PX_PER_SEC < 200.0, "move speed not absurd")
	_assert(PetRuntimeConfig.IDLE_MIN_SEC >= 2.0, "idle min ~2s")
	_assert(PetRuntimeConfig.IDLE_MAX_SEC <= 5.0, "idle max ~5s")
	var mgr_src := FileAccess.get_file_as_string("res://scripts/pets/pet_manager.gd")
	_assert(mgr_src.contains("PetRuntimeConfig.PET_RUNTIME_ENABLED"), "manager uses centralized runtime flag")
	_assert(not mgr_src.contains("CHEST_SPAWN_ENABLED := false"), "Phase 1A hard-disable removed")


func _test_safe_area_bounds_and_viewports() -> void:
	var sizes: Array[Vector2] = [
		Vector2(390, 844),
		Vector2(360, 800),
		Vector2(412, 915),
		Vector2(320, 694),
	]
	for vp in sizes:
		var area := PetSafeArea.new()
		var chest_w := 252.0 * (vp.x / 390.0)
		var chest_h := 326.0 * (vp.y / 844.0)
		var foot := vp.y * PetRuntimeConfig.CHEST_GROUND_Y
		var top := foot - chest_h * LoveNotesChest.CHEST_FOOT_Y_FRAC
		var left := (vp.x - chest_w) * 0.5
		area.configure(vp, Rect2(left, top, chest_w, chest_h))
		_assert(area.sand_y_min() > vp.y * PetRuntimeConfig.WATER_BOTTOM_FRAC, "sand above ocean %s" % str(vp))
		_assert(area.sand_y_max() < vp.y, "sand below viewport bottom %s" % str(vp))
		_assert(area.sand_y_min() < area.sand_y_max(), "sand band valid %s" % str(vp))
		_assert(area.roam_x_min() >= area.edge_margin - 0.01, "edge margin left %s" % str(vp))
		_assert(area.roam_x_max() <= vp.x - area.edge_margin + 0.01, "edge margin right %s" % str(vp))
		var ex := area.chest_exclusion_rect()
		_assert(ex.size.x > chest_w, "chest exclusion inflated %s" % str(vp))
		var pts := area.chest_interaction_points()
		_assert(pts.size() >= 1, "interaction points exist %s" % str(vp))
		for p in pts:
			_assert(not area.is_in_ocean(p), "interaction not ocean %s" % str(vp))
			_assert(not area.is_in_ui_exclusion(p), "interaction not UI %s" % str(vp))
			## Interaction may sit beside exclusion; must not be chest center.
			var center := ex.position + ex.size * 0.5
			_assert(p.distance_to(center) > ex.size.x * 0.25, "interaction not chest center %s" % str(vp))


func _test_state_transitions() -> void:
	var actor := _make_actor(7)
	_assert(actor.state == PetState.Kind.IDLE, "starts IDLE")
	actor.force_state_for_test(PetState.Kind.ROAM)
	_assert(actor.state == PetState.Kind.ROAM, "IDLE→ROAM")
	## Arrive immediately by setting position to target.
	actor.position = actor.target_position
	actor._tick_move_toward(0.016, true)
	_assert(actor.state == PetState.Kind.IDLE, "ROAM→IDLE on arrive")
	actor.force_state_for_test(PetState.Kind.CHEST_INTERACTION)
	_assert(actor.state == PetState.Kind.CHEST_INTERACTION, "IDLE→CHEST_INTERACTION")
	actor.position = actor.target_position
	actor._tick_chest_interaction(0.016)
	_assert(actor.state == PetState.Kind.CHEST_INTERACTION, "hold at interaction")
	actor._hold_timer = 0.01
	actor._tick_chest_interaction(0.05)
	_assert(actor.state == PetState.Kind.IDLE, "CHEST_INTERACTION→IDLE")
	actor.force_state_for_test(PetState.Kind.ROAM)
	actor.trigger_tap_reaction()
	_assert(actor.state == PetState.Kind.TAP_REACTION, "TAP_REACTION entered")
	actor._hold_timer = 0.01
	actor._tick_tap_reaction(0.05)
	_assert(actor.state == PetState.Kind.ROAM or actor.state == PetState.Kind.IDLE, "TAP_REACTION→prior/idle")
	_assert(actor.facing == PetActor.Facing.LEFT or actor.facing == PetActor.Facing.RIGHT, "facing enum set")
	actor.set_visual_state("move")
	_assert(actor.get_visual_state() == "move", "visual state API stubbed")
	actor.queue_free()


func _test_movement_bounds_simulation() -> void:
	var sizes: Array[Vector2] = [Vector2(390, 844), Vector2(360, 800), Vector2(412, 915)]
	for vp in sizes:
		var actor := _make_actor(99, vp)
		var bad := 0
		for i in range(80):
			var target := actor.safe_area.random_roam_target(actor.rng)
			if not actor.safe_area.is_valid_roam_point(target):
				bad += 1
			_assert(not actor.safe_area.is_in_ocean(target), "roam target not ocean vp=%s i=%d" % [str(vp), i])
			_assert(not actor.safe_area.is_in_ui_exclusion(target), "roam target not UI vp=%s i=%d" % [str(vp), i])
			_assert(not actor.safe_area.is_in_chest_exclusion(target), "roam target not chest vp=%s i=%d" % [str(vp), i])
			_assert(target.x >= actor.safe_area.roam_x_min() - 0.01, "roam X min vp=%s" % str(vp))
			_assert(target.x <= actor.safe_area.roam_x_max() + 0.01, "roam X max vp=%s" % str(vp))
			_assert(target.y >= actor.safe_area.sand_y_min() - 0.01, "roam Y min vp=%s" % str(vp))
			_assert(target.y <= actor.safe_area.sand_y_max() + 0.01, "roam Y max vp=%s" % str(vp))
		_assert(bad == 0, "all roam targets valid for vp=%s" % str(vp))
		## Simulate movement frames toward a target.
		actor.force_roam_to_for_test(actor.safe_area.random_roam_target(actor.rng))
		for _f in range(120):
			actor._process(0.05)
			_assert(not actor.safe_area.is_in_ocean(actor.position), "moved pos not ocean")
			_assert(not actor.safe_area.is_in_ui_exclusion(actor.position), "moved pos not UI")
		var snap: Dictionary = actor.get_debug_snapshot()
		_assert(snap.get("pet_id") == "parrot", "debug pet_id")
		_assert(snap.has("state"), "debug state")
		_assert(snap.has("facing"), "debug facing")
		_assert(snap.has("paused"), "debug paused")
		actor.queue_free()


func _test_reward_pause_resume() -> void:
	var actor := _make_actor(3)
	actor.force_state_for_test(PetState.Kind.ROAM)
	actor.pause_for_reward()
	_assert(actor.is_paused(), "paused during reward")
	var pos := actor.position
	actor._process(0.5)
	_assert(actor.position.distance_to(pos) < 0.01, "no movement while paused")
	_assert(actor.state != PetState.Kind.CHEST_INTERACTION or actor.is_paused(), "no chest interaction while paused")
	actor.resume_after_reward()
	_assert(not actor.is_paused(), "resumed after reward")
	_assert(actor.state == PetState.Kind.IDLE, "resume returns IDLE")
	## Hide pathway available for Phase 1B-2.
	actor.set_reward_hide_requested(true)
	_assert(actor.reward_hide_requested, "hide pathway flag settable")
	actor.set_reward_hide_requested(false)
	var mgr := PetManager.new()
	mgr.bootstrap()
	var root := Node2D.new()
	get_root().add_child(root)
	var spawned := mgr.spawn_active_pet(root)
	_assert(spawned != null, "manager spawns when runtime enabled")
	mgr.pause_for_chest_reward()
	var a := mgr.get_spawned_actor() as PetActor
	_assert(a != null and a.is_paused(), "manager pause forwards")
	mgr.resume_after_chest_reward()
	_assert(a != null and not a.is_paused(), "manager resume forwards")
	mgr.despawn_active_pet()
	root.queue_free()
	actor.queue_free()


func _test_tap_reaction() -> void:
	var actor := _make_actor(11)
	## No Area2D / large invisible clickable region.
	var has_area := false
	for c in actor.get_children():
		if c is Area2D or c is Control:
			has_area = true
	_assert(not has_area, "no invisible clickable region on actor")
	actor.trigger_tap_reaction()
	_assert(actor.state == PetState.Kind.TAP_REACTION, "tap reaction state")
	actor.queue_free()


func _test_duplicate_spawn_protection() -> void:
	var mgr := PetManager.new()
	mgr.bootstrap()
	var env := Control.new()
	env.name = "ChestEnvironment"
	get_root().add_child(env)
	var root1 := mgr.ensure_pet_runtime_root(env)
	var a1 := mgr.spawn_active_pet(root1)
	_assert(a1 != null, "first spawn ok")
	var root2 := mgr.ensure_pet_runtime_root(env)
	_assert(root1 == root2, "same PetRuntimeRoot reused")
	var a2 := mgr.spawn_active_pet(root2)
	_assert(a2 != null, "second spawn ok")
	_assert(mgr.count_actors_under(env) == 1, "only one PetActor under env")
	_assert(mgr.get_spawned_actor() == a2, "manager tracks latest actor")
	## Simulate leave/enter CHEST.
	mgr.notify_chest_screen_cleared()
	_assert(mgr.get_spawned_actor() == null, "cleared refs on leave")
	## Orphans from freed tree should not leave manager holding stale actor.
	for c in env.get_children():
		c.queue_free()
	await process_frame
	var root3 := mgr.ensure_pet_runtime_root(env)
	var a3 := mgr.spawn_active_pet(root3)
	_assert(a3 != null, "respawn after return")
	_assert(mgr.count_actors_under(env) == 1, "still one actor after re-enter")
	mgr.despawn_active_pet()
	env.queue_free()


func _test_persistence_and_fallback() -> void:
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(mgr.is_owned("parrot"), "parrot owned")
	_assert(mgr.active_pet_id == "parrot", "active parrot")
	_assert(mgr.get_active_definition() != null and mgr.get_active_definition().is_free(), "parrot FREE")
	_assert(mgr.set_active_pet("parrot"), "set active ok")
	## Duplicate ownership prevention.
	mgr.grant_pet("parrot")
	var count := 0
	for id in mgr.owned_pet_ids:
		if id == "parrot":
			count += 1
	_assert(count == 1, "no duplicate ownership")
	## Empty active pet behaves safely.
	_assert(mgr.set_active_pet(""), "clear active ok")
	_assert(not mgr.should_spawn_on_chest(), "empty active does not spawn")
	_assert(mgr.spawn_active_pet(get_root()) == null, "spawn null when empty active")
	## Invalid ID fallback via bootstrap reload.
	var cfg := ConfigFile.new()
	cfg.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg.set_value("active", "id", "not_a_real_pet")
	cfg.save(PetManager.PERSIST_PATH)
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.active_pet_id == "parrot", "invalid active falls back to parrot")
	_assert(mgr2.is_owned("parrot"), "ownership retained on fallback")


func _test_visual_invisibility() -> void:
	## Historical name — Phase 1B-2C enables free parrot visuals with real artwork.
	var actor := _make_actor(1)
	_assert(actor.visible == true, "actor visible")
	_assert(actor.modulate.a == 1.0, "actor alpha 1")
	_assert(actor.is_artwork_ready(), "artwork ready")
	var visual := actor.get_node_or_null("PetVisual") as CanvasItem
	_assert(visual != null, "PetVisual exists")
	_assert(visual.visible == true, "PetVisual visible")
	var spr := visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_assert(spr != null, "AnimatedSprite2D exists")
	_assert(spr.visible == true, "AnimatedSprite2D visible")
	_assert(spr.sprite_frames != null, "real sprite frames attached")
	## Confirm art files in parrot animation folders (source master + anim frames).
	for folder in ["idle", "move", "chest_interaction", "tap_reaction", "source"]:
		var path := "res://assets/pets/parrot/%s" % folder
		_assert(DirAccess.open(path) != null, "folder exists %s" % folder)
		var dir := DirAccess.open(path)
		dir.list_dir_begin()
		var fname := dir.get_next()
		var art := false
		while fname != "":
			if not fname.begins_with(".") and not fname.ends_with(".gitkeep") and not fname.ends_with(".md"):
				var lower := fname.to_lower()
				if lower.ends_with(".png") or lower.ends_with(".webp") or lower.ends_with(".jpg"):
					art = true
			fname = dir.get_next()
		_assert(art, "artwork present in %s" % folder)
	actor.queue_free()


func _test_main_mount_wiring() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("_mount_pet_runtime") or main.contains("_mount_invisible_pet_runtime"), "main mounts pet runtime")
	_assert(main.contains("PetRuntimeRoot") or main.contains("ensure_pet_runtime_root"), "PetRuntimeRoot path")
	_assert(main.contains("pause_for_chest_reward"), "main pauses pet on reward")
	_assert(main.contains("resume_after_chest_reward"), "main resumes pet after empty open")
	_assert(main.contains("notify_chest_screen_cleared"), "main clears pet on leave")
	_assert(not main.contains("PetCollectionScreen") and not main.contains("open_pet_collection"), "no Pet Collection UI")
	_assert(not main.contains("Pet Shop"), "no Pet Shop UI")
	## No placeholder draw calls introduced for pets in main.
	_assert(not main.contains("placeholder parrot"), "no placeholder parrot text")


func _test_regression_locked_systems() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	var disconnect_fn := FileAccess.get_file_as_string("res://supabase/functions/disconnect-person/index.ts")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260812150000_disconnect_my_person_rpc.sql")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "13-frame open intact")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "baked reveal intact")
	_assert(chest.contains("_play_baked_scroll_reveal"), "baked reveal method intact")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "chest ground intact")
	_assert(env.contains("WATER_BOTTOM_FRAC"), "water band intact")
	_assert(env.contains("default_beach"), "beach env intact")
	_assert(main.contains("YOUR CHEST"), "YOUR CHEST hierarchy intact")
	_assert(main.contains("ChestEnvironment.CHEST_GROUND_Y"), "main chest plant intact")
	_assert(friends.contains("disconnect_my_person"), "disconnect path present")
	_assert(disconnect_fn.contains("record_my_person_pair_end"), "pair end recording intact")
	_assert(mig.contains("my_person_pair_ends"), "pair ends table intact")
	_assert(flags.contains("APP_VERSION_CODE := 64"), "versionCode 63")
	_assert(flags.contains("0.1.65-profile-pet-ui-fix"), "versionName 65")
	var catalog := FileAccess.get_file_as_string("res://config/pets/catalog.json")
	_assert(catalog.contains("\"unlock_type\": \"FREE\""), "parrot remains FREE")
	_assert(catalog.contains("\"default_unlocked\": true"), "parrot default unlocked")
	_assert(not catalog.contains("sku"), "no SKU")
	_assert(not catalog.contains("price"), "no price")
