# Parrot Spec — First Free Pet

| Field | Value |
| --- | --- |
| Pet ID | `parrot` |
| Display name | Parrot |
| Unlock type | **FREE** |
| Default unlocked | Yes — available to all users |
| Role | First test / flagship free pet |
| Billing | **None** — never tied to Google Play Billing |
| Artwork | **None currently** — art integration pending |

Do **not** invent a final visual design here. Animation art will be provided later.

---

## Scale / scene considerations (pending art)

- CHEST design space is ~390×844; chest host is 252×326
- Parrot should read as a companion on the sand, not compete with the chest as the hero
- Prefer a modest horizontal footprint so roam beside the chest stays clear of UI
- Exact pixel scale TBD when sprites arrive; integrate under `assets/pets/parrot/`

---

## Required future animation groups

| Group | Folder | Intent (Phase 1B+) |
| --- | --- | --- |
| Idle | `idle/` | Stand/perch naturally; occasional subtle idle motion |
| Move / roam | `move/` | Hop/walk across approved sand safe areas |
| Chest interaction | `chest_interaction/` | Approach chest; rub/nuzzle or perch beside |
| Tap reaction | `tap_reaction/` | Brief reaction on tap, then return to normal |
| Source | `source/` | Raw/source art for tooling (not runtime) |

No sprites exist in these folders yet (`.gitkeep` only).

---

## Intended Phase 1 behavior (document only — not implemented visually in 1A)

### IDLE

- Stands/perches naturally on sand
- Occasional subtle idle motion

### ROAM

- Moves around approved safe sand areas (`docs/PET_SAFE_AREA.md`)
- Does not cover important UI
- Does not wander into ocean
- Does not obscure chest reward presentation

### CHEST_INTERACTION

- Occasionally approaches the chest
- May rub/nuzzle against or perch beside the chest
- Must not alter chest position, frames, or timing

### TAP_REACTION

- Reacts briefly when tapped
- Returns to normal state behavior

---

## Catalog / unlock

Defined in `config/pets/catalog.json`:

- `unlock_type`: `FREE`
- `default_unlocked`: `true`
- `enabled`: `true`
- `asset_root`: `res://assets/pets/parrot/`

Phase 1A persists ownership locally via `PetManager`; parrot is owned by default. The production CHEST screen does **not** spawn the actor until Phase 1B.
