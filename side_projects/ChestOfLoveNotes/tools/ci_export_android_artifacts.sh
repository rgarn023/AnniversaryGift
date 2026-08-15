#!/usr/bin/env bash
# CI-only: reproduce Chest of Love Notes RELEASE APK (arm64) + Play AAB.
# Version is read from export_presets.cfg (version/code + version/name).
#
# - Uses --export-release (not tools/export_android_apk.sh / --export-debug)
# - Temporarily adjusts export_presets.cfg + LAST_RELEASED_VERSION_CODE in the
#   runner workspace only; restores both before exit (never commit those edits)
# - Signs with the tracked project test keystore (stable cert)
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
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"

EXPECTED_PACKAGE="$(tr -d '[:space:]' < "$EXPECTED_PKG_FILE")"
EXPECTED_CERT="$(tr -d '[:space:]' < "$EXPECTED_CERT_FILE" | tr 'A-F' 'a-f')"
VERSION_CODE="$(awk -F= '/^version\/code=/{print $2; exit}' "$PRESETS")"
VERSION_NAME="$(awk -F= '/^version\/name=/{gsub(/"/,"",$2); print $2; exit}' "$PRESETS")"

APK_NAME="ChestOfLoveNotes-v${VERSION_CODE}-arm64-release.apk"
AAB_NAME="ChestOfLoveNotes-v${VERSION_CODE}.aab"
SHA_NAME="ChestOfLoveNotes-v${VERSION_CODE}-SHA256.txt"
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
[[ "$VERSION_CODE" =~ ^[0-9]+$ ]] || die "invalid version/code='$VERSION_CODE'"
[[ -n "$VERSION_NAME" ]] || die "missing version/name in export_presets.cfg"
GATE_PIN="$(tr -d '[:space:]' < "$LAST_RELEASED_FILE")"
PRIOR_CODE=$((VERSION_CODE - 1))
[[ "$VERSION_CODE" -gt "$GATE_PIN" ]] || die "version/code $VERSION_CODE must be > LAST_RELEASED_VERSION_CODE ($GATE_PIN)"
echo "Building versionCode=$VERSION_CODE versionName=$VERSION_NAME (gate=$GATE_PIN)"

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

# Resolve apkanalyzer if present (preferred for application-id).
resolve_apkanalyzer() {
  if command -v apkanalyzer >/dev/null 2>&1; then
    command -v apkanalyzer
    return 0
  fi
  local cand
  for cand in \
    "$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer" \
    "$ANDROID_HOME/tools/bin/apkanalyzer"; do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

# Extract Android application ID from an APK.
# Never use a greedy ".*name='...'" match: that falsely returns values from
# versionName / platformBuildVersionName / compileSdkVersionCodename (e.g. "16").
# Prints the ID on stdout; returns non-zero (with ERROR on stderr) on failure.
# Callers must not rely on die/exit inside $(...) — that only kills the subshell.
extract_apk_package_id() {
  local apk="$1"
  local pkg="" analyzer=""

  if analyzer="$(resolve_apkanalyzer)"; then
    pkg="$("$analyzer" manifest application-id "$apk" 2>/dev/null | tr -d '[:space:]' || true)"
  fi

  if [[ -z "$pkg" ]]; then
    # Anchor to the package: line's name='...' field only.
    pkg="$("$AAPT" dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n1 | tr -d '[:space:]')"
  fi

  if [[ -z "$pkg" ]]; then
    echo "ERROR: failed to parse package/application ID from APK (empty parser output)" >&2
    return 1
  fi
  if [[ "$pkg" =~ ^[0-9]+$ ]]; then
    echo "ERROR: parsed package ID is purely numeric ('$pkg'); refusing misleading mismatch (likely parser bug)" >&2
    return 1
  fi
  # Require at least one dot-separated Java-style package segment pair.
  if [[ ! "$pkg" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]; then
    echo "ERROR: malformed package/application ID from parser: '$pkg'" >&2
    return 1
  fi
  printf '%s\n' "$pkg"
}

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

# Godot Android release packs remapped textures as:
#   .../assets/.godot/imported/frame_XXXX.png-<hash>.ctex
# with remap sidecars under:
#   .../assets/assets/branding/splash_frames/frame_XXXX.png.import
# (AAB may nest the same under base/ or assetPackInstallTime/.)
# Do NOT require "splash_frames" in the .ctex ZIP path — that path never exists.
verify_godot_splash_packaging() {
  local archive="$1"
  local label="$2"
  python3 - "$archive" "$label" <<'PY'
import re
import sys
import zipfile

archive, label = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as z:
    names = z.namelist()

gif_hits = [n for n in names if n.endswith(".gif") or "154659_cursor_under4mb" in n]
if gif_hits:
    raise SystemExit(f"{label}: source GIF present in archive: {gif_hits[:5]}")

# Godot project data / resource containers (not individual top-level .pck required).
project_binary = [n for n in names if n.endswith("project.binary") or n.endswith("/project.binary")]
sparsepck = [n for n in names if n.endswith("assets.sparsepck") or n.endswith("/assets.sparsepck")]
imported_dir = [n for n in names if "/.godot/imported/" in n]
if not project_binary:
    raise SystemExit(f"{label}: missing Godot project.binary in packaged assets")
if not imported_dir and not sparsepck:
    raise SystemExit(
        f"{label}: missing Godot imported resources and assets.sparsepck "
        "(no project resource pack detected)"
    )

# Remapped splash frames: .ctex basenames, not splash_frames/.../.ctex ZIP members.
frame_ctex_re = re.compile(r"(?:^|/)(?:\.godot/)?imported/frame_(\d{4})\.png-[0-9a-fA-F]+\.ctex$")
frame_idxs = sorted({int(m.group(1)) for n in names for m in [frame_ctex_re.search(n)] if m})
frame_imports = [
    n for n in names
    if "splash_frames/" in n and n.endswith(".png.import") and re.search(r"frame_\d{4}\.png\.import$", n)
]
meta = [n for n in names if n.endswith("splash_frames_meta.json")]
still_ctex = [
    n for n in names
    if re.search(r"(?:^|/)(?:\.godot/)?imported/splash_still\.png-[0-9a-fA-F]+\.ctex$", n)
]
still_import = [n for n in names if n.endswith("splash_still.png.import")]

if frame_idxs != list(range(48)):
    raise SystemExit(
        f"{label}: expected imported splash frame .ctex indices 0..47, "
        f"found {len(frame_idxs)} ({frame_idxs[:8]}{'...' if len(frame_idxs) > 8 else ''})"
    )
if len(frame_imports) != 48:
    raise SystemExit(
        f"{label}: expected 48 splash_frames/*.png.import remaps, found {len(frame_imports)}"
    )
if not meta:
    raise SystemExit(f"{label}: splash_frames_meta.json missing from packaged project data")
if not still_ctex and not still_import:
    raise SystemExit(
        f"{label}: splash_still missing (expected .godot/imported splash_still*.ctex and/or .import)"
    )

# Optional: sparsepck index should mention at least one splash frame when present.
if sparsepck:
    with zipfile.ZipFile(archive) as z:
        blob = z.read(sparsepck[0])
    if b"frame_0000.png-" not in blob and b"splash_frames/frame_0000" not in blob:
        raise SystemExit(
            f"{label}: assets.sparsepck present but does not index splash frame_0000"
        )

print(
    f"OK ({label}): GIF absent; Godot project.binary present; "
    f"imported splash .ctex frames=48; remaps=48; still/meta present"
    + (f"; sparsepck={sparsepck[0]}" if sparsepck else "")
)
PY
}

verify_source_splash_resources() {
  echo "== Verify source splash resources (pre-export) =="
  python3 - "$ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
frames_dir = root / "assets/branding/splash_frames"
meta_path = root / "assets/branding/splash_frames_meta.json"
still = root / "assets/branding/splash_still.png"
gif = root / "assets/branding/154659_cursor_under4mb.gif"
boot = (root / "scripts/ui/charoite_boot.gd").read_text(encoding="utf-8")
presets = (root / "export_presets.cfg").read_text(encoding="utf-8")

pngs = sorted(frames_dir.glob("frame_*.png"))
imports = sorted(frames_dir.glob("frame_*.png.import"))
if len(pngs) != 48:
    raise SystemExit(f"expected 48 splash PNG frames, found {len(pngs)}")
if len(imports) != 48:
    raise SystemExit(f"expected 48 splash .import sidecars, found {len(imports)}")
idxs = [int(p.stem.split("_")[1]) for p in pngs]
if idxs != list(range(48)):
    raise SystemExit(f"splash frame indices not contiguous 0..47: {idxs[:8]}...")

meta = json.loads(meta_path.read_text(encoding="utf-8"))
if int(meta.get("frame_count", -1)) != 48:
    raise SystemExit(f"splash_frames_meta.json frame_count != 48 ({meta.get('frame_count')})")
durs = meta.get("durations_ms", [])
if not isinstance(durs, list) or len(durs) != 48:
    raise SystemExit("splash_frames_meta.json durations_ms must have 48 entries")
if not still.is_file():
    raise SystemExit("splash_still.png missing")
if not gif.is_file():
    raise SystemExit("source GIF missing on disk (must remain in repo but excluded from export)")

for imp in imports:
    text = imp.read_text(encoding="utf-8")
    if ".ctex" not in text or "dest_files=" not in text:
        raise SystemExit(f"{imp.name} does not remap to a .ctex dest")

if "splash_frames/frame_%04d.png" not in boot:
    raise SystemExit("CharoiteBoot does not reference generated splash_frames paths")
if "splash_frames_meta.json" not in boot:
    raise SystemExit("CharoiteBoot does not reference splash_frames_meta.json")
if re.search(r"load\(\s*SOURCE_GIF\s*\)|FileAccess\.open\(\s*SOURCE_GIF", boot):
    raise SystemExit("CharoiteBoot must not load the excluded source GIF at runtime")

exc = re.search(r'^exclude_filter="([^"]*)"$', presets, re.M)
inc = re.search(r'^include_filter="([^"]*)"$', presets, re.M)
if not exc or "154659_cursor_under4mb.gif" not in exc.group(1):
    raise SystemExit("export_presets.cfg must exclude the source splash GIF")
if not inc or "splash_frames" not in inc.group(1):
    raise SystemExit("export_presets.cfg include_filter must keep splash_frames")
if "154659_cursor_under4mb.gif" in (inc.group(1) if inc else ""):
    raise SystemExit("source GIF must not be in include_filter")

print(
    "OK: source splash frames=48; imports=48; meta/still present; "
    "CharoiteBoot uses generated frames; GIF excluded from Android export"
)
PY
}

# Godot may probe adb after a successful headless Android export even with no device.
# It often invokes $ANDROID_HOME/platform-tools/adb by absolute path (PATH alone is not enough).
# Stub only around export invocations; do not start an emulator or adb server.
with_adb_stub() {
  local stub_dir sdk_adb sdk_adb_bak
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/adb" <<'ADB'
#!/usr/bin/env bash
# CI stub: Godot/headless export probes adb; no device is required for artifact builds.
case "${1:-}" in
  start-server|kill-server|wait-for-device) exit 0 ;;
  devices) echo "List of devices attached"; exit 0 ;;
  version) echo "Android Debug Bridge version 1.0.41 (ci-stub)"; exit 0 ;;
  *) exit 0 ;;
esac
ADB
  chmod +x "$stub_dir/adb"

  sdk_adb=""
  sdk_adb_bak=""
  if [[ -n "${ANDROID_HOME:-}" && -x "${ANDROID_HOME}/platform-tools/adb" && ! -L "${ANDROID_HOME}/platform-tools/adb" ]]; then
    sdk_adb="${ANDROID_HOME}/platform-tools/adb"
    sdk_adb_bak="$(mktemp)"
    cp -f "$sdk_adb" "$sdk_adb_bak"
    cp -f "$stub_dir/adb" "$sdk_adb"
    chmod +x "$sdk_adb"
  fi

  set +e
  PATH="$stub_dir:$PATH" "$@"
  local rc=$?
  set -e

  if [[ -n "$sdk_adb" && -n "$sdk_adb_bak" && -f "$sdk_adb_bak" ]]; then
    cp -f "$sdk_adb_bak" "$sdk_adb"
    chmod +x "$sdk_adb"
    rm -f "$sdk_adb_bak"
  fi
  rm -rf "$stub_dir"
  return "$rc"
}

verify_apk() {
  local apk="$1"
  local bytes mib sha pkg vc vn abis cert verify_rc
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
  pkg="$(extract_apk_package_id "$apk")" || die "package/application ID extraction failed"
  # versionCode / versionName: match those keys explicitly (not a bare name=).
  vc=$(sed -n "s/^package:.*versionCode='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)
  vn=$(sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)
  abis=$(sed -n "s/^native-code: '\([^']*\)'.*/\1/p" <<<"$badging" | head -n1 | tr -d ' ')

  echo "package=$pkg"
  echo "versionCode=$vc"
  echo "versionName=$vn"
  echo "abis=$abis"

  [[ -n "$vc" ]] || die "failed to parse versionCode from APK badging"
  [[ -n "$vn" ]] || die "failed to parse versionName from APK badging"
  [[ -n "$abis" ]] || die "failed to parse native-code ABIs from APK badging"
  [[ "$pkg" == "$EXPECTED_PACKAGE" ]] || die "package mismatch: got '$pkg', expected '$EXPECTED_PACKAGE'"
  [[ "$vc" == "$VERSION_CODE" ]] || die "versionCode mismatch: $vc (want $VERSION_CODE)"
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

  verify_godot_splash_packaging "$apk" "APK"

  python3 - "$apk" <<'PY'
import sys, zipfile
apk = sys.argv[1]
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
libs = [n for n in names if n.startswith('lib/') and n.endswith('.so')]
non_arm64 = [n for n in libs if '/arm64-v8a/' not in n]
if non_arm64:
    raise SystemExit(f'non-arm64 libs present: {non_arm64[:8]}')
print('OK: arm64-only libs')
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

  python3 - "$manifest_dump" "$EXPECTED_PACKAGE" "$VERSION_NAME" "$VERSION_CODE" <<'PY'
import sys
text, pkg, vname, vc = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
if f'package="{pkg}"' not in text and pkg not in text:
    raise SystemExit(f'AAB package not found / mismatch (expected {pkg})')
if f'android:versionCode="{vc}"' not in text and f'versionCode="{vc}"' not in text:
    raise SystemExit(f'AAB versionCode {vc} not found in manifest dump')
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
print('OK: modules/abis OK')
PY

  # Same Godot remapped packaging as APK (paths may live under base/ or assetPackInstallTime/).
  verify_godot_splash_packaging "$aab" "AAB"

  out_dir="$(mktemp -d)"
  device_spec="$out_dir/device-spec-arm64.json"
  apks_out="$out_dir/chest_v${VERSION_CODE}.apks"
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
# Chest of Love Notes v${VERSION_CODE} Android Build

## APK
- **filename:** \`$APK_NAME\`
- **size:** ${APK_BYTES} bytes (${APK_MIB} MiB)
- **SHA-256:** \`${APK_SHA}\`
- **ARM64-only:** yes (\`${APK_ABIS}\`)
- **signing verification:** ${APK_VERIFY} (cert \`${APK_CERT}\`)
- **package / version:** \`${EXPECTED_PACKAGE}\` / code \`${VERSION_CODE}\` / name \`${VERSION_NAME}\`

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

echo "== CI v${VERSION_CODE} Android release artifacts =="
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
verify_source_splash_resources

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -f "$APK_OUT" "$AAB_OUT" "$SHA_OUT" \
  "$BUILD_DIR/.tmp-export-v${VERSION_CODE}-release.apk" \
  "$BUILD_DIR/.tmp-export-v${VERSION_CODE}.aab" \
  "$BUILD_DIR/$APK_NAME" \
  "$BUILD_DIR/$AAB_NAME"

# Temporary CI-only gate: allow building VERSION_CODE while committed gate is prior release.
# Restored by EXIT trap to the checked-in gate pin.
printf '%s\n' "$PRIOR_CODE" > "$LAST_RELEASED_FILE"
echo "Temporarily set LAST_RELEASED_VERSION_CODE=$PRIOR_CODE for CI build of v${VERSION_CODE} (will restore to $GATE_PIN)"

echo "== Export RELEASE APK (arm64-only) =="
patch_presets 0 false true "build/.tmp-export-v${VERSION_CODE}-release.apk"
with_adb_stub "$GODOT" --headless --path . --export-release "Android" "$BUILD_DIR/.tmp-export-v${VERSION_CODE}-release.apk"
[[ -f "$BUILD_DIR/.tmp-export-v${VERSION_CODE}-release.apk" ]] || die "APK export failed"
cp -f "$BUILD_DIR/.tmp-export-v${VERSION_CODE}-release.apk" "$APK_OUT"
cp -f "$APK_OUT" "$BUILD_DIR/$APK_NAME"
verify_apk "$APK_OUT"

echo "== Export RELEASE AAB (armeabi-v7a + arm64-v8a) =="
patch_presets 1 true true "build/.tmp-export-v${VERSION_CODE}.aab"
with_adb_stub "$GODOT" --headless --path . --export-release "Android" "$BUILD_DIR/.tmp-export-v${VERSION_CODE}.aab"
[[ -f "$BUILD_DIR/.tmp-export-v${VERSION_CODE}.aab" ]] || die "AAB export failed"
cp -f "$BUILD_DIR/.tmp-export-v${VERSION_CODE}.aab" "$AAB_OUT"
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
# then re-check gate pin is the committed value (still prior release until approval).
restore_tracked
trap - EXIT
[[ "$(tr -d '[:space:]' < "$LAST_RELEASED_FILE")" == "$GATE_PIN" ]] || die "LAST_RELEASED_VERSION_CODE restore failed (want $GATE_PIN)"
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
