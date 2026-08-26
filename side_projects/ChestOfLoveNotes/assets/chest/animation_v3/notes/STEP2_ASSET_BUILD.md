# Step 2 — Baked Scroll-Reveal Asset Build

**Branch:** `cursor/mobile-production-polish-caa0`  
**Pass:** asset creation + validation only  
**Runtime modified:** no  
**APK built:** no  
**Version:** unchanged (0.1.60)  
**Verdict:** READY FOR STEP 3 INTEGRATION  

---

## Compositing architecture

Every production frame is built by `tools/build_baked_scroll_reveal.py` from immutable sources:

| Layer | Source | Role |
|-------|--------|------|
| A. Base | `assets/chest/animation_v2/chest_frames/chest_12_fully_open.png` | Exact full open chest (512×512 RGBA) |
| B. Scroll | `assets/chest/animation_v2/scroll/love_scroll_reward.png` | Horizontal love scroll, fixed scale, Y-only |
| C. Occluder | `assets/chest/animation_v2/layers/chest_open_front_rim.png` + lip burial | Front lip / pillars restored over scroll |

### Order (visible frames)

1. Start from an exact copy of `chest_12`
2. Alpha-composite the scaled scroll at fixed X / per-frame Y
3. Restore **exact** `chest_12` pixels wherever:
   - the front-rim layer is opaque, **or**
   - `y >= 269` (lip burial)

Lip burial closes small rim gaps so scroll cannot bleed through the gold lip. Restore is a direct pixel copy (not `alpha_composite`) to avoid alpha-stacking drift on semi-transparent rim edges.

### `reveal_00_hidden`

Byte-identical / pixel-identical copy of `chest_12` (no scroll paste).  
SHA-256 matches the chest source.

---

## Foreground occluder

| Field | Value |
|-------|-------|
| Source | Existing `chest_open_front_rim.png` |
| Reused vs re-derived | **Reused** (not re-derived) |
| Pixel-compatible with chest_12 | Yes — 0 mismatches where rim opaque |
| Extra | Deterministic lip burial from chest_12 for `y >= 269` |

No new artwork. No AI. No chest geometry edits.

---

## Fixed scroll production parameters

| Parameter | Value |
|-----------|-------|
| Native scroll | 720×305 RGBA |
| Production size | **118×50** (LANCZOS, aspect preserved) |
| Opening width used | 164 px (`CAVITY_INNER` 137→301) |
| Width fraction of opening | **0.72** (within 65–75% target) |
| Fixed scroll X (left) | **188** |
| Fixed scroll center X | **247** (= cavity center 219 + right bias 28) |
| Orientation | Horizontal only |
| Motion | Y only — identical art/scale every frame |
| Lip Y | **269** |

---

## Per-frame Y / visibility

| File | Intended % | scroll_top_y | Geometric % | Actual % est. |
|------|------------|--------------|-------------|---------------|
| `reveal_00_hidden.png` | 0 | 269 | 0 | 0 |
| `reveal_01_peek.png` | 5 | **266** | 6 | 6 |
| `reveal_02_15.png` | 15 | **262** | 14 | 14 |
| `reveal_03_30.png` | 30 | **254** | 30 | 30 |
| `reveal_04_50.png` | 50 | **244** | 50 | 50 |
| `reveal_05_70.png` | 70 | **234** | 70 | 70 |
| `reveal_06_85.png` | 85 | **226** | 86 | 86 |
| `reveal_07_final.png` | 88 | **225** | 88 | 88 |

All outputs: **512×512 8-bit RGBA**.

Early frames first-visible Y sits immediately above the lip (266…), not on the rear-lid band.

---

## Validation results

| Check | Result |
|-------|--------|
| `reveal_00` vs `chest_12` pixel diff | **0** (SHA-256 identical) |
| Unexpected chest diffs outside scroll region | **0** on every frame |
| Scroll size/X constant | Yes |
| Mask / gray rectangle artifacts | None |
| Rear-lid overlap in early frames | None |
| Deterministic rebuild | Same PNG hashes on re-run |

Audit JSON: `assets/chest/animation_v3/notes/STEP2_REVEAL_AUDIT.json`

Validation-only (do **not** commit):

- `assets/chest/animation_v3/validation/scroll_reveal_contact_sheet.png`
- `assets/chest/animation_v3/validation/scroll_reveal_lip_closeup.png`
- `assets/chest/animation_v3/validation/scroll_reveal_preview.mp4`

---

## Step 3 integration expectations

Wire **normal unread scroll reward only** after `chest_12`:

```
chest_00 … chest_12
→ reveal_00_hidden
→ reveal_01_peek … reveal_07_final
→ hold
→ existing note / inventory transition
```

- Do **not** use `open_back` / `front_rim` / runtime scroll tween for that path
- Empty-chest path stays on the approved 13-frame opening only
- Effects (glow, particles, badge, beach) remain runtime layers — not baked
- Do not change plant / environment / backend

Rebuild assets anytime with:

```bash
python3 tools/build_baked_scroll_reveal.py
```
