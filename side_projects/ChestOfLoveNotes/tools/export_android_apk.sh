#!/usr/bin/env bash
# MANDATORY Android debug export for Chest of Love Notes.
#
# Do NOT call `godot --export-debug` directly.
# Raw Godot export:
#   - skips gitignored config/backend_config.json staging (v70 "Backend is not configured")
#   - may use a machine-local debug keystore (certificate churn → "App not installed")
#   - may leave differently named duplicate APKs
#
# This wrapper is the only supported export path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIGNING_DIR="$ROOT/android/signing"
KEYSTORE="$SIGNING_DIR/chest_test_debug.keystore"
EXPECTED_CERT_FILE="$SIGNING_DIR/EXPECTED_TEST_CERT_SHA256"
EXPECTED_PKG_FILE="$SIGNING_DIR/EXPECTED_PACKAGE_ID"
LAST_RELEASED_FILE="$SIGNING_DIR/LAST_RELEASED_VERSION_CODE"

GODOT="${GODOT:-/home/ubuntu/godot/Godot_v4.7.1-stable_linux.x86_64}"
if [[ ! -x "$GODOT" && -x /tmp/godot/Godot_v4.7.1-stable_linux.x86_64 ]]; then
  GODOT="/tmp/godot/Godot_v4.7.1-stable_linux.x86_64"
fi
export ANDROID_HOME="${ANDROID_HOME:-/home/ubuntu/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$KEYSTORE" ]] || die "missing project test keystore: $KEYSTORE"
[[ -f "$EXPECTED_CERT_FILE" ]] || die "missing $EXPECTED_CERT_FILE"
[[ -f "$EXPECTED_PKG_FILE" ]] || die "missing $EXPECTED_PKG_FILE"
[[ -f "$LAST_RELEASED_FILE" ]] || die "missing $LAST_RELEASED_FILE"
[[ -f export_presets.cfg ]] || die "missing export_presets.cfg"

VERSION_CODE="$(awk -F= '/^version\/code=/{print $2; exit}' export_presets.cfg)"
VERSION_NAME="$(awk -F= '/^version\/name=/{gsub(/"/,"",$2); print $2; exit}' export_presets.cfg)"
PACKAGE_ID="$(awk -F= '/^package\/unique_name=/{gsub(/"/,"",$2); print $2; exit}' export_presets.cfg)"
EXPECTED_PACKAGE="$(tr -d '[:space:]' < "$EXPECTED_PKG_FILE")"
LAST_RELEASED="$(tr -d '[:space:]' < "$LAST_RELEASED_FILE")"

[[ -n "$VERSION_CODE" ]] || die "could not read version/code from export_presets.cfg"
[[ -n "$VERSION_NAME" ]] || die "could not read version/name from export_presets.cfg"
[[ -n "$PACKAGE_ID" ]] || die "could not read package/unique_name from export_presets.cfg"

if [[ "$PACKAGE_ID" != "$EXPECTED_PACKAGE" ]]; then
  die "export_presets package ID '$PACKAGE_ID' != expected '$EXPECTED_PACKAGE'"
fi
if ! [[ "$VERSION_CODE" =~ ^[0-9]+$ ]]; then
  die "version/code is not an integer: $VERSION_CODE"
fi
if (( VERSION_CODE <= LAST_RELEASED )); then
  die "versionCode $VERSION_CODE must be > LAST_RELEASED_VERSION_CODE ($LAST_RELEASED)"
fi

# Deterministic canonical filename from actual version fields.
VERSION_SLUG="${VERSION_NAME}"
# Strip leading "0.1.NN-" if present so filename stays ChestOfLoveNotes-vNN-<slug>-debug.apk
if [[ "$VERSION_SLUG" =~ ^0\.1\.[0-9]+-(.+)$ ]]; then
  VERSION_SLUG="${BASH_REMATCH[1]}"
fi
CANONICAL_NAME="ChestOfLoveNotes-v${VERSION_CODE}-${VERSION_SLUG}-debug.apk"
# Optional CLI override must match canonical to prevent dual naming.
if [[ "${1:-}" != "" && "${1:-}" != "$CANONICAL_NAME" ]]; then
  die "refusing non-canonical APK name '$1' (required: $CANONICAL_NAME)"
fi

BUILD_DIR="$ROOT/build"
mkdir -p "$BUILD_DIR"
CANONICAL_APK="$BUILD_DIR/$CANONICAL_NAME"
TEMP_APK="$BUILD_DIR/.tmp-export-v${VERSION_CODE}.apk"

# Keep export_presets export_path aligned with the single canonical name.
python3 - <<PY
from pathlib import Path
path = Path("export_presets.cfg")
text = path.read_text(encoding="utf-8")
old = None
import re
m = re.search(r'^export_path="([^"]*)"$', text, re.M)
if m:
    old = m.group(1)
new = "build/${CANONICAL_NAME}"
text2, n = re.subn(r'^export_path="[^"]*"$', f'export_path="{new}"', text, count=1, flags=re.M)
if n != 1:
    raise SystemExit("failed to update export_path in export_presets.cfg")
if text2 != text:
    path.write_text(text2, encoding="utf-8")
    print(f"Updated export_path: {old} -> {new}")
else:
    print(f"export_path already canonical: {new}")
PY

echo "== Stable test signing (project keystore) =="
# Test-only credentials for the tracked project keystore. Never print values.
# Override via env if needed; do not commit alternate passwords.
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

mkdir -p /home/ubuntu/.config/godot
# Editor settings: SDK paths only — do not rely on machine debug keystore.
cat > /home/ubuntu/.config/godot/editor_settings-4.7.tres <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "${ANDROID_HOME}"
export/android/java_sdk_path = "${JAVA_HOME}"
export/android/debug_keystore = "${KEYSTORE}"
export/android/debug_keystore_user = "${GODOT_ANDROID_KEYSTORE_DEBUG_USER}"
EOF
# Password stays out of the tres file when possible; Godot also reads GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD.

# Credentials file (gitignored via .godot/) — path + user only in plaintext logs avoided.
mkdir -p .godot
cat > .godot/export_credentials.cfg <<EOF
[preset.0]

[preset.0.options]

keystore/debug="${KEYSTORE}"
keystore/debug_user="${GODOT_ANDROID_KEYSTORE_DEBUG_USER}"
keystore/debug_password="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD}"
EOF

echo "Using project keystore: $KEYSTORE"
echo "Canonical APK: $CANONICAL_APK"
echo "versionCode=$VERSION_CODE versionName=$VERSION_NAME package=$PACKAGE_ID"

echo "== Prepare backend_config.json from env =="
python3 tools/prepare_backend_config.py
python3 tools/verify_backend_config_for_export.py

if [[ ! -f config/backend_config.json ]]; then
  die "config/backend_config.json missing after prepare — aborting export"
fi
SRC_CFG_SIZE=$(wc -c < config/backend_config.json | tr -d ' ')
if [[ "${SRC_CFG_SIZE}" -lt 80 ]]; then
  die "staged backend_config.json too small (${SRC_CFG_SIZE})"
fi
echo "OK: staged config/backend_config.json bytes=${SRC_CFG_SIZE}"

echo "== Install Android plugins into gradle template =="
if [[ ! -d android/build/src ]]; then
  die "android/build template missing. Install Godot Android build template first."
fi
bash android/plugins/chest_secure_storage/install_into_android_build.sh

echo "== Optional splash GIF → SpriteFrames =="
if [[ -f assets/branding/154659_cursor_under4mb.gif ]]; then
  python3 tools/prepare_charoite_splash_from_gif.py
else
  echo "WARNING: assets/branding/154659_cursor_under4mb.gif missing — splash animation not rebuilt"
fi

# Remove any prior incomplete temp / same-version outputs before export.
rm -f "$TEMP_APK"
# Clean current-version duplicates only (keep other historical versions).
shopt -s nullglob
for existing in "$BUILD_DIR"/ChestOfLoveNotes-v"${VERSION_CODE}"-*.apk "$BUILD_DIR"/.tmp-export-v"${VERSION_CODE}".apk; do
  echo "Removing prior same-version APK: $existing"
  rm -f "$existing"
done
shopt -u nullglob

echo "== Godot export-debug → temporary APK =="
[[ -x "$GODOT" ]] || die "Godot binary not executable: $GODOT"
"$GODOT" --headless --path . --export-debug "Android" "$TEMP_APK"

if [[ ! -f "$TEMP_APK" ]]; then
  die "temporary APK not written at $TEMP_APK"
fi

echo "== Validate temporary APK (backend + update compatibility) =="
python3 tools/verify_apk_packed_backend_config.py "$TEMP_APK"
python3 tools/validate_exported_backend_runtime.py "$TEMP_APK"
python3 tools/verify_apk_update_compatibility.py "$TEMP_APK"

PACKED_SIZE=$(unzip -l "$TEMP_APK" | awk '/assets\/config\/backend_config\.json$/ {print $1; exit}')
if [[ "${PACKED_SIZE:-0}" -ne "${SRC_CFG_SIZE}" ]]; then
  die "packed config size (${PACKED_SIZE}) != staged source (${SRC_CFG_SIZE})"
fi
echo "OK: packed size matches staged source (${PACKED_SIZE} bytes)"

TEMP_SHA=$(sha256sum "$TEMP_APK" | awk '{print $1}')
echo "TEMP SHA-256: $TEMP_SHA"

echo "== Canonicalize: copy temp → $CANONICAL_NAME =="
cp -f "$TEMP_APK" "$CANONICAL_APK"
CANON_SHA=$(sha256sum "$CANONICAL_APK" | awk '{print $1}')
if [[ "$TEMP_SHA" != "$CANON_SHA" ]]; then
  die "canonical copy SHA mismatch (temp=$TEMP_SHA canon=$CANON_SHA)"
fi
echo "OK: canonical copy byte-identical ($CANON_SHA)"

# Re-validate the canonical file (the artifact that will be uploaded/reported).
python3 tools/verify_apk_update_compatibility.py "$CANONICAL_APK"

echo "== Remove temporary / duplicate same-version outputs =="
rm -f "$TEMP_APK"
# Godot/gradle intermediate names that must never be user-facing for this version.
for junk in \
  "$BUILD_DIR/app-debug.apk" \
  "$BUILD_DIR/ChestOfLoveNotes-debug.apk" \
  "$BUILD_DIR/android_debug.apk"
 do
  if [[ -f "$junk" ]]; then
    # Only remove if it matches this versionCode (avoid deleting unrelated historical copies
    # that happen to share a generic name — those generics are non-canonical anyway).
    if command -v aapt >/dev/null 2>&1; then
      jc="$(aapt dump badging "$junk" 2>/dev/null | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")"
      if [[ "$jc" == "$VERSION_CODE" ]]; then
        echo "Removing non-canonical same-version APK: $junk"
        rm -f "$junk"
      fi
    else
      echo "Removing non-canonical APK candidate: $junk"
      rm -f "$junk"
    fi
  fi
done

# Ensure exactly one user-facing APK for this versionCode in build/.
SAME_VERSION=( "$BUILD_DIR"/ChestOfLoveNotes-v"${VERSION_CODE}"-*.apk )
COUNT="${#SAME_VERSION[@]}"
if [[ "$COUNT" -ne 1 ]]; then
  printf 'ERROR: expected exactly 1 APK for versionCode %s, found %s:\n' "$VERSION_CODE" "$COUNT" >&2
  printf '  %s\n' "${SAME_VERSION[@]}" >&2
  exit 1
fi
if [[ "${SAME_VERSION[0]}" != "$CANONICAL_APK" ]]; then
  die "canonical path mismatch: found ${SAME_VERSION[0]} expected $CANONICAL_APK"
fi

echo "== Stage single canonical artifact =="
ARTIFACTS_DIR="/opt/cursor/artifacts"
mkdir -p "$ARTIFACTS_DIR"
# Remove any prior same-version staged APKs with different names.
shopt -s nullglob
for staged in "$ARTIFACTS_DIR"/ChestOfLoveNotes-v"${VERSION_CODE}"-*.apk; do
  if [[ "$(basename "$staged")" != "$CANONICAL_NAME" ]]; then
    echo "Removing non-canonical staged APK: $staged"
    rm -f "$staged"
  fi
done
# Also clear generic confusing names from staging.
for staged in "$ARTIFACTS_DIR"/app-debug.apk "$ARTIFACTS_DIR"/ChestOfLoveNotes-debug.apk; do
  [[ -f "$staged" ]] && rm -f "$staged" && echo "Removed staged generic: $staged"
done
shopt -u nullglob

if cp -f "$CANONICAL_APK" "$ARTIFACTS_DIR/$CANONICAL_NAME"; then
  ART_SHA=$(sha256sum "$ARTIFACTS_DIR/$CANONICAL_NAME" | awk '{print $1}')
  if [[ "$ART_SHA" != "$CANON_SHA" ]]; then
    die "artifacts copy SHA mismatch"
  fi
  ls -lh "$CANONICAL_APK" "$ARTIFACTS_DIR/$CANONICAL_NAME"
else
  echo "WARNING: could not copy APK to $ARTIFACTS_DIR (export still OK)" >&2
  ls -lh "$CANONICAL_APK"
fi

echo
echo "========================================"
echo "CANONICAL_APK=$CANONICAL_APK"
echo "CANONICAL_NAME=$CANONICAL_NAME"
echo "VERSION_CODE=$VERSION_CODE"
echo "VERSION_NAME=$VERSION_NAME"
echo "PACKAGE_ID=$PACKAGE_ID"
echo "APK_SHA256=$CANON_SHA"
echo "EXPORT_OK $CANONICAL_APK"
echo "========================================"
