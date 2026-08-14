extends SceneTree
## v69 — Pet Store + gift delivery architecture tests.


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


func _wipe_pets() -> void:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)


func _run() -> void:
	print("=== v69 Pet Store + gift delivery ===")
	_test_version()
	_test_catalog()
	_test_clean_state()
	_test_migration_preserves_owned()
	await _test_self_delivery_flow()
	await _test_my_person_and_security()
	await _test_duplicate_pending()
	_test_profile_ui()
	_test_runtime_spawn_rules()
	_test_backend_migration()
	_test_behavior_weights_and_flight_gate()
	_test_regressions()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE == 71, "versionCode 71")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.71-android-backend-config-fix", "versionName 71")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("version/code=71"), "export versionCode 71")
	_assert(preset.contains("0.1.71-android-backend-config-fix"), "export versionName 71")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_assert(proj.contains("0.1.71-android-backend-config-fix"), "project.godot version")


func _test_catalog() -> void:
	var catalog := PetCatalog.new()
	_assert(catalog.load_catalog(), "catalog loads")
	_assert(catalog.has_pet("parrot"), "parrot in catalog")
	var def := catalog.get_definition("parrot")
	_assert(def != null and def.is_free(), "parrot FREE")
	_assert(def.price_type == "FREE", "price_type FREE")
	_assert(def.available_in_store, "available_in_store")
	_assert(not def.default_unlocked, "NOT default_unlocked")
	_assert(catalog.store_definitions().size() == 1, "store has parrot only")
	var raw := FileAccess.get_file_as_string("res://config/pets/catalog.json")
	_assert(not raw.contains("sku"), "no SKU")
	_assert(not raw.contains("PAID"), "no paid pets")
	_assert(not raw.contains("BillingClient"), "no billing")
	_assert(raw.contains("\"available_in_store\": true"), "store flag in JSON")
	_assert(raw.contains("\"default_unlocked\": false"), "default_unlocked false in JSON")


func _test_clean_state() -> void:
	_wipe_pets()
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(not mgr.is_owned("parrot"), "clean: no parrot ownership")
	_assert(mgr.owned_pet_ids.is_empty(), "clean: owned empty")
	_assert(mgr.active_pet_id.is_empty(), "clean: no active")
	_assert(not mgr.pet_enabled or not mgr.should_spawn_on_chest(), "clean: should not spawn")
	_assert(not mgr.should_spawn_on_chest(), "clean: should_spawn false")
	var env := Node2D.new()
	root.add_child(env)
	_assert(mgr.spawn_active_pet(env) == null, "clean: no PetActor")
	_assert(mgr.count_actors_under(env) == 0, "clean: zero actors")
	env.queue_free()
	## Profile selection: no Parrot choice when unowned.
	_assert(mgr.get_profile_pet_selection() == "off", "clean profile selection off")
	var state := AppState.new()
	state.bootstrap()
	_assert(not state.pets.is_owned("parrot"), "AppState clean unowned")
	_assert(state.pet_gifts != null, "AppState has pet_gifts service")


func _test_migration_preserves_owned() -> void:
	## Existing install that already owned parrot must keep it.
	var cfg := ConfigFile.new()
	cfg.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg.set_value("active", "id", "parrot")
	cfg.set_value("settings", "pet_enabled", true)
	cfg.save(PetManager.PERSIST_PATH)
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(mgr.is_owned("parrot"), "migration preserves owned parrot")
	_assert(mgr.active_pet_id == "parrot", "migration preserves active")
	_assert(mgr.pet_enabled == true, "migration preserves enabled")
	## Must NOT re-grant on second bootstrap if somehow cleared from catalog defaults.
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.is_owned("parrot"), "second load still owned once")
	var count := 0
	for id in mgr2.owned_pet_ids:
		if id == "parrot":
			count += 1
	_assert(count == 1, "no duplicate ownership after reload")


func _test_self_delivery_flow() -> void:
	_wipe_pets()
	var svc := PetGiftService.new(null)
	var sender := "demo-robert"
	## Get Free → send self → pending (no ownership yet).
	var send: Dictionary = await svc.send_pet_gift("parrot", sender, sender, true)
	_assert(bool(send.get("ok", false)), "self send ok")
	_assert(str(send.get("status", "")) == "pending", "self pending")
	_assert(not bool(send.get("duplicate", false)), "self not duplicate")
	_assert(svc.pending_count_for(sender) == 1, "one pending self gift")
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(not mgr.is_owned("parrot"), "ownership empty before claim")
	## Claim → ownership once; enabled stays Off until Profile.
	var gift := svc.first_pending_for(sender)
	var claim: Dictionary = await svc.claim_pet_gift(str(gift.get("delivery_id", gift.get("id", ""))), sender, true)
	_assert(bool(claim.get("ok", false)), "claim ok")
	_assert(str(claim.get("pet_id", "")) == "parrot", "claim pet parrot")
	mgr.grant_pet_from_claim("parrot", true)
	_assert(mgr.is_owned("parrot"), "owned after claim")
	_assert(mgr.pet_enabled == false, "Off after first claim")
	_assert(not mgr.should_spawn_on_chest(), "no spawn until enable")
	## Idempotent claim.
	var claim2: Dictionary = await svc.claim_pet_gift(str(gift.get("delivery_id", gift.get("id", ""))), sender, true)
	_assert(bool(claim2.get("ok", false)), "idempotent claim ok")
	_assert(bool(claim2.get("idempotent", false)) or str(claim2.get("code", "")) == "already_claimed", "idempotent flag")
	mgr.grant_pet_from_claim("parrot", true)
	var n := 0
	for id in mgr.owned_pet_ids:
		if id == "parrot":
			n += 1
	_assert(n == 1, "no duplicate ownership after double claim")
	## Enable → spawn one.
	_assert(mgr.select_profile_pet("parrot"), "enable parrot")
	_assert(mgr.should_spawn_on_chest(), "spawn after enable")
	var env := Node2D.new()
	root.add_child(env)
	var rt := mgr.ensure_pet_runtime_root(env)
	_assert(mgr.spawn_active_pet(rt) != null, "one PetActor")
	_assert(mgr.count_actors_under(env) == 1, "exactly one actor")
	mgr.despawn_active_pet()
	env.queue_free()


func _test_my_person_and_security() -> void:
	var svc := PetGiftService.new(null)
	svc.clear_local()
	var sender := "demo-robert"
	var person := "demo-mandy"
	var stranger := "demo-stranger"
	var send: Dictionary = await svc.send_pet_gift("parrot", sender, person, true)
	_assert(bool(send.get("ok", false)), "person send ok")
	_assert(str(send.get("recipient_user_id", "")) == person, "correct recipient")
	## Sender does not own from sending.
	_assert(not svc.is_locally_owned(sender, "parrot"), "sender not owned by send")
	## Recipient sees pending; stranger does not.
	_assert(svc.pending_count_for(person) == 1, "recipient pending visible")
	_assert(svc.pending_count_for(stranger) == 0, "stranger no inbox")
	var gift := svc.first_pending_for(person)
	var did := str(gift.get("delivery_id", gift.get("id", "")))
	## Unauthorized claim blocked.
	var bad: Dictionary = await svc.claim_pet_gift(did, stranger, true)
	_assert(not bool(bad.get("ok", false)), "stranger cannot claim")
	_assert(str(bad.get("code", "")) == "forbidden", "forbidden code")
	## Sender cannot claim recipient gift.
	var sender_claim: Dictionary = await svc.claim_pet_gift(did, sender, true)
	_assert(not bool(sender_claim.get("ok", false)), "sender cannot claim recipient gift")
	## Recipient claims once.
	var ok: Dictionary = await svc.claim_pet_gift(did, person, true)
	_assert(bool(ok.get("ok", false)), "recipient claim ok")
	_assert(svc.is_locally_owned(person, "parrot"), "recipient owned")
	_assert(svc.pending_count_for(person) == 0, "pending cleared")


func _test_duplicate_pending() -> void:
	var svc := PetGiftService.new(null)
	svc.clear_local()
	var a := "u1"
	var r1: Dictionary = await svc.send_pet_gift("parrot", a, a, true)
	var r2: Dictionary = await svc.send_pet_gift("parrot", a, a, true)
	_assert(bool(r1.get("ok", false)) and bool(r2.get("ok", false)), "both send calls ok")
	_assert(bool(r2.get("duplicate", false)) or str(r2.get("code", "")) == "already_pending", "duplicate pending")
	_assert(svc.pending_count_for(a) == 1, "still one pending")


func _test_profile_ui() -> void:
	_wipe_pets()
	var main_script := load("res://scripts/main.gd") as Script
	var main: Node = main_script.new()
	root.add_child(main)
	main.state = AppState.new()
	main.state.bootstrap()
	main.state.mode = AppState.Mode.LOCAL_DEMO
	main.state.demo.enable()
	main.state.pets.bootstrap()
	main._screen_host = Control.new()
	main.add_child(main._screen_host)
	## Unowned: no Parrot button.
	var section: VBoxContainer = main._build_profile_pets_section()
	main._screen_host.add_child(section)
	_assert(section.get_node_or_null("ProfilePetsEmpty") != null, "no pets yet label")
	_assert(section.get_node_or_null("ProfilePetChoiceParrot") == null, "Parrot not selectable unowned")
	_assert(_tree_has_button_text(section, ProductStrings.PET_STORE) or _tree_has_button_text(section, "Pet Store"), "Pet Store entry")
	section.queue_free()
	## Owned: Off + Parrot.
	main.state.pets.grant_pet_from_claim("parrot", true)
	var section2: VBoxContainer = main._build_profile_pets_section()
	main._screen_host.add_child(section2)
	_assert(section2.get_node_or_null("ProfilePetChoiceOff") != null, "Off after own")
	_assert(section2.get_node_or_null("ProfilePetChoiceParrot") != null, "Parrot after own")
	_assert(main.state.pets.get_profile_pet_selection() == "off", "starts Off after claim")
	var parrot_btn := section2.get_node_or_null("ProfilePetChoiceParrot") as Button
	parrot_btn.button_pressed = true
	_assert(main.state.pets.pet_enabled == true, "enable via Profile")
	var off_btn := section2.get_node_or_null("ProfilePetChoiceOff") as Button
	off_btn.button_pressed = true
	_assert(main.state.pets.pet_enabled == false, "Off persists ownership")
	_assert(main.state.pets.is_owned("parrot"), "owned while Off")
	## Store UI source checks.
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(src.contains("_show_pet_store"), "pet store screen")
	_assert(src.contains("_show_pet_recipient_picker"), "recipient picker")
	_assert(src.contains("PetRecipientMyself"), "Myself control")
	_assert(src.contains("PetRecipientMyPerson"), "My Person control")
	_assert(src.contains("_present_pet_gift_delivery"), "PET_GIFT presentation")
	_assert(src.contains("PET_GIFT") or src.contains("PetGift"), "pet gift branch")
	_assert(not src.contains("BillingClient"), "no billing in main")
	main.queue_free()


func _test_runtime_spawn_rules() -> void:
	_wipe_pets()
	var mgr := PetManager.new()
	mgr.bootstrap()
	var env := Node2D.new()
	root.add_child(env)
	_assert(mgr.count_actors_under(env) == 0, "zero before own")
	mgr.grant_pet_from_claim("parrot", true)
	_assert(mgr.spawn_active_pet(mgr.ensure_pet_runtime_root(env)) == null, "owned but Off → no actor")
	mgr.select_profile_pet("parrot")
	_assert(mgr.spawn_active_pet(mgr.ensure_pet_runtime_root(env)) != null, "owned+enabled → actor")
	_assert(mgr.count_actors_under(env) == 1, "one actor")
	mgr.select_profile_pet("off")
	_assert(mgr.count_actors_under(env) == 0, "Off → zero actors")
	mgr.despawn_active_pet()
	env.queue_free()


func _test_backend_migration() -> void:
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260814120000_pet_store_delivery.sql")
	_assert(mig.contains("create table if not exists public.pet_catalog"), "pet_catalog")
	_assert(mig.contains("create table if not exists public.pet_deliveries"), "pet_deliveries")
	_assert(mig.contains("create table if not exists public.user_pet_ownership"), "ownership table")
	_assert(mig.contains("send_pet_gift"), "send RPC")
	_assert(mig.contains("list_pending_pet_gifts"), "list RPC")
	_assert(mig.contains("claim_pet_gift"), "claim RPC")
	_assert(mig.contains("pet_deliveries_unique_pending"), "spam unique index")
	_assert(mig.contains("primary key (user_id, pet_id)"), "ownership unique")
	_assert(mig.contains("enable row level security"), "RLS")
	_assert(mig.contains("_pet_users_are_paired"), "pair check")
	_assert(not mig.contains("disconnect_my_person"), "does not redefine disconnect")
	_assert(not mig.contains("my_person_pair_ends"), "does not touch pair ends")
	var svc := FileAccess.get_file_as_string("res://scripts/network/pet_gift_service.gd")
	_assert(svc.contains("send_pet_gift"), "client send")
	_assert(svc.contains("claim_pet_gift"), "client claim")
	_assert(svc.contains("REWARD_PET_GIFT"), "PET_GIFT reward type")
	_assert(not svc.contains("BillingClient"), "no billing client")


func _test_behavior_weights_and_flight_gate() -> void:
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_SHORT_ROAM_WEIGHT, 0.35), "short 35%")
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_MEDIUM_ROAM_WEIGHT, 0.30), "medium 30%")
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_CROSS_ROAM_WEIGHT, 0.20), "cross 20%")
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_CHEST_WEIGHT, 0.10), "chest 10%")
	_assert(is_equal_approx(PetRuntimeConfig.BEHAVIOR_LONG_IDLE_WEIGHT, 0.05), "long idle 5%")
	_assert(PetRuntimeConfig.PET_FLIGHT_ENABLED == false, "flight disabled")
	_assert(PetRuntimeConfig.PET_FLIGHT_VISUALS_READY == false, "flight visuals not ready")
	var actor_src := FileAccess.get_file_as_string("res://scripts/pets/pet_actor.gd")
	_assert(actor_src.contains("_pick_ground_behavior"), "behavior picker")
	_assert(actor_src.contains("TAKEOFF") or actor_src.contains("Kind.TAKEOFF"), "takeoff arch")
	var safe := FileAccess.get_file_as_string("res://scripts/pets/pet_safe_area.gd")
	_assert(safe.contains("RoamRegion.LEFT"), "LEFT region")
	_assert(safe.contains("RoamRegion.RIGHT"), "RIGHT region")
	_assert(safe.contains("roam_kind"), "roam kind routing")


func _test_regressions() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "13-frame open")
	_assert(chest.contains("_play_baked_scroll_reveal"), "baked scroll intact")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	_assert(friends.contains("disconnect_my_person"), "disconnect intact")
	var disconnect_mig := FileAccess.get_file_as_string("res://supabase/migrations/20260812150000_disconnect_my_person_rpc.sql")
	_assert(disconnect_mig.contains("create or replace function public.disconnect_my_person()"), "disconnect RPC file intact")
	_assert(FileAccess.file_exists("res://docs/PET_STORE_GIFT_DELIVERY.md"), "docs present")
	_assert(FileAccess.file_exists("res://assets/pets/parrot/idle/parrot_idle_00.png"), "approved idle art")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(not main.contains("Pet Shop"), "no Pet Shop string")
	_assert(main.contains("Pet Store") or main.contains("PET_STORE"), "Pet Store present")


func _tree_has_button_text(n: Node, needle: String) -> bool:
	if n is Button and str((n as Button).text).contains(needle):
		return true
	for c in n.get_children():
		if _tree_has_button_text(c, needle):
			return true
	return false
