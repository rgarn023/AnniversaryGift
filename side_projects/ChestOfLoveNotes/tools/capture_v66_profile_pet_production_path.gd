extends SceneTree
## v66 — SAME-RUNTIME proof: v63 migration parrot + production Profile Off/Parrot.
## Uses Main._show_profile / Main._show_main_chest (bottom-nav production path).
## Must run under Xvfb (not --headless) so Viewport.get_texture() works.

const OUT_DIR := "/tmp/v66_profile_pet_production_path"
const ART_DIR := "/opt/cursor/artifacts/v66_profile_pet_production_path"
const VP := Vector2i(390, 844)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	DisplayServer.window_set_size(VP)

	var fail := 0
	print("=== v66 SAME-RUNTIME PRODUCTION PATH PROOF ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME, " code=", BuildFlags.APP_VERSION_CODE)

	fail += _assert_source_wiring()

	## Simulate physically-verified v63 save: owned+active parrot, NO pet_enabled key.
	var cfg := ConfigFile.new()
	cfg.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg.set_value("active", "id", "parrot")
	cfg.save(PetManager.PERSIST_PATH)
	print("SEEDED v63-style save (no pet_enabled key)")

	var main := await _boot_main()
	if main == null:
		print("FAIL: could not boot Main")
		quit(1)
		return

	## Re-bootstrap pets from the seeded save after AppState may have rewritten it.
	main.state.pets.bootstrap()
	print("RUNTIME pet_enabled=", main.state.pets.pet_enabled,
		" active=", main.state.pets.active_pet_id,
		" owned=", main.state.pets.owned_pet_ids,
		" selection=", main.state.pets.get_profile_pet_selection())
	if not main.state.pets.pet_enabled:
		print("FAIL: migration left pet_enabled=false")
		fail += 1
	elif main.state.pets.active_pet_id != "parrot":
		print("FAIL: active_pet != parrot")
		fail += 1
	elif not main.state.pets.is_owned("parrot"):
		print("FAIL: owned missing parrot")
		fail += 1
	else:
		print("PASS: migrated pet_enabled=true active=parrot owned=[parrot]")

	## ——— STEP 5 / A: CHEST with migrated parrot ———
	await main._show_main_chest()
	await _settle(20)
	fail += await _assert_chest_parrot(main, true, "parrot_restored_on_chest.png")

	## ——— Profile Parrot selected ———
	main._show_profile()
	await _settle(12)
	fail += _assert_profile_controls(main, "parrot")
	if not await _shot(main, "profile_parrot_selected.png"):
		fail += 1
	else:
		print("PASS: profile_parrot_selected.png")

	## ——— Off via real control ———
	var off_btn := _find_named(main._screen_host, "ProfilePetChoiceOff") as Button
	if off_btn == null:
		print("FAIL: Off button missing")
		fail += 1
	else:
		off_btn.set_pressed_no_signal(false)
		off_btn.button_pressed = true
		await _settle(6)
		main._show_profile()
		await _settle(12)
		fail += _assert_profile_controls(main, "off")
		if not await _shot(main, "profile_off_selected.png"):
			fail += 1
		else:
			print("PASS: profile_off_selected.png")

	## ——— CHEST with Off ———
	await main._show_main_chest()
	await _settle(16)
	fail += await _assert_chest_parrot(main, false, "chest_pet_off.png")

	## ——— Parrot again via Profile ———
	main._show_profile()
	await _settle(10)
	var parrot_btn := _find_named(main._screen_host, "ProfilePetChoiceParrot") as Button
	if parrot_btn == null:
		print("FAIL: Parrot button missing for re-enable")
		fail += 1
	else:
		parrot_btn.set_pressed_no_signal(false)
		parrot_btn.button_pressed = true
		await _settle(6)
		if not main.state.pets.pet_enabled or main.state.pets.active_pet_id != "parrot":
			print("FAIL: Parrot re-enable did not stick")
			fail += 1
		else:
			print("PASS: Parrot re-enabled pet_enabled=true")

	await main._show_main_chest()
	await _settle(20)
	fail += await _assert_chest_parrot(main, true, "chest_parrot_on.png")

	print("=== v66 SAME-RUNTIME fail=%d ===" % fail)
	quit(0 if fail == 0 else 1)


func _assert_source_wiring() -> int:
	var fail := 0
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var mgr_src := FileAccess.get_file_as_string("res://scripts/pets/pet_manager.gd")
	var p0 := main_src.find("func _show_profile()")
	var p1 := main_src.find("func _show_diagnostics()")
	if p0 < 0 or p1 <= p0:
		print("FAIL: cannot locate _show_profile")
		return 1
	var body := main_src.substr(p0, p1 - p0)
	if body.contains("_build_android_diagnostics_panel"):
		print("FAIL: _show_profile mounts diagnostics")
		fail += 1
	else:
		print("PASS: _show_profile does not mount diagnostics")
	if not body.contains("_build_profile_pets_section"):
		print("FAIL: pets missing from _show_profile")
		fail += 1
	else:
		print("PASS: pets mounted from _show_profile")
	if main_src.contains('sec.text = "Android Diagnostics"'):
		print("FAIL: production UI still assigns Android Diagnostics title")
		fail += 1
	else:
		print("PASS: no Android Diagnostics title assignment in main.gd")
	if not mgr_src.contains("_migrate_pet_enabled") or not mgr_src.contains("has_section_key"):
		print("FAIL: pet_enabled migration missing")
		fail += 1
	else:
		print("PASS: pet_enabled migration present")
	if not main_src.contains("set_pressed_no_signal"):
		print("FAIL: Profile pet buttons missing set_pressed_no_signal")
		fail += 1
	else:
		print("PASS: Profile pet buttons use set_pressed_no_signal")
	var loader := FileAccess.get_file_as_string("res://scripts/pets/pet_animation_loader.gd")
	if not loader.contains("ResourceLoader.exists"):
		print("FAIL: export-safe ResourceLoader probe missing")
		fail += 1
	else:
		print("PASS: ResourceLoader.exists frame probe")
	return fail


func _boot_main() -> Node:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		return null
	var main: Node = packed.instantiate()
	root.add_child(main)
	var frames := 0
	while frames < 600:
		await process_frame
		frames += 1
		if main.get("_screen_host") != null and main.get("state") != null:
			break
	if main.get("_screen_host") == null or main.get("state") == null:
		return null
	var st: Object = main.state
	st.set("mode", AppState.Mode.LOCAL_DEMO)
	if st.get("demo") != null and st.demo.has_method("enable"):
		st.demo.enable()
	if st.get("membership") != null:
		st.membership.is_member = true
	main.set("_startup_done", true)
	for c in main.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("charoite_boot.gd"):
			c.queue_free()
	await _settle(8)
	return main


func _assert_profile_controls(main: Node, expect_choice: String) -> int:
	var fail := 0
	var host: Node = main._screen_host
	var section := _find_named(host, "ProfilePetsSection")
	var title := _find_named(host, "ProfilePetsTitle") as Label
	var off_btn := _find_named(host, "ProfilePetChoiceOff") as Button
	var parrot_btn := _find_named(host, "ProfilePetChoiceParrot") as Button
	if section == null:
		print("FAIL: ProfilePetsSection missing")
		fail += 1
	else:
		print("PASS: ProfilePetsSection present")
	if title == null or title.text != "Pets":
		print("FAIL: Pets title wrong")
		fail += 1
	else:
		print("PASS: Pets title")
	if off_btn == null or not str(off_btn.text).contains("Off"):
		print("FAIL: Off control missing")
		fail += 1
	else:
		print("PASS: Off text=", off_btn.text)
	if parrot_btn == null or not str(parrot_btn.text).contains("Parrot"):
		print("FAIL: Parrot control missing")
		fail += 1
	else:
		print("PASS: Parrot text=", parrot_btn.text)
	if _tree_has_text(host, "Android Diagnostics"):
		print("FAIL: Android Diagnostics visible on Profile")
		fail += 1
	else:
		print("PASS: Android Diagnostics absent from Profile tree")
	var sel := str(main.state.pets.get_profile_pet_selection())
	if sel != expect_choice:
		print("FAIL: selection want=", expect_choice, " got=", sel)
		fail += 1
	else:
		print("PASS: selection=", sel)
	if expect_choice == "off":
		if off_btn and not off_btn.text.contains("●"):
			print("FAIL: Off not selected visually")
			fail += 1
	elif expect_choice == "parrot":
		if parrot_btn and not parrot_btn.text.contains("●"):
			print("FAIL: Parrot not selected visually")
			fail += 1
	return fail


func _assert_chest_parrot(main: Node, expect_visible: bool, shot_name: String) -> int:
	var fail := 0
	var env: Node = main._screen_host.get_node_or_null("ChestEnvironment")
	if env == null:
		## Search recursively — mount may nest.
		env = _find_named(main._screen_host, "ChestEnvironment")
	if env == null:
		print("FAIL: ChestEnvironment missing for ", shot_name)
		fail += 1
		await _shot(main, shot_name)
		return fail
	var mgr: PetManager = main.state.pets
	var count := mgr.count_actors_under(env)
	var actor: PetActor = mgr.get_spawned_actor() as PetActor
	print("CHEST_ASSERT ", shot_name, " expect_visible=", expect_visible,
		" count=", count, " pet_enabled=", mgr.pet_enabled,
		" actor=", actor != null)
	if expect_visible:
		if count != 1 or actor == null:
			print("FAIL: expected 1 PetActor, count=", count)
			fail += 1
		else:
			print("PASS: exactly 1 PetActor")
			## Wait for artwork / visual gate.
			for _i in range(12):
				await process_frame
			var visual := actor.get_node_or_null("PetVisual") as Node2D
			var spr := actor.get_node_or_null("PetVisual/AnimatedSprite2D") as AnimatedSprite2D
			if not actor.is_artwork_ready():
				print("FAIL: artwork_ready false detail=", actor.animation_loader.load_detail)
				fail += 1
			else:
				print("PASS: artwork_ready")
			if visual == null or not visual.visible or visual.modulate.a < 0.99:
				print("FAIL: PetVisual not fully visible a=", visual.modulate.a if visual else -1)
				fail += 1
			else:
				print("PASS: PetVisual.visible alpha=1")
			if spr == null or not spr.visible:
				print("FAIL: AnimatedSprite2D not visible")
				fail += 1
			else:
				print("PASS: AnimatedSprite2D visible anim=", spr.animation, " playing=", spr.is_playing())
			if actor.safe_area.is_in_ocean(actor.position) or actor.safe_area.is_in_ui_exclusion(actor.position):
				print("FAIL: parrot outside sand safe area pos=", actor.position)
				fail += 1
			else:
				print("PASS: parrot in sand safe area pos=", actor.position)
	else:
		if count != 0 or actor != null:
			print("FAIL: expected 0 PetActor when Off, count=", count)
			fail += 1
		else:
			print("PASS: PetActor count 0 (Off)")
	if not await _shot(main, shot_name):
		fail += 1
	else:
		print("PASS: screenshot ", shot_name)
	return fail


func _settle(n: int = 8) -> void:
	for _i in range(n):
		await process_frame


func _find_named(root_node: Node, node_name: String) -> Node:
	if root_node == null:
		return null
	if root_node.name == node_name:
		return root_node
	for c in root_node.get_children():
		var found := _find_named(c, node_name)
		if found != null:
			return found
	return null


func _tree_has_text(root_node: Node, needle: String) -> bool:
	if root_node == null:
		return false
	if root_node is Label and str((root_node as Label).text).contains(needle):
		return true
	if root_node is Button and str((root_node as Button).text).contains(needle):
		return true
	for c in root_node.get_children():
		if _tree_has_text(c, needle):
			return true
	return false


func _shot(main: Node, filename: String) -> bool:
	if main.has_method("_dismiss_toast_if_visible"):
		main._dismiss_toast_if_visible()
	await _settle(10)
	RenderingServer.force_draw(true)
	await process_frame
	var img: Image = null
	var vp := root.get_viewport()
	if vp != null and vp.get_texture() != null:
		img = vp.get_texture().get_image()
	if img == null:
		print("FAIL: no image for ", filename)
		return false
	if img.get_width() >= 390 and img.get_height() >= 844:
		img = img.get_region(Rect2i(0, 0, 390, 844))
	var path := OUT_DIR.path_join(filename)
	var err := img.save_png(path)
	if err != OK:
		print("FAIL: save ", path, " err=", err)
		return false
	DirAccess.copy_absolute(path, ART_DIR.path_join(filename))
	print("WROTE ", ART_DIR.path_join(filename), " bytes=", FileAccess.get_file_as_bytes(path).size())
	return true
