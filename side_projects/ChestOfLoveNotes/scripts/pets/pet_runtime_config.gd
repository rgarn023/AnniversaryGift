extends RefCounted
class_name PetRuntimeConfig
## Centralized Phase 1B pet runtime switches.
## Keep flags here — do not scatter enable/disable checks across the app.

## Runtime state machine + spawn on CHEST (logic only).
const PET_RUNTIME_ENABLED := true
## Artwork / sprites / drawn placeholders. Must stay false until Phase 1B-2C
## (after 1B-2B artwork validation). Phase 1B-2A prepares the loader only.
const PET_VISUALS_ENABLED := false

## Design-space reference (matches project.godot logical size).
const DESIGN_WIDTH := 390.0
const DESIGN_HEIGHT := 844.0

## Movement speed in design-space pixels per second (scaled to viewport).
const MOVE_SPEED_PX_PER_SEC := 72.0

## IDLE wait before choosing ROAM / CHEST_INTERACTION (seconds).
const IDLE_MIN_SEC := 2.0
const IDLE_MAX_SEC := 5.0

## Hold times (seconds).
const CHEST_INTERACTION_HOLD_SEC := 1.2
const TAP_REACTION_HOLD_SEC := 0.85

## Geometry margins (design-space px; scaled with viewport).
const EDGE_MARGIN_PX := 12.0
const CHEST_EXCLUSION_MARGIN_PX := 12.0

## Environment fractions (docs/PET_SAFE_AREA.md / ChestEnvironment).
const WATER_BOTTOM_FRAC := 0.560
const CHEST_GROUND_Y := 0.888

## Approximate UI bands as fractions of viewport height (CHEST landing).
## Header (~52) + message (~44) + gutters — pets stay below this band.
const UI_TOP_EXCLUDE_FRAC := 0.16
## Bottom nav (~80 touch units) — pets stay above.
const UI_BOTTOM_NAV_FRAC := 0.095

## Probability weight when leaving IDLE (roam vs chest interaction).
const IDLE_TO_ROAM_WEIGHT := 0.72

## Future reward presentation policy (Phase 1B-2 may choose hide).
enum RewardPetPolicy {
	PAUSE_IN_PLACE,
	HIDE_TEMPORARILY,
}


static func reward_policy_default() -> int:
	## Phase 1B-1: pause only (no visible hide needed while visuals are off).
	return RewardPetPolicy.PAUSE_IN_PLACE
