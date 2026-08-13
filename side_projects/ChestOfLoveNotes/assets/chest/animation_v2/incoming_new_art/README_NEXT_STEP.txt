Chest of Love Notes — animation_v2 incoming art

Files:
- new_chest_opening_master_sheet.png
  New candidate 13-stage chest opening source sheet.
  DO NOT wire directly into Godot yet.
  Cursor must first audit frame-to-frame geometry and extract accepted frames.

- new_love_scroll_master.png
  New standalone scroll candidate.
  Cursor should validate its transparency, proportions, orientation, and match to the chest.

IMPORTANT:
Do not use independently generated open-back/front-rim images from chat.
If the chest sheet passes validation, derive chest_open_back.png and chest_open_front_rim.png from the exact accepted fully-open frame so the layers match pixel-for-pixel.

Next step:
Run the asset-validation Cursor prompt supplied in ChatGPT.
Do not build an APK or modify active chest code during that validation pass.
