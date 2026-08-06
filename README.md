# Anniversary Gift

A private, offline anniversary countdown gift for Mandy — built with **Godot 4.7.1** and **GDScript**, targeting modern Samsung Galaxy phones (portrait, 1080×2400 design).

Package: `com.charoitegames.anniversarygift`

## What it is

From **August 6, 2026** through **August 13, 2026**, a new treasure chest unlocks each day. Opening a chest reveals a handwritten-style scroll message. After the August 13 anniversary message is closed, the chest remains on screen as **One More Surprise** and opens the bundled Groupon gift PDF (in-app page previews plus native open/share).

The app works fully offline. There are no accounts, ads, analytics, tracking, or Internet permissions.

## Date unlocking

- Dates are stored as ISO strings: `2026-08-06` … `2026-08-13`.
- Unlocking uses the device’s local calendar date.
- Before August 6: a soft silhouette chest and the line *Your anniversary surprise begins August 6.*
- From August 6–13: every entry with `date <= effective date` unlocks. Missed days form a chronological catch-up queue.
- After August 13: all scrolls stay accessible; the final gift chest remains permanently after its message is viewed.
- Normal mode remembers the latest legitimate date observed so moving the clock backward cannot relock content.

Progress is saved to:

- Normal: `user://anniversary_progress.json`
- Developer: `user://anniversary_developer_progress.json`

## Scroll archiving

After a message is closed, a miniature scroll lands in the bottom **Scroll Archive**. Archived messages can be reopened anytime (shorter animation). Read/unread styling differs. Archive state persists across restarts.

## Developer test mode / date simulation

Ways to open it:

1. Tap the on-screen **Test Dates** button (top-right), or
2. Long-press the title for about one second, or
3. Tap the title **Anniversary Gift** seven times within about five seconds

Then enter PIN: `0813`

While active you get:

- A red **DEVELOPER TEST MODE** banner
- On-screen **◀ Prev Day / date / Next Day ▶** controls to jump through August 5–14
- A **More…** button for the full developer panel (unlock all, reset progress, PDF tests, etc.)

Developer mode uses a separate save file and **never** modifies normal progress or the normal-mode latest legitimate date. Closing developer mode restores the real device date and normal save state.

## Gift PDF

Place / replace the gift document at:

```text
assets/documents/anniversary_gift.pdf
```

High-resolution page previews live in:

```text
assets/documents/pdf_pages/
```

Current previews were rendered at ~2000px wide with PyMuPDF:

```bash
python3 - <<'PY'
import fitz
from pathlib import Path
doc = fitz.open("assets/documents/anniversary_gift.pdf")
out = Path("assets/documents/pdf_pages")
out.mkdir(parents=True, exist_ok=True)
for i, page in enumerate(doc):
    scale = 2000.0 / page.rect.width
    pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
    pix.save(str(out / f"page_{i+1:02d}.png"))
PY
```

Do not modify the original PDF content, QR code, redemption info, links, or formatting when replacing the file—only swap the PDF and regenerate previews.

### In-app viewer

- Vertical scroll through page PNGs
- Pinch zoom, +, −, Reset, Fit Width
- Loading indicator and Close
- Android Back support
- **Open Original PDF** / **Share or Save PDF** via the native Android plugin

### Native Android PDF plugin

Gradle build template plugin `AnniversaryPdf`:

- Copies `res://assets/documents/anniversary_gift.pdf` to `user://` on first use
- Exposes content URIs through Android FileProvider (never raw `file://`)
- `ACTION_VIEW` / `ACTION_SEND` with chooser and temporary read permission
- Friendly errors if no PDF app is installed; in-app previews still work

Plugin sources:

- `android/build/src/main/java/com/charoitegames/anniversarygift/AnniversaryPdfPlugin.java`
- Portable copy: `android/plugins/AnniversaryPdf/`

## Running in Godot

Requirements: Godot **4.7.1**, Compatibility renderer (already set).

```bash
godot --path .
# or
godot4 --path .
```

Main scene: `res://scenes/Main.tscn`

## Automated tests

```bash
godot --headless --path . --script res://tests/test_anniversary_logic.gd
```

Covers unlock counts, catch-up order, archive persistence, clock rollback safety, developer isolation, final-chest stages, PDF helper soft failures, and save/reload.

## Android export configuration

Export preset name: **Android**

| Setting | Value |
|--------|--------|
| App name | Anniversary Gift |
| Package | com.charoitegames.anniversarygift |
| Orientation | Portrait |
| Architectures | ARM64 (ARM32 optional) |
| Internet permission | Disabled |
| Renderer | gl_compatibility |
| Gradle build | Enabled (required for PDF plugin) |
| Non-resource filter | includes `*.pdf` |
| Launcher icons | realistic antique chest (adaptive) |
| Boot splash | realistic closed chest on night sky |
| versionCode | 2 (1.0.1) |

Editor Android paths (example):

- Android SDK: `$HOME/Android/Sdk`
- Java SDK: OpenJDK 17+ (21 works)
- Debug keystore: Godot default or a local debug keystore

Install the Android build template (required before Gradle export):

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
./tools/install_android_template.sh
```

This extracts Godot’s `android_source.zip`, writes `android/.build_version`, and registers the AnniversaryPdf plugin from `android/plugins/AnniversaryPdf/`. The plugin uses Godot’s built-in FileProvider (`${applicationId}.fileprovider`) — do not add a second provider.

## Build the debug APK

```bash
mkdir -p build
godot --headless --path . --export-debug "Android" build/AnniversaryGift-fixed-debug.apk
```

Exact output path:

```text
build/AnniversaryGift-fixed-debug.apk
```

### Install on a Samsung phone

```bash
adb install -r build/AnniversaryGift-fixed-debug.apk
```

Or copy the APK to the device and open it (enable install from this source if prompted).

### Android launcher icon cache

Android launchers often cache app icons. After installing a build with a new icon:

1. **Uninstall** the previous Anniversary Gift APK.
2. Restart the launcher or phone (optional but helps stubborn caches).
3. Install the new APK (`versionCode` must be higher than the previous install).

Do not assume the icon changed just because a new PNG exists in the project — the export preset, adaptive icon resources, and a fresh install all matter.


## Signed release APK (do not commit secrets)

1. Create your own keystore locally (never commit it):

```bash
keytool -genkeypair -v -keystore release.keystore -alias anniversary \
  -keyalg RSA -keysize 2048 -validity 10000
```

2. In Godot: **Editor → Editor Settings → Export → Android**, set release keystore path/user/password **locally only**.

3. Or use environment / local `export_credentials.cfg` (gitignored).

4. Export:

```bash
godot --headless --path . --export-release "Android" build/AnniversaryGift-release.apk
```

**Warning:** Never commit keystores, passwords, or `export_credentials.cfg`.

## Troubleshooting

| Issue | What to check |
|------|----------------|
| Missing Android SDK | Install cmdline-tools; set `export/android/android_sdk_path` |
| Missing Java | Install JDK 17+; set `export/android/java_sdk_path` |
| Gradle failures | First build downloads deps; ensure network + `ANDROID_HOME` |
| Missing export templates | Install Godot 4.7.1 templates to `~/.local/share/godot/export_templates/4.7.1.stable/` |
| FileProvider errors | Confirm `@xml/file_paths` and `${applicationId}.fileprovider` in the Android manifest |
| No PDF viewer app | In-app page previews still work; install any PDF reader to open the original |
| Package signature conflicts | Uninstall any previous build of `com.charoitegames.anniversarygift` before installing a differently signed APK |
| Reinstalled Android template wiped plugin | Re-copy sources from `android/plugins/AnniversaryPdf/` into `android/build` and restore manifest meta-data |

## Project layout

```text
res://
  project.godot
  export_presets.cfg
  scenes/
  scripts/
  data/messages.json
  assets/art/ fonts/ documents/ shaders/
  android/build/          # Gradle template + AnniversaryPdf plugin
  android/plugins/        # Portable plugin copy
  tests/test_anniversary_logic.gd
  build/                  # APK output
```

## License notes

- App code and original artwork in this repository are created for this private gift.
- Fonts: Cinzel and Cormorant Garamond (SIL Open Font License) via Fontsource/Google Fonts.
- Do not commit keystores or passwords.
