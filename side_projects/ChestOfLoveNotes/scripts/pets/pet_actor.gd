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
	## Last safe point: clamp current against chest/ocean/UI before callers persist.
	if safe_area == null:
		return position
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
	_commit_safe_position()
	paused = true
	if PetRuntimeConfig.reward_policy_default() == PetRuntimeConfig.RewardPetPolicy.HIDE_TEMPORARILY:
		reward_hide_requested = true
	## Abort in-flight motion so reward is never contested.
	if state == PetState.Kind.CHEST_INTERACTION or state == PetState.Kind.ROAM:
		target_position = position
	_chest_anim_playing = false
	_apply_visual_gate()
	set_process(false)


func resume_after_reward() -> void:
	paused = false
	reward_hide_requested = false
	## Stale pre-reward position may now overlap chest — correct before showing.
	position = safe_area.ensure_safe_position(position, rng)
	target_position = position
	_apply_visual_gate()
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	_begin_idle()


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
	return {
		"actor_exists": true,
		"pet_id": pet_id,
		"state": PetState.to_string_id(state),
		"state_id": state,
		"position": position,
		"target_position": target_position,
		"segment_intersects_chest": path_crosses,
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
		_:
			_begin_idle()


func force_roam_to_for_test(point: Vector2) -> void:
	## Test helper: clamp destination; reject chest-crossing by snapping to same-side safe point.
	var dest := safe_area.clamp_to_roam(point)
	if not safe_area.is_roam_path_clear(position, dest):
		dest = safe_area.random_roam_target(rng, position)
	target_position = dest
	transition_to(PetState.Kind.ROAM)


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
	if state != PetState.Kind.ROAM and _shadow_draw != null:
		_shadow_draw.set_hop_lift(0.0)


func _begin_idle() -> void:
	target_position = position
	_chest_anim_playing = false
	_state_timer = rng.randf_range(PetRuntimeConfig.IDLE_MIN_SEC, PetRuntimeConfig.IDLE_MAX_SEC)
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
	if rng.randf() < PetRuntimeConfig.IDLE_TO_ROAM_WEIGHT:
		_begin_roam()
	else:
		_begin_chest_interaction()


func _begin_roam() -> void:
	_chest_anim_playing = false
	## Path-aware: never accept a straight segment that crosses the chest body.
	target_position = safe_area.random_roam_target(rng, position)
	transition_to(PetState.Kind.ROAM)


func _begin_chest_interaction() -> void:
	## Prefer an interaction point whose approach segment does not cross the chest body.
	var pts := safe_area.chest_interaction_points()
	var chosen := Vector2.ZERO
	var found := false
	for p in pts:
		if safe_area.is_in_chest_exclusion(p):
			continue
		## Allow approach along a clear segment; if already near, skip segment check.
		if position.distance_to(p) <= _arrival_epsilon * 2.0 or not safe_area.segment_intersects_chest_exclusion(position, p):
			chosen = p
			found = true
			break
	if not found and not pts.is_empty():
		## Pick nearest side — teleport-step via ensure won't cross mid-body.
		var best := pts[0]
		var best_d := position.distance_squared_to(best)
		for i in range(1, pts.size()):
			var d := position.distance_squared_to(pts[i])
			if d < best_d:
				best = pts[i]
				best_d = d
		## If straight path crosses, reposition to same-side sand first (no tunnel).
		if safe_area.segment_intersects_chest_exclusion(position, best):
			var ex := safe_area.chest_exclusion_rect()
			var mid := ex.get_center().x
			var side_x := ex.position.x - 8.0 if best.x < mid else ex.end.x + 8.0
			position = safe_area.ensure_safe_position(Vector2(side_x, best.y), rng)
		chosen = best
		found = true
	if not found:
		chosen = safe_area.random_chest_interaction_target(rng)
	target_position = chosen
	_hold_timer = 0.0
	_chest_anim_playing = false
	transition_to(PetState.Kind.CHEST_INTERACTION)


func _tick_move_toward(delta: float, return_idle_on_arrive: bool) -> bool:
	var to_target := target_position - position
	var dist := to_target.length()
	if dist <= _arrival_epsilon:
		## Arrival must still respect chest body (interaction points are outside).
		if safe_area.is_in_chest_exclusion(target_position):
			position = safe_area.ensure_safe_position(position, rng)
			target_position = position
			_begin_idle()
			return true
		position = target_position
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
		position = safe_area.ensure_safe_position(position, rng)
		target_position = position
		_begin_idle()
		return true
	_update_facing(dir.x)
	position = candidate
	## Soft clamp — never drift into ocean/UI during movement.
	if safe_area.is_in_ocean(position) or safe_area.is_in_ui_exclusion(position):
		position = safe_area.clamp_to_roam(position)
	if step >= dist:
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
