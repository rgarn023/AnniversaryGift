# animation_v2 — Chest Asset Requirements

Asset-preparation package only. **Not wired into Godot.** Do not treat this as a
shippable smooth lid animation.

## Authoritative sources

| File | Size | Grid |
|------|------|------|
| `assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png` | 1536×1024 | 6×4 cells (256×256) |
| `assets/chest/animation/magical_treasure_chest_animation_sheet.png` | 1536×1024 | 6×4 cells (256×256) |

Use only this fantasy wooden/gold heart-lock chest. Do not substitute the old bronze chest.

## Production canvas

- **512×512** RGBA PNG for every chest frame and open layer
- Chosen from source bounds: closed ≈185×160, open (bleed-cropped) ≈195×201, cell 256×256, plus lid/glow headroom
- Base anchor target: **(256, 420)** — post-lock foot Y drift target **0 px**
- Horizontal visual center target: **x = 256**

## Consistency rules

Every frame in a future lid sequence must be the **exact same chest**:

- same body footprint, camera, perspective, trim, heart-lock, scale, lighting direction
- **only** the lid angle may change
- no grow/shrink/widen/narrow/warp/hinge drift
- no image warping, morphing, AI repainting, or interpolated lid geometry to fake missing poses
- no scroll baked into opening frames
- chest body pixels fully opaque where the source is opaque
- enough transparent headroom for the fully open lid (do not crop the lid)

## Final accepted files

### Chest frames (`chest_frames/`)

| File | Lid open % | Source |
|------|------------|--------|
| `chest_00_closed.png` | 0% | glowing cell 0 |
| `chest_10_fully_open.png` | ~75% (hard-cut open endpoint) | glowing cell 15 (bleed-cropped) |

Only these two production frames were created. Filenames `chest_01`…`chest_09` are **intentionally absent**.

### Scroll (`scroll/`)

- `love_scroll.png` — upright rolled parchment from `assets/art/scroll/scroll_rolled.png`
- Transparent PNG, warm parchment (not white), no chest/lid/rim/glow background
- Glow must stay out of this file (Godot will handle glow later)

### Layers (`layers/`)

Derived from the accepted open endpoint:

- `chest_open_back.png` — open chest / lid / rear interior behind the scroll
- `chest_open_front_rim.png` — foreground rim/front structure only (occlusion)

## Rejected source poses

### Glowing sheet (24 cells)

- **1–5:** closed near-dupes / idle glow pulse; AI micro-drift; not lid opens
- **6–11:** crack/partial-open — planted body remorphs vs closed (~40–46% XOR); rejected
- **12–14, 16–17:** mid-open cluster — body remorph + next-cell bleed; not matched mid-lid art
- **15:** kept only as hard-cut open endpoint (body still mismatches closed ~51% XOR)
- **18–23:** fully-open row **top-sheared** (lid cut by cell edge) — unusable

### Magical sheet (24 cells)

- Entire sheet rejected for the glowing-body sequence: body ~**11% smaller**, different proportions
- Mid/late cells bake scroll into the chest plate; late cells top-sheared
- Scroll artwork consulted only as visual reference; production scroll uses the clean project rolled parchment

## Missing intermediate poses

A genuinely smooth 8–11 frame lid arc is **not** possible from existing source art.

New matched production artwork is required for the **same camera/body/trim/lock/scale/lighting** as glowing cell 0, at approximately:

- 10° / 20° / 30° / 40° / 50° / 60° / 70° / 80° / 90° lid angles
- plus a clean **non-sheared fully-open** pose with the same body as closed

Until then, integration must not pretend mid-lid frames exist.

## Intended future Godot layer order

1. beach  
2. open chest/back (`chest_open_back.png`)  
3. scroll (`love_scroll.png`)  
4. front rim (`chest_open_front_rim.png`)  
5. glow/particles  
6. UI  

Do **not** implement this order in this pass.

## Validation (temporary — do not commit)

Under `validation/`:

- `chest_frames_contact_sheet.png` — accepted frames in order
- `chest_alignment_overlay.png` — body footprint / base / center onion
- `scroll_occlusion_validation.png` — scroll alone, back, cavity place, rim composite

## Tooling

Regenerate prior (glowing/magical) package with:

```bash
python3 tools/prepare_animation_v2_assets.py
```

Audit new candidate masters under `incoming_new_art/` with:

```bash
python3 tools/audit_incoming_animation_v2_art.py
```

### incoming_new_art (2026-08-13)

**FAIL — REGENERATE ART.** Measured 4×4 / 384×256 grid, 13 occupied cells.  
Frames 0–8 geometry-compatible; 9–12 rejected (narrowing; #11 top-sheared).  
No production replacements. Details: `notes/INCOMING_NEW_ART_VALIDATION_FAIL.md`.
