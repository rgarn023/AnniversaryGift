# Known-Good Pre-Pet Baseline

**Status:** User-approved visual/runtime baseline before pet-system development.  
**Date of baseline:** 2026-08-14  
**Do not redefine this baseline** during pet work. Restore from the safety tag / APK if regressions appear.

---

## Identity

| Field | Value |
| --- | --- |
| Branch | `cursor/mobile-production-polish-caa0` |
| Baseline HEAD | `f7c49836e5ad5ac8a7fd695465230fa57437f3ea` |
| Commit subject | `feat(chest): integrate animation_v3 baked scroll reveal (Step 3)` |
| versionCode | `61` |
| versionName | `0.1.61-baked-scroll-reveal` |
| Safety tag (preferred) | `chest-known-good-pre-pets` |
| Safety tag (version-qualified) | `chest-v61-known-good-pre-pets` |
| Working tree at baseline | Clean (nothing to commit) |

This is the version the user physically tested on a **Samsung Galaxy** and reported: **"The app looks good."**

---

## Known-good APK / Release

An existing GitHub Release asset definitively corresponds to this exact HEAD (same commit as `chest-v61-test`).

| Field | Value |
| --- | --- |
| Source release tag | `chest-v61-test` |
| Safety release tag | `chest-v61-known-good-pre-pets` |
| APK filename (release) | `ChestOfLoveNotes-v61-baked-scroll-reveal-debug.apk` |
| Local safety copy | `build/ChestOfLoveNotes-v61-known-good-pre-pets-debug.apk` (gitignored) |
| SHA-256 | `c60161a44b2a928cf944093958ddfcae4cbd373d25f3325bcd3c1186f2f20ee0` |
| Safety release URL | https://github.com/rgarn023/AnniversaryGift/releases/tag/chest-v61-known-good-pre-pets |
| Source release URL | https://github.com/rgarn023/AnniversaryGift/releases/tag/chest-v61-test |

No rebuild was required: the published v61 debug APK matches baseline HEAD.

**Recover:** check out `chest-known-good-pre-pets` (or `f7c4983…`) and install the APK from either release above.

---

## Locked systems (must not change for pet scaffolding)

Future pet work must adapt to these approved systems. Do **not** move the chest or rewrite these to “make room” for pets.

### Chest / reward

- Approved **13-frame** chest opening (`animation_v2` chest_00…chest_12)
- Approved **baked scroll reveal** (`animation_v3` reveal_00…reveal_07)
- Chest position / grounding (`ChestEnvironment.CHEST_GROUND_Y` / foot plant)
- Current reward flow (open → reveal → handoff)
- Empty chest behavior
- Rapid-tap protections

### Environment

- Beach / sand / ocean / shimmer / shoreline presentation
- Sky / moon / stars / time-of-day system

### UI hierarchy

- **CHEST** reward landing vs **YOUR CHEST** management
- Saved / Hidden behavior
- Unread indicator / filters (management only)

### Backend / account

- Persistent login
- Supabase
- My Person / Mandy pairing
- QR / map / location / permissions
- Disconnect (`disconnect_my_person()`, `record_my_person_pair_end`, `my_person_pair_ends`)
- Hide / Delete behavior

### Branding

- Charoite Games splash

---

## Statement

This document records the **user-approved pre-pet visual and runtime baseline**. Phase 1A pet architecture must leave launching the app visually and behaviorally identical to this baseline. Any pet runtime visibility begins only in a later phase after explicit approval.
