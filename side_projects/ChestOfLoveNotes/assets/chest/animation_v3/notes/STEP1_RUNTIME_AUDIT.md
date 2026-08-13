# Step 1 — Runtime Scroll-Reveal Audit

**Branch:** `cursor/mobile-production-polish-caa0`  
**Starting HEAD:** `ea15a071cd8832fbab955013bcda9a09683190c2`  
**Pass:** preparation / audit / scaffolding only  
**Runtime modified:** no  
**APK built:** no  

---

## 1. Approved chest opening (LOCKED)

All frames present under `assets/chest/animation_v2/chest_frames/`:

| File | Dimensions | Color |
|------|------------|-------|
| `chest_00_closed.png` | 512×512 | RGBA 8-bit |
| `chest_01_open_08.png` | 512×512 | RGBA 8-bit |
| `chest_02_open_17.png` | 512×512 | RGBA 8-bit |
| `chest_03_open_25.png` | 512×512 | RGBA 8-bit |
| `chest_04_open_33.png` | 512×512 | RGBA 8-bit |
| `chest_05_open_42.png` | 512×512 | RGBA 8-bit |
| `chest_06_open_50.png` | 512×512 | RGBA 8-bit |
| `chest_07_open_58.png` | 512×512 | RGBA 8-bit |
| `chest_08_open_67.png` | 512×512 | RGBA 8-bit |
| `chest_09_open_75.png` | 512×512 | RGBA 8-bit |
| `chest_10_open_83.png` | 512×512 | RGBA 8-bit |
| `chest_11_open_92.png` | 512×512 | RGBA 8-bit |
| `chest_12_fully_open.png` | 512×512 | RGBA 8-bit |

Exact paths:

```
assets/chest/animation_v2/chest_frames/chest_00_closed.png
assets/chest/animation_v2/chest_frames/chest_01_open_08.png
assets/chest/animation_v2/chest_frames/chest_02_open_17.png
assets/chest/animation_v2/chest_frames/chest_03_open_25.png
assets/chest/animation_v2/chest_frames/chest_04_open_33.png
assets/chest/animation_v2/chest_frames/chest_05_open_42.png
assets/chest/animation_v2/chest_frames/chest_06_open_50.png
assets/chest/animation_v2/chest_frames/chest_07_open_58.png
assets/chest/animation_v2/chest_frames/chest_08_open_67.png
assets/chest/animation_v2/chest_frames/chest_09_open_75.png
assets/chest/animation_v2/chest_frames/chest_10_open_83.png
assets/chest/animation_v2/chest_frames/chest_11_open_92.png
assets/chest/animation_v2/chest_frames/chest_12_fully_open.png
```

Loaded by `LoveNotesChest.CHEST_FRAME_FILES` / `_load_chest_sequence()` in `scripts/chest/treasure_chest.gd`.  
**Not modified in this pass.**

---

## 2. Authoritative fully-open base (`chest_12`)

| Field | Value |
|-------|-------|
| Path | `assets/chest/animation_v2/chest_frames/chest_12_fully_open.png` |
| Dimensions | 512×512 |
| RGBA / alpha | Yes (8-bit RGBA) |
| Visible chest bounds (alpha bbox) | (117, 144, 442, 428) |
| Base anchor (authored / runtime constant) | (256, 420) — `CHEST_FOOT_CANVAS_Y = 420` |
| Visual center (bbox midpoint) | ≈ (279.5, 286.0) |
| Mid-body horizontal center (~y 300–380) | ≈ 256 |
| Current runtime scale | `_fit_scale ≈ 0.4921875` (host 252×326 fit into 512 canvas) |
| Current runtime draw rect | ≈ Rect2(0, 60.70, 252, 252) inside host |
| Safe as immutable base for baked reveal | **Yes** |

Manifest / code agree: production canvas 512×512, base anchor (256, 420).  
Layers `chest_open_back.png` + `chest_open_front_rim.png` are derived from this frame for the *current* layered reveal (to be retired later for normal scroll).

---

## 3. Current runtime chest placement (DO NOT CHANGE)

| Field | Value |
|-------|-------|
| Script / class | `scripts/chest/treasure_chest.gd` → `LoveNotesChest` |
| Scene template | `scenes/chest/Chest.tscn` (Control + script; runtime usually constructs via `.new()`) |
| Runtime node path | `…/_screen_host` → `ChestStage` → `LoveNotesChest` (created in `main.gd::_show_main_chest`) |
| Host size | 252×326 |
| Anchors | left/right 0.5; top/bottom `ChestEnvironment.CHEST_GROUND_Y` = **0.888** |
| Offsets | ±126 X; top `-(h * 420/512)`; bottom `+(h * (1 - 420/512))` |
| Foot fraction | `CHEST_FOOT_Y_FRAC = 420/512 ≈ 0.8203125` |
| Fit / scale | `_fit_scale = min(host.x/512, host.y/512) ≈ 0.4921875` |
| Pivot | `ChestAnimationRoot.pivot_offset = size * 0.5` |
| Wrapper transform | `_emphasis_scale` (default 1.0 at settle); `_anticipation_y` (0 at settle) |
| Host z_index | 5 |
| Fully-open runtime pose | same plant/size; frame index 12 on `ChestFrame` until layered swap |

---

## 4. Current broken normal-scroll reveal — involved pieces

### Scenes / scripts

| Piece | Role |
|-------|------|
| `scripts/main.gd` | `_on_chest_tapped` decides `has_new`, calls `play_open_animation(..., emerge_scroll)`, then inventory fade |
| `scripts/chest/treasure_chest.gd` | All opening + layered scroll emerge logic |
| `scenes/chest/Chest.tscn` | Template for `LoveNotesChest` |
| `scripts/chest/chest_environment.gd` | Beach plant constant only (`CHEST_GROUND_Y`); not part of scroll compositing |

### Runtime visual hierarchy (inside `LoveNotesChest`)

```
LoveNotesChest (Control, z_index 5 on stage)
├── ChestAnimationRoot                    (_root_visual)
│   ├── ChestContactShadow                z=1
│   ├── ChestWarmSpill                    z=2
│   ├── ChestFrame                        z=3   ← single chest sprite; becomes open_back when layered
│   ├── ScrollCavityClip                  z=5   ← Control host; clip_contents=false; clip_children=DISABLED
│   │   └── ScrollLayer                   (TextureRect; love_scroll_reward.png; Y-rises)
│   ├── ChestFrontRim                     z=6   ← front_rim occlusion
│   ├── GlowPulse                         z=7
│   ├── dust / sparks / motes             z=8   (CPUParticles2D)
├── badge Label                           z=20
├── label Label                           z=12
└── Button (full-rect tap)
```

### z_index order (reward layered mode)

1. Contact shadow (1)  
2. Warm spill (2)  
3. Open back via `ChestFrame` (3)  
4. Scroll cavity host + `ScrollLayer` (5)  
5. Front rim (6)  
6. Glow (7)  
7. Particles (8)  
8. UI labels / button  

### Textures

| Asset | Used at runtime? |
|-------|------------------|
| `layers/chest_open_back.png` (512×512) | **Yes** — `_enter_layered_open` swaps onto `ChestFrame` |
| `layers/chest_open_front_rim.png` (512×512) | **Yes** — `ChestFrontRim` |
| `scroll/love_scroll_reward.png` (720×305) | **Yes** — `ScrollLayer` (primary) |
| `scroll/love_scroll.png` (56×132) | Preloaded only; not drawn (vertical legacy) |
| `scroll/love_scroll_horizontal.png` (132×56) | Preloaded only; not drawn (tiny legacy) |
| `layers/chest_cavity_mask.png` (512×512) | **Not loaded/drawn** (v57+); kept on disk; historically caused gray rectangle |

### Tweens / animation

| Mechanism | Usage |
|-----------|-------|
| `Tween` (`create_tween`) | Open progress, scroll rise Y, glow/spill, dim overlay, press feedback |
| `AnimationPlayer` | **None** for chest/scroll reveal |
| Shaders / materials | `ScrollLayer.material = null` — no shader |
| `ColorRect` | Dim overlay in `main.gd::_on_chest_tapped` only (screen fade), not cavity mask |
| `Panel` / StyleBox | Badge only; not scroll cavity |
| `CanvasLayer` | Not used for chest reveal |

### Mask / clip nodes

| Node | Current state |
|------|---------------|
| `ScrollCavityClip` | Plain `Control`; **no** StyleBox/ColorRect/texture; `clip_contents=false`; `CLIP_CHILDREN_DISABLED` |
| Legacy `CavityMaskHost` / `chest_cavity_mask.png` | Removed from runtime draw path (v57); constant `CAVITY_MASK_LEGACY` remains for history |
| Front rim occlusion | Soft occlusion via transparent PNG over scroll — source of Z-order / cavity glitches the redesign abandons |

### Key methods (normal scroll)

| Method | Role |
|--------|------|
| `play_open_animation(short, emerge_scroll)` | Entry; sets `_show_scroll_on_finish` |
| `_open_full` / `_open_short` | 13-frame open; if scroll → arm + tween + hold |
| `_set_frame_progress` | Discrete opaque frame swaps during open |
| `_arm_scroll_hidden_behind_lip` | Layer swap + buried scroll visible behind lip |
| `_enter_layered_open` | `ChestFrame` → `open_back`; show scroll+rim |
| `_play_scroll_rise_tween` | Continuous Y rise 0→1 over `SCROLL_EMERGE_SEC` (0.55) |
| `_set_scroll_rise_amount` | Places scroll; emits `scroll_emerged` |
| `_place_scroll_and_rim` | Geometry / rise math |
| `_apply_finished_state` | End pose |

Timing constants (current):

- `OPEN_DURATION_SEC = 1.0` (+ anticipation 0.06, settle 0.10)  
- `SCROLL_POST_OPEN_BEAT_SEC = 0.11`  
- `SCROLL_EMERGE_SEC = 0.55`  
- `REWARD_HOLD_SEC = 0.60`  

---

## 5. Exact current unread reward flow

```
main.gd::_on_chest_tapped
  guards: private chest, animating, _chest_action_busy
  has_new = unread>0 OR requests>0 OR debug force
  [if already OPEN_EMPTY/OPENED and not has_new → empty retap path; return]
  create dim ColorRect (z=4); tween alpha → 0.45
  await _chest.play_open_animation(reduced_motion, emerge_scroll=has_new=true)
      treasure_chest.gd::play_open_animation
        state = OPENING
        play_press_feedback()
        await _open_full()   [or _open_short if RM]
          ANTICIPATION_SEC (0.06)
          tween _set_frame_progress(0→1, emerge_scroll=false) over OPEN_DURATION_SEC (1.0)
            discrete swaps chest_00 … chest_12 on ChestFrame
            mid-open: particles + glow
          force show chest_12; settle emphasis/glow (SETTLE_SEC 0.10)
          ★ LAYER SWAP: _arm_scroll_hidden_behind_lip()
               _enter_layered_open()  → ChestFrame = open_back; rim+scroll layers on
               _scroll_rise = 0; place buried behind lip; ScrollCavityClip.visible = true
          wait SCROLL_POST_OPEN_BEAT_SEC (0.11)
          await _play_scroll_rise_tween(SCROLL_EMERGE_SEC 0.55)
               state = OPEN_SCROLL_EMERGING
               tween _set_scroll_rise_amount(0→1)  # continuous Y only
               emit scroll_emerged when tip clears lip
          glow swell
          state = OPEN_WAITING_FOR_SCROLL
          await REWARD_HOLD_SEC (0.60)
        state = TRANSITIONING
        emit open_finished
  dim fade alpha → 0.92 (0.34s) + 0.06s
  _show_inventory()   # existing note / chest inventory transition
```

Where chest switches to layered mode: `_arm_scroll_hidden_behind_lip` → `_enter_layered_open` **after** fully open, **before** scroll tween.  
Where scroll visibility changes: same arm call sets `ScrollCavityClip` / `ScrollLayer` / `ChestFrontRim` visible.  
Where scroll tween starts: `_play_scroll_rise_tween` after post-open beat.  
Where final transition begins: back in `main.gd` after `play_open_animation` returns — dim deepen → `_show_inventory`.

---

## 6. Exact current empty reward flow (DO NOT ALTER)

**First open, no unread:**

```
_on_chest_tapped (has_new=false)
  dim overlay
  play_open_animation(..., emerge_scroll=false)
    _open_full: chest_00→chest_12 only
    NO layer swap, NO scroll tween
    brief settle; state = OPEN_EMPTY
  undim
  EmptyChestHint = "No new scrolls today."
```

**Already-open empty retap:**

```
_on_chest_tapped
  play_open_empty_pulse()
    glow/motes/shimmer only; stay on fully-open frame
  "No new scrolls today."
```

animation_v3 must not touch this path.

---

## 7. Functions / scripts that will eventually need replacement (Step 3)

Primary: `scripts/chest/treasure_chest.gd`

- `_enter_layered_open` / `_exit_layered_open`  
- `_arm_scroll_hidden_behind_lip`  
- `_play_scroll_rise_tween`  
- `_set_scroll_rise_amount` / scroll rise math in `_place_scroll_and_rim`  
- `_set_scroll_layers_visible`  
- layered branches inside `_set_frame_progress`, `_apply_finished_state`, `hide_rolled_scroll`  
- Constants: `OPEN_BACK`, `FRONT_RIM`, `SCROLL_LAYER`, cavity/scroll geometry constants  

Caller remains `main.gd::_on_chest_tapped` (likely only a flag / post-open call change).  
Empty pulse + 13-frame open remain.

---

## 8. Known failure modes motivating animation_v3

Observed with the current layered approach (documented in code comments / prior passes):

- Scroll appearing to cut through or come from behind the chest incorrectly  
- Chest-back / interior glitches at handoff  
- Clipping / mask artifacts; visible gray mask rectangles (cavity mask path — removed from draw but illustrative)  
- Complicated Z-order (`open_back` → scroll → `front_rim`)  

Baked frames with immutable `chest_12` pixels eliminate runtime compositing for the normal reward path.

---

## 9. Can chest_12 safely serve as immutable base?

**Yes.** It is the exact end frame of the approved opening, 512×512 RGBA, planted at authored (256, 420), and already used as the derivation source for today’s layers. No runtime issue found that would prevent a baked reveal approach; the layered compositor itself is what we are retiring for normal scroll rewards.

---

## 10. Out of scope confirmations

- Water / sky / beach / moon / stars: not modified  
- Backend / auth / My Person / disconnect / QR / map / Hide-Delete / Saved-Hidden: not modified  
- App version: not incremented  
- APK / export / GitHub Release: not performed  
- Fake reveal frames: not created  
- Current scroll reveal runtime: not deleted, not switched  
