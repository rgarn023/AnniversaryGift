# Pet System Plan — Chest of Love Notes

First free pet: **Parrot** (`id: parrot`).  
Phase 1A is **architecture only** — no visible pet, no pet UI, no purchases, no gifting.

Baseline protected by: `docs/KNOWN_GOOD_PRE_PET_BASELINE.md`  
Safe-area notes: `docs/PET_SAFE_AREA.md`  
Parrot art/behavior pending: `assets/pets/parrot/PARROT_SPEC.md`

---

## PHASE 1A — Architecture / scaffolding (this phase)

**Goal:** Clean foundation with zero user-visible change.

Delivered:

- `PetDefinition` + scalable catalog (`config/pets/catalog.json`)
- `PetManager` — catalog, owned IDs, active pet ID, local persistence
- `PetState` enum — IDLE / ROAM / CHEST_INTERACTION / TAP_REACTION
- `PetActor` scene + script (structural only; **not** mounted on production CHEST)
- Default: parrot **FREE**, `default_unlocked`, considered owned
- Asset folder tree under `assets/pets/parrot/` (no artwork)
- Docs for plan, safe area, parrot spec

Explicitly **not** in 1A:

- Visible parrot on CHEST
- Placeholder/debug sprites in production UI
- Pet button / Collection / Shop / selector
- Google Play Billing
- PET_GIFT reward type wiring
- Changes to approved chest/scroll/beach/backend/UI systems

---

## PHASE 1B — Free parrot runtime on CHEST

**Goal:** Parrot appears on the CHEST reward screen only.

### PHASE 1B-1 — Invisible runtime integration (this sub-phase)

**Goal:** Mount pet runtime on CHEST with **zero visible pixels**.

Expected:

- `PetRuntimeConfig.PET_RUNTIME_ENABLED = true`
- `PetRuntimeConfig.PET_VISUALS_ENABLED = false`
- CHEST → `ChestEnvironment` → `PetRuntimeRoot` → `PetActor`
- IDLE / ROAM / CHEST_INTERACTION / TAP_REACTION state machine (logic only)
- Safe-area roam clamps; chest exclusion; reward pause/resume
- Still no artwork, Pet Collection UI, purchases, or gifting

### PHASE 1B-2 — Parrot art + visible runtime (next)

Expected:

- Spawn selected/owned parrot via `PetManager` into the CHEST stage
- IDLE + ROAM within documented safe area
- Occasional CHEST_INTERACTION
- TAP_REACTION then return to normal
- Respect UI exclusion zones; never obscure reward presentation
- Still no Pet Collection UI, no purchases, no gifting

Art integration required before visual ship (see `PARROT_SPEC.md`).

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

- Future reward type: `PET_GIFT` (not implemented in 1A)
- Delivery animation distinct from scroll reveal (do not break scroll path)
- Pairing / My Person flows extended carefully; disconnect semantics unchanged

---

## PHASE 3 — Google Play Billing / paid pets

**Goal:** Paid pet unlocks via Play Billing.

Expected:

- BillingClient / SKUs / receipts / entitlements
- Paid catalog entries (none in 1A)
- Free parrot remains free and must not depend on billing

---

## Architecture sketch (1A)

```
PetManager
  ├─ catalog (PetDefinition[])
  ├─ owned_pet_ids
  ├─ active_pet_id
  ├─ load/save user://coln_pets.cfg
  └─ spawn/despawn hooks (unused on CHEST until 1B)

PetActor (future instance)
  └─ PetState: IDLE → ROAM → CHEST_INTERACTION → TAP_REACTION
```

Persistence is local for the free test pet. Do not add backend dependence for parrot ownership in early phases.
