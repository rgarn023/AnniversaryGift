#!/usr/bin/env bash
# Wire ChestSecureStorage (+ Location/Media/Focus/Notify) into the Godot Android Gradle export template.
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
cp -f "$PLUGIN_DIR/ChestMediaPlugin.kt" "$JAVA_DST/ChestMediaPlugin.kt"
cp -f "$PLUGIN_DIR/ChestFocusPlugin.kt" "$JAVA_DST/ChestFocusPlugin.kt"
cp -f "$PLUGIN_DIR/ChestNotifyPlugin.kt" "$JAVA_DST/ChestNotifyPlugin.kt"
cp -f "$PLUGIN_DIR/backup_rules.xml" "$RES_XML/coln_backup_rules.xml"
cp -f "$PLUGIN_DIR/data_extraction_rules.xml" "$RES_XML/coln_data_extraction_rules.xml"

rm -f "$BUILD_DIR/src/main/java/com/charoitegames/chestoflovenotes/SecureSessionPlugin.kt"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: AndroidManifest.xml not found at $MANIFEST" >&2
  exit 1
fi

python3 - <<'PY' "$MANIFEST"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()

if 'xmlns:tools=' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"',
        1,
    )

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

plugins = [
    ('ChestSecureStorage', 'ChestSecureStoragePlugin', 'Android Keystore-backed ChestSecureStorage plugin'),
    ('ChestLocation', 'ChestLocationPlugin', 'one-shot Location Lock helper'),
    ('ChestMedia', 'ChestMediaPlugin', 'Android Photo Picker helper'),
    ('ChestFocus', 'ChestFocusPlugin', 'Focus Lock Usage Access helper'),
    ('ChestNotify', 'ChestNotifyPlugin', 'local notification helper'),
]

# Ensure each plugin meta-data exists once.
for name, cls, comment in plugins:
    android_name = f'org.godotengine.plugin.v2.{name}'
    block = f'''
        <!-- Chest of Love Notes: {comment} -->
        <meta-data
            android:name="{android_name}"
            android:value="com.charoitegames.chestoflovenotes.securestorage.{cls}" />
'''
    if android_name not in text:
        text = re.sub(r'(\n\s*<activity\b)', block + r'\1', text, count=1)
    else:
        text = re.sub(
            rf'android:name="{re.escape(android_name)}"\s*\n\s*android:value="[^"]*"',
            f'android:name="{android_name}"\n            android:value="com.charoitegames.chestoflovenotes.securestorage.{cls}"',
            text,
        )

for perm, extra in (
    ('android.permission.ACCESS_COARSE_LOCATION', ''),
    ('android.permission.ACCESS_FINE_LOCATION', ''),
    ('android.permission.POST_NOTIFICATIONS', ''),
    ('android.permission.PACKAGE_USAGE_STATS', ' tools:ignore="ProtectedPermissions"'),
):
    if perm not in text:
        text = text.replace(
            '</manifest>',
            f'    <uses-permission android:name="{perm}"{extra} />\n</manifest>',
            1,
        )

path.write_text(text)
print('Updated', path)
PY

echo "Installed Chest plugins into android/build"
echo "  kotlin dir: $JAVA_DST"

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
