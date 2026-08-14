# Pet Store + Gift Delivery — Chest of Love Notes

Validates the future paid-pet pipeline using a **FREE Parrot**.

## Product flow

```
Pet Store → Get Free → Myself | My Person → pending delivery
  → CHEST (PET_GIFT) → claim → ownership → Profile Off/Parrot → enable → PetActor
```

**Hard rules**

- Opening the store does **not** grant ownership.
- Pressing Get Free does **not** spawn the pet.
- Ownership is granted only after the recipient claims the delivery.
- Clean users have **zero** PetActor nodes until owned **and** enabled.

## Catalog

`config/pets/catalog.json`

| Field | Parrot |
|-------|--------|
| `pet_id` / `id` | `parrot` |
| `price_type` / `unlock_type` | `FREE` |
| `default_unlocked` | `false` |
| `available_in_store` | `true` |

No Google Play Billing. No SKUs. No BillingClient.

## Local ownership migration

Persistence: `user://coln_pets.cfg`

| Situation | Behavior |
|-----------|----------|
| Fresh install (no cfg) | Empty ownership; `pet_enabled=false` |
| Existing cfg with `owned.ids` containing `parrot` | **Preserved** (dev builds that already used Parrot) |
| Existing cfg without parrot | Not auto-granted |
| Every startup | Does **not** re-grant via `default_unlocked` |

Schema marker: `meta/ownership_schema = 2`.

DEV reset for clean testing: delete `user://coln_pets.cfg` (and restart).

## Backend (Supabase)

Migration: `supabase/migrations/20260814120000_pet_store_delivery.sql`

| Table | Role |
|-------|------|
| `pet_catalog` | Metadata only (no art blobs) |
| `pet_deliveries` | pending / claimed / cancelled |
| `user_pet_ownership` | unique `(user_id, pet_id)` |

RPCs (authenticated, security definer):

- `send_pet_gift(p_pet_id, p_recipient_user_id)` — self or current My Person friendship
- `list_pending_pet_gifts()` — recipient inbox only
- `claim_pet_gift(p_delivery_id)` — recipient only; ownership upsert then mark claimed; idempotent
- `list_owned_pets()` — optional sync

Spam protection: unique partial index on pending `(sender, recipient, pet)`.

Does **not** modify `disconnect_my_person`, `my_person_pair_ends`, or pairing behavior.

## Client

- `PetGiftService` — online RPC + demo/local queue
- Profile → **Pet Store** → Get Free → recipient picker
- CHEST reward types: `NORMAL_SCROLL` (baked reveal) vs `PET_GIFT` (own branch)
- After claim: ownership recorded; **pet_enabled=false** until Profile enable

## Profile Pets

| State | UI |
|-------|----|
| No ownership | “No pets yet” + Pet Store |
| Owned | Off / Parrot |
| Off | preserves ownership + last safe position |
| Parrot | `pet_enabled=true`, `active_pet=parrot` |

## Flight

`PET_FLIGHT_ENABLED = false` until approved takeoff/fly/land art exists.  
Architecture (TAKEOFF / FLY / LAND) retained; no fake ground-hop flight.

## Ground roam

Regions: LEFT / LEFT_CENTER / RIGHT_CENTER / RIGHT with waypoint routing around the chest.  
Behavior weights: 35% short / 30% medium / 20% cross / 10% chest / 5% long idle.

## Artwork note

Dedicated **pet-delivery chest emergence** animation is **still needed**.  
This pass uses approved idle parrot art + a celebratory overlay after the normal 13-frame open (no scroll reveal; pet does not cut through the chest).

## Version

`0.1.70-pet-store-gifting` (versionCode **70**)
