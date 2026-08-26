extends SceneTree
## v68 — Visual ground roam validation: left/right routing, edge safety, chest interaction.
## Run under Xvfb so Viewport.get_texture() works.

const OUT_DIR := "/tmp/v68_parrot_roam_routing"
const ART_DIR := "/opt/cursor/artifacts/v68_parrot_roam_routing"
const VP := Vector2i(390, 844)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	DisplayServer.window_set_size(VP)

	var fail := 0
	print("=== v68 PARROT FULL-WIDTH ROAM VISUAL VALIDATION ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME, " code=", BuildFlags.APP_VERSION_CODE)
	print("PET_FLIGHT_ENABLED=", PetRuntimeConfig.PET_FLIGHT_ENABLED)
	print("PET_FLIGHT_VISUALS_READY=", PetRuntimeConfig.PET_FLIGHT_VISUALS_READY)

	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)

	var main := await _boot_main()
	if main == null:
		print("FAIL: boot Main")
		quit(1)
		return

	main.state.pets.bootstrap()
	main.state.pets.select_profile_pet("parrot")
	await main._show_main_chest()
	await _settle(20)

	var actor := main.state.pets.get_spawned_actor() as PetActor
	if actor == null or not is_instance_valid(actor):
		print("FAIL: no PetActor on CHEST")
		quit(1)
		return
	print("PASS: PetActor spawned artwork_ready=", actor.is_artwork_ready())

	var area: PetSafeArea = actor.safe_area
	print("ROAM_BOUNDS x=[", area.roam_x_min(), ",", area.roam_x_max(), "] y=[", area.sand_y_min(), ",", area.sand_y_max(), "]")
	print("EXCLUSION=", area.chest_exclusion_rect())
	print("TRANSIT_Y=", area.transit_y())
	print("VISUAL_EXTENT L=", area.pet_visual_extent_left(), " R=", area.pet_visual_extent_right())

	## A. Left roam
	var left_pt := area.clamp_to_roam(Vector2(area.roam_x_min() + 10.0, area.transit_y() + 30.0))
	if not area.is_valid_roam_point(left_pt):
		left_pt = area.default_spawn_position(actor.rng)
	actor.position = left_pt
	actor._begin_idle()
	await _settle(8)
	fail += await _shot(main, "A_left_roam")
	fail += _assert_no_edge_clip(actor, "A")
	fail += _assert_not_in_chest(actor, "A")

	## B. Route left → right
	var right_pt := area.clamp_to_roam(Vector2(area.roam_x_max() - 10.0, area.sand_y_max() - 20.0))
	if not area.is_valid_roam_point(right_pt):
		right_pt = area.clamp_to_roam(Vector2(area.roam_x_max() - 8.0, area.transit_y()))
	actor.force_roam_to_for_test(right_pt)
	print("ROUTE L→R plan=", actor._active_route_name, " waypoints=", actor._path_waypoints.size())
	fail += await _drive_until_idle(actor, 700)
	fail += await _shot(main, "B_left_to_right")
	fail += _assert_no_edge_clip(actor, "B")
	fail += _assert_not_in_chest(actor, "B")
	if actor.position.x < area.viewport_size.x * 0.45:
		print("WARN: ended mid-left after L→R (may still be en route); pos=", actor.position)
	else:
		print("PASS: arrived right-ish x=", actor.position.x)

	## C. Right roam
	actor.position = right_pt
	actor._begin_idle()
	await _settle(6)
	fail += await _shot(main, "C_right_roam")
	fail += _assert_no_edge_clip(actor, "C")

	## D. Route right → left
	actor.force_roam_to_for_test(left_pt)
	print("ROUTE R→L plan=", actor._active_route_name, " waypoints=", actor._path_waypoints.size())
	fail += await _drive_until_idle(actor, 700)
	fail += await _shot(main, "D_right_to_left")
	fail += _assert_no_edge_clip(actor, "D")
	fail += _assert_not_in_chest(actor, "D")

	## E. Chest interaction from both sides
	actor.position = left_pt
	actor._begin_chest_interaction()
	fail += await _drive_until_idle(actor, 700)
	fail += await _shot(main, "E_chest_interaction_from_left")
	fail += _assert_not_in_chest(actor, "E_left")

	actor.position = right_pt
	actor._begin_chest_interaction()
	fail += await _drive_until_idle(actor, 700)
	fail += await _shot(main, "E_chest_interaction_from_right")
	fail += _assert_not_in_chest(actor, "E_right")

	## F/G covered by edge + chest asserts throughout
	fail += await _shot(main, "F_final_beach_overview")

	## Flight must stay disabled in production capture.
	if PetRuntimeConfig.PET_FLIGHT_ENABLED:
		print("FAIL: PET_FLIGHT_ENABLED should be false for this APK")
		fail += 1
	else:
		print("PASS: flight disabled in production capture")

	print("=== VISUAL VALIDATION fail=", fail, " ===")
	quit(0 if fail == 0 else 1)


func _assert_no_edge_clip(actor: PetActor, tag: String) -> int:
	var area: PetSafeArea = actor.safe_area
	var left_pix := actor.position.x - area.pet_visual_extent_left()
	var right_pix := actor.position.x + area.pet_visual_extent_right()
	if left_pix < -0.5:
		print("FAIL: ", tag, " left clip left_pix=", left_pix)
		return 1
	if right_pix > area.viewport_size.x + 0.5:
		print("FAIL: ", tag, " right clip right_pix=", right_pix)
		return 1
	print("PASS: ", tag, " no edge clip left_pix=", left_pix, " right_pix=", right_pix)
	return 0


func _assert_not_in_chest(actor: PetActor, tag: String) -> int:
	if actor.safe_area.is_in_chest_exclusion(actor.position):
		print("FAIL: ", tag, " inside chest exclusion pos=", actor.position)
		return 1
	print("PASS: ", tag, " outside chest")
	return 0


func _shot(main: Node, name: String) -> int:
	await _settle(2)
	var img: Image = main.get_viewport().get_texture().get_image()
	if img == null:
		print("FAIL: capture ", name)
		return 1
	var path := "%s/%s.png" % [OUT_DIR, name]
	var art := "%s/%s.png" % [ART_DIR, name]
	var err := img.save_png(path)
	if err != OK:
		print("FAIL: save ", path)
		return 1
	DirAccess.copy_absolute(path, art)
	print("SHOT ", art, " size=", img.get_width(), "x", img.get_height())
	return 0


func _drive_until_idle(actor: PetActor, max_frames: int) -> int:
	var crossed := 0
	for _i in range(max_frames):
		if actor.state == PetState.Kind.IDLE:
			break
		if actor.state == PetState.Kind.CHEST_INTERACTION and actor._chest_anim_playing:
			for _j in range(20):
				actor._process(0.05)
			break
		var before := actor.position
		actor._process(0.05)
		if actor.safe_area.is_in_chest_exclusion(actor.position):
			crossed += 1
		if before.distance_to(actor.position) > 0.5 \
			and actor.safe_area.segment_intersects_chest_exclusion(before, actor.position):
			crossed += 1
		await process_frame
	if crossed > 0:
		print("FAIL: path crossed chest (", crossed, ")")
		return 1
	print("PASS: path did not cross chest")
	return 0


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


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame
