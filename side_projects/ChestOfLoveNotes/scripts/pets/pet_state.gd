extends RefCounted
class_name PetState
## Future runtime states for pet actors (Phase 1B+).
## Phase 1A: enum + helpers only — no visual behavior.

enum Kind {
	IDLE,
	ROAM,
	CHEST_INTERACTION,
	TAP_REACTION,
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
	return "idle"


static func from_string_id(id: String) -> Kind:
	match id:
		"roam":
			return Kind.ROAM
		"chest_interaction":
			return Kind.CHEST_INTERACTION
		"tap_reaction":
			return Kind.TAP_REACTION
		_:
			return Kind.IDLE
