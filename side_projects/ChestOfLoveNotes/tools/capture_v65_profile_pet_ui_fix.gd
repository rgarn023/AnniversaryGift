extends SceneTree
## v65 — Capture the REAL production Profile screen from Main._show_profile().
## Must run under Xvfb (not --headless) so Viewport.get_texture() works.

const OUT_DIR := "/tmp/v65_profile_pet_ui_fix"
const ART_DIR := "/opt/cursor/artifacts/v65_profile_pet_ui_fix"
const VP := Vector2i(390, 844)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	DisplayServer.window_set_size(VP)

	var fail := 0
	print("=== v65 REAL PROFILE CAPTURE ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME)

	## Static wiring proof first.
	fail += _assert_source_wiring()

	## Wipe pet save so selection starts known.
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)

	var main := await _boot_main_to_profile()
	if main == null:
		print("FAIL: could not boot Main to Profile")
		quit(1)
		return

	## A — Parrot selected (default)
	main.state.pets.select_profile_pet("parrot")
	main._show_profile()
	await _settle()
	fail += _assert_profile_controls(main, "parrot")
	if not await _shot_host(main, "A_profile_parrot_selected.png"):
		fail += 1
	else:
		print("PASS: screenshot A Parrot selected")

	## B — Off selected via REAL Off button callback
	var off_btn := _find_named(main._screen_host, "ProfilePetChoiceOff") as Button
	var parrot_btn := _find_named(main._screen_host, "ProfilePetChoiceParrot") as Button
	if off_btn == null or parrot_btn == null:
		print("FAIL: Off/Parrot buttons missing before Off click")
		fail += 1
	else:
		off_btn.set_pressed_no_signal(false)
		off_btn.button_pressed = true ## fires toggled → select_profile_pet("off")
		await _settle()
		## Profile may rebuild via toast only — ensure screen reflects Off.
		if main.state.pets.get_profile_pet_selection() != "off":
			print("FAIL: Off button did not change pet_enabled/selection")
			fail += 1
		else:
			print("PASS: Off control callback set pet_enabled=false")
		## Rebuild Profile so selected visuals match persisted state.
		main._show_profile()
		await _settle()
		fail += _assert_profile_controls(main, "off")
		if not await _shot_host(main, "B_profile_off_selected.png"):
			fail += 1
		else:
			print("PASS: screenshot B Off selected")

		## Off → Parrot via REAL Parrot button
		parrot_btn = _find_named(main._screen_host, "ProfilePetChoiceParrot") as Button
		if parrot_btn == null:
			print("FAIL: Parrot button missing after Off rebuild")
			fail += 1
		else:
			parrot_btn.set_pressed_no_signal(false)
			parrot_btn.button_pressed = true
			await _settle()
			if main.state.pets.get_profile_pet_selection() != "parrot" or not main.state.pets.pet_enabled:
				print("FAIL: Parrot button did not enable parrot")
				fail += 1
			else:
				print("PASS: Parrot control callback set pet_enabled=true active_pet=parrot")
			## Persistence reload
			var mgr2 := PetManager.new()
			mgr2.bootstrap()
			if mgr2.get_profile_pet_selection() != "parrot" or not mgr2.pet_enabled:
				print("FAIL: Parrot selection did not persist")
				fail += 1
			else:
				print("PASS: Parrot selection persisted to user://coln_pets.cfg")

	## C — same Profile proves Android Diagnostics absent
	main._show_profile()
	await _settle()
	if _tree_has_text(main._screen_host, "Android Diagnostics"):
		print("FAIL: Android Diagnostics still visible on Profile tree")
		fail += 1
	else:
		print("PASS: Android Diagnostics absent from live Profile tree")
	if not await _shot_host(main, "C_android_diagnostics_absent.png"):
		fail += 1
	else:
		print("PASS: screenshot C diagnostics absent")

	## PetActor counts via manager (Off / Parrot)
	fail += _assert_actor_counts(main)

	print("=== v65 CAPTURE fail=%d ===" % fail)
	quit(0 if fail == 0 else 1)


func _assert_source_wiring() -> int:
	var fail := 0
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var p0 := main_src.find("func _show_profile()")
	var p1 := main_src.find("func _show_diagnostics()")
	if p0 < 0 or p1 <= p0:
		print("FAIL: cannot locate _show_profile body")
		return 1
	var body := main_src.substr(p0, p1 - p0)
	if body.contains("_build_android_diagnostics_panel"):
		print("FAIL: _show_profile still references diagnostics panel")
		fail += 1
	else:
		print("PASS: _show_profile does not mount diagnostics panel")
	if not body.contains("_build_profile_pets_section"):
		print("FAIL: _show_profile missing pets section")
		fail += 1
	else:
		print("PASS: _show_profile mounts pets section")
	if not main_src.contains('sec.text = "Pets"'):
		print("FAIL: Pets title missing")
		fail += 1
	else:
		print("PASS: Pets title present")
	if not main_src.contains("ProfilePetChoiceOff") or not main_src.contains("ProfilePetChoiceParrot"):
		print("FAIL: named Off/Parrot controls missing")
		fail += 1
	else:
		print("PASS: named Off/Parrot controls present")
	## No Android-only / mobile-only alternate Profile builder.
	if main_src.contains("AndroidProfile") or main_src.contains("_show_profile_android"):
		print("FAIL: alternate Android Profile path found")
		fail += 1
	else:
		print("PASS: no Android-specific Profile alternate path")
	return fail


func _boot_main_to_profile() -> Node:
	## Instantiate production Main scene, skip long splash wait by finishing boot ASAP.
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		return null
	var main: Node = packed.instantiate()
	root.add_child(main)
	## Wait until chrome exists.
	var frames := 0
	while frames < 600:
		await process_frame
		frames += 1
		if main.get("_screen_host") != null and main.get("state") != null:
			break
	if main.get("_screen_host") == null or main.get("state") == null:
		return null

	## Force a Profile-capable local state regardless of backend config.
	var st: Object = main.state
	st.set("mode", AppState.Mode.LOCAL_DEMO)
	if st.get("demo") != null and st.demo.has_method("enable"):
		st.demo.enable()
	if st.get("membership") != null:
		st.membership.is_member = true
	if st.get("pets") != null:
		st.pets.bootstrap()

	## Mark startup done so Profile rebuild / resume paths behave.
	main.set("_startup_done", true)
	## Dismiss splash if still present.
	for c in main.get_children():
		if str(c.get_class()).contains("Charoite") or (c.get_script() != null and str(c.get_script().resource_path).ends_with("charoite_boot.gd")):
			c.queue_free()
		if c is CanvasItem and c.z_index >= 80 and c != main._screen_host:
			## Likely boot overlay
			if c.get_script() != null and str(c.get_script().resource_path).ends_with("charoite_boot.gd"):
				c.queue_free()

	await _settle()
	main._show_profile()
	await _settle()
	if str(main.get("_current_screen")) != "profile":
		print("WARN: current_screen=", main.get("_current_screen"))
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
		print("FAIL: Pets title control missing/wrong")
		fail += 1
	else:
		print("PASS: Pets title visible")
	if off_btn == null or not off_btn.visible:
		print("FAIL: Off control missing")
		fail += 1
	else:
		print("PASS: Off control exists text=", off_btn.text)
	if parrot_btn == null or not parrot_btn.visible:
		print("FAIL: Parrot control missing")
		fail += 1
	else:
		print("PASS: Parrot control exists text=", parrot_btn.text)
	if _tree_has_text(host, "Android Diagnostics"):
		print("FAIL: Android Diagnostics text in Profile tree")
		fail += 1
	var sel := str(main.state.pets.get_profile_pet_selection())
	if sel != expect_choice:
		print("FAIL: selection want=", expect_choice, " got=", sel)
		fail += 1
	else:
		print("PASS: selection=", sel)
	if expect_choice == "off":
		if off_btn and not off_btn.text.contains("●"):
			print("FAIL: Off not visually selected text=", off_btn.text)
			fail += 1
		if parrot_btn and not parrot_btn.text.contains("○"):
			print("FAIL: Parrot should be unselected text=", parrot_btn.text)
			fail += 1
	elif expect_choice == "parrot":
		if parrot_btn and not parrot_btn.text.contains("●"):
			print("FAIL: Parrot not visually selected text=", parrot_btn.text)
			fail += 1
		if off_btn and not off_btn.text.contains("○"):
			print("FAIL: Off should be unselected text=", off_btn.text)
			fail += 1
	return fail


func _assert_actor_counts(main: Node) -> int:
	var fail := 0
	var env := Node2D.new()
	env.name = "ChestEnvironment"
	root.add_child(env)
	var mgr: PetManager = main.state.pets
	var rt := mgr.ensure_pet_runtime_root(env)
	mgr.select_profile_pet("off")
	mgr.despawn_active_pet()
	var spawned_off := mgr.spawn_active_pet(rt)
	var c_off := mgr.count_actors_under(env)
	if spawned_off != null or c_off != 0:
		print("FAIL: Off PetActor count=", c_off)
		fail += 1
	else:
		print("PASS: PetActor count Off = 0")
	mgr.select_profile_pet("parrot")
	var spawned_on := mgr.spawn_active_pet(rt)
	var c_on := mgr.count_actors_under(env)
	if spawned_on == null or c_on != 1:
		print("FAIL: Parrot PetActor count=", c_on)
		fail += 1
	else:
		print("PASS: PetActor count Parrot = 1")
	mgr.despawn_active_pet()
	env.queue_free()
	return fail


func _settle() -> void:
	for _i in range(8):
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
	if root_node is RichTextLabel and str((root_node as RichTextLabel).text).contains(needle):
		return true
	for c in root_node.get_children():
		if _tree_has_text(c, needle):
			return true
	return false


func _shot_host(main: Node, filename: String) -> bool:
	## Dismiss snackbar so it never covers Pets controls in proof shots.
	if main.has_method("_dismiss_toast_if_visible"):
		main._dismiss_toast_if_visible()
	await _settle()
	## Extra frames so toast fade completes.
	for _i in range(10):
		await process_frame
	var img: Image = null
	## Prefer capturing the full window (includes Profile + nav chrome).
	var vp := root.get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			img = tex.get_image()
	if img == null and main._screen_host != null:
		img = main._screen_host.get_viewport().get_texture().get_image()
	if img == null:
		print("FAIL: no image for ", filename)
		return false
	var path := OUT_DIR.path_join(filename)
	var err := img.save_png(path)
	if err != OK:
		print("FAIL: save ", path, " err=", err)
		return false
	var art := ART_DIR.path_join(filename)
	DirAccess.copy_absolute(path, art)
	print("WROTE ", art, " bytes=", FileAccess.get_file_as_bytes(path).size())
	return true
