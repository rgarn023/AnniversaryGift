extends Node2D
class_name PetActor
## Runtime pet instance on the CHEST screen.
## Phase 1B-2C: free parrot visuals enabled (validated artwork).

signal state_changed(previous: int, next: int)
signal tapped

enum Facing { LEFT, RIGHT }

var pet_id: String = ""
var definition: PetDefinition = null
var state: int = PetState.Kind.IDLE
var facing: int = Facing.RIGHT
var safe_area: PetSafeArea = PetSafeArea.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var animation_loader: PetAnimationLoader = PetAnimationLoader.new()

var target_position: Vector2 = Vector2.ZERO
var paused: bool = false
var reward_hide_requested: bool = false
var _visual_state: String = "idle"
var _state_timer: float = 0.0
var _hold_timer: float = 0.0
var _state_before_tap: int = PetState.Kind.IDLE
var _arrival_epsilon: float = 3.0
var _configured: bool = false
var _chest_anim_playing: bool = false
## Ground path following (waypoints around chest).
var _path_waypoints: Array[Vector2] = []
var _path_index: int = 0
var _active_route_name: String = ""
var _planned_destination: Vector2 = Vector2.ZERO
## Flight architecture (disabled in production until art exists).
var _flight_path: PetFlightPath = null
var _last_safe_ground: Vector2 = Vector2.ZERO
var _flight_phase_timer: float = 0.0
var _intended_landing: Vector2 = Vector2.ZERO

var _pet_visual: Node2D = null
var _animated_sprite: AnimatedSprite2D = null
var _pet_shadow: Node2D = null
var _tap_hit: Control = null
var _runtime_scale: float = 0.72
var _shadow_draw: PetShadowDraw = null
var _position_persist_cb: Callable = Callable()
var _last_committed_pos: Vector2 = Vector2(INF, INF)


func _ready() -> void:
	_ensure_visual_nodes()
	_load_animation_contract()
	_apply_visual_gate()
	z_index = 3
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	set_physics_process(false)
	if not _configured:
		_begin_idle()


func setup_from_definition(def: PetDefinition) -> void:
	definition = def
	if def != null:
		pet_id = def.id
	state = PetState.Kind.IDLE
	_visual_state = "idle"
	_ensure_visual_nodes()
	_load_animation_contract()
	_apply_visual_gate()


func configure_runtime(vp_size: Vector2, chest_local_rect: Rect2, seed: int = -1, restore_world: Variant = null) -> void:
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	safe_area.configure(vp_size, chest_local_rect)
	_arrival_epsilon = 3.0 * safe_area.scale_factor()
	## Prefer restored last-safe world position; always validate against CURRENT safe area.
	var spawn := safe_area.default_spawn_position(rng)
	if typeof(restore_world) == TYPE_VECTOR2:
		spawn = safe_area.ensure_safe_position(restore_world as Vector2, rng)
	else:
		## Spawn must never start inside / overlapping the expanded chest obstacle.
		spawn = safe_area.ensure_safe_position(spawn, rng)
	position = spawn
	target_position = position
	_configured = true
	_ensure_visual_nodes()
	_load_animation_contract()
	_apply_runtime_scale()
	_layout_tap_hitbox()
	_apply_visual_gate()
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	_begin_idle()
	## Initial commit happens via _begin_idle once persist callback is wired.


func set_position_persist_callback(cb: Callable) -> void:
	_position_persist_cb = cb


func get_persistable_world_position() -> Vector2:
	## Last safe GROUND point. Never persist midair flight positions.
	if safe_area == null:
		return position
	if PetState.is_flight_state(state):
		var ground := _intended_landing if _intended_landing != Vector2.ZERO else _last_safe_ground
		if ground == Vector2.ZERO:
			ground = position
		return safe_area.ensure_safe_position(ground, rng)
	return safe_area.ensure_safe_position(position, rng)


func _commit_safe_position() -> void:
	## Disk writes only through PetManager callback; skip duplicates / every-frame spam.
	if not _position_persist_cb.is_valid():
		return
	var safe_pos := get_persistable_world_position()
	if safe_pos.distance_squared_to(_last_committed_pos) < 0.25:
		return
	_last_committed_pos = safe_pos
	_position_persist_cb.call(safe_pos)


func _ensure_visual_nodes() -> void:
	## Structure:
	## PetActor
	## └── PetVisual (Node2D)
	##     ├── PetShadow (PetShadowDraw) — soft runtime ellipse
	##     ├── AnimatedSprite2D — real parrot frames when artwork_ready
	##     └── TapHitBox (Control) — tight finger hitbox; does not cover chest
	if _pet_visual != null and is_instance_valid(_pet_visual):
		_ensure_shadow_script()
		_ensure_tap_hitbox_node()
		_apply_anchor_offset()
		return
	_pet_visual = get_node_or_null("PetVisual") as Node2D
	if _pet_visual == null:
		_pet_visual = Node2D.new()
		_pet_visual.name = "PetVisual"
		add_child(_pet_visual)
	_pet_shadow = _pet_visual.get_node_or_null("PetShadow") as Node2D
	if _pet_shadow == null:
		_pet_shadow = Node2D.new()
		_pet_shadow.name = "PetShadow"
		_pet_visual.add_child(_pet_shadow)
	_ensure_shadow_script()
	_animated_sprite = _pet_visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _animated_sprite == null:
		_animated_sprite = AnimatedSprite2D.new()
		_animated_sprite.name = "AnimatedSprite2D"
		_pet_visual.add_child(_animated_sprite)
	_ensure_tap_hitbox_node()
	_apply_anchor_offset()
	_animated_sprite.centered = true
	_animated_sprite.flip_h = false
	## Default hidden until gate enables (artwork + PET_VISUALS_ENABLED).
	_pet_visual.visible = false
	_pet_visual.modulate.a = 0.0
	_animated_sprite.visible = false
	_animated_sprite.modulate.a = 0.0
	_pet_shadow.visible = false
	_pet_shadow.modulate.a = 0.0


func _ensure_shadow_script() -> void:
	if _pet_shadow == null:
		return
	if _pet_shadow.get_script() == null:
		_pet_shadow.set_script(load("res://scripts/pets/pet_shadow.gd"))
	_shadow_draw = _pet_shadow as PetShadowDraw
	if _shadow_draw != null:
		_shadow_draw.queue_redraw()


func _ensure_tap_hitbox_node() -> void:
	if _pet_visual == null:
		return
	_tap_hit = _pet_visual.get_node_or_null("TapHitBox") as Control
	if _tap_hit == null:
		_tap_hit = Control.new()
		_tap_hit.name = "TapHitBox"
		_tap_hit.focus_mode = Control.FOCUS_NONE
		_tap_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_tap_hit.gui_input.connect(_on_tap_hit_gui_input)
		_pet_visual.add_child(_tap_hit)
	_layout_tap_hitbox()


func _layout_tap_hitbox() -> void:
	if _tap_hit == null or animation_loader == null:
		return
	## Hitbox in PetVisual / canvas space (PetVisual.scale applies on screen).
	## Body bbox (24,28)-(99,115) + 10px pad → 96×108, origin at ground_anchor.
	var pad := PetRuntimeConfig.TAP_HITBOX_PAD_PX
	var left := PetRuntimeConfig.TAP_HITBOX_BODY_LEFT_PX - pad
	var top := PetRuntimeConfig.TAP_HITBOX_BODY_TOP_PX - pad
	var size := PetRuntimeConfig.tap_hitbox_size_canvas()
	var anchor := animation_loader.ground_anchor
	_tap_hit.position = Vector2(left - anchor.x, top - anchor.y)
	_tap_hit.size = size
	_tap_hit.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if PetRuntimeConfig.PET_VISUALS_ENABLED and is_artwork_ready() and not reward_hide_requested and not paused
		else Control.MOUSE_FILTER_IGNORE
	)


func _on_tap_hit_gui_input(event: InputEvent) -> void:
	if not PetRuntimeConfig.PET_VISUALS_ENABLED:
		return
	if paused or reward_hide_requested:
		return
	if not is_artwork_ready():
		return
	if state == PetState.Kind.TAP_REACTION:
		## Consume rapid re-taps during reaction so they cannot fall through to chest.
		if _is_press_event(event):
			_tap_hit.accept_event()
		return
	if not _is_press_event(event):
		return
	_tap_hit.accept_event()
	trigger_tap_reaction()


func _is_press_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false


func _load_animation_contract() -> void:
	if animation_loader == null:
		animation_loader = PetAnimationLoader.new()
	if pet_id.is_empty() or pet_id == "parrot":
		animation_loader.load_parrot_manifest()
	else:
		animation_loader.load_parrot_manifest()
	if animation_loader.artwork_ready and animation_loader.sprite_frames != null:
		if _animated_sprite != null:
			_animated_sprite.sprite_frames = animation_loader.sprite_frames
	else:
		if _animated_sprite != null:
			_animated_sprite.sprite_frames = null
			if _animated_sprite.is_playing():
				_animated_sprite.stop()
	_runtime_scale = animation_loader.recommended_runtime_scale
	_apply_anchor_offset()
	_apply_runtime_scale()
	_apply_facing_to_sprite()
	_layout_tap_hitbox()


func _apply_anchor_offset() -> void:
	if _animated_sprite == null or animation_loader == null:
		return
	var anchor := animation_loader.ground_anchor
	var canvas := animation_loader.frame_canvas
	## Centered sprite: local (0,0) is frame center. Shift so ground_anchor maps to actor origin.
	var center := Vector2(float(canvas.x) * 0.5, float(canvas.y) * 0.5)
	_animated_sprite.position = Vector2(center.x - anchor.x, center.y - anchor.y)
	if _pet_shadow != null:
		## Shadow centered under feet (actor origin / ground anchor).
		_pet_shadow.position = Vector2(0, 1)


func _apply_runtime_scale() -> void:
	if _pet_visual == null:
		return
	var s := _runtime_scale
	if safe_area != null:
		s *= safe_area.scale_factor()
	_pet_visual.scale = Vector2(s, s)


func _apply_visual_gate() -> void:
	_ensure_visual_nodes()
	var show := (
		PetRuntimeConfig.PET_VISUALS_ENABLED
		and animation_loader != null
		and animation_loader.artwork_ready
		and not reward_hide_requested
	)
	if show:
		visible = true
		modulate.a = 1.0
		_pet_visual.visible = true
		_pet_visual.modulate.a = 1.0
		_animated_sprite.visible = true
		_animated_sprite.modulate.a = 1.0
		_pet_shadow.visible = true
		_pet_shadow.modulate.a = 1.0
		if _shadow_draw != null:
			_shadow_draw.queue_redraw()
		_play_animation_for_visual_state(_visual_state)
	else:
		visible = false if not PetRuntimeConfig.PET_VISUALS_ENABLED or not is_artwork_ready() else true
		## When reward-hiding, keep actor node alive but fully invisible.
		if reward_hide_requested and PetRuntimeConfig.PET_VISUALS_ENABLED and is_artwork_ready():
			visible = true
			modulate.a = 0.0
		elif not show:
			visible = false
			modulate.a = 0.0
		if _pet_visual != null:
			_pet_visual.visible = false
			_pet_visual.modulate.a = 0.0
		if _animated_sprite != null:
			_animated_sprite.visible = false
			_animated_sprite.modulate.a = 0.0
			if _animated_sprite.is_playing():
				_animated_sprite.stop()
		if _pet_shadow != null:
			_pet_shadow.visible = false
			_pet_shadow.modulate.a = 0.0
		for c in get_children():
			if c is CanvasItem and c != _pet_visual:
				(c as CanvasItem).visible = false
				(c as CanvasItem).modulate.a = 0.0
	_layout_tap_hitbox()


func set_runtime_visible(enabled: bool) -> void:
	if not PetRuntimeConfig.PET_VISUALS_ENABLED or not is_artwork_ready():
		_apply_visual_gate()
		set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
		return
	if reward_hide_requested and not enabled:
		_apply_visual_gate()
		set_process(false)
		return
	visible = enabled
	modulate.a = 1.0 if enabled else 0.0
	if _pet_visual != null:
		_pet_visual.visible = enabled
		_pet_visual.modulate.a = 1.0 if enabled else 0.0
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED and enabled)


func set_visual_state(visual_name: String) -> void:
	_visual_state = visual_name
	_apply_facing_to_sprite()
	if not PetRuntimeConfig.PET_VISUALS_ENABLED:
		return
	if animation_loader == null or not animation_loader.artwork_ready:
		return
	_play_animation_for_visual_state(visual_name)


func get_visual_state() -> String:
	return _visual_state


func is_artwork_ready() -> bool:
	return animation_loader != null and animation_loader.artwork_ready


func get_artwork_ready() -> bool:
	return is_artwork_ready()


func get_tap_hitbox_size_canvas() -> Vector2:
	return PetRuntimeConfig.tap_hitbox_size_canvas()


func get_tap_hitbox_size_screen() -> Vector2:
	var s := _runtime_scale
	if safe_area != null:
		s *= safe_area.scale_factor()
	return PetRuntimeConfig.tap_hitbox_size_canvas() * s


func get_on_screen_visible_height() -> float:
	## Approx visible parrot height after runtime scale (master body ~88px).
	var s := _runtime_scale
	if safe_area != null:
		s *= safe_area.scale_factor()
	return PetRuntimeConfig.TAP_HITBOX_BODY_H_PX * s


func _play_animation_for_visual_state(visual_name: String) -> void:
	if _animated_sprite == null:
		return
	if animation_loader == null or not animation_loader.should_attempt_playback():
		return
	var anim := animation_loader.animation_name_for_visual_state(visual_name)
	if _animated_sprite.sprite_frames == null:
		return
	if not _animated_sprite.sprite_frames.has_animation(anim):
		return
	if _animated_sprite.animation != anim or not _animated_sprite.is_playing():
		_animated_sprite.play(anim)


func transition_to(next_state: int) -> void:
	if next_state == state:
		return
	var prev := state
	state = next_state
	state_changed.emit(prev, next_state)
	match state:
		PetState.Kind.IDLE:
			set_visual_state("idle")
		PetState.Kind.ROAM:
			set_visual_state("move")
		PetState.Kind.CHEST_INTERACTION:
			## Approach uses move; one-shot chest anim starts on arrival.
			_chest_anim_playing = false
			set_visual_state("move")
		PetState.Kind.TAP_REACTION:
			set_visual_state("tap_reaction")
		PetState.Kind.TAKEOFF:
			## Flight art not ready → keep idle pose (never fake with ground move).
			if PetRuntimeConfig.flight_visuals_allowed():
				set_visual_state("takeoff")
			else:
				set_visual_state("idle")
		PetState.Kind.FLY:
			if PetRuntimeConfig.flight_visuals_allowed():
				set_visual_state("fly")
			else:
				set_visual_state("idle")
		PetState.Kind.LAND:
			if PetRuntimeConfig.flight_visuals_allowed():
				set_visual_state("land")
			else:
				set_visual_state("idle")
		_:
			set_visual_state("idle")


func trigger_tap_reaction() -> void:
	if paused or reward_hide_requested:
		return
	if state == PetState.Kind.TAP_REACTION:
		return
	_state_before_tap = state
	_hold_timer = PetRuntimeConfig.TAP_REACTION_HOLD_SEC
	## Prefer authored anim length when available (5 @ 10fps = 0.5s).
	if animation_loader != null and animation_loader.artwork_ready:
		var anim_def: Dictionary = animation_loader.get_animation_def("tap_reaction")
		var frames := int(anim_def.get("expected_frame_count", 5))
		var fps := float(anim_def.get("fps", 10.0))
		if fps > 0.0:
			_hold_timer = maxf(PetRuntimeConfig.TAP_REACTION_HOLD_SEC, float(frames) / fps + 0.15)
	transition_to(PetState.Kind.TAP_REACTION)
	tapped.emit()


func request_tap_reaction() -> void:
	trigger_tap_reaction()


func pause_for_reward() -> void:
	## Persist before temporary hide so restore survives reward teardown.
	## Cancel any in-flight path; never leave a flying pet over reward UI.
	_cancel_flight_for_reward()
	_commit_safe_position()
	paused = true
	if PetRuntimeConfig.reward_policy_default() == PetRuntimeConfig.RewardPetPolicy.HIDE_TEMPORARILY:
		reward_hide_requested = true
	## Abort in-flight motion so reward is never contested.
	if state == PetState.Kind.CHEST_INTERACTION or state == PetState.Kind.ROAM \
		or PetState.is_flight_state(state):
		target_position = position
		_clear_path()
	_chest_anim_playing = false
	_apply_visual_gate()
	set_process(false)


func resume_after_reward() -> void:
	paused = false
	reward_hide_requested = false
	## Stale pre-reward position may now overlap chest — correct before showing.
	## Always restore to valid ground (never midair).
	var ground := _last_safe_ground if _last_safe_ground != Vector2.ZERO else position
	position = safe_area.ensure_safe_position(ground, rng)
	target_position = position
	_clear_path()
	_flight_path = null
	_apply_visual_gate()
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	_begin_idle()


func _cancel_flight_for_reward() -> void:
	if not PetState.is_flight_state(state) and _flight_path == null:
		return
	var ground := _intended_landing if _intended_landing != Vector2.ZERO else _last_safe_ground
	if ground == Vector2.ZERO:
		ground = position
	position = safe_area.ensure_safe_position(ground, rng)
	_flight_path = null
	_flight_phase_timer = 0.0
	_clear_path()
	state = PetState.Kind.IDLE
	set_visual_state("idle")


func set_reward_hide_requested(hide: bool) -> void:
	reward_hide_requested = hide
	_apply_visual_gate()


func is_paused() -> bool:
	return paused


func is_chest_interacting() -> bool:
	return state == PetState.Kind.CHEST_INTERACTION


func facing_string() -> String:
	return "left" if facing == Facing.LEFT else "right"


func get_debug_snapshot() -> Dictionary:
	var anim_debug := {}
	if animation_loader != null:
		anim_debug = animation_loader.to_debug_dict()
	var path_crosses := false
	if safe_area != null:
		path_crosses = safe_area.segment_intersects_chest_exclusion(position, target_position)
	var region := -1
	if safe_area != null:
		region = safe_area.classify_region(position)
	return {
		"actor_exists": true,
		"pet_id": pet_id,
		"state": PetState.to_string_id(state),
		"state_id": state,
		"position": position,
		"target_position": target_position,
		"planned_destination": _planned_destination,
		"path_waypoints": _path_waypoints.duplicate(),
		"path_index": _path_index,
		"active_route": _active_route_name,
		"current_region": region,
		"segment_intersects_chest": path_crosses,
		"last_plan": safe_area.last_plan_debug if safe_area != null else {},
		"facing": facing_string(),
		"paused": paused,
		"reward_hide_requested": reward_hide_requested,
		"chest_interacting": is_chest_interacting(),
		"visual_state": _visual_state,
		"visuals_enabled": PetRuntimeConfig.PET_VISUALS_ENABLED,
		"runtime_enabled": PetRuntimeConfig.PET_RUNTIME_ENABLED,
		"artwork_ready": is_artwork_ready(),
		"visible": visible,
		"modulate_a": modulate.a,
		"pet_visual_visible": _pet_visual.visible if _pet_visual != null else false,
		"shadow_visible": _pet_shadow.visible if _pet_shadow != null else false,
		"flip_h": _animated_sprite.flip_h if _animated_sprite != null else false,
		"tap_hitbox_canvas": get_tap_hitbox_size_canvas(),
		"tap_hitbox_screen": get_tap_hitbox_size_screen(),
		"on_screen_visible_height": get_on_screen_visible_height(),
		"runtime_scale": _runtime_scale,
		"pet_visual_scale": _pet_visual.scale if _pet_visual != null else Vector2.ZERO,
		"safe_area": safe_area.to_debug_dict(),
		"animation_loader": anim_debug,
		"flight_enabled": PetRuntimeConfig.PET_FLIGHT_ENABLED,
		"flight_visuals_ready": PetRuntimeConfig.PET_FLIGHT_VISUALS_READY,
		"flight_behavior_allowed": PetRuntimeConfig.flight_behavior_allowed(),
		"flight_eligibility": _flight_eligibility_debug(),
		"flight_zone": safe_area.flight_zone_rect() if safe_area != null else Rect2(),
		"last_safe_ground": _last_safe_ground,
		"intended_landing": _intended_landing,
		"flight_path": _flight_path.to_debug_dict() if _flight_path != null else {},
		"saved_position_note": "persist uses last safe ground / landing — never midair",
	}


func _flight_eligibility_debug() -> Dictionary:
	return {
		"pet_flight_enabled": PetRuntimeConfig.PET_FLIGHT_ENABLED,
		"pet_flight_visuals_ready": PetRuntimeConfig.PET_FLIGHT_VISUALS_READY,
		"test_mode": PetRuntimeConfig.PET_FLIGHT_TEST_MODE,
		"behavior_allowed": PetRuntimeConfig.flight_behavior_allowed(),
		"visuals_allowed": PetRuntimeConfig.flight_visuals_allowed(),
		"idle_chance_when_enabled": PetRuntimeConfig.FLIGHT_IDLE_CHANCE,
	}


func force_state_for_test(next_state: int) -> void:
	match next_state:
		PetState.Kind.IDLE:
			_begin_idle()
		PetState.Kind.ROAM:
			_begin_roam()
		PetState.Kind.CHEST_INTERACTION:
			_begin_chest_interaction()
		PetState.Kind.TAP_REACTION:
			trigger_tap_reaction()
		PetState.Kind.TAKEOFF:
			_begin_takeoff_for_test()
		PetState.Kind.FLY:
			_begin_takeoff_for_test()
			if state == PetState.Kind.TAKEOFF:
				_enter_fly_from_takeoff()
		PetState.Kind.LAND:
			_begin_takeoff_for_test()
			if PetState.is_flight_state(state):
				_enter_land_from_fly()
		_:
			_begin_idle()


func force_roam_to_for_test(point: Vector2) -> void:
	## Test helper: plan a safe (possibly multi-waypoint) path to destination.
	if not _begin_path_to(point, PetState.Kind.ROAM):
		var dest := safe_area.random_roam_target(rng, position)
		_begin_path_to(dest, PetState.Kind.ROAM)


func force_facing_for_test(next_facing: int) -> void:
	facing = next_facing
	_apply_facing_to_sprite()


func _process(delta: float) -> void:
	if not PetRuntimeConfig.PET_RUNTIME_ENABLED:
		return
	if paused:
		return
	match state:
		PetState.Kind.IDLE:
			_tick_idle(delta)
		PetState.Kind.ROAM:
			_tick_move_toward(delta, true)
			_update_shadow_hop_from_move_anim()
		PetState.Kind.CHEST_INTERACTION:
			_tick_chest_interaction(delta)
		PetState.Kind.TAP_REACTION:
			_tick_tap_reaction(delta)
		PetState.Kind.TAKEOFF:
			_tick_takeoff(delta)
		PetState.Kind.FLY:
			_tick_fly(delta)
		PetState.Kind.LAND:
			_tick_land(delta)
	if state != PetState.Kind.ROAM and _shadow_draw != null:
		_shadow_draw.set_hop_lift(0.0)


func _clear_path() -> void:
	_path_waypoints.clear()
	_path_index = 0
	_active_route_name = ""
	_planned_destination = Vector2.ZERO


func _begin_path_to(dest: Vector2, next_state: int) -> bool:
	var plan := safe_area.plan_ground_path(position, dest)
	if not bool(plan.get("ok", false)):
		_clear_path()
		return false
	var wps: Array = plan.get("waypoints", [])
	_path_waypoints.clear()
	for w in wps:
		_path_waypoints.append(w as Vector2)
	if _path_waypoints.is_empty():
		_clear_path()
		return false
	_path_index = 0
	_active_route_name = str(plan.get("route", ""))
	_planned_destination = dest
	target_position = _path_waypoints[0]
	transition_to(next_state)
	return true


func _advance_waypoint_or_finish() -> bool:
	## Returns true if path fully complete (arrived at final dest).
	_path_index += 1
	if _path_index >= _path_waypoints.size():
		return true
	target_position = _path_waypoints[_path_index]
	return false


func _begin_idle() -> void:
	target_position = position
	_clear_path()
	_chest_anim_playing = false
	_flight_path = null
	_state_timer = rng.randf_range(PetRuntimeConfig.IDLE_MIN_SEC, PetRuntimeConfig.IDLE_MAX_SEC)
	_last_safe_ground = safe_area.ensure_safe_position(position, rng)
	transition_to(PetState.Kind.IDLE)
	## Persist when entering IDLE after movement / arrival (not every process frame).
	_commit_safe_position()


func _commit_safe_position_from_roam_arrive() -> void:
	## Explicit ROAM-target-reached hook (also covered by _begin_idle).
	_commit_safe_position()


func _tick_idle(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	## Flight is architecturally ready but production-disabled (no fake ground art).
	if PetRuntimeConfig.PET_FLIGHT_ENABLED and PetRuntimeConfig.flight_behavior_allowed():
		if rng.randf() < PetRuntimeConfig.FLIGHT_IDLE_CHANCE:
			if _begin_takeoff():
				return
	if rng.randf() < PetRuntimeConfig.IDLE_TO_ROAM_WEIGHT:
		_begin_roam()
	else:
		_begin_chest_interaction()


func _begin_roam() -> void:
	_chest_anim_playing = false
	## Region-balanced target + waypoint routing around chest (no left trap).
	var dest := safe_area.random_roam_target(rng, position)
	if not _begin_path_to(dest, PetState.Kind.ROAM):
		## Safe idle fallback — never walk a blocked straight segment.
		_begin_idle()


func _begin_chest_interaction() -> void:
	## Prefer an interaction point with a safe planned route (may detour around chest).
	var pts := safe_area.chest_interaction_points()
	var chosen := Vector2.ZERO
	var found := false
	## Prefer nearer point first, but allow opposite-side via routing.
	var ordered: Array[Vector2] = []
	for p in pts:
		ordered.append(p)
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return position.distance_squared_to(a) < position.distance_squared_to(b)
	)
	for p in ordered:
		if safe_area.is_in_chest_exclusion(p):
			continue
		var plan := safe_area.plan_ground_path(position, p)
		if bool(plan.get("ok", false)):
			chosen = p
			found = true
			break
	if not found:
		chosen = safe_area.random_chest_interaction_target(rng)
		var plan2 := safe_area.plan_ground_path(position, chosen)
		if not bool(plan2.get("ok", false)):
			_begin_roam()
			return
	_hold_timer = 0.0
	_chest_anim_playing = false
	if not _begin_path_to(chosen, PetState.Kind.CHEST_INTERACTION):
		_begin_idle()


func _tick_move_toward(delta: float, return_idle_on_arrive: bool) -> bool:
	var to_target := target_position - position
	var dist := to_target.length()
	if dist <= _arrival_epsilon:
		## Arrival must still respect chest body (interaction points are outside).
		if safe_area.is_in_chest_exclusion(target_position):
			position = safe_area.ensure_safe_position(position, rng)
			target_position = position
			_clear_path()
			_begin_idle()
			return true
		position = target_position
		## Multi-waypoint: advance to next segment before finishing.
		if not _path_waypoints.is_empty() and not _advance_waypoint_or_finish():
			return false
		_clear_path()
		if return_idle_on_arrive:
			_begin_idle()
		return true
	var step := safe_area.move_speed() * delta
	var dir := to_target / maxf(dist, 0.0001)
	var candidate: Vector2
	if step >= dist:
		candidate = target_position
	else:
		candidate = position + dir * step
	## Per-frame + high-delta tunneling protection against the expanded chest obstacle.
	if safe_area.candidate_step_blocked(position, candidate):
		## Try re-plan toward remaining destination; else idle.
		var dest := _planned_destination if _planned_destination != Vector2.ZERO else target_position
		position = safe_area.ensure_safe_position(position, rng)
		if dest != Vector2.ZERO and _begin_path_to(dest, state):
			return false
		target_position = position
		_clear_path()
		_begin_idle()
		return true
	_update_facing(dir.x)
	position = candidate
	## Soft clamp — never drift into ocean/UI during movement.
	if safe_area.is_in_ocean(position) or safe_area.is_in_ui_exclusion(position):
		position = safe_area.clamp_to_roam(position)
	if step >= dist:
		if not _path_waypoints.is_empty() and not _advance_waypoint_or_finish():
			return false
		_clear_path()
		if return_idle_on_arrive:
			_begin_idle()
		return true
	return false


func _tick_chest_interaction(delta: float) -> void:
	if _chest_anim_playing:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_begin_idle()
		return
	var arrived := _tick_move_toward(delta, false)
	if arrived:
		_face_toward_chest()
		## Stop translation; play chest_interaction once.
		target_position = position
		_chest_anim_playing = true
		set_visual_state("chest_interaction")
		var hold := PetRuntimeConfig.CHEST_INTERACTION_HOLD_SEC
		if animation_loader != null and animation_loader.artwork_ready:
			var anim_def: Dictionary = animation_loader.get_animation_def("chest_interaction")
			var frames := int(anim_def.get("expected_frame_count", 8))
			var fps := float(anim_def.get("fps", 10.0))
			if fps > 0.0:
				hold = maxf(hold, float(frames) / fps + 0.2)
		_hold_timer = hold


func _tick_tap_reaction(delta: float) -> void:
	_hold_timer -= delta
	if _hold_timer <= 0.0:
		if _state_before_tap == PetState.Kind.ROAM:
			_begin_roam()
		else:
			_begin_idle()


## --- Flight architecture (production disabled until art ready) ---

func _begin_takeoff() -> bool:
	if not PetRuntimeConfig.flight_behavior_allowed():
		return false
	_last_safe_ground = safe_area.ensure_safe_position(position, rng)
	_commit_safe_position() ## persist ground before leaving sand
	_flight_path = safe_area.build_flight_path(_last_safe_ground, rng)
	_intended_landing = _flight_path.landing_point
	_flight_path.last_safe_ground = _last_safe_ground
	_flight_phase_timer = PetRuntimeConfig.FLIGHT_TAKEOFF_DURATION_SEC
	_clear_path()
	transition_to(PetState.Kind.TAKEOFF)
	return true


func _begin_takeoff_for_test() -> void:
	## Test harness entry — requires PET_FLIGHT_TEST_MODE or PET_FLIGHT_ENABLED.
	if not PetRuntimeConfig.flight_behavior_allowed():
		return
	_begin_takeoff()


func _enter_fly_from_takeoff() -> void:
	if _flight_path == null:
		_begin_idle()
		return
	_flight_phase_timer = PetRuntimeConfig.FLIGHT_CRUISE_DURATION_SEC
	_flight_path.progress = 0.0
	transition_to(PetState.Kind.FLY)


func _enter_land_from_fly() -> void:
	if _flight_path == null:
		position = safe_area.ensure_safe_position(_last_safe_ground, rng)
		_begin_idle()
		return
	_flight_phase_timer = PetRuntimeConfig.FLIGHT_LAND_DURATION_SEC
	## Snap approach → landing lerp uses path.landing_point.
	transition_to(PetState.Kind.LAND)


func _tick_takeoff(delta: float) -> void:
	if not PetRuntimeConfig.flight_behavior_allowed():
		_cancel_flight_for_reward()
		_begin_idle()
		return
	_flight_phase_timer -= delta
	## Soft vertical lift into flight zone (architecture; visuals gated).
	if _flight_path != null:
		var t := 1.0 - clampf(_flight_phase_timer / maxf(PetRuntimeConfig.FLIGHT_TAKEOFF_DURATION_SEC, 0.001), 0.0, 1.0)
		var lift_target := safe_area.clamp_to_flight_zone(
			Vector2(_last_safe_ground.x, safe_area.flight_zone_rect().end.y - 4.0)
		)
		position = _last_safe_ground.lerp(lift_target, t)
		## Ground collision does not apply while airborne; still avoid UI top.
		if safe_area.is_in_ui_exclusion(position):
			position = safe_area.clamp_to_flight_zone(position)
	if _flight_phase_timer <= 0.0:
		_enter_fly_from_takeoff()


func _tick_fly(delta: float) -> void:
	if not PetRuntimeConfig.flight_behavior_allowed() or _flight_path == null:
		_cancel_flight_for_reward()
		_begin_idle()
		return
	_flight_path.advance(delta, PetRuntimeConfig.FLIGHT_CRUISE_DURATION_SEC)
	var p := _flight_path.current_point()
	p = safe_area.clamp_to_flight_zone(p)
	## Airborne: chest ground obstacle does not apply; UI/flight-zone does.
	if safe_area.is_in_ui_exclusion(p):
		p = safe_area.clamp_to_flight_zone(p)
	var dx := p.x - position.x
	position = p
	_update_facing(dx)
	if _flight_path.is_complete():
		_enter_land_from_fly()


func _tick_land(delta: float) -> void:
	if not PetRuntimeConfig.flight_behavior_allowed():
		_cancel_flight_for_reward()
		_begin_idle()
		return
	_flight_phase_timer -= delta
	var landing := _intended_landing
	if landing == Vector2.ZERO and _flight_path != null:
		landing = _flight_path.landing_point
	landing = safe_area.ensure_safe_position(landing, rng)
	var t := 1.0 - clampf(_flight_phase_timer / maxf(PetRuntimeConfig.FLIGHT_LAND_DURATION_SEC, 0.001), 0.0, 1.0)
	var from := position
	if _flight_path != null:
		from = _flight_path.destination
	position = from.lerp(landing, t)
	## Final frames must not enter chest exclusion.
	if safe_area.is_in_chest_exclusion(position):
		position = safe_area.ensure_safe_position(position, rng)
	if _flight_phase_timer <= 0.0:
		position = landing
		_last_safe_ground = position
		_flight_path = null
		_intended_landing = Vector2.ZERO
		_begin_idle()


func _face_toward_chest() -> void:
	var mid := safe_area.chest_exclusion_rect().get_center().x
	if position.x <= mid:
		facing = Facing.RIGHT
	else:
		facing = Facing.LEFT
	_apply_facing_to_sprite()


func _update_facing(dx: float) -> void:
	var prev := facing
	if dx < -0.01:
		facing = Facing.LEFT
	elif dx > 0.01:
		facing = Facing.RIGHT
	if facing != prev:
		_apply_facing_to_sprite()


func _apply_facing_to_sprite() -> void:
	## Author art faces RIGHT. LEFT = flip_h.
	if _animated_sprite == null:
		return
	_animated_sprite.flip_h = (facing == Facing.LEFT)


func _update_shadow_hop_from_move_anim() -> void:
	if _shadow_draw == null or _animated_sprite == null:
		return
	if not _animated_sprite.is_playing() or _animated_sprite.animation != "move":
		_shadow_draw.set_hop_lift(0.0)
		return
	## Move frames: crouch→lift→peak→land. Peak around mid indices.
	var frame := _animated_sprite.frame
	var lift := 0.0
	match frame:
		1:
			lift = 0.25
		2:
			lift = 0.55
		3:
			lift = 0.85
		4:
			lift = 0.45
		5:
			lift = 0.15
		_:
			lift = 0.0
	_shadow_draw.set_hop_lift(lift)


func is_y_in_ocean_exclusion(y_frac: float) -> bool:
	return y_frac < PetRuntimeConfig.WATER_BOTTOM_FRAC


func clamp_roam_y_frac(y_frac: float) -> float:
	return clampf(y_frac, PetRuntimeConfig.WATER_BOTTOM_FRAC + 0.02, PetRuntimeConfig.CHEST_GROUND_Y)
