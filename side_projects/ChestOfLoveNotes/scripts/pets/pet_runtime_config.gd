extends RefCounted
class_name PetRuntimeConfig
## Centralized Phase 1B pet runtime switches.
## Keep flags here — do not scatter enable/disable checks across the app.

## Runtime state machine + spawn on CHEST.
const PET_RUNTIME_ENABLED := true
## Phase 1B-2C: artwork validated → visible free parrot on CHEST.
const PET_VISUALS_ENABLED := true

## Design-space reference (matches project.godot logical size).
const DESIGN_WIDTH := 390.0
const DESIGN_HEIGHT := 844.0

## Movement speed in design-space pixels per second (scaled to viewport).
const MOVE_SPEED_PX_PER_SEC := 72.0

## IDLE wait before choosing ROAM / CHEST_INTERACTION (seconds).
const IDLE_MIN_SEC := 2.0
const IDLE_MAX_SEC := 5.0

## Hold times (seconds). Chest interaction also waits for one-shot anim length.
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

## Tap hitbox — derived from master visible bbox (76×88), not full 128×128 canvas.
## Pad keeps Galaxy fingertip usable without stealing nearby chest taps.
const TAP_HITBOX_BODY_W_PX := 76.0
const TAP_HITBOX_BODY_H_PX := 88.0
const TAP_HITBOX_PAD_PX := 10.0
## Master visible bbox (alpha>0) inside 128×128 canvas.
const TAP_HITBOX_BODY_LEFT_PX := 24.0
const TAP_HITBOX_BODY_TOP_PX := 28.0

## Reward presentation: hide parrot so chest open + baked scroll stay pristine.
enum RewardPetPolicy {
	PAUSE_IN_PLACE,
	HIDE_TEMPORARILY,
}


static func reward_policy_default() -> int:
	return RewardPetPolicy.HIDE_TEMPORARILY


static func tap_hitbox_size_canvas() -> Vector2:
	return Vector2(
		TAP_HITBOX_BODY_W_PX + TAP_HITBOX_PAD_PX * 2.0,
		TAP_HITBOX_BODY_H_PX + TAP_HITBOX_PAD_PX * 2.0
	)
