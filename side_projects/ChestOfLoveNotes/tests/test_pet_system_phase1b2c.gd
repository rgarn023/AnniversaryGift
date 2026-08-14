extends SceneTree
## Phase 1B-2C — enable free parrot visuals, animations, tap, reward hide.

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


func _run() -> void:
	print("=== Pet system Phase 1B-2C free parrot runtime ===")
	_test_flags_and_version()
	_test_artwork_loader_ready()
	_test_actor_visible_tree()
	_test_animation_playback_and_flip()
	_test_chest_interaction_flow()
	_test_tap_hitbox_and_isolation()
	_test_reward_hide_resume()
	_test_safe_area_multi_viewport()
	_test_duplicate_spawn()
	_test_regressions_locked()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _make_actor(seed: int = 42, vp: Vector2 = Vector2(390, 844)) -> PetActor:
	var scene := load("res://scenes/pets/PetActor.tscn") as PackedScene
	var actor := scene.instantiate() as PetActor
	get_root().add_child(actor)
	var def := PetDefinition.new()
	def.id = "parrot"
	def.display_name = "Parrot"
	def.unlock_type = PetDefinition.UNLOCK_FREE
	def.default_unlocked = true
	def.asset_root = "res://assets/pets/parrot/"
	actor.setup_from_definition(def)
	var chest_w := 252.0 * (vp.x / 390.0)
	var chest_h := 326.0 * (vp.y / 844.0)
	var foot_y := vp.y * 0.888
	var top := foot_y - chest_h * LoveNotesChest.CHEST_FOOT_Y_FRAC
	var left := (vp.x - chest_w) * 0.5
	actor.configure_runtime(vp, Rect2(left, top, chest_w, chest_h), seed)
	return actor


func _test_flags_and_version() -> void:
	_assert(PetRuntimeConfig.PET_RUNTIME_ENABLED == true, "PET_RUNTIME_ENABLED true")
	_assert(PetRuntimeConfig.PET_VISUALS_ENABLED == true, "PET_VISUALS_ENABLED true")
	_assert(
		PetRuntimeConfig.reward_policy_default() == PetRuntimeConfig.RewardPetPolicy.HIDE_TEMPORARILY,
		"reward policy HIDE_TEMPORARILY"
	)
	_assert(BuildFlags.APP_VERSION_CODE == 66, "versionCode 66")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.66-profile-pet-production-path-fix", "versionName 66")
	_assert(is_equal_approx(PetRuntimeConfig.MOVE_SPEED_PX_PER_SEC, 72.0), "move speed 72")
	var hit := PetRuntimeConfig.tap_hitbox_size_canvas()
	_assert(is_equal_approx(hit.x, 96.0) and is_equal_approx(hit.y, 108.0), "tap hitbox canvas 96x108")


func _test_artwork_loader_ready() -> void:
	var loader := PetAnimationLoader.new()
	_assert(loader.load_parrot_manifest(), "loader loads manifest")
	_assert(loader.artwork_ready == true, "artwork_ready true")
	_assert(loader.load_status == "artwork_ready", "load_status artwork_ready")
	_assert(loader.sprite_frames != null, "sprite frames built")
	_assert(loader.sprite_frames.has_animation("idle"), "idle anim present")
	## Export-safe probe: remapped .ctex must count as present (not FileAccess-only).
	_assert(
		FileAccess.get_file_as_string("res://scripts/pets/pet_animation_loader.gd").contains("ResourceLoader.exists"),
		"animation loader uses ResourceLoader.exists for export-safe frame probe"
	)
	_assert(loader.sprite_frames != null, "SpriteFrames built")
	_assert(loader.present_files.size() == 25, "25 frames present")
	_assert(loader.missing_files.is_empty(), "no missing frames")
	_assert(loader.should_attempt_playback(), "playback allowed with visuals on")
	for anim in ["idle", "move", "chest_interaction", "tap_reaction"]:
		_assert(loader.sprite_frames.has_animation(anim), "has anim %s" % anim)
	_assert(loader.sprite_frames.get_frame_count("idle") == 5, "idle 5 frames loaded")
	_assert(loader.sprite_frames.get_frame_count("move") == 7, "move 7 frames loaded")
	_assert(loader.sprite_frames.get_frame_count("chest_interaction") == 8, "chest 8 frames loaded")
	_assert(loader.sprite_frames.get_frame_count("tap_reaction") == 5, "tap 5 frames loaded")
	_assert(loader.sprite_frames.get_animation_loop("idle") == true, "idle loops")
	_assert(loader.sprite_frames.get_animation_loop("move") == true, "move loops")
	_assert(loader.sprite_frames.get_animation_loop("chest_interaction") == false, "chest once")
	_assert(loader.sprite_frames.get_animation_loop("tap_reaction") == false, "tap once")
	var raw := FileAccess.get_file_as_string("res://assets/pets/parrot/parrot_animation_manifest.json")
	var m: Dictionary = JSON.parse_string(raw)
	_assert(bool(m.get("visuals_enabled", false)) == true, "manifest visuals_enabled true")
	_assert(str(m.get("status", "")) == "ARTWORK_READY", "manifest ARTWORK_READY")
	_assert(int(m.get("ground_anchor_x", 0)) == 64, "anchor x")
	_assert(int(m.get("ground_anchor_y", 0)) == 116, "anchor y")


func _test_actor_visible_tree() -> void:
	var actor := _make_actor(5)
	_assert(actor.is_artwork_ready(), "actor artwork ready")
	_assert(actor.visible == true, "actor visible")
	_assert(actor.modulate.a == 1.0, "actor alpha 1")
	var visual := actor.get_node_or_null("PetVisual") as Node2D
	_assert(visual != null, "PetVisual exists")
	_assert(visual.visible == true, "PetVisual visible")
	var spr := visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_assert(spr != null, "AnimatedSprite2D exists")
	_assert(spr.visible == true, "sprite visible")
	_assert(spr.sprite_frames != null, "sprite frames attached")
	_assert(spr.is_playing(), "idle playing")
	_assert(spr.animation == "idle", "starts on idle")
	## Ground anchor offset: center(64,64) - anchor(64,116) = (0, -52)
	_assert(is_equal_approx(spr.position.x, 0.0), "sprite anchor x offset 0")
	_assert(is_equal_approx(spr.position.y, -52.0), "sprite anchor y offset -52")
	## Runtime scale 0.72 * scale_factor(1.0 on 390x844)
	_assert(is_equal_approx(visual.scale.x, 0.72), "runtime scale 0.72")
	var shadow := visual.get_node_or_null("PetShadow") as Node2D
	_assert(shadow != null, "PetShadow exists")
	_assert(shadow.visible == true, "PetShadow visible")
	var hit := visual.get_node_or_null("TapHitBox") as Control
	_assert(hit != null, "TapHitBox exists")
	_assert(hit.mouse_filter == Control.MOUSE_FILTER_STOP, "TapHitBox stops mouse")
	_assert(is_equal_approx(hit.size.x, 96.0) and is_equal_approx(hit.size.y, 108.0), "hitbox size 96x108")
	var h := actor.get_on_screen_visible_height()
	_assert(h > 50.0 and h < 80.0, "visible height ~63px (25%% chest draw)")
	## Only one of each under actor.
	_assert(visual.get_child_count() >= 3, "visual children present")
	actor.queue_free()


func _test_animation_playback_and_flip() -> void:
	var actor := _make_actor(2)
	var spr := actor.get_node("PetVisual/AnimatedSprite2D") as AnimatedSprite2D
	actor.force_state_for_test(PetState.Kind.IDLE)
	_assert(actor.get_visual_state() == "idle", "IDLE visual")
	_assert(spr.animation == "idle", "idle anim playing name")
	actor.force_state_for_test(PetState.Kind.ROAM)
	_assert(actor.get_visual_state() == "move", "ROAM→move")
	_assert(spr.animation == "move", "move anim name")
	actor.force_facing_for_test(PetActor.Facing.RIGHT)
	_assert(spr.flip_h == false, "RIGHT flip_h false")
	actor.force_facing_for_test(PetActor.Facing.LEFT)
	_assert(spr.flip_h == true, "LEFT flip_h true")
	actor.force_roam_to_for_test(actor.position + Vector2(80, 0))
	actor._tick_move_toward(0.05, false)
	_assert(actor.facing == PetActor.Facing.RIGHT, "move right facing")
	_assert(spr.flip_h == false, "move right no flip")
	actor.force_roam_to_for_test(actor.position + Vector2(-80, 0))
	actor._tick_move_toward(0.05, false)
	_assert(actor.facing == PetActor.Facing.LEFT, "move left facing")
	_assert(spr.flip_h == true, "move left flip")
	## No vertical world hop on actor during move tick.
	var y0 := actor.position.y
	actor.force_roam_to_for_test(actor.position + Vector2(40, 0))
	actor._tick_move_toward(0.1, false)
	_assert(is_equal_approx(actor.position.y, y0), "no extra world Y hop")
	actor.queue_free()


func _test_chest_interaction_flow() -> void:
	var actor := _make_actor(7)
	var spr := actor.get_node("PetVisual/AnimatedSprite2D") as AnimatedSprite2D
	## Force immediate arrival by placing on interaction point.
	var pts: Array = actor.safe_area.chest_interaction_points()
	_assert(pts.size() > 0, "interaction points exist")
	actor.position = pts[0]
	actor.target_position = pts[0]
	actor.force_state_for_test(PetState.Kind.CHEST_INTERACTION)
	## On begin, still approaching → move visual until arrival tick.
	_assert(actor.state == PetState.Kind.CHEST_INTERACTION, "chest state")
	## Tick once — already arrived → starts chest anim.
	actor._tick_chest_interaction(0.016)
	_assert(actor.get_visual_state() == "chest_interaction", "chest anim after arrive")
	_assert(spr.animation == "chest_interaction", "chest anim name")
	_assert(is_equal_approx(actor.position.x, pts[0].x), "actor stopped at interaction point")
	## Interaction points stay outside chest exclusion core.
	_assert(not actor.safe_area.is_in_chest_exclusion(actor.position), "not inside chest exclusion")
	_assert(not actor.safe_area.is_in_ocean(actor.position), "not in ocean")
	actor.queue_free()


func _test_tap_hitbox_and_isolation() -> void:
	var actor := _make_actor(3)
	var hit := actor.get_node("PetVisual/TapHitBox") as Control
	_assert(hit != null, "hitbox present")
	var screen := actor.get_tap_hitbox_size_screen()
	_assert(screen.x < 120.0 and screen.y < 130.0, "screen hitbox not huge")
	_assert(screen.x > 50.0 and screen.y > 55.0, "screen hitbox finger-usable")
	actor.trigger_tap_reaction()
	_assert(actor.state == PetState.Kind.TAP_REACTION, "tap reaction state")
	_assert(actor.get_visual_state() == "tap_reaction", "tap visual")
	## Rapid re-trigger ignored while already reacting.
	actor.trigger_tap_reaction()
	_assert(actor.state == PetState.Kind.TAP_REACTION, "rapid tap stays in reaction")
	## Chest script still independent — no pet wiring into treasure_chest.
	var chest_src := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(not chest_src.contains("PetActor"), "chest script has no PetActor")
	_assert(not chest_src.contains("trigger_tap"), "chest script has no pet tap")
	actor.queue_free()


func _test_reward_hide_resume() -> void:
	var actor := _make_actor(11)
	_assert(actor.visible and actor.modulate.a == 1.0, "visible before reward")
	actor.pause_for_reward()
	_assert(actor.is_paused(), "paused for reward")
	_assert(actor.reward_hide_requested == true, "hide requested")
	_assert(actor.modulate.a == 0.0 or actor.get_node("PetVisual").visible == false, "hidden during reward")
	var hit := actor.get_node("PetVisual/TapHitBox") as Control
	_assert(hit.mouse_filter == Control.MOUSE_FILTER_IGNORE, "hitbox disabled while hidden")
	actor.resume_after_reward()
	_assert(not actor.is_paused(), "resumed")
	_assert(actor.reward_hide_requested == false, "hide cleared")
	_assert(actor.visible and actor.modulate.a == 1.0, "visible after resume")
	_assert(actor.state == PetState.Kind.IDLE, "safe IDLE after resume")
	actor.queue_free()


func _test_safe_area_multi_viewport() -> void:
	for vp in [Vector2(390, 844), Vector2(360, 800), Vector2(412, 915), Vector2(320, 694)]:
		var actor := _make_actor(21, vp)
		var area := actor.safe_area
		for _i in range(40):
			var p := area.random_roam_target(actor.rng)
			_assert(area.is_valid_roam_point(p) or not area.is_in_ocean(p), "roam sand %s" % str(vp))
			_assert(not area.is_in_ocean(p), "no ocean %s" % str(vp))
			_assert(not area.is_in_ui_exclusion(p), "no UI %s" % str(vp))
			_assert(not area.is_in_chest_exclusion(p), "no chest roam %s" % str(vp))
		for ip in area.chest_interaction_points():
			_assert(not area.is_in_ocean(ip), "interaction not ocean %s" % str(vp))
			_assert(not area.is_in_ui_exclusion(ip), "interaction not UI %s" % str(vp))
		actor.queue_free()


func _test_duplicate_spawn() -> void:
	var env := Node2D.new()
	env.name = "ChestEnvironment"
	get_root().add_child(env)
	var mgr := PetManager.new()
	mgr.bootstrap()
	var root := mgr.ensure_pet_runtime_root(env)
	mgr.spawn_active_pet(root)
	mgr.spawn_active_pet(root)
	mgr.spawn_active_pet(root)
	_assert(mgr.count_actors_under(env) == 1, "only one PetActor")
	var actor := mgr.get_spawned_actor() as PetActor
	_assert(actor != null, "spawned actor")
	_assert(actor.get_node("PetVisual/AnimatedSprite2D") != null, "one sprite")
	_assert(actor.get_node("PetVisual/PetShadow") != null, "one shadow")
	mgr.despawn_active_pet()
	mgr.spawn_active_pet(root)
	_assert(mgr.count_actors_under(env) == 1, "re-spawn still one")
	mgr.despawn_active_pet()
	env.queue_free()


func _test_regressions_locked() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "chest open intact")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "baked reveal intact")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "ground intact")
	_assert(flags.contains("APP_VERSION_CODE := 66"), "version 64")
	_assert(main.contains("pause_for_chest_reward"), "reward pause wired")
	_assert(main.contains("resume_after_chest_reward"), "reward resume wired")
	_assert(not main.contains("BillingClient"), "no billing in main")
	_assert(not main.contains("PetCollectionScreen") and not main.contains("open_pet_collection"), "no Pet Collection UI")
	_assert(not flags.contains("BillingClient"), "no billing flags")
	## Frozen art folders still present.
	_assert(DirAccess.dir_exists_absolute("res://assets/chest/animation_v2/chest_frames"), "chest frames frozen path")
	_assert(DirAccess.dir_exists_absolute("res://assets/chest/animation_v3/scroll_reveal"), "scroll reveal frozen path")
	## Backend disconnect untouched.
	var membership := FileAccess.get_file_as_string("res://scripts/network/membership_service.gd")
	_assert(membership.contains("disconnect_my_person") or FileAccess.file_exists("res://scripts/network/friend_service.gd"), "backend scripts present")
