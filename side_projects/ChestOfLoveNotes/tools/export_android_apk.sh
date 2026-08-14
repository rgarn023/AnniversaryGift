#!/usr/bin/env bash
# MANDATORY Android debug export for Chest of Love Notes.
#
# Do NOT call `godot --export-debug` directly for private-online APKs.
# Raw Godot export skips gitignored config/backend_config.json staging and
# produces APKs that show "Backend is not configured" on device (v70 failure).
#
# This wrapper:
#   1) stages live config from SUPABASE_URL + SUPABASE_ANON_KEY
#   2) hard-fails if config is missing/placeholder
#   3) installs Android plugins
#   4) exports the APK
#   5) hard-fails if packed APK lacks live backend_config.json
#   6) validates exported runtime load rules against the packed bytes
#
# Never embeds service-role / DB / FCM secrets — only URL + publishable/anon key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APK_NAME="${1:-ChestOfLoveNotes-v71-android-backend-config-fix-debug.apk}"
OUT="build/${APK_NAME}"
GODOT="${GODOT:-/home/ubuntu/godot/Godot_v4.7.1-stable_linux.x86_64}"
if [[ ! -x "$GODOT" && -x /tmp/godot/Godot_v4.7.1-stable_linux.x86_64 ]]; then
  GODOT="/tmp/godot/Godot_v4.7.1-stable_linux.x86_64"
fi
export ANDROID_HOME="${ANDROID_HOME:-/home/ubuntu/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

echo "== Prepare backend_config.json from env =="
python3 tools/prepare_backend_config.py
python3 tools/verify_backend_config_for_export.py

if [[ ! -f config/backend_config.json ]]; then
  echo "ERROR: config/backend_config.json missing after prepare — aborting export" >&2
  exit 1
fi
SRC_CFG_SIZE=$(wc -c < config/backend_config.json | tr -d ' ')
if [[ "${SRC_CFG_SIZE}" -lt 80 ]]; then
  echo "ERROR: staged backend_config.json too small (${SRC_CFG_SIZE})" >&2
  exit 1
fi
echo "OK: staged config/backend_config.json bytes=${SRC_CFG_SIZE}"

echo "== Install Android plugins into gradle template =="
if [[ ! -d android/build/src ]]; then
  echo "ERROR: android/build template missing. Install Godot Android build template first." >&2
  exit 1
fi
bash android/plugins/chest_secure_storage/install_into_android_build.sh

echo "== Optional splash GIF → SpriteFrames =="
if [[ -f assets/branding/154659_cursor_under4mb.gif ]]; then
  python3 tools/prepare_charoite_splash_from_gif.py
else
  echo "WARNING: assets/branding/154659_cursor_under4mb.gif missing — splash animation not rebuilt"
fi

mkdir -p build
mkdir -p /home/ubuntu/.config/godot
cat > /home/ubuntu/.config/godot/editor_settings-4.7.tres <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "${ANDROID_HOME}"
export/android/java_sdk_path = "${JAVA_HOME}"
EOF

echo "== Godot export-debug → ${OUT} =="
"$GODOT" --headless --path . --export-debug "Android" "$OUT"

if [[ ! -f "$OUT" ]]; then
  echo "ERROR: APK not written at $OUT" >&2
  exit 1
fi

echo "== Post-export hard gate: packed backend_config must be live =="
python3 tools/verify_apk_packed_backend_config.py "$OUT"
python3 tools/validate_exported_backend_runtime.py "$OUT"

# Size parity: packed bytes should match staged source (Godot stores raw JSON).
PACKED_SIZE=$(unzip -l "$OUT" | awk '/assets\/config\/backend_config\.json$/ {print $1; exit}')
if [[ "${PACKED_SIZE:-0}" -ne "${SRC_CFG_SIZE}" ]]; then
  echo "ERROR: packed config size (${PACKED_SIZE}) != staged source (${SRC_CFG_SIZE})" >&2
  exit 1
fi
echo "OK: packed size matches staged source (${PACKED_SIZE} bytes)"

echo "== Copy persistent artifacts =="
mkdir -p /opt/cursor/artifacts
if cp -f "$OUT" /opt/cursor/artifacts/; then
  ls -lh "$OUT" /opt/cursor/artifacts/"$(basename "$OUT")"
else
  echo "WARNING: could not copy APK to /opt/cursor/artifacts (export still OK)" >&2
  ls -lh "$OUT"
fi
echo "EXPORT_OK $OUT"
