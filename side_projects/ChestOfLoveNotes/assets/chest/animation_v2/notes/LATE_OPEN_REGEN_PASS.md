# Late-open regen — validation PASS

**Verdict: PASS FOR GODOT INTEGRATION**  
**Date:** 2026-08-13  
**Branch:** `cursor/mobile-production-polish-caa0`  
**Scope:** Art regeneration / asset validation only. No Godot scene/script changes. No APK.

## What was regenerated

Only late-open frames:

| File | Lid % |
|------|------:|
| `chest_frames/chest_09_open_75.png` | 75 |
| `chest_frames/chest_10_open_83.png` | 83 |
| `chest_frames/chest_11_open_92.png` | 92 |
| `chest_frames/chest_12_fully_open.png` | 100 |

`chest_08_open_67.png` was **not** regenerated (continuity into the late arc was acceptable).

## Locked references

Accepted early/mid frames `#00`–`#08` from  
`incoming_new_art/new_chest_opening_master_sheet.png` (aligned to 512×512, base anchor `(256, 420)`).

Body lock source for late frames: accepted aligned `#08`.

## Method

- Planted body / trim / heart lock / feet from locked `#08` (identical mid-body geometry).
- `#09`–`#10` lids: incoming master-sheet lids, hinge-registered to locked body.
- `#11`–`#12` lids: regenerated with extra vertical headroom (eliminates prior `#11` top-shear), hinge-registered to locked body.
- Only lid angle + interior glow progress; body does not narrow/remorph.

## Mid-body width (final late frames)

Reference closed `#00` mid-width = **237 px** (limit ±4).

| Frame | mid_w | Δ vs #00 |
|------:|------:|---------:|
| 09 | 234 | −3 |
| 10 | 234 | −3 |
| 11 | 234 | −3 |
| 12 | 234 | −3 |

## Full `#00`–`#12` gate

- Top clipping: **eliminated** (all frames `top_hits = 0`)
- Late-open geometry matches early/mid locked body: **yes**
- Full sequence passes for Godot integration (assets only): **yes**

## Layers

Derived from the exact accepted `chest_12_fully_open.png`:

- `layers/chest_open_back.png`
- `layers/chest_open_front_rim.png`

Scroll occlusion validated with existing `scroll/love_scroll.png` (validation preview only; not re-integrated into Godot).

## Production files

Also extracted accepted early/mid frames `#00`–`#08` into `chest_frames/` so the package is a complete closed→fully-open arc. Old hard-cut `chest_10_fully_open.png` (glowing-sheet endpoint) was removed.

## Audit JSON

`notes/late_open_regen_audit.json`
