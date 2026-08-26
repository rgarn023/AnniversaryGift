#!/usr/bin/env bash
# Strict Android export wrapper (v78+).
#
# Godot can emit GDScript parse/compile errors during Android export yet still
# return success and produce an APK. This wrapper treats those diagnostics as
# fatal so a broken client can never be published as a successful artifact.
#
# It also applies two export-workspace-only auth normalizations and restores the
# tracked sources afterward:
#   1) Explicit self.tokens member access around session writes, avoiding the
#      malformed identifier observed in the v75 export log.
#   2) Do not send a modern sb_publishable_* key as Authorization: Bearer.
#      Supabase Auth only needs the apikey header for unauthenticated requests;
#      retain the legacy anon-JWT bearer only when the public key is JWT-shaped.
#
# Finally, it verifies the FINAL APK and AAB manifests contain the dedicated
# exported AuthCallbackActivity + exact VIEW/BROWSABLE custom-scheme route. This
# prevents a repeat of v77, where source manifest injection appeared successful
# but the callback intent filter was absent from the packaged app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AUTH="scripts/network/auth_service.gd"
API="scripts/network/api_client.gd"
AUTH_BAK="$(mktemp)"
API_BAK="$(mktemp)"
LOG="$(mktemp)"
cp -f "$AUTH" "$AUTH_BAK"
cp -f "$API" "$API_BAK"

restore_sources() {
  cp -f "$AUTH_BAK" "$AUTH"
  cp -f "$API_BAK" "$API"
  rm -f "$AUTH_BAK" "$API_BAK" "$LOG"
}
trap restore_sources EXIT

python3 - "$AUTH" "$API" <<'PY'
from pathlib import Path
import sys

auth = Path(sys.argv[1])
api = Path(sys.argv[2])

auth_text = auth.read_text(encoding="utf-8")
# The v75 Godot export reported Identifier "okens" at a tokens.set_session
# line even though the Git blob displays the member correctly. Rewrite session
# member accesses explicitly in the clean CI workspace before Godot parses it.
auth_new = auth_text.replace("tokens.set_session(", "self.tokens.set_session(")
if auth_new == auth_text:
    raise SystemExit("auth normalization found no tokens.set_session calls")
auth.write_text(auth_new, encoding="utf-8")

api_text = api.read_text(encoding="utf-8")
old = '''\tif authed:\n\t\tvar auth_header := tokens.authorization_header()\n\t\tif auth_header.is_empty():\n\t\t\thttp.queue_free()\n\t\t\treturn _fail("Not signed in.", 401)\n\t\t# Must be the signed-in user JWT — never the publishable key.\n\t\theaders.append("Authorization: %s" % auth_header)\n\telse:\n\t\t# Unauthenticated Auth endpoints still need apikey; optional anon bearer for GoTrue.\n\t\theaders.append("Authorization: Bearer %s" % config.supabase_publishable_key)\n'''
new = '''\tif authed:\n\t\tvar auth_header := tokens.authorization_header()\n\t\tif auth_header.is_empty():\n\t\t\thttp.queue_free()\n\t\t\treturn _fail("Not signed in.", 401)\n\t\t# Must be the signed-in user JWT — never the publishable key.\n\t\theaders.append("Authorization: %s" % auth_header)\n\telif config.supabase_publishable_key.split(".").size() == 3:\n\t\t# Legacy anon keys are JWTs and may be sent as the optional GoTrue\n\t\t# anonymous bearer. Modern sb_publishable_* keys are not JWTs and\n\t\t# must never be placed in Authorization: Bearer.\n\t\theaders.append("Authorization: Bearer %s" % config.supabase_publishable_key)\n'''
if old not in api_text:
    raise SystemExit("api auth-header normalization block not found")
api.write_text(api_text.replace(old, new, 1), encoding="utf-8")
print("Prepared strict auth sources for Android export")
PY

set +e
bash tools/ci_export_android_artifacts.sh 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: Android export command failed with exit code $rc" >&2
  exit "$rc"
fi

if grep -Eiq 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script' "$LOG"; then
  echo "ERROR: Godot reported a script parse/compile/load error during export." >&2
  echo "Refusing to publish APK/AAB artifacts even though Godot returned success." >&2
  grep -Ei 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script' "$LOG" >&2 || true
  exit 1
fi

VERSION_CODE="$(awk -F= '/^version\/code=/{print $2; exit}' export_presets.cfg)"
DIST="${CI_DIST_DIR:-$ROOT/build/ci-dist}"
APK="$DIST/ChestOfLoveNotes-v${VERSION_CODE}-arm64-release.apk"
AAB="$DIST/ChestOfLoveNotes-v${VERSION_CODE}.aab"
AAPT="${ANDROID_HOME}/build-tools/34.0.0/aapt"

[[ -f "$APK" ]] || { echo "ERROR: strict manifest check missing APK: $APK" >&2; exit 1; }
[[ -f "$AAB" ]] || { echo "ERROR: strict manifest check missing AAB: $AAB" >&2; exit 1; }
[[ -x "$AAPT" ]] || { echo "ERROR: aapt missing for strict manifest check: $AAPT" >&2; exit 1; }
[[ -n "${BUNDLETOOL_JAR:-}" && -f "$BUNDLETOOL_JAR" ]] || {
  echo "ERROR: bundletool missing for strict manifest check" >&2
  exit 1
}

APK_MANIFEST="$(mktemp)"
AAB_MANIFEST="$(mktemp)"
"$AAPT" dump xmltree "$APK" AndroidManifest.xml > "$APK_MANIFEST"
java -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$AAB" > "$AAB_MANIFEST"

# The APK check is intentionally simple/global; the structured AAB check below
# proves the VIEW/BROWSABLE/data filter belongs to AuthCallbackActivity itself.
for needle in \
  'com.charoitegames.chestoflovenotes.securestorage.AuthCallbackActivity' \
  'android.intent.action.VIEW' \
  'android.intent.category.BROWSABLE' \
  'com.charoitegames.chestoflovenotes' \
  'auth-callback'; do
  if ! grep -Fq "$needle" "$APK_MANIFEST"; then
    echo "ERROR: final APK manifest missing auth callback marker: $needle" >&2
    rm -f "$APK_MANIFEST" "$AAB_MANIFEST"
    exit 1
  fi
done

python3 - "$AAB_MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
root = ET.parse(path).getroot()
android = '{http://schemas.android.com/apk/res/android}'
want = 'com.charoitegames.chestoflovenotes.securestorage.AuthCallbackActivity'
activity = None
for node in root.findall('.//activity'):
    if node.get(android + 'name') == want:
        activity = node
        break
if activity is None:
    raise SystemExit('AAB manifest missing AuthCallbackActivity')
if activity.get(android + 'exported') != 'true':
    raise SystemExit('AuthCallbackActivity is not exported=true')

matched = False
for filt in activity.findall('intent-filter'):
    actions = {n.get(android + 'name') for n in filt.findall('action')}
    cats = {n.get(android + 'name') for n in filt.findall('category')}
    for data in filt.findall('data'):
        if (
            'android.intent.action.VIEW' in actions
            and 'android.intent.category.DEFAULT' in cats
            and 'android.intent.category.BROWSABLE' in cats
            and data.get(android + 'scheme') == 'com.charoitegames.chestoflovenotes'
            and data.get(android + 'host') == 'auth-callback'
        ):
            matched = True
            break
    if matched:
        break
if not matched:
    raise SystemExit('AuthCallbackActivity missing exact VIEW/DEFAULT/BROWSABLE callback filter')
print('STRICT_AUTH_CALLBACK_OK: final AAB contains exact exported auth callback Activity/filter')
PY
rm -f "$APK_MANIFEST" "$AAB_MANIFEST"

echo "STRICT_EXPORT_OK: no Godot script errors; packaged auth callback route verified"
