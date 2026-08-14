extends SceneTree
## Phase 1A pet architecture tests — catalog, ownership, persistence, actor load.
## Confirms production CHEST does not spawn pets yet (zero visible change).

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
	print("=== Pet system Phase 1A scaffold ===")
	_test_catalog()
	_test_manager_defaults_and_persistence()
	_test_pet_actor_scene()
	_test_no_chest_spawn_wiring()
	_test_asset_folders_and_docs()
	_test_regression_untouched()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_catalog() -> void:
	var catalog := PetCatalog.new()
	_assert(catalog.load_catalog(), "catalog JSON loads")
	_assert(catalog.has_pet("parrot"), "catalog contains parrot")
	_assert(catalog.all_ids().size() == 1, "catalog has exactly one pet")
	var def := catalog.get_definition("parrot")
	_assert(def != null, "parrot definition present")
	_assert(def.display_name == "Parrot", "display name Parrot")
	_assert(def.is_free(), "parrot unlock FREE")
	_assert(def.unlock_type == PetDefinition.UNLOCK_FREE, "unlock_type FREE const")
	_assert(def.default_unlocked, "parrot default_unlocked")
	_assert(def.enabled, "parrot enabled")
	_assert(def.asset_root.begins_with("res://assets/pets/parrot"), "asset_root set")
	_assert(catalog.default_unlocked_ids().has("parrot"), "default unlocked includes parrot")
	var raw := FileAccess.get_file_as_string("res://config/pets/catalog.json")
	_assert(not raw.contains("price"), "catalog has no fake prices")
	_assert(not raw.contains("sku"), "catalog has no billing SKUs")
	_assert(not raw.contains("PAID"), "catalog has no paid pets yet")


func _test_manager_defaults_and_persistence() -> void:
	## Isolate persistence path side effects under user:// for this test run.
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(mgr.is_owned("parrot"), "parrot owned by default")
	_assert(mgr.owned_pet_ids.has("parrot"), "owned list contains parrot")
	_assert(mgr.active_pet_id == "parrot", "active pet defaults to parrot")
	_assert(mgr.get_active_definition() != null, "active definition resolves")
	_assert(mgr.get_active_definition().is_free(), "active pet is FREE")
	_assert(not mgr.should_spawn_on_chest(), "CHEST spawn disabled in Phase 1A")
	_assert(mgr.spawn_active_pet(get_root()) == null, "spawn_active_pet returns null while gated")

	## Persistence round-trip: change active, reload.
	_assert(mgr.set_active_pet("parrot"), "set_active parrot ok")
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.is_owned("parrot"), "persisted ownership reload")
	_assert(mgr2.active_pet_id == "parrot", "persisted active pet reload")

	## AppState wires PetManager without UI.
	var state := AppState.new()
	state.bootstrap()
	_assert(state.pets != null, "AppState has pets manager")
	_assert(state.pets.is_owned("parrot"), "AppState bootstrap owns parrot")
	_assert(not state.pets.should_spawn_on_chest(), "AppState pets do not spawn on CHEST")


func _test_pet_actor_scene() -> void:
	_assert(ResourceLoader.exists("res://scenes/pets/PetActor.tscn"), "PetActor.tscn exists")
	_assert(ResourceLoader.exists("res://scripts/pets/pet_actor.gd"), "pet_actor.gd exists")
	_assert(ResourceLoader.exists("res://scripts/pets/pet_state.gd"), "pet_state.gd exists")
	_assert(ResourceLoader.exists("res://scripts/pets/pet_definition.gd"), "pet_definition.gd exists")
	_assert(ResourceLoader.exists("res://scripts/pets/pet_catalog.gd"), "pet_catalog.gd exists")
	_assert(ResourceLoader.exists("res://scripts/pets/pet_manager.gd"), "pet_manager.gd exists")
	var scene := load("res://scenes/pets/PetActor.tscn") as PackedScene
	_assert(scene != null, "PetActor PackedScene loads")
	var actor := scene.instantiate() as PetActor
	_assert(actor != null, "PetActor instantiates")
	get_root().add_child(actor)
	var def := PetDefinition.new()
	def.id = "parrot"
	def.display_name = "Parrot"
	def.unlock_type = PetDefinition.UNLOCK_FREE
	actor.setup_from_definition(def)
	_assert(actor.pet_id == "parrot", "actor pet_id set")
	_assert(actor.state == PetState.Kind.IDLE, "actor starts IDLE")
	_assert(actor.visible == false or actor.modulate.a == 0.0, "actor not visually presented")
	actor.transition_to(PetState.Kind.ROAM)
	_assert(actor.state == PetState.Kind.ROAM, "actor state machine accepts ROAM")
	actor.queue_free()


func _test_no_chest_spawn_wiring() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(not main.contains("spawn_active_pet"), "main does not spawn pets")
	_assert(not main.contains("PetActor"), "main does not reference PetActor")
	_assert(not main.contains("Pet Collection"), "no Pet Collection UI string")
	_assert(not main.contains("Pet Shop"), "no Pet Shop UI string")
	var mgr_src := FileAccess.get_file_as_string("res://scripts/pets/pet_manager.gd")
	_assert(mgr_src.contains("CHEST_SPAWN_ENABLED := false"), "spawn gate hard-false")
	_assert(not mgr_src.contains("BillingClient"), "no BillingClient")
	_assert(not mgr_src.contains("sku"), "no purchase SKUs in PetManager")


func _test_asset_folders_and_docs() -> void:
	_assert(DirAccess.open("res://assets/pets/parrot/idle") != null, "parrot idle dir")
	_assert(DirAccess.open("res://assets/pets/parrot/move") != null, "parrot move dir")
	_assert(DirAccess.open("res://assets/pets/parrot/chest_interaction") != null, "parrot chest_interaction dir")
	_assert(DirAccess.open("res://assets/pets/parrot/tap_reaction") != null, "parrot tap_reaction dir")
	_assert(DirAccess.open("res://assets/pets/parrot/source") != null, "parrot source dir")
	_assert(FileAccess.file_exists("res://assets/pets/parrot/PARROT_SPEC.md"), "PARROT_SPEC.md")
	_assert(FileAccess.file_exists("res://docs/PET_SYSTEM_PLAN.md"), "PET_SYSTEM_PLAN.md")
	_assert(FileAccess.file_exists("res://docs/PET_SAFE_AREA.md"), "PET_SAFE_AREA.md")
	_assert(FileAccess.file_exists("res://docs/KNOWN_GOOD_PRE_PET_BASELINE.md"), "KNOWN_GOOD_PRE_PET_BASELINE.md")


func _test_regression_untouched() -> void:
	## Spot-check locked systems remain present; Phase 1A must not strip them.
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "13-frame open intact")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "baked reveal intact")
	_assert(chest.contains("_play_baked_scroll_reveal"), "baked reveal method intact")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "chest ground intact")
	_assert(env.contains("default_beach"), "beach env intact")
	_assert(env.contains("WATER_TOP_FRAC"), "water band intact")
	_assert(main.contains("YOUR CHEST"), "YOUR CHEST hierarchy intact")
	_assert(main.contains("ChestEnvironment.CHEST_GROUND_Y"), "main chest plant intact")
	_assert(main.contains("disconnect_my_person") or FileAccess.get_file_as_string("res://scripts/network/friend_service.gd").contains("disconnect_my_person"), "disconnect path present")
	_assert(flags.contains("APP_VERSION_CODE := 61"), "versionCode unchanged at 61")
	_assert(flags.contains("0.1.61-baked-scroll-reveal"), "versionName unchanged")
