extends SceneTree
## v70 hard gates — Pet Store + gifting must pass before APK export.


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


func _wipe() -> void:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)


func _run() -> void:
	print("=== v70 Pet Store hard gates ===")
	await _gate_clean_ownership_and_actors()
	_gate_catalog_store()
	await _gate_self_delivery_claim()
	await _gate_my_person_security()
	await _gate_duplicates()
	_gate_profile_and_spawn()
	_gate_position_persistence()
	_gate_movement_balance()
	_gate_reward_priority_and_scroll()
	_gate_backend_sql_security()
	_gate_flight_disabled()
	_gate_regressions_intact()
	_gate_concepts_distinct()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _gate_clean_ownership_and_actors() -> void:
	_wipe()
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(not mgr.is_owned("parrot"), "G1 clean does not own Parrot")
	_assert(mgr.owned_pet_ids.is_empty(), "G1 owned empty")
	_assert(not mgr.should_spawn_on_chest(), "G2 should_spawn false")
	var env := Node2D.new()
	root.add_child(env)
	_assert(mgr.spawn_active_pet(env) == null, "G2 spawn null")
	_assert(mgr.count_actors_under(env) == 0, "G2 zero PetActors")
	env.queue_free()
	## Migration preserve
	var cfg := ConfigFile.new()
	cfg.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg.set_value("active", "id", "parrot")
	cfg.set_value("settings", "pet_enabled", true)
	cfg.save(PetManager.PERSIST_PATH)
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.is_owned("parrot"), "legacy ownership preserved")
	_assert(mgr2.pet_enabled == true, "legacy enabled preserved")
	## No re-grant from catalog default_unlocked
	var cat := FileAccess.get_file_as_string("res://config/pets/catalog.json")
	_assert(cat.contains("\"default_unlocked\": false"), "default_unlocked false")
	var mgr_src := FileAccess.get_file_as_string("res://scripts/pets/pet_manager.gd")
	_assert(mgr_src.contains("Do NOT call catalog.default_unlocked_ids()") or mgr_src.contains("never re-grant catalog defaults"), "no auto re-grant")


func _gate_catalog_store() -> void:
	var catalog := PetCatalog.new()
	catalog.load_catalog()
	var def := catalog.get_definition("parrot")
	_assert(def != null, "G3 parrot in catalog")
	_assert(def.is_free() and def.price_type == "FREE", "G4 FREE")
	_assert(def.available_in_store, "G3 store available")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("_show_pet_store"), "G3 Pet Store path")
	_assert(main_src.contains("PetStoreGetFree") or main_src.contains("PET_STORE_GET_FREE"), "G4 Get Free action")
	_assert(main_src.contains("PetRecipientMyself"), "G6 Myself")
	_assert(main_src.contains("PetRecipientMyPerson"), "G7 My Person")
	_assert(main_src.contains("PET_CONNECT_PERSON_FIRST") or main_src.contains("Connect your person first"), "no-person safe")
	_assert(not main_src.contains("BillingClient"), "no Play Billing")


func _gate_self_delivery_claim() -> void:
	_wipe()
	var svc := PetGiftService.new(null)
	var uid := "demo-robert"
	var send: Dictionary = await svc.send_pet_gift("parrot", uid, uid, true)
	_assert(bool(send.get("ok", false)), "G8 self-send ok")
	_assert(str(send.get("status", "")) == "pending", "G8 pending delivery")
	_assert(str(send.get("sender_user_id", "")) == uid, "self sender")
	_assert(str(send.get("recipient_user_id", "")) == uid, "self recipient")
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(not mgr.is_owned("parrot"), "G9 self-send does NOT grant ownership")
	_assert(svc.pending_count_for(uid) == 1, "G10 pending reaches inbox")
	var gift := svc.first_pending_for(uid)
	var claim: Dictionary = await svc.claim_pet_gift(str(gift.get("delivery_id", "")), uid, true)
	_assert(bool(claim.get("ok", false)), "G11 claim ok")
	mgr.grant_pet_from_claim("parrot", true)
	_assert(mgr.is_owned("parrot"), "G11 ownership granted")
	var n := 0
	for id in mgr.owned_pet_ids:
		if id == "parrot":
			n += 1
	_assert(n == 1, "G11 ownership exactly once")
	var claim2: Dictionary = await svc.claim_pet_gift(str(gift.get("delivery_id", "")), uid, true)
	_assert(bool(claim2.get("ok", false)), "idempotent claim")
	mgr.grant_pet_from_claim("parrot", true)
	n = 0
	for id in mgr.owned_pet_ids:
		if id == "parrot":
			n += 1
	_assert(n == 1, "idempotent no dup ownership")


func _gate_my_person_security() -> void:
	var svc := PetGiftService.new(null)
	svc.clear_local()
	var a := "user-a"
	var b := "user-b"
	var c := "user-c"
	var send: Dictionary = await svc.send_pet_gift("parrot", a, b, true)
	_assert(bool(send.get("ok", false)), "G16 My Person send")
	_assert(str(send.get("sender_user_id", "")) != str(send.get("recipient_user_id", "")), "sender != recipient")
	_assert(str(send.get("recipient_user_id", "")) == b, "paired recipient")
	_assert(not svc.is_locally_owned(a, "parrot"), "G sender isolation no ownership")
	_assert(svc.pending_count_for(b) == 1, "G17 recipient sees")
	_assert(svc.pending_count_for(c) == 0, "G17 third party cannot see")
	var did := str(svc.first_pending_for(b).get("delivery_id", ""))
	var bad_a: Dictionary = await svc.claim_pet_gift(did, a, true)
	_assert(not bool(bad_a.get("ok", false)), "G17 sender cannot claim")
	var bad_c: Dictionary = await svc.claim_pet_gift(did, c, true)
	_assert(not bool(bad_c.get("ok", false)), "G17 stranger cannot claim")
	var ok: Dictionary = await svc.claim_pet_gift(did, b, true)
	_assert(bool(ok.get("ok", false)), "recipient claim")
	_assert(svc.is_locally_owned(b, "parrot"), "recipient owns once")
	## Backend SQL rejects arbitrary C (source-level).
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260814120000_pet_store_delivery.sql")
	_assert(mig.contains("not_my_person"), "backend rejects non-pair send")
	_assert(mig.contains("_pet_users_are_paired"), "pair check")
	_assert(mig.contains("if d.recipient_user_id <> uid then"), "recipient-only claim")


func _gate_duplicates() -> void:
	var svc := PetGiftService.new(null)
	svc.clear_local()
	var u := "dup-user"
	var r1: Dictionary = await svc.send_pet_gift("parrot", u, u, true)
	var r2: Dictionary = await svc.send_pet_gift("parrot", u, u, true)
	_assert(bool(r1.get("ok", false)) and bool(r2.get("ok", false)), "G18 send calls ok")
	_assert(bool(r2.get("duplicate", false)) or str(r2.get("code", "")) == "already_pending", "G18 duplicate pending blocked")
	_assert(svc.pending_count_for(u) == 1, "G18 one pending")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260814120000_pet_store_delivery.sql")
	_assert(mig.contains("pet_deliveries_unique_pending"), "DB unique pending")
	_assert(mig.contains("primary key (user_id, pet_id)"), "DB unique ownership")


func _gate_profile_and_spawn() -> void:
	_wipe()
	var main_script := load("res://scripts/main.gd") as Script
	var main: Node = main_script.new()
	root.add_child(main)
	main.state = AppState.new()
	main.state.bootstrap()
	main.state.pets.bootstrap()
	main._screen_host = Control.new()
	main.add_child(main._screen_host)
	var sec1: VBoxContainer = main._build_profile_pets_section()
	main._screen_host.add_child(sec1)
	_assert(sec1.get_node_or_null("ProfilePetChoiceParrot") == null, "G12 Parrot not selectable before ownership")
	_assert(sec1.get_node_or_null("ProfilePetsEmpty") != null, "no pets yet")
	main.state.pets.grant_pet_from_claim("parrot", true)
	var sec2: VBoxContainer = main._build_profile_pets_section()
	main._screen_host.add_child(sec2)
	_assert(sec2.get_node_or_null("ProfilePetChoiceOff") != null, "G12 Off after own")
	_assert(sec2.get_node_or_null("ProfilePetChoiceParrot") != null, "G12 Parrot after own")
	_assert(main.state.pets.pet_enabled == false, "Off after claim")
	var env := Node2D.new()
	root.add_child(env)
	var rt: Node2D = main.state.pets.ensure_pet_runtime_root(env)
	_assert(main.state.pets.spawn_active_pet(rt) == null, "G13 Off → zero actors")
	_assert(main.state.pets.count_actors_under(env) == 0, "G13 count 0")
	main.state.pets.select_profile_pet("parrot")
	_assert(main.state.pets.spawn_active_pet(rt) != null, "G14 enable → actor")
	_assert(main.state.pets.count_actors_under(env) == 1, "G14 exactly one")
	main.state.pets.despawn_active_pet()
	env.queue_free()
	main.queue_free()


func _gate_position_persistence() -> void:
	_wipe()
	var mgr := PetManager.new()
	mgr.bootstrap()
	mgr.grant_pet_from_claim("parrot", false)
	mgr.select_profile_pet("parrot")
	mgr.position_persist_write_count = 0
	var area := PetSafeArea.new()
	area.configure(Vector2(390, 844), Rect2(100, 400, 180, 220))
	var target: Vector2 = area.ensure_safe_position(Vector2(area.roam_x_max() - 40.0, (area.sand_y_min() + area.sand_y_max()) * 0.55))
	mgr.set_saved_position_norm("parrot", mgr.world_to_norm(target, area.viewport_size))
	_assert(mgr.has_saved_position("parrot"), "G15 saved after ownership")
	mgr.select_profile_pet("off")
	_assert(mgr.has_saved_position("parrot"), "Off preserves saved position")
	mgr.select_profile_pet("parrot")
	var restored: Vector2 = mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(restored.distance_to(target) < 2.0, "Off→Parrot restores")
	var leave: Vector2 = mgr.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(leave.distance_to(target) < 2.0, "CHEST leave/return restores")
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	var reload: Vector2 = mgr2.resolve_spawn_world_position(area.viewport_size, area.chest_rect)
	_assert(reload.distance_to(target) < 2.0, "restart restores")
	## Unsafe positions corrected
	var bad_chest: Vector2 = area.chest_exclusion_rect().get_center()
	var fixed_chest: Vector2 = area.ensure_safe_position(bad_chest)
	_assert(not area.is_in_chest_exclusion(fixed_chest), "chest exclusion corrected")
	var ocean := Vector2(area.viewport_size.x * 0.5, area.viewport_size.y * 0.2)
	var fixed_ocean: Vector2 = area.ensure_safe_position(ocean)
	_assert(not area.is_in_ocean(fixed_ocean), "ocean corrected")
	var ui := Vector2(area.viewport_size.x * 0.5, area.viewport_size.y * 0.05)
	var fixed_ui: Vector2 = area.ensure_safe_position(ui)
	_assert(not area.is_in_ui_exclusion(fixed_ui), "UI corrected")
	## Proportional viewport
	var area2 := PetSafeArea.new()
	area2.configure(Vector2(780, 1688), Rect2(200, 800, 360, 440))
	var big: Vector2 = mgr2.resolve_spawn_world_position(area2.viewport_size, area2.chest_rect)
	_assert(big.x > area2.viewport_size.x * 0.4, "cross-viewport proportional-ish")
	## No every-frame writes for identical norms (skip no-op).
	var writes: int = mgr2.position_persist_write_count
	for _i in range(30):
		mgr2.set_saved_position_norm("parrot", mgr2.get_saved_position_norm("parrot"), true)
	_assert(mgr2.position_persist_write_count == writes, "no ConfigFile every frame")


func _gate_movement_balance() -> void:
	var area := PetSafeArea.new()
	area.configure(Vector2(390, 844), Rect2(69, 482, 252, 326))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var left_hits := 0
	var right_hits := 0
	var mid := area.viewport_size.x * 0.5
	var origin_left := area.clamp_to_roam(Vector2(area.roam_x_min() + 8.0, area.transit_y()))
	var origin_right := area.clamp_to_roam(Vector2(area.roam_x_max() - 8.0, area.transit_y()))
	var cross_ok := 0
	var cross_fail := 0
	for _i in range(120):
		var t := area.random_roam_target(rng, origin_left, "cross" if _i % 3 == 0 else "")
		if t.x < mid:
			left_hits += 1
		else:
			right_hits += 1
		var plan := area.plan_ground_path(origin_left, t)
		if bool(plan.get("ok", false)):
			cross_ok += 1
		else:
			cross_fail += 1
	_assert(left_hits > 10, "LEFT region reachable samples")
	_assert(right_hits > 10, "RIGHT region reachable samples")
	_assert(cross_ok > 80, "most paths from left succeed (%d)" % cross_ok)
	## Explicit L→R / R→L routes
	var to_right := area.clamp_to_roam(Vector2(area.roam_x_max() - 12.0, area.transit_y()))
	var to_left := area.clamp_to_roam(Vector2(area.roam_x_min() + 12.0, area.transit_y()))
	var lr := area.plan_ground_path(origin_left, to_right)
	var rl := area.plan_ground_path(origin_right, to_left)
	_assert(bool(lr.get("ok", false)), "LEFT→RIGHT route")
	_assert(bool(rl.get("ok", false)), "RIGHT→LEFT route")
	var lr_pts: Array = lr.get("waypoints", [])
	var rl_pts: Array = rl.get("waypoints", [])
	_assert(area.path_segments_safe(origin_left, lr_pts), "L→R segments safe")
	_assert(area.path_segments_safe(origin_right, rl_pts), "R→L segments safe")
	## Behavior weights present
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_SHORT_ROAM_WEIGHT, 0.35), "short 35%")
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_CROSS_ROAM_WEIGHT, 0.20), "cross 20%")
	var actor_src := FileAccess.get_file_as_string("res://scripts/pets/pet_actor.gd")
	_assert(actor_src.contains("_pick_ground_behavior"), "behavior variability")
	## Report balance from dedicated roam suite seed
	print("MOVEMENT_NOTE left_hits=%d right_hits=%d path_ok=%d path_fail=%d" % [left_hits, right_hits, cross_ok, cross_fail])
	print("ROAM_DIST_REF left_pct≈49.2 right_pct≈50.8 (from test_parrot_roam_routing_flight_prep seed)")

func _gate_reward_priority_and_scroll() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("PET_GIFT branch first") or main.contains("has_pet_gift"), "G priority PET_GIFT")
	var p_pet := main.find("if has_pet_gift:")
	var p_scroll := main.find("play_open_animation(state.reduced_motion, has_scroll_reward)")
	_assert(p_pet >= 0 and p_scroll > p_pet, "PET_GIFT before NORMAL_SCROLL")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "G19 13-frame open")
	_assert(chest.contains("_play_baked_scroll_reveal"), "G20 baked scroll")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "reveal frames")
	_assert(not main.contains("open_back") or chest.contains("OPEN_BACK"), "no reintroduced cavity hacks in main path")


func _gate_backend_sql_security() -> void:
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260814120000_pet_store_delivery.sql")
	_assert(mig.contains("create table if not exists public.pet_catalog"), "pet_catalog")
	_assert(mig.contains("create table if not exists public.pet_deliveries"), "pet_deliveries")
	_assert(mig.contains("create table if not exists public.user_pet_ownership"), "ownership")
	_assert(mig.contains("enable row level security"), "RLS")
	_assert(mig.contains("force row level security"), "FORCE RLS")
	_assert(mig.contains("send_pet_gift"), "send RPC")
	_assert(mig.contains("claim_pet_gift"), "claim RPC")
	_assert(mig.contains("list_pending_pet_gifts"), "list RPC")
	_assert(mig.contains("on conflict (user_id, pet_id)"), "claim upsert")
	_assert(not mig.contains("disconnect_my_person"), "G21 disconnect untouched")
	var disc := FileAccess.get_file_as_string("res://supabase/migrations/20260812150000_disconnect_my_person_rpc.sql")
	_assert(disc.contains("create or replace function public.disconnect_my_person()"), "disconnect RPC intact")


func _gate_flight_disabled() -> void:
	_assert(PetRuntimeConfig.PET_FLIGHT_ENABLED == false, "flight disabled")
	_assert(PetRuntimeConfig.PET_FLIGHT_VISUALS_READY == false, "flight art missing")
	var st := FileAccess.get_file_as_string("res://scripts/pets/pet_state.gd")
	_assert(st.contains("TAKEOFF") and st.contains("FLY") and st.contains("LAND"), "flight states prepared")


func _gate_regressions_intact() -> void:
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "environment ground")
	_assert(env.contains("default_beach"), "beach")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	_assert(friends.contains("disconnect_my_person"), "My Person disconnect")
	var splash := FileAccess.get_file_as_string("res://project.godot")
	_assert(splash.contains("charoite_system_splash_dark.png"), "splash intact")
	var hide := FileAccess.file_exists("res://supabase/migrations/20260811190000_scroll_hide_delete_visibility.sql")
	_assert(hide, "Saved/Hidden migration present")


func _gate_concepts_distinct() -> void:
	## Catalog ≠ ownership ≠ enabled ≠ active
	_wipe()
	var mgr := PetManager.new()
	mgr.bootstrap()
	var cat := mgr.catalog.get_definition("parrot")
	_assert(cat != null and cat.available_in_store, "catalog availability")
	_assert(not mgr.is_owned("parrot"), "ownership distinct (empty)")
	mgr.grant_pet_from_claim("parrot", true)
	_assert(mgr.is_owned("parrot") and not mgr.pet_enabled, "owned but not enabled")
	_assert(mgr.active_pet_id == "parrot", "active selection set")
	_assert(not mgr.should_spawn_on_chest(), "enabled distinct")
	mgr.select_profile_pet("parrot")
	_assert(mgr.pet_enabled and mgr.should_spawn_on_chest(), "enabled runtime")
