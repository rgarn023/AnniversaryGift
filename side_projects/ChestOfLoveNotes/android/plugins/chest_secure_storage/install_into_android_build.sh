#!/usr/bin/env bash
# Wire ChestSecureStorage into the Godot Android Gradle export template.
# Safe to re-run. Does not modify Anniversary Gift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/android/build"
JAVA_DST="$BUILD_DIR/src/main/java/com/charoitegames/chestoflovenotes/securestorage"
RES_XML="$BUILD_DIR/res/xml"
MANIFEST="$BUILD_DIR/src/main/AndroidManifest.xml"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "ERROR: android/build template missing. Install Godot Android build template first." >&2
  exit 1
fi

mkdir -p "$JAVA_DST" "$RES_XML"
cp -f "$PLUGIN_DIR/ChestSecureStoragePlugin.kt" "$JAVA_DST/ChestSecureStoragePlugin.kt"
cp -f "$PLUGIN_DIR/ChestLocationPlugin.kt" "$JAVA_DST/ChestLocationPlugin.kt"
cp -f "$PLUGIN_DIR/backup_rules.xml" "$RES_XML/coln_backup_rules.xml"
cp -f "$PLUGIN_DIR/data_extraction_rules.xml" "$RES_XML/coln_data_extraction_rules.xml"

# Remove legacy SecureSession plugin class if present.
rm -f "$BUILD_DIR/src/main/java/com/charoitegames/chestoflovenotes/SecureSessionPlugin.kt"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: AndroidManifest.xml not found at $MANIFEST" >&2
  exit 1
fi

python3 - <<'PY' "$MANIFEST"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()

# Ensure xmlns:tools present on manifest root.
if 'xmlns:tools=' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"',
        1,
    )

# Application attributes for backup exclusion.
app_open = re.search(r'<application\b[^>]*>', text, re.S)
if not app_open:
    raise SystemExit('application tag not found')
app_tag = app_open.group(0)
replacements = {
    'android:allowBackup': 'android:allowBackup="false"',
    'android:fullBackupContent': 'android:fullBackupContent="@xml/coln_backup_rules"',
    'android:dataExtractionRules': 'android:dataExtractionRules="@xml/coln_data_extraction_rules"',
}
for attr, full in replacements.items():
    if attr in app_tag:
        app_tag = re.sub(rf'{attr}="[^"]*"', full, app_tag)
    else:
        app_tag = app_tag[:-1] + f'\n        {full}>'

text = text[:app_open.start()] + app_tag + text[app_open.end():]

# Remove legacy SecureSession meta-data.
text = re.sub(
    r'\s*<!--\s*Chest of Love Notes: Android Keystore-backed secure session plugin\s*-->\s*'
    r'<meta-data\s+android:name="org\.godotengine\.plugin\.v2\.SecureSession"[^/]*/>\s*',
    '\n',
    text,
    count=1,
    flags=re.S,
)
text = re.sub(
    r'\s*<meta-data\s+android:name="org\.godotengine\.plugin\.v2\.SecureSession"[^/]*/>\s*',
    '\n',
    text,
)

meta = '''
        <!-- Chest of Love Notes: Android Keystore-backed ChestSecureStorage plugin -->
        <meta-data
            android:name="org.godotengine.plugin.v2.ChestSecureStorage"
            android:value="com.charoitegames.chestoflovenotes.securestorage.ChestSecureStoragePlugin" />
        <!-- Chest of Love Notes: one-shot Location Lock helper -->
        <meta-data
            android:name="org.godotengine.plugin.v2.ChestLocation"
            android:value="com.charoitegames.chestoflovenotes.securestorage.ChestLocationPlugin" />
'''

if 'org.godotengine.plugin.v2.ChestSecureStorage' not in text:
    # Insert before first <activity
    text = re.sub(r'(\n\s*<activity\b)', meta + r'\1', text, count=1)
else:
    # Refresh value path if needed.
    text = re.sub(
        r'android:name="org\.godotengine\.plugin\.v2\.ChestSecureStorage"\s*\n\s*android:value="[^"]*"',
        'android:name="org.godotengine.plugin.v2.ChestSecureStorage"\n            android:value="com.charoitegames.chestoflovenotes.securestorage.ChestSecureStoragePlugin"',
        text,
    )
    if 'org.godotengine.plugin.v2.ChestLocation' not in text:
        text = re.sub(
            r'(android:name="org\.godotengine\.plugin\.v2\.ChestSecureStorage"[^/]*/>)',
            r'''\1
        <meta-data
            android:name="org.godotengine.plugin.v2.ChestLocation"
            android:value="com.charoitegames.chestoflovenotes.securestorage.ChestLocationPlugin" />''',
            text,
            count=1,
            flags=re.S,
        )

# Location permissions for Location Lock (requested at use-time by the OS dialog).
for perm in (
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_FINE_LOCATION',
):
    if perm not in text:
        text = text.replace(
            '</manifest>',
            f'    <uses-permission android:name="{perm}" />\n</manifest>',
            1,
        )

path.write_text(text)
print('Updated', path)
PY

echo "Installed ChestSecureStorage + ChestLocation into android/build"
echo "  kotlin: $JAVA_DST/ChestSecureStoragePlugin.kt"
echo "  location: $JAVA_DST/ChestLocationPlugin.kt"
echo "  backup rules: $RES_XML/coln_backup_rules.xml"
echo "  data extraction: $RES_XML/coln_data_extraction_rules.xml"

# Ensure Godot-copied *.import sidecars under res/ cannot break Android resource merge.
BUILD_GRADLE="$BUILD_DIR/build.gradle"
if [[ -f "$BUILD_GRADLE" ]] && ! grep -q 'colnStripImportSidecars' "$BUILD_GRADLE"; then
  cat >> "$BUILD_GRADLE" <<'GRADLE'

// Chest of Love Notes: Godot may copy *.webp.import sidecars into res/ during export.
tasks.register("colnStripImportSidecars") {
    doLast {
        def resDir = file("res")
        if (!resDir.exists()) {
            return
        }
        resDir.eachFileRecurse { f ->
            if (f.isFile() && f.name.endsWith(".import")) {
                f.delete()
            }
        }
    }
}
tasks.matching { it.name.startsWith("merge") && it.name.contains("Resources") }.configureEach {
    dependsOn("colnStripImportSidecars")
}
preBuild.dependsOn("colnStripImportSidecars")
GRADLE
  echo "Patched android/build/build.gradle to strip *.import sidecars"
fi
