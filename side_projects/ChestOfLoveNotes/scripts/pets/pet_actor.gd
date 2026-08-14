extends Node2D
class_name PetActor
## Runtime pet instance on the CHEST screen.
## Phase 1B-1: state machine + movement only — ZERO visible pixels.

signal state_changed(previous: int, next: int)
signal tapped

enum Facing { LEFT, RIGHT }

var pet_id: String = ""
var definition: PetDefinition = null
var state: int = PetState.Kind.IDLE
var facing: int = Facing.RIGHT
var safe_area: PetSafeArea = PetSafeArea.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var target_position: Vector2 = Vector2.ZERO
var paused: bool = false
var reward_hide_requested: bool = false
var _visual_state: String = "idle"
var _state_timer: float = 0.0
var _hold_timer: float = 0.0
var _state_before_tap: int = PetState.Kind.IDLE
var _arrival_epsilon: float = 3.0
var _configured: bool = false


func _ready() -> void:
	_apply_visual_gate()
	z_index = 3
	## Logic runs even while visually invisible.
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	set_physics_process(false)
	## No Area2D / clickable region — do not intercept CHEST taps.
	if not _configured:
		_begin_idle()


func setup_from_definition(def: PetDefinition) -> void:
	definition = def
	if def != null:
		pet_id = def.id
	state = PetState.Kind.IDLE
	_visual_state = "idle"
	_apply_visual_gate()


func configure_runtime(vp_size: Vector2, chest_local_rect: Rect2, seed: int = -1) -> void:
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	safe_area.configure(vp_size, chest_local_rect)
	_arrival_epsilon = 3.0 * safe_area.scale_factor()
	position = safe_area.default_spawn_position(rng)
	target_position = position
	_configured = true
	_apply_visual_gate()
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	_begin_idle()


func _apply_visual_gate() -> void:
	## Critical: no placeholder graphics. Node2D draws nothing without children.
	if PetRuntimeConfig.PET_VISUALS_ENABLED:
		visible = true
		modulate.a = 1.0
	else:
		visible = false
		modulate.a = 0.0
		## Strip any accidental drawable children (safety).
		for c in get_children():
			if c is CanvasItem:
				(c as CanvasItem).visible = false
				(c as CanvasItem).modulate.a = 0.0


func set_runtime_visible(enabled: bool) -> void:
	## Kept for API compatibility; Phase 1B-1 still honors PET_VISUALS_ENABLED.
	if not PetRuntimeConfig.PET_VISUALS_ENABLED:
		_apply_visual_gate()
		set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
		return
	visible = enabled
	modulate.a = 1.0 if enabled else 0.0
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)


func set_visual_state(visual_name: String) -> void:
	## Future animation API for Phase 1B-2. No-op while visuals are disabled.
	_visual_state = visual_name
	if not PetRuntimeConfig.PET_VISUALS_ENABLED:
		return
	## Phase 1B-2: play idle / move / chest_interaction / tap_reaction groups.


func get_visual_state() -> String:
	return _visual_state


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
			set_visual_state("chest_interaction")
		PetState.Kind.TAP_REACTION:
			set_visual_state("tap_reaction")
		_:
			set_visual_state("idle")


func trigger_tap_reaction() -> void:
	## Callable by tests / future hitbox. Does not register input itself.
	if paused:
		return
	_state_before_tap = state
	if _state_before_tap == PetState.Kind.TAP_REACTION:
		_state_before_tap = PetState.Kind.IDLE
	_hold_timer = PetRuntimeConfig.TAP_REACTION_HOLD_SEC
	transition_to(PetState.Kind.TAP_REACTION)
	tapped.emit()


func request_tap_reaction() -> void:
	## Alias for Phase 1A API.
	trigger_tap_reaction()


func pause_for_reward() -> void:
	paused = true
	## Optional future hide pathway (no visible effect while visuals are off).
	if PetRuntimeConfig.reward_policy_default() == PetRuntimeConfig.RewardPetPolicy.HIDE_TEMPORARILY:
		reward_hide_requested = true
	## Abort in-flight chest interaction so reward is never contested.
	if state == PetState.Kind.CHEST_INTERACTION or state == PetState.Kind.ROAM:
		target_position = position
	set_process(false)


func resume_after_reward() -> void:
	paused = false
	reward_hide_requested = false
	_apply_visual_gate()
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	_begin_idle()


func set_reward_hide_requested(hide: bool) -> void:
	## Explicit control for Phase 1B-2 policy choice A vs B.
	reward_hide_requested = hide
	_apply_visual_gate()


func is_paused() -> bool:
	return paused


func is_chest_interacting() -> bool:
	return state == PetState.Kind.CHEST_INTERACTION


func facing_string() -> String:
	return "left" if facing == Facing.LEFT else "right"


func get_debug_snapshot() -> Dictionary:
	return {
		"actor_exists": true,
		"pet_id": pet_id,
		"state": PetState.to_string_id(state),
		"state_id": state,
		"position": position,
		"target_position": target_position,
		"facing": facing_string(),
		"paused": paused,
		"reward_hide_requested": reward_hide_requested,
		"chest_interacting": is_chest_interacting(),
		"visual_state": _visual_state,
		"visuals_enabled": PetRuntimeConfig.PET_VISUALS_ENABLED,
		"runtime_enabled": PetRuntimeConfig.PET_RUNTIME_ENABLED,
		"visible": visible,
		"modulate_a": modulate.a,
		"safe_area": safe_area.to_debug_dict(),
	}


func force_state_for_test(next_state: int) -> void:
	## Deterministic test hook.
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
	target_position = safe_area.clamp_to_roam(point)
	transition_to(PetState.Kind.ROAM)


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
		PetState.Kind.CHEST_INTERACTION:
			_tick_chest_interaction(delta)
		PetState.Kind.TAP_REACTION:
			_tick_tap_reaction(delta)


func _begin_idle() -> void:
	target_position = position
	_state_timer = rng.randf_range(PetRuntimeConfig.IDLE_MIN_SEC, PetRuntimeConfig.IDLE_MAX_SEC)
	transition_to(PetState.Kind.IDLE)


func _tick_idle(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	if rng.randf() < PetRuntimeConfig.IDLE_TO_ROAM_WEIGHT:
		_begin_roam()
	else:
		_begin_chest_interaction()


func _begin_roam() -> void:
	target_position = safe_area.random_roam_target(rng)
	transition_to(PetState.Kind.ROAM)


func _begin_chest_interaction() -> void:
	target_position = safe_area.random_chest_interaction_target(rng)
	_hold_timer = 0.0
	transition_to(PetState.Kind.CHEST_INTERACTION)


func _tick_move_toward(delta: float, return_idle_on_arrive: bool) -> bool:
	var to_target := target_position - position
	var dist := to_target.length()
	if dist <= _arrival_epsilon:
		position = target_position
		if return_idle_on_arrive:
			_begin_idle()
		return true
	var step := safe_area.move_speed() * delta
	if step >= dist:
		_update_facing(to_target.x)
		position = target_position
		if return_idle_on_arrive:
			_begin_idle()
		return true
	var dir := to_target / dist
	_update_facing(dir.x)
	position += dir * step
	## Soft clamp — never drift into ocean/UI during movement.
	if safe_area.is_in_ocean(position) or safe_area.is_in_ui_exclusion(position):
		position = safe_area.clamp_to_roam(position)
	return false


func _tick_chest_interaction(delta: float) -> void:
	if _hold_timer > 0.0:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_begin_idle()
		return
	var arrived := _tick_move_toward(delta, false)
	if arrived:
		_hold_timer = PetRuntimeConfig.CHEST_INTERACTION_HOLD_SEC


func _tick_tap_reaction(delta: float) -> void:
	_hold_timer -= delta
	if _hold_timer <= 0.0:
		## Return to prior calm state (IDLE if previous was TAP/CHEST).
		if _state_before_tap == PetState.Kind.ROAM:
			_begin_roam()
		else:
			_begin_idle()


func _update_facing(dx: float) -> void:
	if dx < -0.01:
		facing = Facing.LEFT
	elif dx > 0.01:
		facing = Facing.RIGHT


func is_y_in_ocean_exclusion(y_frac: float) -> bool:
	return y_frac < PetRuntimeConfig.WATER_BOTTOM_FRAC


func clamp_roam_y_frac(y_frac: float) -> float:
	return clampf(y_frac, PetRuntimeConfig.WATER_BOTTOM_FRAC + 0.02, PetRuntimeConfig.CHEST_GROUND_Y)
