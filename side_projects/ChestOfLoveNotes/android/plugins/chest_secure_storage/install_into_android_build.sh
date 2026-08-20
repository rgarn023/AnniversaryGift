#!/usr/bin/env bash
# Wire ChestSecureStorage (+ Location/Media/Focus/Notify/Activity/Schedule) into the Godot Android Gradle export template.
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
RES_DRAWABLE="$BUILD_DIR/res/drawable"
mkdir -p "$RES_DRAWABLE"
cp -f "$PLUGIN_DIR/ChestSecureStoragePlugin.kt" "$JAVA_DST/ChestSecureStoragePlugin.kt"
cp -f "$PLUGIN_DIR/ChestLocationPlugin.kt" "$JAVA_DST/ChestLocationPlugin.kt"
cp -f "$PLUGIN_DIR/ChestMediaPlugin.kt" "$JAVA_DST/ChestMediaPlugin.kt"
cp -f "$PLUGIN_DIR/ChestFocusPlugin.kt" "$JAVA_DST/ChestFocusPlugin.kt"
cp -f "$PLUGIN_DIR/ChestNotifyPlugin.kt" "$JAVA_DST/ChestNotifyPlugin.kt"
cp -f "$PLUGIN_DIR/ChestQrPlugin.kt" "$JAVA_DST/ChestQrPlugin.kt"
cp -f "$PLUGIN_DIR/QrScanActivity.kt" "$JAVA_DST/QrScanActivity.kt"
cp -f "$PLUGIN_DIR/ActivityLockService.kt" "$JAVA_DST/ActivityLockService.kt"
cp -f "$PLUGIN_DIR/ScheduledNotifyReceiver.kt" "$JAVA_DST/ScheduledNotifyReceiver.kt"
cp -f "$PLUGIN_DIR/GeofenceReceiver.kt" "$JAVA_DST/GeofenceReceiver.kt"
cp -f "$PLUGIN_DIR/backup_rules.xml" "$RES_XML/coln_backup_rules.xml"
cp -f "$PLUGIN_DIR/data_extraction_rules.xml" "$RES_XML/coln_data_extraction_rules.xml"
if [[ -f "$PLUGIN_DIR/res/drawable/ic_coln_notification.xml" ]]; then
  cp -f "$PLUGIN_DIR/res/drawable/ic_coln_notification.xml" "$RES_DRAWABLE/ic_coln_notification.xml"
fi

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
    ('ChestLocation', 'ChestLocationPlugin', 'Location Lock + Activity Lock foreground helper'),
    ('ChestMedia', 'ChestMediaPlugin', 'Android Photo Picker helper'),
    ('ChestFocus', 'ChestFocusPlugin', 'Focus Lock Usage Access helper'),
    ('ChestNotify', 'ChestNotifyPlugin', 'local + scheduled notification helper'),
    ('ChestQr', 'ChestQrPlugin', 'QR encode + camera scan for My Person pairing'),
]

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

# Service + boot receiver (idempotent insert before </application>)
service_block = '''
        <!-- Chest of Love Notes: Activity Lock foreground location service -->
        <service
            android:name="com.charoitegames.chestoflovenotes.securestorage.ActivityLockService"
            android:exported="false"
            android:foregroundServiceType="location" />
        <!-- Chest of Love Notes: scheduled notification + reboot re-register -->
        <receiver
            android:name="com.charoitegames.chestoflovenotes.securestorage.ScheduledNotifyReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="coln.notify.FIRE" />
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
        <!-- Chest of Love Notes: My Person QR scanner -->
        <activity
            android:name="com.charoitegames.chestoflovenotes.securestorage.QrScanActivity"
            android:exported="false"
            android:screenOrientation="portrait"
            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" />
        <!-- Chest of Love Notes: opt-in Location Lock geofence -->
        <receiver
            android:name="com.charoitegames.chestoflovenotes.securestorage.GeofenceReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="coln.geofence.TRANSITION" />
            </intent-filter>
        </receiver>
'''
if 'ActivityLockService' not in text:
    text = text.replace('</application>', service_block + '\n    </application>', 1)
else:
    if 'QrScanActivity' not in text:
        qr_act = '''
        <activity
            android:name="com.charoitegames.chestoflovenotes.securestorage.QrScanActivity"
            android:exported="false"
            android:screenOrientation="portrait"
            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" />
'''
        text = text.replace('</application>', qr_act + '\n    </application>', 1)
    if 'GeofenceReceiver' not in text:
        geo_rx = '''
        <receiver
            android:name="com.charoitegames.chestoflovenotes.securestorage.GeofenceReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="coln.geofence.TRANSITION" />
            </intent-filter>
        </receiver>
'''
        text = text.replace('</application>', geo_rx + '\n    </application>', 1)

for perm, extra in (
    ('android.permission.ACCESS_COARSE_LOCATION', ''),
    ('android.permission.ACCESS_FINE_LOCATION', ''),
    ('android.permission.ACCESS_BACKGROUND_LOCATION', ''),
    ('android.permission.CAMERA', ''),
    ('android.permission.POST_NOTIFICATIONS', ''),
    ('android.permission.PACKAGE_USAGE_STATS', ' tools:ignore="ProtectedPermissions"'),
    ('android.permission.FOREGROUND_SERVICE', ''),
    ('android.permission.FOREGROUND_SERVICE_LOCATION', ''),
    ('android.permission.RECEIVE_BOOT_COMPLETED', ''),
    ('android.permission.WAKE_LOCK', ''),
):
    if perm not in text:
        text = text.replace(
            '</manifest>',
            f'    <uses-permission android:name="{perm}"{extra} />\n</manifest>',
            1,
        )

# Auth callback deep link on the main Godot activity (password recovery + Google OAuth).
auth_filter = '''
            <!-- Chest of Love Notes: Supabase auth callback (recovery + Google OAuth) -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="com.charoitegames.chestoflovenotes"
                    android:host="auth-callback" />
            </intent-filter>
'''
if 'android:host="auth-callback"' not in text and "android:host='auth-callback'" not in text:
    # Insert after the first launcher MAIN/LAUNCHER intent-filter's closing tag inside an activity.
    # Prefer the Godot main activity when identifiable; otherwise first exported activity.
    inserted = False
    # Match first activity block that contains MAIN + LAUNCHER and inject after that filter.
    act_iter = list(re.finditer(r'<activity\b[^>]*>.*?</activity>', text, flags=re.S))
    for m in act_iter:
        block = m.group(0)
        if 'android.intent.action.MAIN' in block and 'android.intent.category.LAUNCHER' in block:
            # Insert before </activity>
            new_block = block.replace('</activity>', auth_filter + '\n        </activity>', 1)
            text = text[:m.start()] + new_block + text[m.end():]
            inserted = True
            break
    if not inserted:
        # Fallback: append a dedicated exported alias activity that forwards via VIEW.
        alias = '''
        <!-- Chest of Love Notes: auth callback activity (fallback) -->
        <activity-alias
            android:name="com.charoitegames.chestoflovenotes.AuthCallbackAlias"
            android:exported="true"
            android:targetActivity=".GodotApp">
''' + auth_filter + '''
        </activity-alias>
'''
        # Last resort: inject filter before </application> as comment + note — still try activity.
        if '</activity>' in text:
            text = text.replace('</activity>', auth_filter + '\n        </activity>', 1)
        else:
            text = text.replace('</application>', alias + '\n    </application>', 1)

path.write_text(text)
print('Updated', path)
PY

echo "Installed Chest plugins into android/build"
echo "  kotlin dir: $JAVA_DST"

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

# ZXing for QR encode/scan (My Person) + Play Services fused location / geofencing
if [[ -f "$BUILD_GRADLE" ]]; then
  python3 - <<'PY' "$BUILD_GRADLE"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needed = []
if 'zxing:core' not in text:
    needed.append('''
    // Chest of Love Notes: QR encode + camera scan (My Person)
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
''')
if 'play-services-location' not in text:
    needed.append('''
    // Chest of Love Notes: Fused Location + Geofencing
    implementation("com.google.android.gms:play-services-location:21.3.0")
''')
if not needed:
    print('Location/ZXing dependencies already present')
    raise SystemExit(0)
m = re.search(r'dependencies\s*\{', text)
if m:
    idx = m.end()
    text = text[:idx] + ''.join(needed) + text[idx:]
    path.write_text(text)
    print('Added Android dependencies to', path)
else:
    print('WARNING: dependencies block not found', file=sys.stderr)
PY
fi
