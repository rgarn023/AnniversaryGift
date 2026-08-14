# Pet System Plan — Chest of Love Notes

First free pet: **Parrot** (`id: parrot`).  
Phases through **1B-2A** keep the production app visually identical to the known-good pre-pet baseline.

Baseline protected by: `docs/KNOWN_GOOD_PRE_PET_BASELINE.md`  
Safe-area notes: `docs/PET_SAFE_AREA.md`  
Parrot art contract: `assets/pets/parrot/PARROT_SPEC.md`  
Animation manifest: `assets/pets/parrot/parrot_animation_manifest.json`

---

## PHASE 1A — Architecture / scaffolding — **COMPLETE**

**Goal:** Clean foundation with zero user-visible change.

Delivered:

- `PetDefinition` + scalable catalog (`config/pets/catalog.json`)
- `PetManager` — catalog, owned IDs, active pet ID, local persistence
- `PetState` enum — IDLE / ROAM / CHEST_INTERACTION / TAP_REACTION
- `PetActor` scene + script (structural; later mounted invisibly)
- Default: parrot **FREE**, `default_unlocked`, considered owned
- Asset folder tree under `assets/pets/parrot/` (no artwork)
- Docs for plan, safe area, parrot spec

---

## PHASE 1B — Free parrot runtime on CHEST

### PHASE 1B-1 — Invisible runtime integration — **COMPLETE**

**Goal:** Mount pet runtime on CHEST with **zero visible pixels**.

Delivered:

- `PetRuntimeConfig.PET_RUNTIME_ENABLED = true`
- `PetRuntimeConfig.PET_VISUALS_ENABLED = false`
- CHEST → `ChestEnvironment` → `PetRuntimeRoot` → `PetActor`
- IDLE / ROAM / CHEST_INTERACTION / TAP_REACTION state machine (logic only)
- Safe-area roam clamps; chest exclusion; reward pause/resume
- Duplicate-spawn protection; persistence; no artwork / Pet UI / billing

### PHASE 1B-2A — Asset contract + visual loader preparation — **COMPLETE**

**Goal:** Lock the exact production art/animation contract and runtime loader **without** enabling visuals.

Delivered:

- `parrot_animation_manifest.json` (canvas, anchors, frame counts, fps, filenames)
- Updated `PARROT_SPEC.md` with size / facing / flip / shadow contract
- `PetAnimationLoader` — non-fatal missing-art path; later `artwork_ready = true`
- `PetActor` visual tree (`PetVisual` → `AnimatedSprite2D`) prepared
- State → animation mapping + `flip_h` facing hooks
- `tools/validate_parrot_assets.py`

### PHASE 1B-2B — Actual parrot artwork + validation — **COMPLETE**

Delivered:

- Author PNG frames per manifest filenames / canvas / anchors
- `validate_parrot_assets.py` → `ARTWORK_READY` (25 frames)
- Still did **not** enable `PET_VISUALS_ENABLED` until 1B-2C

### PHASE 1B-2C — Enable visible runtime + Galaxy test — **THIS PHASE**

Expected / delivered:

- Flip `PET_VISUALS_ENABLED` after artwork passes validation
- Spawn/show free parrot on CHEST with idle/move/chest/tap animations
- Soft runtime shadow + tight tap hitbox; hide during reward
- Still no Pet Collection UI, purchases, or gifting
- versionCode 63 / `0.1.63-parrot-visible-fix`
---

## PHASE 1C — Pet selection / basic Pet Collection

**Goal:** User can view owned pets and choose the active one.

Expected:

- Minimal Pet Collection surface (not on first CHEST viewport clutter)
- Select active pet → persist `active_pet_id`
- Still free parrot only unless later catalog entries exist
- No billing

---

## PHASE 2 — My Person pet gifting + chest delivery

**Goal:** Gift pets to My Person; receive via chest-style delivery.

Expected:

- Future reward type: `PET_GIFT` (not implemented yet)
- Delivery animation distinct from scroll reveal (do not break scroll path)
- Pairing / My Person flows extended carefully; disconnect semantics unchanged

---

## PHASE 3 — Google Play Billing / paid pets

**Goal:** Paid pet unlocks via Play Billing.

Expected:

- BillingClient / SKUs / receipts / entitlements
- Paid catalog entries (none yet)
- Free parrot remains free and must not depend on billing

---

## Architecture sketch (through 1B-2A)

```
PetManager
  ├─ catalog (PetDefinition[])
  ├─ owned_pet_ids
  ├─ active_pet_id
  ├─ load/save user://coln_pets.cfg
  └─ spawn → PetRuntimeRoot → PetActor (invisible)

PetActor
  ├─ state machine: IDLE / ROAM / CHEST_INTERACTION / TAP_REACTION
  ├─ PetAnimationLoader (manifest; artwork_ready=false until 1B-2B)
  └─ PetVisual (hidden)
       ├─ PetShadow (reserved)
       └─ AnimatedSprite2D (no frames until art exists)
```

Persistence is local for the free test pet. Do not add backend dependence for parrot ownership in early phases.
