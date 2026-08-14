extends RefCounted
class_name PetState
## Runtime states for pet actors (Phase 1B+).
## TAKEOFF / FLY / LAND are architecturally ready; production gated by PET_FLIGHT_ENABLED.

enum Kind {
	IDLE,
	ROAM,
	CHEST_INTERACTION,
	TAP_REACTION,
	TAKEOFF,
	FLY,
	LAND,
}


static func to_string_id(kind: Kind) -> String:
	match kind:
		Kind.IDLE:
			return "idle"
		Kind.ROAM:
			return "roam"
		Kind.CHEST_INTERACTION:
			return "chest_interaction"
		Kind.TAP_REACTION:
			return "tap_reaction"
		Kind.TAKEOFF:
			return "takeoff"
		Kind.FLY:
			return "fly"
		Kind.LAND:
			return "land"
	return "idle"


static func from_string_id(id: String) -> Kind:
	match id:
		"roam":
			return Kind.ROAM
		"chest_interaction":
			return Kind.CHEST_INTERACTION
		"tap_reaction":
			return Kind.TAP_REACTION
		"takeoff":
			return Kind.TAKEOFF
		"fly":
			return Kind.FLY
		"land":
			return Kind.LAND
		_:
			return Kind.IDLE


static func is_flight_state(kind: Kind) -> bool:
	return kind == Kind.TAKEOFF or kind == Kind.FLY or kind == Kind.LAND


static func is_ground_state(kind: Kind) -> bool:
	return not is_flight_state(kind)
