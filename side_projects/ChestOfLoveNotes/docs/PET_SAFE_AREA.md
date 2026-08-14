# Pet Safe Area — CHEST Environment (Audit Only)

**Phase 1A:** Documentation only. The CHEST scene was **not** modified.  
Pets must adapt to the approved layout; the chest must not move for pets.

Logical design space: **390 × 844** (`project.godot`).

---

## Environment vertical bands (fractions of environment height)

From `ChestEnvironment`:

| Band | Approx. Y frac | Notes |
| --- | --- | --- |
| Sky | `0.0` → `SKY_BOTTOM_FRAC` (`0.470`) | Stars / sky wash; not a roam target |
| Water / ocean | `WATER_TOP_FRAC` (`0.470`) → `WATER_BOTTOM_FRAC` (`0.560`) | **Exclusion** — no wander into ocean |
| Sand / beach | below `~0.560` to bottom | Primary future roam surface |
| Chest foot plant | `CHEST_GROUND_Y` (`0.888`) | Locked grounding line |

---

## Chest bounds (do not change)

From `_show_main_chest()` in `main.gd` + `LoveNotesChest`:

- Host size: **252 × 326**
- Horizontally centered
- Foot aligned to `ChestEnvironment.CHEST_GROUND_Y` via `LoveNotesChest.CHEST_FOOT_Y_FRAC`
- `z_index = 5` on chest

**Pet rules:**

- May approach / nuzzle / perch **beside** the chest (Phase 1B+)
- Must not cover the chest during open / baked scroll reveal / reward handoff
- Must not sit on the unread badge or block the chest tap target while a reward is in progress

Conceptual chest exclusion during reward: inflate the chest host rect by a small margin (~8–16 px) and treat as no-roam / pause-roam.

---

## UI exclusion zones

On the **CHEST** reward landing (not YOUR CHEST):

| Zone | Role | Pet rule |
| --- | --- | --- |
| Top safe margins | Status bar / notch (`MobileUi.apply_safe_margins`) | Stay below |
| `ChestHeaderRow` (~52 touch units) | Centered **CHEST** title | Do not obscure title |
| `ChestMessageSafeZone` (~44 touch units) | Empty/status text (“No new scrolls today.”) | Do not cover message band |
| Bottom nav (~`TOUCH_NAV_H`) | Primary navigation | Stay above nav |
| Screen-edge margins | ~8–12 px inset | Keep paws/body inside |

YOUR CHEST management (filters, Saved/Hidden, lists) is a separate screen — pets are **CHEST-environment** creatures for Phase 1B; do not invent roam on inventory lists in 1A/1B.

---

## Conceptual roam polygon (Phase 1B+)

Approximate safe sand roam (viewport fractions; refine with art scale later):

- **Y min:** just below message safe-zone bottom, and always `> WATER_BOTTOM_FRAC` (~0.56)
- **Y max:** above bottom nav; typically stay north of chest foot when idle, or approach chest X for interaction
- **X:** inset from left/right edges; prefer open sand left/right of chest host

Shoreline/ocean exclusion: `y < WATER_BOTTOM_FRAC` is out of bounds.

### Chest-interaction targets (Phase 1B-1)

`PetSafeArea.chest_interaction_points()` places the pet **beside** the inflated chest exclusion (left and right), near ~72% of exclusion height (lower body / sand contact), never over the reward cavity center. Chosen points are clamped to roam X and sand Y.

---

## Screen-edge margins

- Left/right: ≥ 12 px (design space)
- Bottom: clear of nav hit targets
- Top: clear of title + message safe-zone

---

## Implementation note

Phase 1B-1 implements these constraints in `PetSafeArea` / `PetActor` using
viewport-derived fractions (not a single fragile fixed coordinate set).
`PET_VISUALS_ENABLED` remains false — roam is validated programmatically only.
