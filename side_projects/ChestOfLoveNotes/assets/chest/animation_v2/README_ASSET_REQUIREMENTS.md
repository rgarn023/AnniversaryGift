# animation_v2 — Chest Asset Requirements

Asset-preparation package only. **Not wired into Godot.** Do not treat this as a
shippable smooth lid animation until a dedicated Godot integration pass.

## Authoritative sources (this pass)

| File | Size | Grid / notes |
|------|------|----------------|
| `incoming_new_art/new_chest_opening_master_sheet.png` | 1536×1024 | 4×4 cells of 384×256; frames `#00`–`#08` accepted; `#09`–`#12` regenerated |
| Locked body reference | — | Accepted aligned `#08` body for late-open regen |

Legacy glowing/magical sheets remain historical references only; they are **not** the production sequence anymore.

## Production canvas

- **512×512** RGBA PNG for every chest frame and open layer
- Base anchor target: **(256, 420)** — post-lock foot Y drift target **≤1 px**
- Horizontal visual center target: **x ≈ 256**
- Mid-body width must stay within **±4 px** of closed (`#00`)

## Consistency rules

Every frame in the lid sequence must be the **exact same chest**:

- same body footprint, camera, perspective, trim, heart-lock, scale, lighting direction
- **only** the lid angle / intentional interior glow may change
- no grow/shrink/widen/narrow/warp/hinge drift
- no scroll baked into opening frames
- enough transparent headroom for the fully open lid (do not crop the lid)

## Final accepted files

### Chest frames (`chest_frames/`)

| File | Lid open % |
|------|------------|
| `chest_00_closed.png` | 0 |
| `chest_01_open_08.png` | 8 |
| `chest_02_open_17.png` | 17 |
| `chest_03_open_25.png` | 25 |
| `chest_04_open_33.png` | 33 |
| `chest_05_open_42.png` | 42 |
| `chest_06_open_50.png` | 50 |
| `chest_07_open_58.png` | 58 |
| `chest_08_open_67.png` | 67 |
| `chest_09_open_75.png` | 75 |
| `chest_10_open_83.png` | 83 |
| `chest_11_open_92.png` | 92 |
| `chest_12_fully_open.png` | 100 |

### Scroll (`scroll/`)

- `love_scroll.png` — upright rolled parchment (existing production candidate)
- Transparent PNG; Godot will handle glow later

### Layers (`layers/`)

Derived from the accepted fully-open frame `chest_12_fully_open.png`:

- `chest_open_back.png` — open chest / lid / rear interior behind the scroll
- `chest_open_front_rim.png` — foreground rim/front structure only (occlusion)

## Late-open regen (2026-08-13)

**PASS FOR GODOT INTEGRATION** (assets only).  
Details: `notes/LATE_OPEN_REGEN_PASS.md` and `notes/late_open_regen_audit.json`.

- Regenerated `#09`–`#12` only; `#08` not regenerated
- Late mid-body widths: **234 px** (Δ −3 vs closed 237)
- Top clipping eliminated
- Layers derived from accepted `#12`

## Intended future Godot layer order

1. beach  
2. open chest/back (`chest_open_back.png`)  
3. scroll (`love_scroll.png`)  
4. front rim (`chest_open_front_rim.png`)  
5. glow/particles  
6. UI  

Do **not** implement this order in the art-regen pass.

## Validation (temporary — do not commit)

Under `validation/`:

- `chest_frames_contact_sheet.png`
- `chest_alignment_overlay.png`
- `scroll_occlusion_validation.png`
- `late_open_regen_audit.json`

## Tooling

```bash
# Prior glowing/magical package (historical)
python3 tools/prepare_animation_v2_assets.py

# Audit incoming master sheets
python3 tools/audit_incoming_animation_v2_art.py

# Package late-open regen working plates → production frames/layers
python3 tools/package_late_open_regen_assets.py
```
