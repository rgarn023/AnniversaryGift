# Step 3 — Baked Scroll Reveal Integration

**Branch:** `cursor/mobile-production-polish-caa0`  
**Version:** `0.1.61-baked-scroll-reveal` (versionCode 61)  
**Runtime script:** `scripts/chest/treasure_chest.gd`

## Previous normal-scroll flow (retired for production)

```
chest_00…chest_12
→ _arm_scroll_hidden_behind_lip / _enter_layered_open
→ ChestFrame = open_back
→ ScrollLayer visible + Y tween (_play_scroll_rise_tween)
→ ChestFrontRim occlusion
→ REWARD_HOLD
→ inventory transition
```

## New normal-scroll flow

```
chest_00…chest_12
→ SCROLL_POST_OPEN_BEAT_SEC (0.10)
→ _play_baked_scroll_reveal()
     reveal_00_hidden … reveal_07_final (discrete opaque swaps)
→ REWARD_HOLD_SEC (0.60) on reveal_07
→ inventory transition
```

## Inactive / retained legacy methods

- `_enter_layered_open`, `_exit_layered_open`
- `_arm_scroll_hidden_behind_lip`
- `_play_scroll_rise_tween`
- `_set_scroll_rise_amount`

These remain in source for history/tooling but are **not** called from `_open_full` / `_open_short` normal reward paths.

## Empty chest

Unchanged: approved open only → glow / “No new scrolls today.” No baked reveal.
