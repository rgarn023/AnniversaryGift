extends Node2D
class_name PetActor
## Runtime pet instance on the CHEST screen.
## Phase 1B-2A: animation contract + loader ready; ZERO visible pixels.
## PetVisual exists but stays hidden until PET_VISUALS_ENABLED + artwork.

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

var _pet_visual: Node2D = null
var _animated_sprite: AnimatedSprite2D = null
var _pet_shadow: Node2D = null
var _runtime_scale: float = 0.72


func _ready() -> void:
	_ensure_visual_nodes()
	_load_animation_contract()
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
	_ensure_visual_nodes()
	_load_animation_contract()
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
	_ensure_visual_nodes()
	_load_animation_contract()
	_apply_runtime_scale()
	_apply_visual_gate()
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
	_begin_idle()


func _ensure_visual_nodes() -> void:
	## Structure:
	## PetActor
	## ├── PetVisual (Node2D) — always hidden in 1B-2A
	## │   ├── PetShadow (Node2D) — runtime ellipse later; not drawn yet
	## │   └── AnimatedSprite2D — no SpriteFrames until artwork_ready
	if _pet_visual != null and is_instance_valid(_pet_visual):
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
	_animated_sprite = _pet_visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _animated_sprite == null:
		_animated_sprite = AnimatedSprite2D.new()
		_animated_sprite.name = "AnimatedSprite2D"
		_pet_visual.add_child(_animated_sprite)
	## Offset so ground_anchor lands on PetActor.position (feet on sand path).
	## Sprite draws centered on AnimatedSprite2D by default — shift by anchor.
	_apply_anchor_offset()
	## Hard hide — no placeholder texture, no colored rect.
	_pet_visual.visible = false
	_pet_visual.modulate.a = 0.0
	_animated_sprite.visible = false
	_animated_sprite.modulate.a = 0.0
	_pet_shadow.visible = false
	_pet_shadow.modulate.a = 0.0
	_animated_sprite.sprite_frames = null
	_animated_sprite.centered = true
	_animated_sprite.flip_h = false


func _load_animation_contract() -> void:
	## Safe if called repeatedly. Missing art → artwork_ready=false, no spam.
	if animation_loader == null:
		animation_loader = PetAnimationLoader.new()
	if pet_id.is_empty() or pet_id == "parrot":
		animation_loader.load_parrot_manifest()
	else:
		## Future pets: still use parrot loader path only for Phase 1.
		animation_loader.load_parrot_manifest()
	if animation_loader.artwork_ready and animation_loader.sprite_frames != null:
		## Attach frames only when complete; still keep node hidden.
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


func _apply_anchor_offset() -> void:
	if _animated_sprite == null or animation_loader == null:
		return
	var anchor := animation_loader.ground_anchor
	var canvas := animation_loader.frame_canvas
	## Centered sprite: local (0,0) is frame center. Shift so ground_anchor maps to actor origin.
	var center := Vector2(float(canvas.x) * 0.5, float(canvas.y) * 0.5)
	_animated_sprite.position = Vector2(center.x - anchor.x, center.y - anchor.y)
	if _pet_shadow != null:
		## Shadow sits at feet (actor origin) — tiny downward bias reserved for later.
		_pet_shadow.position = Vector2(0, 1)


func _apply_runtime_scale() -> void:
	if _pet_visual == null:
		return
	var s := _runtime_scale
	if safe_area != null:
		s *= safe_area.scale_factor()
	_pet_visual.scale = Vector2(s, s)


func _apply_visual_gate() -> void:
	## Critical: no placeholder graphics. Visual subtree stays fully hidden in 1B-2A.
	_ensure_visual_nodes()
	var show := PetRuntimeConfig.PET_VISUALS_ENABLED and animation_loader != null and animation_loader.artwork_ready
	if show:
		visible = true
		modulate.a = 1.0
		_pet_visual.visible = true
		_pet_visual.modulate.a = 1.0
		_animated_sprite.visible = true
		_animated_sprite.modulate.a = 1.0
		## Shadow still reserved — not rendered until Phase 1B-2C chooses to.
		_pet_shadow.visible = false
		_pet_shadow.modulate.a = 0.0
	else:
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
		## Strip any accidental drawable children (safety) except known structure.
		for c in get_children():
			if c is CanvasItem and c != _pet_visual:
				(c as CanvasItem).visible = false
				(c as CanvasItem).modulate.a = 0.0


func set_runtime_visible(enabled: bool) -> void:
	## Kept for API compatibility; Phase 1B-2A still honors PET_VISUALS_ENABLED + artwork.
	if not PetRuntimeConfig.PET_VISUALS_ENABLED or not is_artwork_ready():
		_apply_visual_gate()
		set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)
		return
	visible = enabled
	modulate.a = 1.0 if enabled else 0.0
	if _pet_visual != null:
		_pet_visual.visible = enabled
		_pet_visual.modulate.a = 1.0 if enabled else 0.0
	set_process(PetRuntimeConfig.PET_RUNTIME_ENABLED)


func set_visual_state(visual_name: String) -> void:
	## Animation API — no-op playback while visuals disabled or art missing.
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
	var anim_debug := {}
	if animation_loader != null:
		anim_debug = animation_loader.to_debug_dict()
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
		"artwork_ready": is_artwork_ready(),
		"visible": visible,
		"modulate_a": modulate.a,
		"pet_visual_visible": _pet_visual.visible if _pet_visual != null else false,
		"flip_h": _animated_sprite.flip_h if _animated_sprite != null else false,
		"safe_area": safe_area.to_debug_dict(),
		"animation_loader": anim_debug,
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


func is_y_in_ocean_exclusion(y_frac: float) -> bool:
	return y_frac < PetRuntimeConfig.WATER_BOTTOM_FRAC


func clamp_roam_y_frac(y_frac: float) -> float:
	return clampf(y_frac, PetRuntimeConfig.WATER_BOTTOM_FRAC + 0.02, PetRuntimeConfig.CHEST_GROUND_Y)
