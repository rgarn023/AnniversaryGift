extends SceneTree
## v69 — Pet Store + gift delivery UI/runtime captures.
## Prefer Xvfb (not --headless) so Viewport.get_texture() works for PNGs.

const OUT_DIR := "/tmp/v69_pet_store_gift"
const ART_DIR := "/opt/cursor/artifacts/v69_pet_store_gift"
const VP := Vector2i(390, 844)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	DisplayServer.window_set_size(VP)
	print("=== v69 PET STORE + GIFT CAPTURE ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME, " code=", BuildFlags.APP_VERSION_CODE)
	print("NOTE: dedicated pet-delivery emergence animation artwork still needed")

	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)

	var main_script := load("res://scripts/main.gd") as Script
	var main: Node = main_script.new()
	root.add_child(main)
	## Wait out Charoite cold boot so captures are not the studio splash.
	for _i in range(360):
		if bool(main.get("_startup_done")):
			break
		await process_frame
	## Force demo pet-store path for captures (overwrite post-boot state).
	main.state.mode = AppState.Mode.LOCAL_DEMO
	main.state.demo.enable()
	var wipe2 := ConfigFile.new()
	wipe2.save(PetManager.PERSIST_PATH)
	main.state.pets.bootstrap()
	main.state.pet_gifts.clear_local()
	## Ensure screen host exists (boot may have navigated to welcome).
	if main._screen_host == null or not is_instance_valid(main._screen_host):
		main._screen_host = Control.new()
		main._screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main._screen_host.custom_minimum_size = Vector2(VP)
		main.add_child(main._screen_host)
	## Hide any leftover boot overlays.
	for c in main.get_children():
		if c is CharoiteBoot or str(c.get_class()).contains("Charoite"):
			c.visible = false
			c.queue_free()
	main._screen_host.modulate.a = 1.0
	main._screen_host.visible = true
	main._screen_host.z_index = 50
	print("startup_done=", main.get("_startup_done"), " screen=", main._current_screen)

	## 1) Profile with no pets
	_clear_host(main)
	_ensure_capture_bg(main)
	var no_pets: Control = main._build_profile_pets_section()
	main._screen_host.add_child(no_pets)
	main._screen_host.modulate.a = 1.0
	await _settle(8)
	await _snap(main, "profile_no_pets.png")

	## 2) Pet Store (direct builder path — avoid splash race)
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
	store_col.add_child(main._build_pet_store_card(def))
	main._screen_host.modulate.a = 1.0
	await _settle(12)
	await _snap(main, "pet_store.png")

	## 3) Recipient picker
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

	## 4) CHEST before pet (clean ownership)
	_clear_host(main)
	await main._show_main_chest()
	main._screen_host.modulate.a = 1.0
	await _settle(16)
	var actors_before := 0
	if main.state.pets != null:
		actors_before = main.state.pets.count_actors_under(main._screen_host)
	print("actors_before_claim=", actors_before)
	await _snap(main, "chest_before_pet.png")

	## 5) Self-send → pending gift → chest badge
	var uid: String = main.state.current_user_id()
	var send: Dictionary = await main.state.pet_gifts.send_pet_gift("parrot", uid, uid, true)
	print("self_send=", send)
	await main.state.refresh_pending_pet_gifts()
	_clear_host(main)
	await main._show_main_chest()
	main._screen_host.modulate.a = 1.0
	await _settle(16)
	await _snap(main, "chest_pet_delivery_pending.png")

	## 6) Open gift presentation (simulate claim overlay path)
	var gift: Dictionary = main.state.first_pending_pet_gift()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main._screen_host.add_child(dim)
	await main._present_pet_gift_delivery(gift, dim)
	main._screen_host.modulate.a = 1.0
	await _settle(10)
	await _snap(main, "chest_pet_delivery_open.png")

	## 7) Profile owned Off/Parrot
	_clear_host(main)
	main._show_profile()
	main._screen_host.modulate.a = 1.0
	await _settle(18)
	await _snap(main, "profile_parrot_owned.png")

	## 8) Enable + CHEST with one parrot
	main.state.pets.select_profile_pet("parrot")
	_clear_host(main)
	await main._show_main_chest()
	main._screen_host.modulate.a = 1.0
	await _settle(20)
	var actors_after: int = main.state.pets.count_actors_under(main._screen_host)
	print("actors_after_enable=", actors_after)
	await _snap(main, "chest_after_pet_enabled.png")

	print("=== CAPTURE COMPLETE artifacts under ", ART_DIR, " ===")
	quit(0 if actors_before == 0 and actors_after == 1 else 1)


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
