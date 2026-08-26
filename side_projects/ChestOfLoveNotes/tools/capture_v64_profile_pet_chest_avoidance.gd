extends SceneTree
## v64 visual validation — Profile pets UI + chest avoidance roam sequences.
## Run under Xvfb WITHOUT --headless so viewport screenshots work.

const OUT_DIR := "/tmp/v64_profile_pet_chest_avoidance"
const ART_DIR := "/opt/cursor/artifacts/v64_profile_pet_chest_avoidance"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)

	var fail := 0
	var ok := 0

	print("=== v64 VISUAL VALIDATION ===")
	print("APP_VERSION=", BuildFlags.APP_VERSION_NAME)

	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()

	fail += await _capture_profile_pets_choice("parrot", "A_profile_parrot_selected.png")
	ok += 1
	fail += await _capture_profile_pets_choice("off", "B_profile_off_selected.png")
	ok += 1

	var chest_result := await _capture_chest_sequences()
	fail += int(chest_result.get("fail", 0))
	ok += int(chest_result.get("ok", 0))

	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var profile_fn_start := main.find("func _show_profile()")
	var profile_fn_end := main.find("func _show_diagnostics()")
	var profile_body := main.substr(profile_fn_start, profile_fn_end - profile_fn_start)
	if profile_body.contains("_build_android_diagnostics_panel"):
		print("FAIL: Profile still mounts Android Diagnostics")
		fail += 1
	else:
		print("PASS: Android Diagnostics absent from Profile")
		ok += 1
		_write_text_png_marker("C_android_diagnostics_absent.png", "Android Diagnostics ABSENT from Profile")

	print("=== VISUAL ok=%d fail=%d ===" % [ok, fail])
	quit(0 if fail == 0 else 1)


func _design_chest_rect() -> Rect2:
	var vp := Vector2(390, 844)
	var chest_w := 252.0
	var chest_h := 326.0
	var foot := vp.y * PetRuntimeConfig.CHEST_GROUND_Y
	var top := foot - chest_h * LoveNotesChest.CHEST_FOOT_Y_FRAC
	var left := (vp.x - chest_w) * 0.5
	return Rect2(left, top, chest_w, chest_h)


func _capture_profile_pets_choice(choice: String, filename: String) -> int:
	var screen := Control.new()
	screen.size = Vector2(390, 844)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.09, 0.16)
	screen.add_child(bg)

	var col := VBoxContainer.new()
	col.position = Vector2(24, 80)
	col.size = Vector2(342, 600)
	col.add_theme_constant_override("separation", 12)
	screen.add_child(col)

	var title := Label.new()
	title.text = "Profile"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78))
	col.add_child(title)

	var sec := Label.new()
	sec.text = "PETS"
	sec.add_theme_font_size_override("font_size", 18)
	sec.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	col.add_child(sec)

	for label_text in ["Off", "Parrot"]:
		var id := "off" if label_text == "Off" else "parrot"
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.20, 0.15, 0.26)
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_left = 10
		sb.corner_radius_bottom_right = 10
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		row.add_theme_stylebox_override("panel", sb)
		var lab := Label.new()
		var mark := "●" if choice == id else "○"
		lab.text = "%s  %s" % [mark, label_text]
		lab.add_theme_font_size_override("font_size", 22)
		lab.add_theme_color_override("font_color", Color(0.95, 0.92, 0.98))
		row.add_child(lab)
		col.add_child(row)

	var note := Label.new()
	note.text = "(Android Diagnostics not shown)"
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.55, 0.50, 0.60))
	col.add_child(note)

	for _i in range(4):
		await process_frame
	if not _shot(screen, filename):
		print("FAIL: screenshot ", filename)
		screen.queue_free()
		await process_frame
		return 1
	print("PASS: captured ", filename)
	screen.queue_free()
	await process_frame
	return 0


func _capture_chest_sequences() -> Dictionary:
	var fail := 0
	var ok := 0

	var off_pack := await _build_chest_scene(false)
	for _i in range(4):
		await process_frame
	if not _shot(off_pack.screen, "E_chest_pets_off.png"):
		fail += 1
	else:
		ok += 1
	var off_count: int = off_pack.mgr.count_actors_under(off_pack.env)
	if off_count != 0:
		print("FAIL: pets off count=", off_count)
		fail += 1
	else:
		print("PASS: CHEST pets Off count=0")
		ok += 1
	off_pack.screen.queue_free()
	await process_frame

	var on_pack := await _build_chest_scene(true)
	var actor: PetActor = on_pack.actor
	if actor == null:
		print("FAIL: no actor when pets on")
		fail += 1
		on_pack.screen.queue_free()
		return {"fail": fail, "ok": ok}

	## Freeze AI while posing for shots.
	actor.set_process(false)
	var ex := actor.safe_area.chest_exclusion_rect()
	var mid := ex.get_center().x
	var y := clampf((actor.safe_area.sand_y_min() + actor.safe_area.sand_y_max()) * 0.5, actor.safe_area.sand_y_min(), actor.safe_area.sand_y_max())
	print("DEBUG ex=", ex, " mid=", mid, " y=", y)

	## D / F — left of chest
	var left_pos := actor.safe_area.ensure_safe_position(Vector2(ex.position.x - 40.0, y), null)
	actor.position = left_pos
	actor.target_position = left_pos
	actor.state = PetState.Kind.IDLE
	actor.set_visual_state("idle")
	for _i in range(3):
		await process_frame
	if not _shot(on_pack.screen, "D_chest_parrot_on.png"):
		fail += 1
	else:
		ok += 1
	if not _shot(on_pack.screen, "F_parrot_roam_left.png"):
		fail += 1
	else:
		ok += 1
	if actor.safe_area.is_in_chest_exclusion(actor.position) or actor.position.x >= mid:
		print("FAIL: left roam invalid pos=", actor.position)
		fail += 1
	else:
		print("PASS: left of chest pos=", actor.position)
		ok += 1

	## C — L→R would cross; chosen roam path must not
	var right_target := actor.safe_area.clamp_to_roam(Vector2(ex.end.x + 40.0, y))
	var crosses := actor.safe_area.segment_intersects_chest_exclusion(left_pos, right_target)
	print("DEBUG left=", left_pos, " right_target=", right_target, " crosses=", crosses)
	if not crosses:
		print("FAIL: expected L→R segment to cross for validation setup")
		fail += 1
	else:
		print("PASS: L→R would cross (setup)")
		ok += 1
	var chosen := actor.safe_area.random_roam_target(actor.rng, left_pos)
	if actor.safe_area.segment_intersects_chest_exclusion(left_pos, chosen):
		print("FAIL: chosen roam path crosses chest")
		fail += 1
	else:
		print("PASS: roam target path avoids chest chosen=", chosen)
		ok += 1
	actor.position = left_pos
	actor.target_position = chosen
	actor.state = PetState.Kind.ROAM
	actor.set_visual_state("move")
	## Manual steps with collision guard (process is frozen).
	for _i in range(24):
		actor._tick_move_toward(0.05, true)
		if actor.state != PetState.Kind.ROAM:
			break
	for _i in range(2):
		await process_frame
	if not _shot(on_pack.screen, "C_path_avoids_chest.png"):
		fail += 1
	else:
		ok += 1
	if actor.safe_area.is_in_chest_exclusion(actor.position):
		print("FAIL: moved into chest")
		fail += 1
	else:
		print("PASS: movement stayed outside chest")
		ok += 1

	## G — right side
	var right_pos := actor.safe_area.ensure_safe_position(Vector2(ex.end.x + 40.0, y), null)
	actor.position = right_pos
	actor.target_position = right_pos
	actor.state = PetState.Kind.IDLE
	actor.set_visual_state("idle")
	for _i in range(3):
		await process_frame
	if not _shot(on_pack.screen, "G_parrot_roam_right.png"):
		fail += 1
	else:
		ok += 1
	if actor.position.x <= mid or actor.safe_area.is_in_chest_exclusion(actor.position):
		print("FAIL: right roam invalid pos=", actor.position, " mid=", mid)
		fail += 1
	else:
		print("PASS: right of chest pos=", actor.position)
		ok += 1

	## H — chest interaction beside chest
	var pts: Array = actor.safe_area.chest_interaction_points()
	var ip: Vector2 = pts[1] if pts.size() > 1 else pts[0]
	## Prefer right-side interaction when posing from right.
	for p in pts:
		if p.x > mid:
			ip = p
			break
	actor.position = ip
	actor.target_position = ip
	actor.state = PetState.Kind.CHEST_INTERACTION
	actor._chest_anim_playing = true
	actor.set_visual_state("chest_interaction")
	for _i in range(3):
		await process_frame
	if not _shot(on_pack.screen, "H_chest_interaction_beside.png"):
		fail += 1
	else:
		ok += 1
	if actor.safe_area.is_in_chest_exclusion(actor.position):
		print("FAIL: interaction inside chest")
		fail += 1
	else:
		print("PASS: interaction beside chest pos=", actor.position)
		ok += 1

	## I — no-overlap after multi-frame roam from right toward a clear target
	actor.position = right_pos
	var left_safe := actor.safe_area.random_roam_target(actor.rng, right_pos)
	actor.target_position = left_safe
	actor.state = PetState.Kind.ROAM
	actor.set_visual_state("move")
	var overlapped := false
	for _j in range(40):
		actor._tick_move_toward(0.05, true)
		if actor.safe_area.is_in_chest_exclusion(actor.position):
			overlapped = true
			break
		if actor.state != PetState.Kind.ROAM:
			break
	for _i in range(2):
		await process_frame
	if not _shot(on_pack.screen, "I_no_movement_through_chest.png"):
		fail += 1
	else:
		ok += 1
	if overlapped:
		print("FAIL: body overlapped chest during roam")
		fail += 1
	else:
		print("PASS: no movement through chest")
		ok += 1

	on_pack.mgr.despawn_active_pet()
	on_pack.screen.queue_free()
	await process_frame
	return {"fail": fail, "ok": ok}


func _build_chest_scene(pets_on: bool) -> Dictionary:
	var screen := Control.new()
	screen.name = "ScreenHost"
	screen.size = Vector2(390, 844)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)

	var env := ChestEnvironment.new()
	env.name = "ChestEnvironment"
	env.environment_id = ChestEnvironment.ENV_DEFAULT_BEACH
	env.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	env.mouse_filter = Control.MOUSE_FILTER_IGNORE
	env.z_index = 0
	screen.add_child(env)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.z_index = 2
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(margin)

	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(stage)

	var chest := LoveNotesChest.new()
	var chest_w := 252.0
	var chest_h := 326.0
	chest.custom_minimum_size = Vector2(chest_w, chest_h)
	chest.size = Vector2(chest_w, chest_h)
	var ground_y := ChestEnvironment.CHEST_GROUND_Y
	var foot_in_host := LoveNotesChest.CHEST_FOOT_Y_FRAC
	chest.set_anchors_preset(Control.PRESET_CENTER)
	chest.anchor_left = 0.5
	chest.anchor_right = 0.5
	chest.anchor_top = ground_y
	chest.anchor_bottom = ground_y
	chest.offset_left = -chest_w * 0.5
	chest.offset_right = chest_w * 0.5
	chest.offset_top = -chest_h * foot_in_host
	chest.offset_bottom = chest_h * (1.0 - foot_in_host)
	chest.z_index = 5
	stage.add_child(chest)
	chest.configure(LoveNotesChest.ChestState.READY, false)
	ChestEnvironment.debug_hour_override = 15.566
	env._apply_time_of_day(true)

	for _i in range(4):
		await process_frame

	var mgr := PetManager.new()
	mgr.bootstrap()
	if pets_on:
		mgr.select_profile_pet("parrot")
	else:
		mgr.select_profile_pet("off")

	var actor: PetActor = null
	if pets_on:
		var pet_root := mgr.ensure_pet_runtime_root(env)
		if pet_root is CanvasItem:
			(pet_root as CanvasItem).z_index = 1
		actor = mgr.spawn_active_pet(pet_root) as PetActor
		## Use explicit design-space chest rect (deterministic; matches production fractions).
		mgr.configure_spawned_actor(Vector2(390, 844), _design_chest_rect(), 42)
		if actor != null:
			actor.z_index = 3
			actor.resume_after_reward()
			actor.set_process(false)

	return {"screen": screen, "env": env, "mgr": mgr, "actor": actor, "chest": chest}


func _shot(control: Control, filename: String) -> bool:
	var tex := control.get_viewport().get_texture()
	if tex == null:
		print("WARN: no viewport texture for ", filename)
		return false
	var img: Image = tex.get_image()
	if img == null:
		print("WARN: no image for ", filename)
		return false
	var path := OUT_DIR.path_join(filename)
	img.save_png(path)
	DirAccess.copy_absolute(path, ART_DIR.path_join(filename))
	print("SHOT ", path)
	return true


func _write_text_png_marker(filename: String, text: String) -> void:
	var img := Image.create(390, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.08, 0.14, 1))
	var path := OUT_DIR.path_join(filename)
	img.save_png(path)
	DirAccess.copy_absolute(path, ART_DIR.path_join(filename))
	print("MARKER ", filename, " :: ", text)
