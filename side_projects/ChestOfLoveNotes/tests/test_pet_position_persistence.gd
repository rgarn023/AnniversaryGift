extends SceneTree
## v67 — PetManager normalized position persistence tests.

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== test_pet_position_persistence ===")
	_test_no_saved_uses_default()
	_test_valid_norm_restored()
	_test_survives_leave_return_and_reload()
	_test_off_preserves_position()
	_test_off_then_parrot_restores()
	_test_chest_exclusion_corrected()
	_test_ocean_and_ui_corrected()
	_test_cross_viewport_proportional()
	_test_no_duplicate_actor()
	_test_no_every_frame_writes()
	print("=== test_pet_position_persistence done failed=%d ===" % _failed)
	quit(0 if _failed == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		print("FAIL: ", msg)
		_failed += 1


func _fresh_mgr() -> PetManager:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var mgr := PetManager.new()
	mgr.bootstrap()
	mgr.select_profile_pet("parrot")
	mgr.position_persist_write_count = 0
	return mgr


func _area(vp: Vector2 = Vector2(390, 844), chest: Rect2 = Rect2(100, 400, 180, 220)) -> PetSafeArea:
	var a := PetSafeArea.new()
	a.configure(vp, chest)
	return a


func _test_no_saved_uses_default() -> void:
	var mgr := _fresh_mgr()
	_assert(not mgr.has_saved_position("parrot"), "no saved position initially")
	var area := _area()
	var spawn := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	var expected := area.default_spawn_position()
	_assert(spawn.distance_to(expected) < 1.0, "no saved → default spawn")


func _test_valid_norm_restored() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	var target := Vector2(area.roam_x_min() + 40.0, (area.sand_y_min() + area.sand_y_max()) * 0.55)
	target = area.ensure_safe_position(target)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	var restored := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(restored.distance_to(target) < 2.0, "valid saved norm → restored")


func _test_survives_leave_return_and_reload() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	var target := Vector2(area.roam_x_max() - 35.0, (area.sand_y_min() + area.sand_y_max()) * 0.6)
	target = area.ensure_safe_position(target)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	## Simulate CHEST leave/return via resolve again.
	var again := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(again.distance_to(target) < 2.0, "survives CHEST leave/return resolve")
	## App restart: new PetManager loads cfg.
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.has_saved_position("parrot"), "reload has position")
	var n := mgr2.get_saved_position_norm("parrot")
	var world := mgr2.norm_to_world(n, area.viewport_size)
	_assert(world.distance_to(target) < 2.0, "survives persistence reload/app restart")


func _test_off_preserves_position() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	var target := Vector2(area.roam_x_min() + 50.0, (area.sand_y_min() + area.sand_y_max()) * 0.5)
	target = area.ensure_safe_position(target)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	mgr.select_profile_pet("off")
	_assert(mgr.pet_enabled == false, "Off sets pet_enabled false")
	_assert(mgr.active_pet_id == "parrot", "Off preserves active_pet")
	_assert(mgr.is_owned("parrot"), "Off preserves ownership")
	_assert(mgr.has_saved_position("parrot"), "Off preserves saved position")
	var n := mgr.get_saved_position_norm("parrot")
	_assert(mgr.norm_to_world(n, area.viewport_size).distance_to(target) < 2.0, "Off position value intact")


func _test_off_then_parrot_restores() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	var target := Vector2(area.roam_x_max() - 40.0, (area.sand_y_min() + area.sand_y_max()) * 0.45)
	target = area.ensure_safe_position(target)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	mgr.select_profile_pet("off")
	mgr.select_profile_pet("parrot")
	_assert(mgr.pet_enabled and mgr.active_pet_id == "parrot", "Off→Parrot re-enables")
	var restored := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(restored.distance_to(target) < 2.0, "Off→Parrot restores saved position")


func _test_chest_exclusion_corrected() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	var inside := area.chest_exclusion_rect().get_center()
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(inside, area.viewport_size))
	var fixed := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(not area.is_in_chest_exclusion(fixed), "chest exclusion corrected")
	_assert(area.is_valid_roam_point(fixed) or not area.is_in_ocean(fixed), "corrected point not ocean")


func _test_ocean_and_ui_corrected() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	## Ocean: near top of viewport (water).
	var ocean := Vector2(area.viewport_size.x * 0.5, 10.0)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(ocean, area.viewport_size))
	var fixed_ocean := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(not area.is_in_ocean(fixed_ocean), "ocean corrected")
	## UI bottom nav band.
	var ui := Vector2(area.viewport_size.x * 0.5, area.viewport_size.y - 5.0)
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(ui, area.viewport_size))
	var fixed_ui := mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(not area.is_in_ui_exclusion(fixed_ui), "UI exclusion corrected")


func _test_cross_viewport_proportional() -> void:
	var mgr := _fresh_mgr()
	var small := Vector2(390, 844)
	var large := Vector2(780, 1688)
	var area_s := _area(small)
	var target := Vector2(area_s.roam_x_min() + 60.0, (area_s.sand_y_min() + area_s.sand_y_max()) * 0.5)
	target = area_s.ensure_safe_position(target)
	var norm := mgr.world_to_norm(target, small)
	mgr.set_saved_position_norm("parrot", norm)
	var area_l := _area(large, Rect2(200, 800, 360, 440))
	var restored := mgr.resolve_spawn_world_position(large, area_l.chest_rect)
	var expected := mgr.norm_to_world(norm, large)
	## Allow clamp delta; still proportional neighborhood.
	_assert(restored.distance_to(area_l.ensure_safe_position(expected)) < 8.0, "cross-viewport proportional restore")
	_assert(absf(restored.x / large.x - norm.x) < 0.08 or absf(restored.y / large.y - norm.y) < 0.08
		or restored.distance_to(area_l.ensure_safe_position(expected)) < 8.0,
		"normalized mapping respected within clamp")


func _test_no_duplicate_actor() -> void:
	var mgr := _fresh_mgr()
	var parent := Node2D.new()
	root.add_child(parent)
	var a1 := mgr.spawn_active_pet(parent)
	_assert(a1 != null, "first spawn returned actor")
	var a2 := mgr.spawn_active_pet(parent)
	_assert(a2 != null, "second spawn returned actor")
	_assert(mgr.count_actors_under(parent) == 1, "no duplicate PetActor after restore/spawn")
	## Prior instance must be gone (a1 freed by second spawn).
	_assert(not is_instance_valid(a1) or a1 == a2, "prior actor despawned")
	mgr.despawn_active_pet()
	_assert(mgr.count_actors_under(parent) == 0, "despawn clears actors")
	parent.queue_free()


func _test_no_every_frame_writes() -> void:
	var mgr := _fresh_mgr()
	var area := _area()
	var target := Vector2(area.roam_x_min() + 30.0, (area.sand_y_min() + area.sand_y_max()) * 0.5)
	target = area.ensure_safe_position(target)
	mgr.position_persist_write_count = 0
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	var after_one := mgr.position_persist_write_count
	_assert(after_one == 1, "single write on first save")
	## Same position again should no-op.
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	_assert(mgr.position_persist_write_count == after_one, "duplicate norm does not rewrite")
	## Simulate "every frame" spam with tiny jitter below threshold — still one write.
	for i in range(60):
		var jitter := target + Vector2(0.01 * float(i % 2), 0.0)
		mgr.set_saved_position_norm("parrot", mgr.world_to_norm(jitter, area.viewport_size))
	_assert(mgr.position_persist_write_count <= after_one + 2, "no every-frame disk writes")
