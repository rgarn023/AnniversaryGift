extends RefCounted
class_name PetRuntimeConfig
## Centralized Phase 1B pet runtime switches.
## Keep flags here — do not scatter enable/disable checks across the app.

## Runtime state machine + spawn on CHEST.
const PET_RUNTIME_ENABLED := true
## Phase 1B-2C: artwork validated → visible free parrot on CHEST.
const PET_VISUALS_ENABLED := true

## Flight behavior (TAKEOFF / FLY / LAND). Keep false until flight art is approved.
const PET_FLIGHT_ENABLED := false
## Flight sprite groups ready? Always false until takeoff/fly/land PNGs exist + approved.
const PET_FLIGHT_VISUALS_READY := false
## Test-only: allow state/path logic without enabling production flight or visuals.
static var PET_FLIGHT_TEST_MODE := false

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
## Legacy base inset — roam X now uses visual body extents + SCREEN_EDGE_PAD_PX.
const EDGE_MARGIN_PX := 12.0
## Extra pad beyond the visible parrot body at screen L/R edges.
const SCREEN_EDGE_PAD_PX := 8.0
## Visible body extents from ground_anchor (64,116) inside 128 canvas (bbox 24..99).
const PET_VISUAL_EXTENT_LEFT_PX := 40.0
const PET_VISUAL_EXTENT_RIGHT_PX := 35.0
## Base padding around the solid chest obstacle before pet-body Minkowski expand.
const CHEST_EXCLUSION_MARGIN_PX := 12.0
## Extra pad so sprite body (not just feet anchor) stays clear of the chest shell.
const PET_CHEST_BODY_PAD_PX := 10.0
## Matches parrot recommended_runtime_scale (art contract).
const PET_RUNTIME_VISUAL_SCALE := 0.72
## Solid chest body vs full transparent host — leaves seaward sand as a transit band.
const CHEST_SOLID_WIDTH_FRAC := 0.82
const CHEST_SOLID_HEIGHT_PX := 150.0
## Body expand factors (<1) so side pockets + upper transit remain walkable
## after visual screen-edge padding is applied to roam X.
const CHEST_EXCLUSION_HORIZONTAL_BODY_FACTOR := 0.42
const CHEST_EXCLUSION_VERTICAL_BODY_FACTOR := 0.28

## Environment fractions (docs/PET_SAFE_AREA.md / ChestEnvironment).
const WATER_BOTTOM_FRAC := 0.560
const CHEST_GROUND_Y := 0.888

## Approximate UI bands as fractions of viewport height (CHEST landing).
## Header (~52) + message (~44) + gutters — pets stay below this band.
const UI_TOP_EXCLUDE_FRAC := 0.16
## Bottom nav (~80 touch units) — pets stay above.
const UI_BOTTOM_NAV_FRAC := 0.095

## Flight zone (normalized viewport fractions). Sky/ocean/open OK; UI/title/nav excluded.
const FLIGHT_Y_MIN_FRAC := 0.18
const FLIGHT_Y_MAX_FRAC := 0.52
const FLIGHT_X_PAD_FRAC := 0.06
## Eventual idle→takeoff chance when PET_FLIGHT_ENABLED (not used while disabled).
const FLIGHT_IDLE_CHANCE := 0.15
const FLIGHT_TAKEOFF_DURATION_SEC := 0.55
const FLIGHT_CRUISE_DURATION_SEC := 2.4
const FLIGHT_LAND_DURATION_SEC := 0.65

## Ground behavior decision weights (sum = 1.0) when leaving IDLE.
## 35% short / 30% medium / 20% cross-screen / 10% chest / 5% longer idle.
const BEHAVIOR_SHORT_ROAM_WEIGHT := 0.35
const BEHAVIOR_MEDIUM_ROAM_WEIGHT := 0.30
const BEHAVIOR_CROSS_ROAM_WEIGHT := 0.20
const BEHAVIOR_CHEST_WEIGHT := 0.10
const BEHAVIOR_LONG_IDLE_WEIGHT := 0.05
## Legacy alias — roam share of ground decisions (short+medium+cross).
const IDLE_TO_ROAM_WEIGHT := 0.85

## Longer idle hold when the long-idle behavior wins.
const LONG_IDLE_MIN_SEC := 4.5
const LONG_IDLE_MAX_SEC := 8.0

## Roam target distribution (full-width beach — LEFT ↔ RIGHT via routing).
const ROAM_MIN_TRAVEL_PX := 48.0
## Within roam picks, force opposite half often enough to reach both shores.
const ROAM_CROSS_SIDE_CHANCE := 0.55
const ROAM_SHORT_CHANCE := 0.35
const ROAM_MEDIUM_CHANCE := 0.30
## Remainder ≈ long / cross-screen within roam.

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


static func flight_behavior_allowed() -> bool:
	## Production flight OR explicit test harness.
	return PET_FLIGHT_ENABLED or PET_FLIGHT_TEST_MODE


static func flight_visuals_allowed() -> bool:
	## Never fake-fly with ground move art in production.
	return PET_FLIGHT_VISUALS_READY and flight_behavior_allowed()


static func set_flight_test_mode(enabled: bool) -> void:
	PET_FLIGHT_TEST_MODE = enabled
