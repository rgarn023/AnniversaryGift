Chest of Love Notes — animation_v2 incoming art

VALIDATION STATUS: PASS FOR GODOT INTEGRATION (assets packaged)
(see ../notes/LATE_OPEN_REGEN_PASS.md)

Files:
- new_chest_opening_master_sheet.png
  Candidate 13-stage sheet (1536×1024, measured grid 4×4 cells of 384×256).
  Frames 0–8: accepted geometry references (extracted to chest_frames/).
  Frames 9–12: originally REJECTED (narrowing; #11 top-sheared).
  Late frames were regenerated with locked #08 body + progressive lids.

- new_love_scroll_master.png
  Standalone scroll candidate (still not replacing scroll/love_scroll.png here).

IMPORTANT:
Open-back / front-rim layers were derived from accepted chest_12_fully_open.png.
Do not integrate into Godot in this art-regen pass.

Re-package from working plates (if present under validation/late_regen_work/):

  python3 tools/package_late_open_regen_assets.py
