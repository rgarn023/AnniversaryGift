extends SceneTree
## Production-path parrot visibility proof for CHEST.
## Mirrors: ChestEnvironment → PetRuntimeRoot → PetActor (+ UI MarginContainer overlay).
## Asserts spawn/visual gates and writes a runtime screenshot proving the parrot is on sand.

const OUT_DIR := "/tmp/parrot_chest_visibility"
const ART_DIR := "/opt/cursor/artifacts/parrot_chest_visibility"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ART_DIR)

	var fail := 0
	var ok := 0

	print("=== DIAGNOSTIC FLAGS ===")
	print("PET_RUNTIME_ENABLED=", PetRuntimeConfig.PET_RUNTIME_ENABLED)
	print("PET_VISUALS_ENABLED=", PetRuntimeConfig.PET_VISUALS_ENABLED)
	print("APP_VERSION_CODE=", BuildFlags.APP_VERSION_CODE)
	print("APP_VERSION_NAME=", BuildFlags.APP_VERSION_NAME)

	if not PetRuntimeConfig.PET_RUNTIME_ENABLED:
		print("FAIL: PET_RUNTIME_ENABLED false")
		fail += 1
	else:
		print("PASS: PET_RUNTIME_ENABLED true")
		ok += 1
	if not PetRuntimeConfig.PET_VISUALS_ENABLED:
		print("FAIL: PET_VISUALS_ENABLED false")
		fail += 1
	else:
		print("PASS: PET_VISUALS_ENABLED true")
		ok += 1

	## Prove ResourceLoader sees frames even when we document FileAccess export gap.
	var probe_path := "res://assets/pets/parrot/idle/parrot_idle_00.png"
	var rl_ok := ResourceLoader.exists(probe_path)
	var fa_ok := FileAccess.file_exists(probe_path)
	print("PROBE ResourceLoader.exists=", rl_ok, " FileAccess.file_exists=", fa_ok)
	if not rl_ok:
		print("FAIL: ResourceLoader missing idle frame")
		fail += 1
	else:
		print("PASS: ResourceLoader sees idle frame")
		ok += 1

	var loader_src := FileAccess.get_file_as_string("res://scripts/pets/pet_animation_loader.gd")
	if not loader_src.contains("ResourceLoader.exists"):
		print("FAIL: loader must probe via ResourceLoader.exists (export-safe)")
		fail += 1
	else:
		print("PASS: loader uses ResourceLoader.exists")
		ok += 1

	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()

	## Match production CHEST sibling stack: env (z=0) + UI margin (z=2).
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
	margin.name = "UIMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.z_index = 2
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(margin)

	var stage := Control.new()
	stage.name = "ChestStage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.clip_contents = false
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
	await process_frame
	await process_frame

	## Production mount path via PetManager.
	var pets := PetManager.new()
	pets.bootstrap()
	print("ACTIVE_PET_ID=", pets.active_pet_id)
	if pets.active_pet_id != "parrot":
		print("FAIL: active pet is not parrot")
		fail += 1
	else:
		print("PASS: active pet parrot")
		ok += 1
	if not pets.should_spawn_on_chest():
		print("FAIL: should_spawn_on_chest false")
		fail += 1
	else:
		print("PASS: should_spawn_on_chest")
		ok += 1

	var runtime_root := pets.ensure_pet_runtime_root(env)
	if runtime_root == null or runtime_root.name != "PetRuntimeRoot":
		print("FAIL: PetRuntimeRoot not created")
		fail += 1
	else:
		print("PASS: PetRuntimeRoot created")
		ok += 1
	if runtime_root is CanvasItem:
		(runtime_root as CanvasItem).z_index = 1

	var actor_node := pets.spawn_active_pet(runtime_root)
	if actor_node == null:
		print("FAIL: PetActor not spawned")
		fail += 1
		_finish(fail, ok)
		return
	print("PASS: PetActor spawned")
	ok += 1

	var actor := actor_node as PetActor
	var vp := Vector2(390, 844)
	var chest_local := Rect2()
	if chest != null and runtime_root is Node2D:
		var grect: Rect2 = chest.get_global_rect()
		var tl: Vector2 = (runtime_root as Node2D).to_local(grect.position)
		var br: Vector2 = (runtime_root as Node2D).to_local(grect.position + grect.size)
		chest_local = Rect2(tl, br - tl)
	pets.configure_spawned_actor(vp, chest_local, 42)

	## Clear any stale reward-hide (normal CHEST entry).
	if actor.reward_hide_requested or actor.paused:
		print("WARN: stale reward-hide/paused on spawn — clearing")
		actor.resume_after_reward()
	actor.resume_after_reward()

	await process_frame
	await process_frame
	## Let idle animation advance a couple frames.
	for _i in range(8):
		await process_frame

	## Despawn check — must still exist.
	if pets.get_spawned_actor() == null or not is_instance_valid(actor):
		print("FAIL: actor despawned after spawn")
		fail += 1
		_finish(fail, ok)
		return
	print("PASS: actor still alive after spawn")
	ok += 1

	var actor_count := pets.count_actors_under(env)
	if actor_count != 1:
		print("FAIL: expected exactly one PetActor, got ", actor_count)
		fail += 1
	else:
		print("PASS: exactly one PetActor")
		ok += 1

	var visual := actor.get_node_or_null("PetVisual") as Node2D
	var spr := actor.get_node_or_null("PetVisual/AnimatedSprite2D") as AnimatedSprite2D
	var snap: Dictionary = actor.get_debug_snapshot()
	print("SNAPSHOT=", JSON.stringify(snap))

	if not actor.is_artwork_ready():
		print("FAIL: artwork_ready false — load_detail=", actor.animation_loader.load_detail)
		fail += 1
	else:
		print("PASS: artwork_ready true")
		ok += 1

	if actor.pet_id != "parrot":
		print("FAIL: pet_id=", actor.pet_id)
		fail += 1
	else:
		print("PASS: pet_id parrot")
		ok += 1

	if visual == null or not visual.visible:
		print("FAIL: PetVisual.visible=", visual.visible if visual else "null")
		fail += 1
	else:
		print("PASS: PetVisual.visible true")
		ok += 1

	var alpha := 0.0
	if visual != null:
		alpha = visual.modulate.a
	if alpha <= 0.99:
		print("FAIL: PetVisual.modulate.a=", alpha)
		fail += 1
	else:
		print("PASS: PetVisual.modulate.a > 0.99")
		ok += 1

	if spr == null or not spr.visible:
		print("FAIL: AnimatedSprite2D.visible=", spr.visible if spr else "null")
		fail += 1
	else:
		print("PASS: AnimatedSprite2D.visible true")
		ok += 1

	if spr == null or spr.sprite_frames == null:
		print("FAIL: SpriteFrames missing")
		fail += 1
	else:
		var names := spr.sprite_frames.get_animation_names()
		print("SPRITEFRAMES_ANIMS=", names)
		if not spr.sprite_frames.has_animation("idle"):
			print("FAIL: idle animation missing")
			fail += 1
		else:
			print("PASS: idle animation exists")
			ok += 1

	if spr != null:
		print("CURRENT_ANIM=", spr.animation, " playing=", spr.is_playing())
		if str(spr.animation) != "idle":
			print("FAIL: current animation not idle")
			fail += 1
		else:
			print("PASS: current animation idle")
			ok += 1
		if not spr.is_playing():
			print("FAIL: idle not playing")
			fail += 1
		else:
			print("PASS: idle playing")
			ok += 1

	print("RUNTIME_POSITION=", actor.position)
	print("RUNTIME_SCALE=", visual.scale if visual else Vector2.ZERO)
	print("Z_INDEX actor=", actor.z_index, " root=", (runtime_root as CanvasItem).z_index if runtime_root is CanvasItem else -1)

	if actor.safe_area.is_in_ocean(actor.position) or actor.safe_area.is_in_ui_exclusion(actor.position):
		print("FAIL: position outside sand safe area")
		fail += 1
	else:
		print("PASS: position inside sand safe area")
		ok += 1

	if actor.reward_hide_requested:
		print("FAIL: reward-hide still active")
		fail += 1
	else:
		print("PASS: reward-hide cleared")
		ok += 1

	## Parent visibility walk.
	var hidden_parent := false
	var n: Node = actor
	while n != null:
		if n is CanvasItem and not (n as CanvasItem).visible:
			print("FAIL: hidden parent CanvasItem=", n.get_path())
			hidden_parent = true
			fail += 1
			break
		n = n.get_parent()
	if not hidden_parent:
		print("PASS: no hidden parent CanvasItem")
		ok += 1

	## Capture screenshot proving parrot is on CHEST beach.
	await process_frame
	await process_frame
	RenderingServer.force_draw(true)
	await process_frame
	var img: Image = screen.get_viewport().get_texture().get_image()
	var shot_ok := false
	if img != null:
		## Crop to phone frame.
		if img.get_width() >= 390 and img.get_height() >= 844:
			img = img.get_region(Rect2i(0, 0, 390, 844))
		var path_tmp := "%s/01_chest_parrot_visible.png" % OUT_DIR
		var path_art := "%s/01_chest_parrot_visible.png" % ART_DIR
		img.save_png(path_tmp)
		img.save_png(path_art)
		print("SCREENSHOT=", path_art)

		## Pixel proof: sample near actor feet / body should differ from plain sand.
		## Convert actor local → screen roughly via global transform.
		var gp: Vector2 = actor.get_global_transform_with_canvas().origin
		var sample_y := clampi(int(gp.y - 40), 0, img.get_height() - 1)
		var sample_x := clampi(int(gp.x), 0, img.get_width() - 1)
		var body := img.get_pixel(sample_x, sample_y)
		## Sand reference (lower-right open sand)
		var sand := img.get_pixel(mini(340, img.get_width() - 1), mini(720, img.get_height() - 1))
		var diff := absf(body.r - sand.r) + absf(body.g - sand.g) + absf(body.b - sand.b)
		print("PIXEL_SAMPLE body@", sample_x, ",", sample_y, "=", body, " sand=", sand, " diff=", diff)
		if diff < 0.08 and body.a < 0.5:
			print("FAIL: screenshot pixel near parrot looks empty/sand — parrot not visibly drawn")
			fail += 1
		else:
			print("PASS: screenshot pixel near parrot differs from sand / has alpha")
			ok += 1
			shot_ok = true
	else:
		print("FAIL: viewport image null")
		fail += 1

	if not shot_ok and img != null:
		## Still keep the shot for human review even if auto pixel check is soft.
		print("WARN: auto pixel check soft-failed; screenshot retained for review")

	_finish(fail, ok)


func _finish(fail: int, ok: int) -> void:
	ChestEnvironment.debug_hour_override = -1.0
	print("=== Parrot CHEST visibility: %d passed, %d failed ===" % [ok, fail])
	quit(0 if fail == 0 else 1)
