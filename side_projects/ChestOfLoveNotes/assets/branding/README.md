# Branding assets

## Approved animated splash (source of truth)

- `154659_cursor_under4mb.gif` — APPROVED Charoite Games CG splash animation
  (optimized under Cursor’s 4 MB upload limit).
  **Do not redraw, regenerate, AI-recreate, recolor, or embellish.**

Derived at build time by `tools/prepare_charoite_splash_from_gif.py` (lossless PNG frames,
original frame order + timing preserved):

- `splash_frames/frame_XXXX.png` — animation frames for CharoiteBoot
- `splash_still.png` — representative first frame for Android/native boot_splash
- `splash_frames_meta.json` — frame count + durations

## Other marks

- `charoite_games_cg_logo.png` — legacy still CG monogram (fallback if GIF frames absent).
- `charoite_games_cg_logo_splash_derived.png` — derived square for launcher/system paths only.
  Never replace the app launcher icon with the CG splash mark automatically.
- `charoite_system_splash_dark.png` — black plane helper for engine boot_splash if still frame absent.

CharoiteBoot shows ONE CG mark against black. No "Presents" label, no wordmark duplicate,
no chest graphic, no starfield behind the studio splash.
