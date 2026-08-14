#!/usr/bin/env bash
# CI-only: reproduce Chest of Love Notes v72 RELEASE APK (arm64) + Play AAB.
#
# - Uses --export-release (not tools/export_android_apk.sh / --export-debug)
# - Temporarily adjusts export_presets.cfg + LAST_RELEASED_VERSION_CODE in the
#   runner workspace only; restores both before exit (never commit those edits)
# - Signs with the tracked project test keystore (same cert as the v72 pipeline)
# - Does NOT stage under /opt/cursor/artifacts
#
# Required env:
#   SUPABASE_URL
#   SUPABASE_ANON_KEY (or SUPABASE_PUBLISHABLE_KEY)
# Optional env:
#   GODOT, ANDROID_HOME, JAVA_HOME, BUNDLETOOL_JAR
#   GODOT_ANDROID_KEYSTORE_* (defaults match tools/export_android_apk.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIGNING_DIR="$ROOT/android/signing"
KEYSTORE="$SIGNING_DIR/chest_test_debug.keystore"
EXPECTED_CERT_FILE="$SIGNING_DIR/EXPECTED_TEST_CERT_SHA256"
EXPECTED_PKG_FILE="$SIGNING_DIR/EXPECTED_PACKAGE_ID"
LAST_RELEASED_FILE="$SIGNING_DIR/LAST_RELEASED_VERSION_CODE"
PRESETS="$ROOT/export_presets.cfg"

GODOT="${GODOT:-/home/ubuntu/godot/Godot_v4.7.1-stable_linux.x86_64}"
if [[ ! -x "$GODOT" && -x /tmp/godot/Godot_v4.7.1-stable_linux.x86_64 ]]; then
  GODOT="/tmp/godot/Godot_v4.7.1-stable_linux.x86_64"
fi
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"

EXPECTED_PACKAGE="$(tr -d '[:space:]' < "$EXPECTED_PKG_FILE")"
EXPECTED_CERT="$(tr -d '[:space:]' < "$EXPECTED_CERT_FILE" | tr 'A-F' 'a-f')"
VERSION_CODE="$(awk -F= '/^version\/code=/{print $2; exit}' "$PRESETS")"
VERSION_NAME="$(awk -F= '/^version\/name=/{gsub(/"/,"",$2); print $2; exit}' "$PRESETS")"

APK_NAME="ChestOfLoveNotes-v72-arm64-release.apk"
AAB_NAME="ChestOfLoveNotes-v72.aab"
SHA_NAME="ChestOfLoveNotes-v72-SHA256.txt"
BUILD_DIR="$ROOT/build"
DIST_DIR="${CI_DIST_DIR:-$BUILD_DIR/ci-dist}"
APK_OUT="$DIST_DIR/$APK_NAME"
AAB_OUT="$DIST_DIR/$AAB_NAME"
SHA_OUT="$DIST_DIR/$SHA_NAME"

MAX_APK_BYTES=104857600
SOFT_WARN_APK_BYTES=$((100 * 1024 * 1024))

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$KEYSTORE" ]] || die "missing project test keystore: $KEYSTORE"
[[ -f "$EXPECTED_CERT_FILE" ]] || die "missing $EXPECTED_CERT_FILE"
[[ -f "$EXPECTED_PKG_FILE" ]] || die "missing $EXPECTED_PKG_FILE"
[[ -f "$LAST_RELEASED_FILE" ]] || die "missing $LAST_RELEASED_FILE"
[[ -f "$PRESETS" ]] || die "missing export_presets.cfg"
[[ -x "$GODOT" ]] || die "Godot binary not executable: $GODOT"
[[ "$VERSION_CODE" == "72" ]] || die "expected version/code=72, got '$VERSION_CODE'"
[[ "$VERSION_NAME" == "0.1.72-apk-signing-pipeline-fix" ]] || die "unexpected version/name='$VERSION_NAME'"

# Test-only credentials for the tracked project keystore. Never print values.
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android}"

PRESETS_BACKUP="$(mktemp)"
GATE_BACKUP="$(mktemp)"
cp -f "$PRESETS" "$PRESETS_BACKUP"
cp -f "$LAST_RELEASED_FILE" "$GATE_BACKUP"

restore_tracked() {
  cp -f "$PRESETS_BACKUP" "$PRESETS"
  cp -f "$GATE_BACKUP" "$LAST_RELEASED_FILE"
  rm -f "$PRESETS_BACKUP" "$GATE_BACKUP"
}
trap restore_tracked EXIT

android_build_tools() {
  local bt base
  bt="$ANDROID_HOME/build-tools"
  [[ -d "$bt" ]] || die "missing build-tools under ANDROID_HOME=$ANDROID_HOME"
  # Prefer pinned 34.0.0, else newest.
  if [[ -x "$bt/34.0.0/aapt" && -x "$bt/34.0.0/apksigner" ]]; then
    echo "$bt/34.0.0"
    return
  fi
  for base in $(ls -1d "$bt"/* 2>/dev/null | sort -V -r); do
    if [[ -x "$base/aapt" && -x "$base/apksigner" ]]; then
      echo "$base"
      return
    fi
  done
  die "aapt/apksigner not found under $bt"
}

BT="$(android_build_tools)"
AAPT="$BT/aapt"
APKSIGNER="$BT/apksigner"

patch_presets() {
  local export_format="$1"
  local armeabi="$2"
  local arm64="$3"
  local export_path="$4"
  python3 - "$PRESETS" "$export_format" "$armeabi" "$arm64" "$export_path" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
export_format, armeabi, arm64, export_path = sys.argv[2:6]
text = path.read_text(encoding="utf-8")

def sub_one(pattern: str, repl: str, label: str) -> None:
    global text
    text2, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        raise SystemExit(f"failed to patch {label} (matches={n})")
    text = text2

sub_one(r'^gradle_build/export_format=\d+$', f'gradle_build/export_format={export_format}', 'export_format')
sub_one(r'^architectures/armeabi-v7a=(true|false)$', f'architectures/armeabi-v7a={armeabi}', 'armeabi-v7a')
sub_one(r'^architectures/arm64-v8a=(true|false)$', f'architectures/arm64-v8a={arm64}', 'arm64-v8a')
sub_one(r'^architectures/x86=(true|false)$', 'architectures/x86=false', 'x86')
sub_one(r'^architectures/x86_64=(true|false)$', 'architectures/x86_64=false', 'x86_64')
sub_one(r'^export_path="[^"]*"$', f'export_path="{export_path}"', 'export_path')

# Preserve GIF exclusion — never package the source splash GIF.
if 'assets/branding/154659_cursor_under4mb.gif' not in text:
    raise SystemExit('GIF exclude missing from export_presets.cfg')
inc = re.search(r'^include_filter="([^"]*)"$', text, re.M)
if not inc:
    raise SystemExit('include_filter missing')
if '154659_cursor_under4mb.gif' in inc.group(1):
    raise SystemExit('source GIF must not be in include_filter')

path.write_text(text, encoding="utf-8")
print(f"Patched presets: format={export_format} armeabi={armeabi} arm64={arm64} path={export_path}")
PY
}

write_signing_config() {
  local cfg_dir settings_dir
  cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
  mkdir -p "$cfg_dir"
  cat > "$cfg_dir/editor_settings-4.7.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "${ANDROID_HOME}"
export/android/java_sdk_path = "${JAVA_HOME}"
export/android/debug_keystore = "${KEYSTORE}"
export/android/debug_keystore_user = "${GODOT_ANDROID_KEYSTORE_DEBUG_USER}"
EOF

  mkdir -p .godot
  # Credentials file is gitignored; do not echo contents.
  cat > .godot/export_credentials.cfg <<EOF
[preset.0]

[preset.0.options]

keystore/debug="${KEYSTORE}"
keystore/debug_user="${GODOT_ANDROID_KEYSTORE_DEBUG_USER}"
keystore/debug_password="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD}"
keystore/release="${KEYSTORE}"
keystore/release_user="${GODOT_ANDROID_KEYSTORE_RELEASE_USER}"
keystore/release_password="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD}"
EOF
}

ensure_android_template() {
  local templates="$HOME/.local/share/godot/export_templates/4.7.1.stable"
  local src_zip="$templates/android_source.zip"
  [[ -f "$src_zip" ]] || die "missing Android source template: $src_zip"
  if [[ ! -d android/build/src ]]; then
    echo "== Install Godot Android Gradle template =="
    rm -rf android/build
    mkdir -p android/build
    unzip -qo "$src_zip" -d android/build
    touch android/build/.gdignore
    printf '4.7.1.stable\n' > android/.build_version
  fi
  echo "sdk.dir=${ANDROID_HOME}" > android/build/local.properties
  bash android/plugins/chest_secure_storage/install_into_android_build.sh
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

verify_apk() {
  local apk="$1"
  local bytes mib sha pkg vc vn abis cert verify_rc gif_hits splash_hits
  [[ -f "$apk" ]] || die "APK missing: $apk"
  bytes=$(wc -c < "$apk" | tr -d ' ')
  mib=$(python3 -c "print(f'{int('$bytes')/1024/1024:.3f}')")
  sha=$(sha256_of "$apk")

  echo "== APK verification =="
  echo "filename=$(basename "$apk")"
  echo "bytes=$bytes"
  echo "mib=$mib"
  echo "sha256=$sha"

  if (( bytes > MAX_APK_BYTES )); then
    die "APK exceeds hard limit ${MAX_APK_BYTES} bytes (got $bytes / ${mib} MiB)"
  fi
  if (( bytes > SOFT_WARN_APK_BYTES )); then
    die "APK unexpectedly exceeds 100 MiB (${mib} MiB / $bytes bytes). Refusing without asset changes."
  fi

  local badging
  badging="$("$AAPT" dump badging "$apk")"
  pkg=$(sed -n "s/.*name='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
  vc=$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
  vn=$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
  abis=$(sed -n "s/.*native-code: '\([^']*\)'.*/\1/p" <<<"$badging" | head -1 | tr -d ' ')

  echo "package=$pkg"
  echo "versionCode=$vc"
  echo "versionName=$vn"
  echo "abis=$abis"

  [[ "$pkg" == "$EXPECTED_PACKAGE" ]] || die "package mismatch: $pkg"
  [[ "$vc" == "72" ]] || die "versionCode mismatch: $vc"
  [[ "$vn" == "$VERSION_NAME" ]] || die "versionName mismatch: $vn"
  [[ "$abis" == "arm64-v8a" ]] || die "ABI mismatch (want arm64-v8a only): '$abis'"

  set +e
  "$APKSIGNER" verify "$apk"
  verify_rc=$?
  set -e
  [[ "$verify_rc" -eq 0 ]] || die "apksigner verify failed"
  cert=$("$APKSIGNER" verify --print-certs "$apk" | sed -n 's/.*SHA-256 digest:[[:space:]]*//p' | head -1 | tr 'A-F' 'a-f')
  echo "signing_cert_sha256=$cert"
  echo "apksigner_verify=OK"
  [[ "$cert" == "$EXPECTED_CERT" ]] || die "signing cert mismatch: $cert"

  python3 - "$apk" <<'PY'
import sys, zipfile
apk = sys.argv[1]
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
gif_hits = [n for n in names if n.endswith('.gif') or '154659_cursor_under4mb' in n]
splash = [n for n in names if 'splash_frames' in n and n.endswith('.ctex')]
# Godot may pack under assets/ or asset-pack-like paths; match by basename.
still = [n for n in names if n.endswith('splash_still.png')]
meta = [n for n in names if n.endswith('splash_frames_meta.json')]
if gif_hits:
    raise SystemExit(f'source GIF present in APK: {gif_hits[:5]}')
if len(splash) != 48:
    raise SystemExit(f'expected 48 splash .ctex frames, found {len(splash)}')
if not still:
    raise SystemExit('splash_still.png missing from APK')
if not meta:
    raise SystemExit('splash_frames_meta.json missing from APK')
libs = [n for n in names if n.startswith('lib/') and n.endswith('.so')]
non_arm64 = [n for n in libs if '/arm64-v8a/' not in n]
if non_arm64:
    raise SystemExit(f'non-arm64 libs present: {non_arm64[:8]}')
print(f'OK: GIF absent; splash frames={len(splash)}; still/meta present; arm64-only libs')
PY

  APK_BYTES="$bytes"
  APK_MIB="$mib"
  APK_SHA="$sha"
  APK_CERT="$cert"
  APK_ABIS="$abis"
  APK_VERIFY="OK"
}

verify_aab() {
  local aab="$1"
  local bytes mib sha jar out_dir device_spec apks_out
  [[ -f "$aab" ]] || die "AAB missing: $aab"
  jar="${BUNDLETOOL_JAR:-}"
  [[ -n "$jar" && -f "$jar" ]] || die "BUNDLETOOL_JAR not set or missing"

  bytes=$(wc -c < "$aab" | tr -d ' ')
  mib=$(python3 -c "print(f'{int('$bytes')/1024/1024:.3f}')")
  sha=$(sha256_of "$aab")
  echo "== AAB verification =="
  echo "filename=$(basename "$aab")"
  echo "bytes=$bytes"
  echo "mib=$mib"
  echo "sha256=$sha"

  local manifest_dump config_dump
  manifest_dump="$(java -jar "$jar" dump manifest --bundle="$aab")"
  config_dump="$(java -jar "$jar" dump config --bundle="$aab")"
  echo "$manifest_dump" | head -n 40
  echo "$config_dump" | head -n 80

  python3 - "$manifest_dump" "$EXPECTED_PACKAGE" "$VERSION_NAME" <<'PY'
import sys
text, pkg, vname = sys.argv[1], sys.argv[2], sys.argv[3]
if f'package="{pkg}"' not in text and pkg not in text:
    raise SystemExit(f'AAB package not found / mismatch (expected {pkg})')
if 'android:versionCode="72"' not in text and 'versionCode="72"' not in text:
    raise SystemExit('AAB versionCode 72 not found in manifest dump')
if f'android:versionName="{vname}"' not in text and f'versionName="{vname}"' not in text:
    raise SystemExit(f'AAB versionName mismatch (expected {vname})')
print('OK: package/versionCode/versionName present in AAB manifest dump')
PY

  # Modules + ABIs from AAB zip layout.
  python3 - "$aab" <<'PY'
import sys, zipfile
aab = sys.argv[1]
with zipfile.ZipFile(aab) as z:
    names = z.namelist()
mods = sorted({n.split('/')[0] for n in names if '/' in n and not n.startswith('BUNDLE-METADATA') and not n.startswith('META-INF')})
# Keep only top-level module-ish dirs
mods = [m for m in mods if m in ('base', 'assetPackInstallTime') or m.endswith('Pack') or m.startswith('asset')]
print('modules=', ','.join(sorted(set(mods))))
if 'base' not in mods or 'assetPackInstallTime' not in mods:
    raise SystemExit(f'expected modules base+assetPackInstallTime, got {mods}')
abis = sorted({n.split('/')[2] for n in names if n.startswith('base/lib/') and n.count('/') >= 3})
print('abis=', ','.join(abis))
if abis != ['arm64-v8a', 'armeabi-v7a']:
    raise SystemExit(f'unexpected AAB ABIs: {abis}')
gif_hits = [n for n in names if n.endswith('.gif') or '154659_cursor_under4mb' in n]
if gif_hits:
    raise SystemExit(f'source GIF present in AAB: {gif_hits[:5]}')
splash = [n for n in names if 'splash_frames' in n and n.endswith('.ctex')]
if len(splash) != 48:
    raise SystemExit(f'expected 48 splash .ctex in AAB, found {len(splash)}')
still = [n for n in names if n.endswith('splash_still.png')]
meta = [n for n in names if n.endswith('splash_frames_meta.json')]
if not still or not meta:
    raise SystemExit('AAB missing splash_still and/or splash_frames_meta')
print(f'OK: GIF absent; splash frames={len(splash)}; modules/abis OK')
PY

  out_dir="$(mktemp -d)"
  device_spec="$out_dir/device-spec-arm64.json"
  apks_out="$out_dir/chest_v72.apks"
  cat > "$device_spec" <<'EOF'
{"supportedAbis":["arm64-v8a"],"supportedLocales":["en-US"],"screenDensity":480,"sdkVersion":34}
EOF

  # Validate by generating APKs (also confirms signing material works for Play-style extract).
  java -jar "$jar" build-apks \
    --bundle="$aab" \
    --output="$apks_out" \
    --mode=default \
    --ks="$KEYSTORE" \
    --ks-pass="pass:${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD}" \
    --ks-key-alias="${GODOT_ANDROID_KEYSTORE_RELEASE_USER}" \
    --key-pass="pass:${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD}"

  java -jar "$jar" extract-apks \
    --apks="$apks_out" \
    --output-dir="$out_dir/extracted" \
    --device-spec="$device_spec"

  # Cert check on an extracted split/base APK if present.
  local sample
  sample="$(find "$out_dir/extracted" -name '*.apk' | head -1 || true)"
  [[ -n "$sample" ]] || die "bundletool extract-apks produced no APK"
  local cert
  cert=$("$APKSIGNER" verify --print-certs "$sample" | sed -n 's/.*SHA-256 digest:[[:space:]]*//p' | head -1 | tr 'A-F' 'a-f')
  echo "extracted_apk_signing_cert_sha256=$cert"
  [[ "$cert" == "$EXPECTED_CERT" ]] || die "AAB-derived APK cert mismatch: $cert"
  "$APKSIGNER" verify "$sample" >/dev/null
  echo "bundle_validation=OK"
  rm -rf "$out_dir"

  AAB_BYTES="$bytes"
  AAB_MIB="$mib"
  AAB_SHA="$sha"
  AAB_CERT="$cert"
  AAB_VALIDATE="OK"
  AAB_ABIS="armeabi-v7a,arm64-v8a"
  AAB_MODULES="base,assetPackInstallTime"
}

write_summary() {
  local body
  body=$(cat <<EOF
# Chest of Love Notes v72 Android Build

## APK
- **filename:** \`$APK_NAME\`
- **size:** ${APK_BYTES} bytes (${APK_MIB} MiB)
- **SHA-256:** \`${APK_SHA}\`
- **ARM64-only:** yes (\`${APK_ABIS}\`)
- **signing verification:** ${APK_VERIFY} (cert \`${APK_CERT}\`)
- **package / version:** \`${EXPECTED_PACKAGE}\` / code \`72\` / name \`${VERSION_NAME}\`

## AAB
- **filename:** \`$AAB_NAME\`
- **size:** ${AAB_BYTES} bytes (${AAB_MIB} MiB)
- **SHA-256:** \`${AAB_SHA}\`
- **validation result:** ${AAB_VALIDATE}
- **ABI configuration:** \`${AAB_ABIS}\`
- **modules:** \`${AAB_MODULES}\`
- **signing certificate SHA-256:** \`${AAB_CERT}\`

Download the APK and AAB from the Artifacts section at the bottom of this workflow run.
EOF
)
  mkdir -p "$DIST_DIR"
  printf '%s\n' "$body" > "$DIST_DIR/GITHUB_STEP_SUMMARY.md"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$body" >> "$GITHUB_STEP_SUMMARY"
  fi
  echo "Wrote job summary"
}

echo "== CI v72 Android release artifacts =="
echo "Godot=$GODOT"
echo "ANDROID_HOME=$ANDROID_HOME"
echo "JAVA_HOME=$JAVA_HOME"
echo "keystore=$KEYSTORE (tracked project test identity)"
echo "expected_cert=$EXPECTED_CERT"

write_signing_config
ensure_android_template

echo "== Prepare backend_config.json =="
python3 tools/prepare_backend_config.py
python3 tools/verify_backend_config_for_export.py

# Splash frames should already be present; regenerate only if missing.
if [[ ! -f assets/branding/splash_frames_meta.json || ! -f assets/branding/splash_still.png ]]; then
  echo "== Prepare splash frames from source GIF (assets missing) =="
  python3 tools/prepare_charoite_splash_from_gif.py
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -f "$APK_OUT" "$AAB_OUT" "$SHA_OUT" \
  "$BUILD_DIR/.tmp-export-v72-release.apk" \
  "$BUILD_DIR/.tmp-export-v72.aab" \
  "$BUILD_DIR/$APK_NAME" \
  "$BUILD_DIR/$AAB_NAME"

# Temporary CI-only gate so versionCode 72 can be reproduced without committing 71.
# Restored by EXIT trap to the checked-in value (72).
printf '71\n' > "$LAST_RELEASED_FILE"
echo "Temporarily set LAST_RELEASED_VERSION_CODE=71 for CI reproduce of v72 (will restore)"

echo "== Export RELEASE APK (arm64-only) =="
patch_presets 0 false true "build/.tmp-export-v72-release.apk"
"$GODOT" --headless --path . --export-release "Android" "$BUILD_DIR/.tmp-export-v72-release.apk"
[[ -f "$BUILD_DIR/.tmp-export-v72-release.apk" ]] || die "APK export failed"
cp -f "$BUILD_DIR/.tmp-export-v72-release.apk" "$APK_OUT"
cp -f "$APK_OUT" "$BUILD_DIR/$APK_NAME"
verify_apk "$APK_OUT"

echo "== Export RELEASE AAB (armeabi-v7a + arm64-v8a) =="
patch_presets 1 true true "build/.tmp-export-v72.aab"
"$GODOT" --headless --path . --export-release "Android" "$BUILD_DIR/.tmp-export-v72.aab"
[[ -f "$BUILD_DIR/.tmp-export-v72.aab" ]] || die "AAB export failed"
cp -f "$BUILD_DIR/.tmp-export-v72.aab" "$AAB_OUT"
cp -f "$AAB_OUT" "$BUILD_DIR/$AAB_NAME"
verify_aab "$AAB_OUT"

{
  echo "${APK_SHA}  ${APK_NAME}"
  echo "${AAB_SHA}  ${AAB_NAME}"
} > "$SHA_OUT"
echo "Wrote $SHA_OUT"
cat "$SHA_OUT"

write_summary

# Restore happens via trap; assert tracked files match backups conceptually by restoring now
# then re-check gate pin is 72.
restore_tracked
trap - EXIT
[[ "$(tr -d '[:space:]' < "$LAST_RELEASED_FILE")" == "72" ]] || die "LAST_RELEASED_VERSION_CODE restore failed"
grep -Eq '^gradle_build/export_format=0$' "$PRESETS" || die "export_format restore failed"
grep -Eq '^architectures/armeabi-v7a=false$' "$PRESETS" || die "armeabi restore failed"
grep -Fq 'assets/branding/154659_cursor_under4mb.gif' "$PRESETS" || die "GIF exclude lost"

echo
echo "========================================"
echo "CI_APK=$APK_OUT"
echo "CI_AAB=$AAB_OUT"
echo "CI_SHA=$SHA_OUT"
echo "APK_SHA256=$APK_SHA"
echo "AAB_SHA256=$AAB_SHA"
echo "EXPORT_OK"
echo "========================================"
