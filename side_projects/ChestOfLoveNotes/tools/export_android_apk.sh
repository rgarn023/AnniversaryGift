#!/usr/bin/env bash
# Export a private-online Android debug APK with canonical Supabase client config packed.
# Never embeds service-role / DB / FCM secrets — only URL + publishable/anon key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APK_NAME="${1:-ChestOfLoveNotes-v53-scroll-layer-sky-polish-debug.apk}"
OUT="build/${APK_NAME}"
GODOT="${GODOT:-/home/ubuntu/godot/Godot_v4.7.1-stable_linux.x86_64}"
export ANDROID_HOME="${ANDROID_HOME:-/home/ubuntu/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

echo "== Prepare backend_config.json from env =="
python3 tools/prepare_backend_config.py
python3 tools/verify_backend_config_for_export.py

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

echo "== Post-export: confirm backend_config packed (no secret print) =="
# Avoid `grep -q` under pipefail (SIGPIPE from early close can false-fail).
PACK_LIST="$(unzip -Z1 "$OUT")"
if ! grep -F 'assets/config/backend_config.json' <<<"$PACK_LIST" >/dev/null; then
  echo "ERROR: backend_config.json missing from APK — would show Backend is not configured on device" >&2
  exit 1
fi
if grep -F 'assets/config/backend_config.example.json' <<<"$PACK_LIST" >/dev/null \
  && ! grep -F 'assets/config/backend_config.json' <<<"$PACK_LIST" >/dev/null; then
  echo "ERROR: only example backend config packed" >&2
  exit 1
fi
CFG_SIZE=$(unzip -l "$OUT" | awk '/assets\/config\/backend_config\.json$/ {print $1; exit}')
if [[ "${CFG_SIZE:-0}" -lt 80 ]]; then
  echo "ERROR: packed backend_config.json looks too small (${CFG_SIZE})" >&2
  exit 1
fi
# Example is 137 bytes; live config must differ (presence of real URL length).
EXAMPLE_SIZE=$(unzip -l "$OUT" | awk '/assets\/config\/backend_config\.example\.json$/ {print $1; exit}')
if [[ -n "${EXAMPLE_SIZE:-}" && "${CFG_SIZE}" -eq "${EXAMPLE_SIZE}" ]]; then
  echo "ERROR: packed backend_config.json size matches example — likely placeholder" >&2
  exit 1
fi
echo "OK: packed backend_config.json bytes=${CFG_SIZE} (example=${EXAMPLE_SIZE:-n/a})"

echo "== Copy persistent artifacts =="
mkdir -p /opt/cursor/artifacts
cp -f "$OUT" /opt/cursor/artifacts/
ls -lh "$OUT" /opt/cursor/artifacts/"$(basename "$OUT")"
echo "EXPORT_OK $OUT"
