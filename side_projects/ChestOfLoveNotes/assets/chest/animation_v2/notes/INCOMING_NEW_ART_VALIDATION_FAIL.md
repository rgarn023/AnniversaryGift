# incoming_new_art — validation FAIL

**Verdict: FAIL — REGENERATE ART**  
**Date of audit:** 2026-08-13  
**Branch:** `cursor/mobile-production-polish-caa0`  
**Scope:** Asset validation only. No Godot integration. No APK. Production `chest_frames/`, `scroll/love_scroll.png`, and `layers/` were **not** replaced.

## Sources inspected

| File | Path | Dimensions | Format |
|------|------|------------|--------|
| Chest master | `incoming_new_art/new_chest_opening_master_sheet.png` | 1536×1024 | PNG RGBA (soft alpha / glow; corners transparent) |
| Scroll master | `incoming_new_art/new_love_scroll_master.png` | 1254×1254 | PNG RGBA (true transparency) |

## Grid (measured, not assumed)

- **4×4** cells of **384×256**
- **13 occupied** cells (row0–2 full; row3 only `r3c0`)
- Layout order left→right, top→bottom = frames `#00`…`#12`

## Hard consistency results

Production plant tested on **512×512** with base anchor **(256, 420)**.

After alignment:

- Base-Y drift: **0…−1 px** (effectively 0)
- Body-center X drift: **0…1.5 px** (effectively 0)
- Feet width: stable ~34–41 px
- Heart-lock relative position: stable across early/mid frames

### Mid-body width delta vs closed (`#00`) after align

| Frame | Δ mid-width | Decision |
|------:|------------:|----------|
| 00–08 | −3…+4 px | **Would accept** (same body; lid arc natural) — **not extracted** (no full arc) |
| 09 | −5 px | **REJECT** — progressive narrowing |
| 10 | −7 px | **REJECT** — progressive narrowing |
| 11 | −9 px | **REJECT** — narrowing + **top-shear** (opaque lid touches cell y=0) |
| 12 | −15 px | **REJECT** — body remorph/narrow (~6.3%); not same physical chest |

Fixed-band body XOR vs closed (audit): median ~2.3%, max ~8% on `#12` — far better than the old glowing-sheet mid poses (~40–51%), but late frames still fail the hard “no widen/narrow” rule.

## Counts

- Candidate frames inspected: **13**
- Geometry-compatible (0–8): **9**
- Rejected: **4** (`#09`–`#12`)
- Production files extracted/committed from this sheet: **0**

## Rejection reasons (exact)

1. **`#09`:** mid-body width Δ −5 px vs closed after align; progressive late-sequence narrowing  
2. **`#10`:** mid-body width Δ −7 px vs closed after align; progressive late-sequence narrowing  
3. **`#11`:** TOP-SHEARED — opaque lid mass touches cell top edge + mid-body Δ −9 px; lid tip clipped by 384×256 cell  
4. **`#12`:** mid-body width Δ −15 px (~6.3%) vs closed; planted body remorphs/narrows; fails same-physical-chest hard test  

## Why overall FAIL (not partial integrate)

A premium smooth open requires the **same** chest through fully open, plus layers derived from an **accepted** fully-open frame.  
This sheet’s usable arc stops at `#08` (~⅔ open). There is **no** accepted fully-open pose, so:

- no `chest_12_fully_open.png` from this art  
- no `layers/chest_open_back.png` / `chest_open_front_rim.png` derived from it  
- must **not** mix these early frames with the old glowing-sheet open endpoint (different body)

Prefer regenerating late-open / fully-open poses over shipping another morphing lid.

## Scroll master assessment

- Standalone rolled parchment with red ribbon + gold heart — **good subject**
- Transparent RGBA, no chest pixels, no beach/background
- **Diagonally tilted** (principal axis ≈ 69° from horizontal) — needs upright rotate for vertical rise
- Soft edge halo present but not an excessive baked glow bloom
- Narrower-than-cavity sizing is achievable after upright scale (~72 px wide candidate vs ~100–118 px cavity glow)
- **Not committed** to `scroll/love_scroll.png` because the chest sequence FAIL blocks this integration pass

## Regeneration guidance

Keep camera / body / trim / lock / scale matching `#00`. Provide:

- Late lid angles (~75–100%) with **identical** planted body width as `#00` (mid-body Δ ≤ ~4 px)
- Extra **vertical headroom** so the open lid is never cell-top clipped (avoid 256-tall cells for near-vertical lids, or place open poses with more top pad)
- Clean non-sheared fully-open pose for layer split (back / front rim)

## Validation artifacts (local only — gitignored)

Under `animation_v2/validation/`:

- `incoming_new_art_candidates_contact_sheet.png`
- `chest_frames_contact_sheet.png` (aligned accepts only)
- `chest_alignment_overlay.png`
- `incoming_body_strip_aligned.png`
- `scroll_occlusion_validation.png` (demo on accept `#08`; not production)
- `scroll_upright_candidate_preview.png`
- `incoming_new_art_audit.json`

## Tooling

```bash
python3 tools/audit_incoming_animation_v2_art.py
```
