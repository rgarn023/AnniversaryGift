extends SceneTree
## Phase 1B-2A — parrot art contract + hidden animation loader (no visible pixels).

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
	print("=== Pet system Phase 1B-2A art contract / loader ===")
	_test_flags_and_manifest()
	_test_loader_missing_art_safe()
	_test_actor_visual_tree_hidden()
	_test_state_animation_mapping()
	_test_facing_flip_logic()
	_test_no_placeholder_and_regression()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _make_actor(seed: int = 42) -> PetActor:
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
	actor.configure_runtime(Vector2(390, 844), Rect2(69, 482, 252, 326), seed)
	return actor


func _test_flags_and_manifest() -> void:
	_assert(PetRuntimeConfig.PET_RUNTIME_ENABLED == true, "PET_RUNTIME_ENABLED true")
	_assert(PetRuntimeConfig.PET_VISUALS_ENABLED == false, "PET_VISUALS_ENABLED false")
	_assert(FileAccess.file_exists("res://assets/pets/parrot/parrot_animation_manifest.json"), "manifest exists")
	var raw := FileAccess.get_file_as_string("res://assets/pets/parrot/parrot_animation_manifest.json")
	var parsed: Variant = JSON.parse_string(raw)
	_assert(typeof(parsed) == TYPE_DICTIONARY, "manifest parses")
	var m: Dictionary = parsed
	_assert(str(m.get("pet_id", "")) == "parrot", "manifest pet_id parrot")
	_assert(int(m.get("frame_canvas_width", 0)) == 128, "canvas width 128")
	_assert(int(m.get("frame_canvas_height", 0)) == 128, "canvas height 128")
	_assert(int(m.get("ground_anchor_x", 0)) == 64, "ground_anchor_x 64")
	_assert(int(m.get("ground_anchor_y", 0)) == 116, "ground_anchor_y 116")
	_assert(str(m.get("default_facing", "")) == "right", "default facing right")
	_assert(is_equal_approx(float(m.get("recommended_runtime_scale", 0.0)), 0.72), "runtime scale 0.72")
	_assert(bool(m.get("visuals_enabled", true)) == false, "manifest visuals_enabled false")
	_assert(str(m.get("status", "")) == "awaiting_artwork", "manifest awaiting_artwork")
	var anims: Array = m.get("animations", [])
	_assert(anims.size() == 4, "four animations defined")
	var by_name := {}
	for a in anims:
		by_name[str(a.get("name", ""))] = a
	_assert(by_name.has("idle"), "idle anim")
	_assert(by_name.has("move"), "move anim")
	_assert(by_name.has("chest_interaction"), "chest_interaction anim")
	_assert(by_name.has("tap_reaction"), "tap_reaction anim")
	_assert(int(by_name["idle"].get("expected_frame_count", 0)) == 5, "idle 5 frames")
	_assert(int(by_name["move"].get("expected_frame_count", 0)) == 7, "move 7 frames")
	_assert(int(by_name["chest_interaction"].get("expected_frame_count", 0)) == 8, "chest 8 frames")
	_assert(int(by_name["tap_reaction"].get("expected_frame_count", 0)) == 5, "tap 5 frames")
	_assert(int(by_name["idle"].get("fps", 0)) == 5, "idle 5 fps")
	_assert(int(by_name["move"].get("fps", 0)) == 10, "move 10 fps")
	_assert(bool(by_name["idle"].get("loop", false)) == true, "idle loops")
	_assert(bool(by_name["move"].get("loop", false)) == true, "move loops")
	_assert(bool(by_name["chest_interaction"].get("loop", true)) == false, "chest once")
	_assert(bool(by_name["tap_reaction"].get("loop", true)) == false, "tap once")
	var mapping: Dictionary = m.get("state_mapping", {})
	_assert(str(mapping.get("IDLE", "")) == "idle", "IDLE→idle")
	_assert(str(mapping.get("ROAM", "")) == "move", "ROAM→move")
	_assert(str(mapping.get("CHEST_INTERACTION", "")) == "chest_interaction", "CHEST→chest_interaction")
	_assert(str(mapping.get("TAP_REACTION", "")) == "tap_reaction", "TAP→tap_reaction")
	_assert(str(by_name["idle"].get("filename_pattern", "")).contains("parrot_idle_"), "idle filename pattern")
	_assert(str(by_name["move"].get("filename_pattern", "")).contains("parrot_move_"), "move filename pattern")
	_assert(str(by_name["chest_interaction"].get("filename_pattern", "")).contains("parrot_chest_"), "chest filename pattern")
	_assert(str(by_name["tap_reaction"].get("filename_pattern", "")).contains("parrot_tap_"), "tap filename pattern")


func _test_loader_missing_art_safe() -> void:
	var loader := PetAnimationLoader.new()
	_assert(loader.load_parrot_manifest(), "loader loads manifest")
	_assert(loader.artwork_ready == false, "artwork_ready false")
	_assert(loader.load_status == "awaiting_artwork", "load_status awaiting_artwork")
	_assert(loader.sprite_frames == null, "no SpriteFrames without art")
	_assert(loader.missing_files.size() > 0, "missing files listed")
	_assert(not loader.should_attempt_playback(), "no playback while visuals off / no art")
	_assert(loader.animation_name_for_visual_state("idle") == "idle", "map idle")
	_assert(loader.animation_name_for_visual_state("move") == "move", "map move")
	_assert(loader.animation_name_for_visual_state("roam") == "move", "map roam→move")
	_assert(loader.animation_name_for_visual_state("chest_interaction") == "chest_interaction", "map chest")
	_assert(loader.animation_name_for_visual_state("tap_reaction") == "tap_reaction", "map tap")
	var dbg: Dictionary = loader.to_debug_dict()
	_assert(dbg.get("artwork_ready") == false, "debug artwork_ready false")
	_assert(dbg.has("load_detail"), "debug load_detail")


func _test_actor_visual_tree_hidden() -> void:
	var actor := _make_actor(5)
	_assert(actor.visible == false, "actor hidden")
	_assert(actor.modulate.a == 0.0, "actor alpha 0")
	_assert(actor.is_artwork_ready() == false, "actor artwork_ready false")
	var visual := actor.get_node_or_null("PetVisual") as Node2D
	_assert(visual != null, "PetVisual exists")
	_assert(visual.visible == false, "PetVisual hidden")
	_assert(visual.modulate.a == 0.0, "PetVisual alpha 0")
	var spr := visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_assert(spr != null, "AnimatedSprite2D exists")
	_assert(spr.visible == false, "sprite hidden")
	_assert(spr.sprite_frames == null, "no sprite frames attached")
	_assert(not spr.is_playing(), "sprite not playing")
	var shadow := visual.get_node_or_null("PetShadow") as Node2D
	_assert(shadow != null, "PetShadow reserved")
	_assert(shadow.visible == false, "PetShadow hidden")
	## set_visual_state must not enable visibility without flags/art.
	actor.set_visual_state("move")
	_assert(actor.visible == false, "still invisible after set_visual_state")
	_assert(spr.visible == false, "sprite still hidden after set_visual_state")
	_assert(not spr.is_playing(), "no playback without artwork")
	var snap: Dictionary = actor.get_debug_snapshot()
	_assert(snap.get("artwork_ready") == false, "snapshot artwork_ready false")
	_assert(snap.get("visuals_enabled") == false, "snapshot visuals false")
	_assert(snap.get("pet_visual_visible") == false, "snapshot pet_visual_visible false")
	actor.queue_free()


func _test_state_animation_mapping() -> void:
	var actor := _make_actor(9)
	_assert(actor.get_visual_state() == "idle", "starts visual idle")
	actor.force_state_for_test(PetState.Kind.ROAM)
	_assert(actor.get_visual_state() == "move", "ROAM→move visual")
	actor.force_state_for_test(PetState.Kind.CHEST_INTERACTION)
	_assert(actor.get_visual_state() == "chest_interaction", "CHEST→chest_interaction visual")
	actor.trigger_tap_reaction()
	_assert(actor.get_visual_state() == "tap_reaction", "TAP→tap_reaction visual")
	actor.queue_free()


func _test_facing_flip_logic() -> void:
	var actor := _make_actor(2)
	var spr := actor.get_node("PetVisual/AnimatedSprite2D") as AnimatedSprite2D
	actor.force_facing_for_test(PetActor.Facing.RIGHT)
	_assert(actor.facing_string() == "right", "facing right")
	_assert(spr.flip_h == false, "RIGHT flip_h false")
	actor.force_facing_for_test(PetActor.Facing.LEFT)
	_assert(actor.facing_string() == "left", "facing left")
	_assert(spr.flip_h == true, "LEFT flip_h true")
	## Movement updates facing.
	actor.force_roam_to_for_test(actor.position + Vector2(80, 0))
	actor._tick_move_toward(0.05, false)
	_assert(actor.facing == PetActor.Facing.RIGHT, "move right sets RIGHT")
	_assert(spr.flip_h == false, "move right clears flip")
	actor.force_roam_to_for_test(actor.position + Vector2(-80, 0))
	actor._tick_move_toward(0.05, false)
	_assert(actor.facing == PetActor.Facing.LEFT, "move left sets LEFT")
	_assert(spr.flip_h == true, "move left sets flip")
	## Still invisible.
	_assert(actor.visible == false, "facing changes stay invisible")
	actor.queue_free()


func _test_no_placeholder_and_regression() -> void:
	## No PNG art yet.
	for folder in ["idle", "move", "chest_interaction", "tap_reaction"]:
		var dir := DirAccess.open("res://assets/pets/parrot/%s" % folder)
		_assert(dir != null, "folder %s" % folder)
		dir.list_dir_begin()
		var fname := dir.get_next()
		var art := false
		while fname != "":
			var lower := fname.to_lower()
			if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".webp"):
				art = true
			fname = dir.get_next()
		_assert(not art, "no artwork yet in %s" % folder)
	_assert(FileAccess.file_exists("res://scripts/pets/pet_animation_loader.gd"), "loader script exists")
	_assert(FileAccess.file_exists("res://assets/pets/parrot/PARROT_SPEC.md"), "PARROT_SPEC updated path")
	var plan := FileAccess.get_file_as_string("res://docs/PET_SYSTEM_PLAN.md")
	_assert(plan.contains("1B-2A"), "plan mentions 1B-2A")
	_assert(plan.contains("1B-2B"), "plan mentions 1B-2B")
	_assert(plan.contains("1B-2C"), "plan mentions 1B-2C")
	## Locked systems untouched.
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "chest open intact")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "baked reveal intact")
	_assert(env.contains("CHEST_GROUND_Y := 0.888"), "ground intact")
	_assert(flags.contains("APP_VERSION_CODE := 61"), "version unchanged")
	_assert(not plan.contains("Pet Collection") or plan.contains("Still no Pet Collection"), "no Pet Collection ship yet")
