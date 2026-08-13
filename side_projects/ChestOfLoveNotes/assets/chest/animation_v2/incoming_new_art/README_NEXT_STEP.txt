Chest of Love Notes — animation_v2 incoming art

VALIDATION STATUS: FAIL — REGENERATE ART
(see ../notes/INCOMING_NEW_ART_VALIDATION_FAIL.md)

Files:
- new_chest_opening_master_sheet.png
  Candidate 13-stage sheet (1536×1024, measured grid 4×4 cells of 384×256).
  Frames 0–8: body-consistent lid arc.
  Frames 9–12: REJECTED (body narrowing; frame 11 top-sheared).
  No production frames were extracted from this sheet.

- new_love_scroll_master.png
  Standalone scroll candidate (1254×1254 RGBA, diagonally tilted).
  Not committed to scroll/love_scroll.png in this FAIL pass.

IMPORTANT:
Do not use independently generated open-back/front-rim images from chat.
Do not integrate this sheet into Godot.
Regenerate late-open / fully-open poses matching frame 0 body width with extra vertical headroom, then re-run:

  python3 tools/audit_incoming_animation_v2_art.py
