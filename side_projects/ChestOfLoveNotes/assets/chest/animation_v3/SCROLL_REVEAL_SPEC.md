# animation_v3 — Baked Scroll-Reveal Specification

**Status:** Step 1 preparation / scaffolding only.  
**Integration allowed:** `false`  
**Runtime behavior:** unchanged. Do not wire this package into Godot yet.

This document freezes the rules for the future **baked chest + scroll reveal** sequence that will replace the current runtime normal-scroll reward path (open_back / front_rim / standalone scroll tween).

---

## 1. Immutable base

Every reveal frame **must** use the exact approved fully-open chest as its visual base:

```
assets/chest/animation_v2/chest_frames/chest_12_fully_open.png
```

| Property | Value |
|----------|-------|
| Dimensions | 512×512 |
| Color | 8-bit RGBA |
| Production canvas | 512×512 |
| Authored base anchor | (256, 420) |
| Visible opaque bbox (measured) | (117, 144, 442, 428) |
| Visual center (bbox midpoint) | ≈ (279.5, 286.0) |
| Mid-body center near plant | ≈ x 256 |

**Hard rules**

- Chest pixels must remain **pixel-identical** in every reveal frame.
- Chest position must **never** change between reveal frames.
- Chest geometry must **never** change.
- Chest lighting must **never** change except via an intentionally separate effect layer later (glow/particles), not baked into the chest pixels.
- No chest repainting.
- No AI-generated alternate chest.
- No perspective changes.

`chest_12_fully_open.png` is the immutable base for **every** future baked scroll-reveal frame.

---

## 2. Scroll artwork

| Role | Path | Notes |
|------|------|-------|
| Approved love scroll (runtime today) | `assets/chest/animation_v2/scroll/love_scroll_reward.png` | 720×305 RGBA; horizontal romantic parchment |
| Legacy vertical source | `assets/chest/animation_v2/scroll/love_scroll.png` | 56×132; not used at runtime (v51+) |
| Legacy tiny horizontal | `assets/chest/animation_v2/scroll/love_scroll_horizontal.png` | 132×56; not used at runtime |
| Master source | `assets/chest/animation_v2/incoming_new_art/new_love_scroll_master.png` | packaging source only |

**Hard rules**

- Scroll remains **horizontal**.
- Scroll artwork remains the existing approved love scroll (reward / master lineage).
- **Only** scroll position / reveal amount changes across reveal frames.
- Scroll should appear to emerge immediately **behind the front lip**.

---

## 3. Forbidden techniques (once animation_v3 is integrated)

Do **not** bake or reintroduce:

- Cavity masks into the frame
- Gray rectangles / visible mask fills
- Reconstructed chest back/front systems for normal scroll rewards
- Runtime `open_back` / `front_rim` compositing for normal scroll rewards
- Runtime clipping hosts that hard-cut the scroll
- Separate scroll TextureRect rising through a layered chest for the normal unread path

These remain on disk for empty-chest / legacy tooling until a later cleanup pass. Step 1 does **not** delete them.

---

## 4. Future reveal frame filenames

Preferred production files under `scroll_reveal/` (do **not** exist yet):

| File | Intended reveal |
|------|-----------------|
| `reveal_00_hidden.png` | Fully-open chest; scroll completely hidden; chest identical to `chest_12` |
| `reveal_01_peek.png` | ≈ 5% of scroll height visible |
| `reveal_02_15.png` | ≈ 15% visible |
| `reveal_03_30.png` | ≈ 30% visible |
| `reveal_04_50.png` | ≈ 50% visible |
| `reveal_05_70.png` | ≈ 70% visible |
| `reveal_06_85.png` | ≈ 85% visible |
| `reveal_07_final.png` | Final clean horizontal presentation; ≈ 85–90% visible (best visual result) |

All frames: **512×512 RGBA**, same canvas / base anchor as `chest_12`.

---

## 5. Intended reveal progression

```
reveal_00_hidden
  - fully-open chest
  - scroll completely hidden inside chest
  - chest visually identical to chest_12

reveal_01_peek
  - approximately 5% of scroll height visible

reveal_02_15
  - approximately 15% visible

reveal_03_30
  - approximately 30% visible

reveal_04_50
  - approximately 50% visible

reveal_05_70
  - approximately 70% visible

reveal_06_85
  - approximately 85% visible

reveal_07_final
  - final clean horizontal presentation
  - approximately 85–90% visible depending on best visual result
```

The scroll emerges immediately behind the front lip.

---

## 6. Future runtime flow (NORMAL SCROLL REWARD ONLY)

```
approved chest_00
→ …
→ approved chest_12_fully_open
→ reveal_00_hidden
→ reveal_01_peek
→ reveal_02_15
→ reveal_03_30
→ reveal_04_50
→ reveal_05_70
→ reveal_06_85
→ reveal_07_final
→ hold
→ existing note transition
```

No `open_back` / `front_rim` reconstruction during this normal scroll sequence.

**Empty chest flow is out of scope** for animation_v3 and must continue to use the approved 13-frame opening only.

---

## 7. Timing recommendation (documentation only — not implemented)

| Phase | Target |
|-------|--------|
| Total scroll-reveal duration | ≈ 0.45–0.65 sec across 8 reveal frames |
| Final hold | ≈ 0.55–0.65 sec |

Tune after visual validation. Do not implement timing in Step 1.

---

## 8. Production placement lock (for artwork + future runtime)

Documented so future baked frames match today's correctly planted chest:

| Item | Value |
|------|-------|
| Production canvas | 512×512 |
| Base anchor | (256, 420) |
| Runtime host node | dynamically created `LoveNotesChest` under `ChestStage` |
| Runtime host size | 252×326 |
| Runtime fit scale | `min(252/512, 326/512)` ≈ **0.4921875** |
| Runtime draw size | ≈ 252×252 (canvas fit) |
| Foot alignment | `LoveNotesChest.CHEST_FOOT_Y_FRAC` (= 420/512) to `ChestEnvironment.CHEST_GROUND_Y` (= 0.888) |
| Host anchors | center X; top/bottom = 0.888; offsets plant foot on sand |
| Pivot | `_root_visual.pivot_offset = size * 0.5` |
| Wrapper emphasis scale | default 1.0 at fully open / reveal |

Do **not** change these values in Step 1.

---

## 9. Folder layout

```
assets/chest/animation_v3/
  SCROLL_REVEAL_SPEC.md          ← this file
  animation_v3_manifest.json
  scroll_reveal/                 ← future reveal_XX_*.png (empty until Step 2)
  source/                        ← working plates / composites for artwork
  validation/                    ← future contact sheets / audits (do not commit junk)
  notes/
    INTEGRATION_PLAN.md
    STEP1_RUNTIME_AUDIT.md
```

---

## 10. Step boundaries

| Step | Purpose |
|------|---------|
| **1 (this pass)** | Audit + scaffold + spec. No runtime change. No APK. |
| **2** | Create baked scroll-reveal artwork |
| **3** | Integrate animation_v3 for normal scroll reward only |
