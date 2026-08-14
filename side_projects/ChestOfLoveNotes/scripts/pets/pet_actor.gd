extends Node2D
class_name PetActor
## Future runtime pet instance (state-machine entry point).
## Phase 1A: structural only — no visible graphics, not mounted on production CHEST.
##
## Safe-area constants mirror docs/PET_SAFE_AREA.md (fractions of viewport height).

signal state_changed(previous: int, next: int)
signal tapped

## Conceptual environment fractions (documentation + future roam clamp).
const WATER_BOTTOM_FRAC := 0.560
const CHEST_GROUND_Y := 0.888
const EDGE_MARGIN_PX := 12.0

var pet_id: String = ""
var definition: PetDefinition = null
var state: int = PetState.Kind.IDLE
var _visible_for_runtime: bool = false


func _ready() -> void:
	## Invisible until Phase 1B enables runtime presentation + art.
	visible = _visible_for_runtime
	modulate.a = 0.0
	z_index = 3
	set_process(false)
	set_physics_process(false)


func setup_from_definition(def: PetDefinition) -> void:
	definition = def
	if def != null:
		pet_id = def.id
	state = PetState.Kind.IDLE


func set_runtime_visible(enabled: bool) -> void:
	## Phase 1B will call this after art is wired. Phase 1A keeps false.
	_visible_for_runtime = enabled
	visible = enabled
	modulate.a = 1.0 if enabled else 0.0
	set_process(enabled)


func transition_to(next_state: int) -> void:
	if next_state == state:
		return
	var prev := state
	state = next_state
	state_changed.emit(prev, next_state)
	## Phase 1B: play idle/move/chest/tap animation groups here.


func request_tap_reaction() -> void:
	transition_to(PetState.Kind.TAP_REACTION)
	tapped.emit()


func is_y_in_ocean_exclusion(y_frac: float) -> bool:
	return y_frac < WATER_BOTTOM_FRAC


func clamp_roam_y_frac(y_frac: float) -> float:
	## Stay on sand below water band; leave chest-ground approach to interaction logic.
	return clampf(y_frac, WATER_BOTTOM_FRAC + 0.02, CHEST_GROUND_Y)
