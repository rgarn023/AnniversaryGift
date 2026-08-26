extends SceneTree
## v67 — SAME-RUNTIME proof via REAL bottom-nav Profile control.
## 1) Dump live Profile control tree after pressing BottomNav_profile
## 2) Assert Pets / Off / Parrot present; Android Diagnostics absent
## 3) Prove Off/Parrot toggle + normalized position persistence across CHEST leave/return
## Must run under Xvfb (not --headless) so Viewport.get_texture() works.

const OUT_DIR := "/tmp/v67_profile_pet_persistence"
const ART_DIR := "/opt/cursor/artifacts/v67_profile_pet_persistence"
const VP := Vector2i(390, 844)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	DisplayServer.window_set_size(VP)

	var fail := 0
	print("=== v67 BOTTOM-NAV PROFILE + POSITION PERSISTENCE PROOF ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME, " code=", BuildFlags.APP_VERSION_CODE)
	print("HEAD_NOTE=runtime capture on production Main bottom-nav path")

	fail += _assert_source_wiring()

	## Clean pet save so we control state.
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)

	var main := await _boot_main()
	if main == null:
		print("FAIL: could not boot Main")
		quit(1)
		return

	main.state.pets.bootstrap()
	main.state.pets.select_profile_pet("parrot")
	print("SEEDED pet_enabled=", main.state.pets.pet_enabled,
		" active=", main.state.pets.active_pet_id,
		" selection=", main.state.pets.get_profile_pet_selection())

	## ——— PART A: CHEST via production path, then REAL bottom-nav Profile ———
	await main._show_main_chest()
	await _settle(18)
	var nav_profile := _find_named(main._screen_host, "BottomNav_profile") as BaseButton
	if nav_profile == null:
		print("FAIL: BottomNav_profile missing on CHEST — cannot prove production Profile path")
		fail += 1
		quit(1)
		return
	print("PASS: BottomNav_profile found text=", nav_profile.text.replace("\n", " / "))
	nav_profile.emit_signal("pressed")
	await _settle(16)

	if str(main._current_screen) != "profile":
		print("FAIL: bottom-nav Profile did not open production profile screen got=", main._current_screen)
		fail += 1
	else:
		print("PASS: _current_screen=profile after BottomNav_profile")

	var tree_dump := _dump_control_tree(main._screen_host, 0)
	var dump_path := "%s/profile_control_tree.txt" % OUT_DIR
	var art_dump := "%s/profile_control_tree.txt" % ART_DIR
	_write_text(dump_path, tree_dump)
	_write_text(art_dump, tree_dump)
	print("=== LIVE PROFILE CONTROL TREE (bottom-nav) ===")
	print(tree_dump)
	print("=== END TREE ===")

	## Identify diagnostics node if present (must be absent).
	var diag := _find_text_node(main._screen_host, "Android Diagnostics")
	if diag != null:
		print("FAIL: Android Diagnostics LIVE node path=", _node_path(diag))
		print("FAIL: node class=", diag.get_class(), " name=", diag.name)
		fail += 1
	else:
		print("PASS: no live node renders text 'Android Diagnostics'")
		print("TRACE: historical producer was main.gd::_build_android_diagnostics_panel")
		print("TRACE: previously mounted from _show_profile via OS.is_debug_build() gate (removed ef6bf26)")
		print("TRACE: production Profile builder is main.gd::_show_profile (bottom nav callback)")

	fail += _assert_profile_controls(main, "parrot")
	if not await _shot(main, "profile_parrot_selected.png"):
		fail += 1
	else:
		print("PASS: profile_parrot_selected.png")

	## ——— CHEST: move parrot, record position ———
	await _click_bottom_nav(main, "chest")
	await _settle(20)
	fail += await _assert_chest_parrot(main, true, "chest_parrot_before_toggle.png")
	var actor: PetActor = main.state.pets.get_spawned_actor() as PetActor
	var pos_before := Vector2.ZERO
	if actor != null:
		## Force a distinctive roam target away from default spawn.
		var area: PetSafeArea = actor.safe_area
		var dest := Vector2(area.roam_x_max() - 20.0, (area.sand_y_min() + area.sand_y_max()) * 0.5)
		dest = area.ensure_safe_position(dest, actor.rng)
		actor.force_roam_to_for_test(dest)
		## Simulate arrival.
		for _i in range(240):
			await process_frame
			if actor.state == PetState.Kind.IDLE:
				break
		## Snap to dest if still moving (deterministic proof).
		if actor.position.distance_to(dest) > 8.0:
			actor.position = area.ensure_safe_position(dest, actor.rng)
			actor.target_position = actor.position
			actor.force_state_for_test(PetState.Kind.IDLE)
			await _settle(4)
		pos_before = actor.position
		main.state.pets.persist_active_actor_position()
		print("RECORDED parrot pos_before=", pos_before,
			" norm=", main.state.pets.get_saved_position_norm("parrot"))
	else:
		print("FAIL: no actor to move before toggle")
		fail += 1

	## ——— Profile Off via bottom nav + real control ———
	await _click_bottom_nav(main, "profile")
	await _settle(12)
	var off_btn := _find_named(main._screen_host, "ProfilePetChoiceOff") as Button
	if off_btn == null:
		print("FAIL: Off button missing after bottom-nav Profile")
		fail += 1
	else:
		off_btn.set_pressed_no_signal(false)
		off_btn.button_pressed = true
		await _settle(6)
		## Re-open Profile so selection is read fresh from PetManager.
		await _click_bottom_nav(main, "profile")
		await _settle(10)
		fail += _assert_profile_controls(main, "off")
		if not await _shot(main, "profile_off_selected.png"):
			fail += 1
		else:
			print("PASS: profile_off_selected.png")

	## Position must survive Off.
	if not main.state.pets.has_saved_position("parrot"):
		print("FAIL: Off cleared saved parrot position")
		fail += 1
	else:
		print("PASS: Off preserved saved position norm=", main.state.pets.get_saved_position_norm("parrot"))

	await _click_bottom_nav(main, "chest")
	await _settle(16)
	fail += await _assert_chest_parrot(main, false, "chest_pet_off.png")

	## ——— Parrot on again; must restore near pos_before ———
	await _click_bottom_nav(main, "profile")
	await _settle(10)
	var parrot_btn := _find_named(main._screen_host, "ProfilePetChoiceParrot") as Button
	if parrot_btn == null:
		print("FAIL: Parrot button missing for re-enable")
		fail += 1
	else:
		parrot_btn.set_pressed_no_signal(false)
		parrot_btn.button_pressed = true
		await _settle(6)

	await _click_bottom_nav(main, "chest")
	await _settle(20)
	fail += await _assert_chest_parrot(main, true, "chest_parrot_restored.png")
	actor = main.state.pets.get_spawned_actor() as PetActor
	if actor == null:
		print("FAIL: parrot missing after Off→Parrot")
		fail += 1
	else:
		var dist := actor.position.distance_to(pos_before)
		print("RESTORE pos=", actor.position, " expected_near=", pos_before, " dist=", dist)
		if dist > 28.0:
			print("FAIL: restored position too far from saved (default spawn regression?)")
			fail += 1
		else:
			print("PASS: restored near previous position dist=", dist)

	## ——— Leave CHEST and return: position still persists ———
	var mid := actor.position if actor else pos_before
	await _click_bottom_nav(main, "profile")
	await _settle(8)
	await _click_bottom_nav(main, "chest")
	await _settle(18)
	actor = main.state.pets.get_spawned_actor() as PetActor
	if actor == null:
		print("FAIL: parrot missing after CHEST leave/return")
		fail += 1
	else:
		var d2 := actor.position.distance_to(mid)
		print("LEAVE_RETURN pos=", actor.position, " mid=", mid, " dist=", d2)
		if d2 > 28.0:
			print("FAIL: CHEST leave/return lost position")
			fail += 1
		else:
			print("PASS: CHEST leave/return position persists dist=", d2)

	## ——— App-restart persistence (reload PetManager from disk) ———
	main.state.pets.persist_active_actor_position()
	var saved_norm: Vector2 = main.state.pets.get_saved_position_norm("parrot")
	var writes_before: int = int(main.state.pets.position_persist_write_count)
	var reloaded := PetManager.new()
	reloaded.bootstrap()
	if not reloaded.has_saved_position("parrot"):
		print("FAIL: position missing after PetManager reload")
		fail += 1
	else:
		var rn: Vector2 = reloaded.get_saved_position_norm("parrot")
		if absf(rn.x - saved_norm.x) > 0.01 or absf(rn.y - saved_norm.y) > 0.01:
			print("FAIL: reload norm mismatch saved=", saved_norm, " got=", rn)
			fail += 1
		else:
			print("PASS: app-restart position reload norm=", rn)
	## Simulate many frames without requiring a write per frame.
	for _i in range(30):
		await process_frame
	var writes_delta: int = int(main.state.pets.position_persist_write_count) - writes_before
	if writes_delta > 5:
		print("FAIL: excessive position writes during idle frames delta=", writes_delta)
		fail += 1
	else:
		print("PASS: no per-frame position writes delta=", writes_delta)

	print("=== v67 SAME-RUNTIME fail=%d ===" % fail)
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
	if not body.contains("_build_profile_pets_section"):
		print("FAIL: _show_profile missing pets section")
		fail += 1
	else:
		print("PASS: _show_profile mounts _build_profile_pets_section")
	if body.contains("_build_android_diagnostics_panel"):
		print("FAIL: _show_profile mounts diagnostics")
		fail += 1
	else:
		print("PASS: _show_profile does not mount diagnostics")
	if main_src.contains('sec.text = "Android Diagnostics"'):
		print("FAIL: production UI still assigns Android Diagnostics title")
		fail += 1
	else:
		print("PASS: no Android Diagnostics title assignment in main.gd")
	if not main_src.contains('b.name = "BottomNav_%s"'):
		print("FAIL: BottomNav stable names missing")
		fail += 1
	else:
		print("PASS: BottomNav_%s names present")
	var nav_profile_cb := main_src.find('["profile", "◎", "Profile", _show_profile]')
	if nav_profile_cb < 0:
		print("FAIL: bottom nav Profile does not call _show_profile")
		fail += 1
	else:
		print("PASS: bottom nav Profile → _show_profile")
	var mgr := FileAccess.get_file_as_string("res://scripts/pets/pet_manager.gd")
	for req in [
		"parrot_position_x_norm",
		"parrot_position_y_norm",
		"persist_active_actor_position",
		"resolve_spawn_world_position",
		"world_to_norm",
		"norm_to_world",
	]:
		if not mgr.contains(req):
			print("FAIL: PetManager missing ", req)
			fail += 1
		else:
			print("PASS: PetManager has ", req)
	var actor := FileAccess.get_file_as_string("res://scripts/pets/pet_actor.gd")
	if not actor.contains("restore_world"):
		print("FAIL: PetActor configure_runtime missing restore_world")
		fail += 1
	else:
		print("PASS: PetActor restore_world support")
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


func _click_bottom_nav(main: Node, tab: String) -> void:
	## Prefer pressing the real bottom-nav button (production path).
	var btn := _find_named(main._screen_host, "BottomNav_%s" % tab) as BaseButton
	if btn != null:
		btn.emit_signal("pressed")
		return
	## Fallback only if nav not yet mounted (should not happen mid-proof).
	match tab:
		"chest":
			await main._show_main_chest()
		"profile":
			main._show_profile()
		_:
			pass


func _assert_profile_controls(main: Node, expect_choice: String) -> int:
	var fail := 0
	var host: Node = main._screen_host
	var section := _find_named(host, "ProfilePetsSection")
	var title := _find_named(host, "ProfilePetsTitle") as Label
	var off_btn := _find_named(host, "ProfilePetChoiceOff") as Button
	var parrot_btn := _find_named(host, "ProfilePetChoiceParrot") as Button
	if section == null or not section.visible:
		print("FAIL: ProfilePetsSection missing/invisible")
		fail += 1
	else:
		print("PASS: ProfilePetsSection path=", _node_path(section))
	if title == null or title.text != "Pets":
		print("FAIL: Pets title wrong")
		fail += 1
	else:
		print("PASS: Pets title path=", _node_path(title))
	if off_btn == null or not str(off_btn.text).contains("Off"):
		print("FAIL: Off control missing")
		fail += 1
	else:
		print("PASS: Off path=", _node_path(off_btn), " text=", off_btn.text)
	if parrot_btn == null or not str(parrot_btn.text).contains("Parrot"):
		print("FAIL: Parrot control missing")
		fail += 1
	else:
		print("PASS: Parrot path=", _node_path(parrot_btn), " text=", parrot_btn.text)
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
		" count=", count, " pet_enabled=", mgr.pet_enabled, " actor=", actor != null)
	if expect_visible:
		if count != 1 or actor == null:
			print("FAIL: expected 1 PetActor, count=", count)
			fail += 1
		else:
			print("PASS: exactly 1 PetActor")
			for _i in range(12):
				await process_frame
			if actor.safe_area.is_in_chest_exclusion(actor.position):
				print("FAIL: parrot inside chest exclusion pos=", actor.position)
				fail += 1
			else:
				print("PASS: parrot outside chest exclusion")
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


func _dump_control_tree(n: Node, depth: int) -> String:
	var pad := ""
	for _i in range(depth):
		pad += "  "
	var text := ""
	if n is Label:
		text = " text=\"%s\"" % str((n as Label).text).replace("\n", "\\n")
	elif n is BaseButton:
		text = " text=\"%s\"" % str((n as BaseButton).text).replace("\n", "\\n")
	elif n is LineEdit:
		text = " text=\"%s\"" % str((n as LineEdit).text).replace("\n", "\\n")
	var vis := ""
	if n is CanvasItem:
		vis = " visible=%s" % str((n as CanvasItem).visible)
	var line := "%s[%s] %s%s%s\n" % [pad, n.get_class(), n.name, vis, text]
	for c in n.get_children():
		line += _dump_control_tree(c, depth + 1)
	return line


func _find_text_node(n: Node, needle: String) -> Node:
	if n is Label and str((n as Label).text).contains(needle):
		return n
	if n is BaseButton and str((n as BaseButton).text).contains(needle):
		return n
	for c in n.get_children():
		var hit := _find_text_node(c, needle)
		if hit != null:
			return hit
	return null


func _node_path(n: Node) -> String:
	if n == null:
		return "(null)"
	var parts: PackedStringArray = PackedStringArray()
	var cur: Node = n
	while cur != null:
		parts.insert(0, cur.name)
		cur = cur.get_parent()
		if parts.size() > 24:
			break
	return "/".join(parts)


func _find_named(n: Node, node_name: String) -> Node:
	if n == null:
		return null
	if n.name == node_name:
		return n
	for c in n.get_children():
		var hit := _find_named(c, node_name)
		if hit != null:
			return hit
	return null


func _tree_has_text(n: Node, needle: String) -> bool:
	return _find_text_node(n, needle) != null


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _shot(main: Node, name: String) -> bool:
	await _settle(2)
	var img: Image = main.get_viewport().get_texture().get_image()
	if img == null:
		print("FAIL: screenshot null ", name)
		return false
	var tmp := "%s/%s" % [OUT_DIR, name]
	var art := "%s/%s" % [ART_DIR, name]
	var err := img.save_png(tmp)
	if err != OK:
		print("FAIL: save ", tmp, " err=", err)
		return false
	DirAccess.copy_absolute(tmp, art)
	print("WROTE ", art)
	return true


func _write_text(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(body)
		f.close()
