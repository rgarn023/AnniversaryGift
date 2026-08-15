#!/usr/bin/env bash
# Install/reinstall the Godot 4.7.1 Android Gradle build template and apply the AnniversaryPdf plugin.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="4.7.1.stable"
TEMPLATES_DIR="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates/$VERSION}"
SRC_ZIP="$TEMPLATES_DIR/android_source.zip"
BUILD_DIR="$ROOT/android/build"
PLUGIN_SRC="$ROOT/android/plugins/AnniversaryPdf/src/main/java/com/charoitegames/anniversarygift/AnniversaryPdfPlugin.java"

if [[ ! -f "$SRC_ZIP" ]]; then
  echo "Missing $SRC_ZIP"
  echo "Install Godot 4.7.1 export templates first."
  exit 1
fi

if [[ ! -f "$PLUGIN_SRC" ]]; then
  echo "Missing plugin source at $PLUGIN_SRC"
  exit 1
fi

echo "Installing Android build template from $SRC_ZIP"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
unzip -qo "$SRC_ZIP" -d "$BUILD_DIR"
touch "$BUILD_DIR/.gdignore"
printf '%s\n' "$VERSION" > "$ROOT/android/.build_version"

mkdir -p "$BUILD_DIR/src/main/java/com/charoitegames/anniversarygift"
cp "$PLUGIN_SRC" "$BUILD_DIR/src/main/java/com/charoitegames/anniversarygift/"

MANIFEST="$BUILD_DIR/src/main/AndroidManifest.xml"
if ! grep -q 'AnniversaryPdf' "$MANIFEST"; then
  python3 - <<PY
from pathlib import Path
path = Path("$MANIFEST")
text = path.read_text()
plugin = '''
        <meta-data
            android:name="org.godotengine.plugin.v2.AnniversaryPdf"
            android:value="com.charoitegames.anniversarygift.AnniversaryPdfPlugin" />
'''
if "</application>" not in text:
    raise SystemExit("AndroidManifest.xml missing </application>")
path.write_text(text.replace("</application>", plugin + "\n    </application>"))
print("Patched AndroidManifest.xml")
PY
fi

if [[ -n "${ANDROID_HOME:-}" ]]; then
  echo "sdk.dir=$ANDROID_HOME" > "$BUILD_DIR/local.properties"
fi

echo "Android build template ready at $BUILD_DIR"
echo "Plugin registered: AnniversaryPdf"
