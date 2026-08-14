# Parrot Spec — First Free Pet

| Field | Value |
| --- | --- |
| Pet ID | `parrot` |
| Display name | Parrot |
| Unlock type | **FREE** |
| Default unlocked | Yes — available to all users |
| Role | First test / flagship free pet |
| Billing | **None** — never tied to Google Play Billing |
| Artwork | **LOCKED master** — Phase 1B-2B ingest; animation frames not authored yet |
| Manifest | `assets/pets/parrot/parrot_animation_manifest.json` |
| Visuals enabled | **false** (`PetRuntimeConfig.PET_VISUALS_ENABLED`) |

---

## Approved production master (LOCKED)

| Field | Value |
| --- | --- |
| `approved_master_path` | `assets/pets/parrot/source/parrot_master.png` |
| `approved_master_sha256` | `89e28ad50111f8c6ebf1e5abbea29934b3df9bd79060e38bc8c5e3e3d382e0e2` |
| `approved_master_status` | **LOCKED** |
| Canvas | 128×128 PNG RGBA |
| Facing | RIGHT |
| Measured visible bbox (alpha>0) | L=24 T=28 R=99 B=115 |
| Measured visible size | 76×88 px |
| Bottom baseline (last opaque row) | **115** (spec ground anchor remains **116**; 1 px harmless) |
| Design | Red / yellow / blue stylized macaw |

This exact parrot design is **LOCKED**. Do not redraw, regenerate, recolor, or change proportions. Future IDLE / MOVE / CHEST_INTERACTION / TAP_REACTION frames must preserve this design (verified against the SHA-256 above). Animation frame PNGs are **not** created yet.

---

## Visual style contract (production direction)

Fit the existing magical beach / chest environment:

- Cute stylized parrot (not realistic)
- Polished mobile-game look
- Warm / friendly companion presence
- Clear silhouette at phone size
- Readable facial features without over-detail
- Companion-sized — not a giant mascot competing with the chest
- Transparent PNG frames only — no baked beach, UI, chest, or text

Final palette / silhouette is locked to the approved master above.

---

## Production frame canvas / anchors

Derived from runtime chest geometry (design space **390×844**):

| Field | Value |
| --- | --- |
| Frame canvas | **128×128** |
| Ground / foot anchor | **(64, 116)** |
| Frame center | **(64, 64)** |
| Baseline Y | **116** |
| Max ground-contact drift between frames | **±2 px** |
| Max hop lift *inside* frame (move) | **≤16 px** |
| Visible target bounds (soft) | x 28–100, y 20–116 |
| Approx solid body size in frame | ~72×88 px |
| Default facing | **RIGHT** (author once) |
| Left / right strategy | Runtime `AnimatedSprite2D.flip_h` for LEFT |
| Recommended runtime scale | **0.72** (× viewport scale_factor) |

### Size vs chest

| Reference | Design px |
| --- | --- |
| Chest host | 252×326 |
| Chest runtime draw square | ≈252×252 |
| Chest opaque silhouette height (alpha bbox × fit) | ≈140 |
| **Proposed visible parrot height** | **≈64** |
| Parrot / chest-draw-height ratio | **≈0.254 (25.4%)** |
| On reference 390×844 viewport | ≈64 logical px tall |

Hop motion animates the body **inside** the frame. The frame ground anchor (and thus `PetActor.position`) stays stable so state changes do not visually jump.

---

## File / alpha requirements

Every production frame must be:

- PNG
- RGBA
- Transparent background
- No baked beach / sand plate
- No baked shadow (runtime soft ellipse later)
- No UI, chest, or text
- Not JPEG

---

## Shadow strategy

**Runtime-generated soft ellipse** under the pet (restrained, similar in spirit to chest contact shadow).

- Small / subtle / underneath
- May scale slightly during hop
- **Not rendered in Phase 1B-2A**
- No authored shadow sheet required

---

## Animation groups (exact contract)

| Runtime state | Animation | Folder | Filenames | Frames | FPS | Loop |
| --- | --- | --- | --- | --- | --- | --- |
| IDLE | `idle` | `idle/` | `parrot_idle_00.png` … `parrot_idle_04.png` | **5** | **5** | yes |
| ROAM | `move` | `move/` | `parrot_move_00.png` … `parrot_move_06.png` | **7** | **10** | yes |
| CHEST_INTERACTION | `chest_interaction` | `chest_interaction/` | `parrot_chest_00.png` … `parrot_chest_07.png` | **8** | **10** | no |
| TAP_REACTION | `tap_reaction` | `tap_reaction/` | `parrot_tap_00.png` … `parrot_tap_04.png` | **5** | **10** | no |

Source / tooling only: `source/` (not loaded at runtime).

### Transition rules

- **IDLE** — loops
- **MOVE** — loops while roaming
- **CHEST_INTERACTION** — play once at interaction point, then return to idle
- **TAP_REACTION** — play once, then return to idle / prior allowed state

Playback is prepared in `PetAnimationLoader` / `PetActor` but **does not run** while `artwork_ready == false` or `PET_VISUALS_ENABLED == false`.

---

## Asset directory contract

```
assets/pets/parrot/
  parrot_animation_manifest.json
  PARROT_SPEC.md
  idle/parrot_idle_XX.png
  move/parrot_move_XX.png
  chest_interaction/parrot_chest_XX.png
  tap_reaction/parrot_tap_XX.png
  source/   # raw / contact sheets (not runtime)
```

Animation folders currently contain `.gitkeep` only — **no fake PNGs**.  
`source/parrot_master.png` is the LOCKED production master (ingest only; not loaded at runtime).

---

## Runtime (Phase 1B-2A)

```
PetActor
├── PetVisual          (hidden)
│   ├── PetShadow      (reserved; not drawn)
│   └── AnimatedSprite2D  (no frames until art exists)
```

| Flag / field | Value |
| --- | --- |
| `PET_RUNTIME_ENABLED` | `true` |
| `PET_VISUALS_ENABLED` | `false` |
| `artwork_ready` | `false` until all contract frames exist |
| Missing art | Non-fatal; no placeholders; no error spam |

Validation: `tools/validate_parrot_assets.py` → `AWAITING_ARTWORK` when empty.  
Contact sheets (later): `tools/build_parrot_contact_sheets.py`.

---

## Catalog / unlock

Defined in `config/pets/catalog.json`:

- `unlock_type`: `FREE`
- `default_unlocked`: `true`
- `enabled`: `true`
- `asset_root`: `res://assets/pets/parrot/`

Parrot remains owned by default via `PetManager`. No Pet Collection UI yet.
