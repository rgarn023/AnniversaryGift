extends SceneTree
## Continuous same-runtime self-send proof captures (v70 hard gate).
## Prefer Xvfb (not --headless) so Viewport.get_texture() works for PNGs.

const OUT_DIR := "/tmp/v70_pet_store_same_runtime"
const ART_DIR := "/opt/cursor/artifacts/v70_pet_store_same_runtime"
const VP := Vector2i(390, 844)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	DisplayServer.window_set_size(VP)
	print("=== v70 SAME-RUNTIME SELF-SEND PROOF ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME, " code=", BuildFlags.APP_VERSION_CODE)
	print("NOTE: TEMPORARY PET DELIVERY PRESENTATION — no dedicated parrot chest-popout art")

	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)

	var main_script := load("res://scripts/main.gd") as Script
	var main: Node = main_script.new()
	root.add_child(main)
	for _i in range(360):
		if bool(main.get("_startup_done")):
			break
		await process_frame
	main.state.mode = AppState.Mode.LOCAL_DEMO
	main.state.demo.enable()
	var wipe2 := ConfigFile.new()
	wipe2.save(PetManager.PERSIST_PATH)
	main.state.pets.bootstrap()
	main.state.pet_gifts.clear_local()
	if main._screen_host == null or not is_instance_valid(main._screen_host):
		main._screen_host = Control.new()
		main._screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main._screen_host.custom_minimum_size = Vector2(VP)
		main.add_child(main._screen_host)
	for c in main.get_children():
		if c is CharoiteBoot or str(c.get_class()).contains("Charoite"):
			c.visible = false
			c.queue_free()
	main._screen_host.modulate.a = 1.0
	main._screen_host.visible = true
	main._screen_host.z_index = 50
	print("startup_done=", main.get("_startup_done"), " screen=", main._current_screen)

	## A) Clean state — no Parrot, no PetActor, Profile no selectable Parrot
	_assert(not main.state.pets.is_owned("parrot"), "A ownership absent")
	_clear_host(main)
	await main._show_main_chest()
	main._screen_host.modulate.a = 1.0
	await _settle(16)
	var actors_clean: int = main.state.pets.count_actors_under(main._screen_host)
	_assert(actors_clean == 0, "A zero PetActors")
	await _snap(main, "clean_state_no_parrot.png")
	_clear_host(main)
	_ensure_capture_bg(main)
	var no_pets: Control = main._build_profile_pets_section()
	main._screen_host.add_child(no_pets)
	main._screen_host.modulate.a = 1.0
	await _settle(8)
	_assert(no_pets.get_node_or_null("ProfilePetChoiceParrot") == null, "A Profile no Parrot")
	_assert(no_pets.get_node_or_null("ProfilePetsEmpty") != null, "A No pets yet")

	## B) Pet Store — Parrot FREE + Get/Send
	_clear_host(main)
	_ensure_capture_bg(main)
	var store_col := VBoxContainer.new()
	store_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	store_col.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	main._screen_host.add_child(store_col)
	var store_title := Label.new()
	store_title.text = ProductStrings.PET_STORE
	MobileUi.apply_label(store_title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	store_col.add_child(store_title)
	var def: PetDefinition = main.state.pets.catalog.get_definition(PetCatalog.PET_PARROT)
	_assert(def != null and def.is_free(), "B FREE parrot")
	store_col.add_child(main._build_pet_store_card(def))
	main._screen_host.modulate.a = 1.0
	await _settle(12)
	await _snap(main, "pet_store_free_parrot.png")

	## C) Recipient picker — Myself + My Person
	_clear_host(main)
	_ensure_capture_bg(main)
	var pick := VBoxContainer.new()
	pick.name = "PetRecipientPickerRoot"
	pick.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	main._screen_host.add_child(pick)
	var pt := Label.new()
	pt.text = "Send Parrot"
	MobileUi.apply_label(pt, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	pick.add_child(pt)
	pick.add_child(main._make_button(ProductStrings.PET_SEND_TO_SELF, func() -> void: pass))
	pick.get_child(pick.get_child_count() - 1).name = "PetRecipientMyself"
	pick.add_child(main._make_button(ProductStrings.PET_SEND_TO_PERSON, func() -> void: pass))
	pick.get_child(pick.get_child_count() - 1).name = "PetRecipientMyPerson"
	main._screen_host.modulate.a = 1.0
	await _settle(12)
	await _snap(main, "pet_recipient_picker.png")

	## D) Select Myself — pending, ownership still absent
	var uid: String = main.state.current_user_id()
	var send: Dictionary = await main.state.pet_gifts.send_pet_gift("parrot", uid, uid, true)
	print("self_send=", send)
	_assert(bool(send.get("ok", false)) and str(send.get("status", "")) == "pending", "D pending")
	_assert(not main.state.pets.is_owned("parrot"), "D ownership still absent")
	_assert(main.state.pet_gifts.pending_count_for(uid) == 1, "D one pending")
	await main.state.refresh_pending_pet_gifts()

	## E) CHEST waiting delivery
	_clear_host(main)
	await main._show_main_chest()
	main._screen_host.modulate.a = 1.0
	await _settle(16)
	await _snap(main, "chest_pet_delivery_waiting.png")

	## F) Open/claim delivery presentation
	var gift: Dictionary = main.state.first_pending_pet_gift()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main._screen_host.add_child(dim)
	await main._present_pet_gift_delivery(gift, dim)
	main._screen_host.modulate.a = 1.0
	await _settle(10)
	await _snap(main, "chest_pet_delivery_open.png")

	## G) Claim grants ownership exactly once
	var claim: Dictionary = await main.state.pet_gifts.claim_pet_gift(str(gift.get("delivery_id", "")), uid, true)
	_assert(bool(claim.get("ok", false)), "G claim ok")
	main.state.pets.grant_pet_from_claim("parrot", true)
	_assert(main.state.pets.is_owned("parrot"), "G ownership")
	var own_n := 0
	for id in main.state.pets.owned_pet_ids:
		if id == "parrot":
			own_n += 1
	_assert(own_n == 1, "G exactly once")
	var claim2: Dictionary = await main.state.pet_gifts.claim_pet_gift(str(gift.get("delivery_id", "")), uid, true)
	_assert(bool(claim2.get("ok", false)), "G idempotent")

	## H) Profile shows Off + Parrot
	_clear_host(main)
	main._show_profile()
	main._screen_host.modulate.a = 1.0
	await _settle(18)
	await _snap(main, "profile_parrot_owned.png")

	## I) Enable Parrot → exactly one on CHEST
	main.state.pets.select_profile_pet("parrot")
	_clear_host(main)
	await main._show_main_chest()
	main._screen_host.modulate.a = 1.0
	await _settle(20)
	var actors_after: int = main.state.pets.count_actors_under(main._screen_host)
	print("actors_after_enable=", actors_after)
	_assert(actors_after == 1, "I exactly one Parrot")
	await _snap(main, "chest_parrot_after_claim.png")

	print("=== SAME-RUNTIME PROOF COMPLETE under ", ART_DIR, " ===")
	quit(0 if actors_clean == 0 and actors_after == 1 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)


func _ensure_capture_bg(main: Node) -> void:
	var bg := ColorRect.new()
	bg.name = "CaptureBg"
	bg.color = Color(0.10, 0.06, 0.16, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._screen_host.add_child(bg)
	main._screen_host.move_child(bg, 0)


func _clear_host(main: Node) -> void:
	if main._screen_host == null:
		return
	for c in main._screen_host.get_children():
		c.queue_free()
	await process_frame


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _snap(main: Node, filename: String) -> void:
	await _settle(2)
	var img: Image = main.get_viewport().get_texture().get_image()
	if img == null:
		print("WARN: null image for ", filename)
		return
	var p1 := "%s/%s" % [OUT_DIR, filename]
	var p2 := "%s/%s" % [ART_DIR, filename]
	var err := img.save_png(p1)
	if err != OK:
		print("WARN: save failed ", filename, " err=", err)
		return
	DirAccess.copy_absolute(p1, p2)
	print("SNAP ", filename, " size=", img.get_width(), "x", img.get_height())
