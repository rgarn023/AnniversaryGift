# animation_v3 — Integration Plan (Step 3 preview)

**This file is documentation only.**  
Step 1 does **not** remove, disable, or rewire any runtime code.

---

## Goal of future integration

Replace **only** the normal unread-scroll reward reveal path with a baked `animation_v3` frame sequence after the approved 13-frame chest opening.

```
CURRENT APPROVED CHEST OPENING (KEEP)
→ NEW BAKED CHEST + SCROLL REVEAL SEQUENCE (REPLACE current layered reveal)
→ reward hold (KEEP / retune)
→ existing transition to inventory / note (KEEP)
```

Empty-chest behavior stays on the approved opening + glow/particles path.

---

## KEEP

| Component | Location | Why |
|-----------|----------|-----|
| Approved 13-frame chest opening `#00`→`#12` | `assets/chest/animation_v2/chest_frames/*`, `LoveNotesChest.CHEST_FRAME_FILES`, `_open_full` / `_open_short` frame walk | Locked, working, shared by empty + unread |
| Empty chest first open | `main.gd::_on_chest_tapped` → `play_open_animation(..., emerge_scroll=false)` | Must remain closed→open→glow→“No new scrolls today.” |
| Already-open empty retap | `play_open_empty_pulse()` | Subtle glow/particles only; no reopen |
| Final reward transition | `main.gd::_on_chest_tapped` dim fade → `_show_inventory()` | Existing note / inventory handoff |
| Rapid-tap / busy guards | `_chest_action_busy`, `animating`, `_input_locked`, `set_interaction_enabled`, skip guards in `play_open_animation` | Prevent overlapping opens |
| Glow / particles (if still appropriate) | `GlowPulse`, `CPUParticles2D` dust/sparks/motes, warm spill | May remain as secondary effects; not a chest reconstruction |
| Chest plant / sand grounding | host size 252×326, `CHEST_GROUND_Y`, `CHEST_FOOT_Y_FRAC` | Correct sand placement must not move |
| Beach / ocean / sky environment | `chest_environment.gd` | Explicitly out of scope |
| Backend / auth / My Person / map / etc. | network scripts, supabase | Explicitly out of scope |

---

## REPLACE (normal scroll reward only — future Step 3)

| Current component | Location | Replace with |
|-------------------|----------|--------------|
| Standalone scroll Y-tween / reveal | `_play_scroll_rise_tween`, `_set_scroll_rise_amount`, `_arm_scroll_hidden_behind_lip`, `_place_scroll_and_rim` (rise math) | Discrete baked `reveal_00`…`reveal_07` frame swaps on the single chest sprite |
| Layered open swap | `_enter_layered_open`, `_exit_layered_open`, `_layered_open` | Stay on single opaque frame sequence after `#12` |
| `open_back` chest reconstruction | `OPEN_BACK` → `ChestFrame` texture swap | Unused for normal scroll once v3 integrated |
| `front_rim` occlusion layer | `FRONT_RIM` → `ChestFrontRim` | Unused for normal scroll once v3 integrated |
| Scroll cavity host / helper clipping | `ScrollCavityClip` (+ any legacy clip/mask paths) | Not needed when reveal is baked |
| Standalone scroll sprite | `ScrollLayer` using `love_scroll_reward.png` | Scroll is painted into baked frames |
| Combined unread progress scroll branch | `_set_frame_progress(..., emerge_scroll=true)` scroll portion | Optional validation path only; production uses discrete reveal frames |
| Timing constants for layered emerge | `SCROLL_POST_OPEN_BEAT_SEC`, `SCROLL_EMERGE_SEC`, rise ease curves | New frame timing from `animation_v3` manifest recommendation |

**Do not delete these in Step 1.** Keep them until Step 3 lands and empty-chest / fallback paths are confirmed.

---

## Suggested future call shape (not implemented)

Today:

```
_on_chest_tapped
  → play_open_animation(reduced_motion, emerge_scroll=has_new)
       → _open_full / _open_short
            → 13-frame open to chest_12
            → if emerge_scroll: _arm_scroll_hidden_behind_lip → _play_scroll_rise_tween → REWARD_HOLD
  → if has_new: fade → _show_inventory
```

Future (conceptual):

```
_on_chest_tapped
  → play_open_animation(reduced_motion, emerge_scroll=has_new)
       → _open_full / _open_short
            → 13-frame open to chest_12   # UNCHANGED
            → if emerge_scroll: play baked reveal_00…reveal_07 → hold
  → if has_new: fade → _show_inventory     # UNCHANGED
```

Empty path never enters the baked reveal.

---

## Explicit non-goals for Step 3

- Do not regenerate or alter `animation_v2` chest frames
- Do not change empty-chest flow
- Do not change beach / water / sky
- Do not touch Supabase / auth / My Person / disconnect / QR / map
- Do not rebuild APK as part of art integration unless a later release step asks for it

---

## Step checklist

1. **Step 1 (done by this pass):** audit + folders + spec + manifest — no runtime change  
2. **Step 2:** create baked `scroll_reveal/reveal_*.png` artwork from `chest_12` + approved scroll  
3. **Step 3:** wire normal scroll reward to `animation_v3`; leave empty path alone; then retire layered reveal for that path only  
