#!/usr/bin/env bash
# Fail if obvious secrets / real emails / passwords appear in client-shipping COLN sources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Sensitive value scan (client-shipping sources) ==="
FAIL=0
CLIENT_GLOBS=(
  -g 'scripts/**/*.gd'
  -g 'scenes/**/*'
  -g 'config/*.example.json'
  -g 'project.godot'
  -g 'export_presets.cfg'
  -g 'build_flags.gd'
)

scan_client() {
  local pattern="$1"
  local label="$2"
  local hits
  hits="$(rg -n "${CLIENT_GLOBS[@]}" -e "$pattern" . 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL: $label"
    echo "$hits"
    FAIL=1
  else
    echo "PASS: $label"
  fi
}

scan_client 'SERVICE_ROLE|service_role_key|MESSAGE_ENCRYPTION_KEY\s*=\s*["'\''][^"'\'']+|MAGIC_PASSWORD_RECOVERY_KEY\s*=\s*["'\''][^"'\'']+' 'no embedded service/encryption secrets in client'
scan_client 'eyJhbGciOi' 'no JWT-like literals in client'
scan_client 'password\s*[:=]\s*["'\''][^"'\'']{6,}["'\'']' 'no hardcoded password assignments in client'
scan_client '@(gmail|yahoo|hotmail|outlook)\.com' 'no consumer email addresses in client'
scan_client 'ROBERT_EMAIL_PLACEHOLDER|MANDY_EMAIL_PLACEHOLDER' 'no invite email placeholders in client binaries sources'

if rg -q 'ROBERT_EMAIL_PLACEHOLDER' supabase/sql/private_allowlist_templates.sql \
  && rg -q 'MANDY_EMAIL_PLACEHOLDER' supabase/sql/private_allowlist_templates.sql; then
  echo "PASS: SQL invite template uses placeholders"
else
  echo "FAIL: SQL invite template missing placeholders"
  FAIL=1
fi
if rg -n -e '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' supabase/sql/private_allowlist_templates.sql >/dev/null; then
  echo "FAIL: SQL invite template contains an email-like domain"
  FAIL=1
else
  echo "PASS: SQL invite template has no email domains"
fi

echo "=== APK configuration validation ==="
if rg -q 'PRIVATE_ONBOARDING_BUILD := true' scripts/build_flags.gd; then
  echo "PASS: PRIVATE_ONBOARDING_BUILD true"
else
  echo "FAIL: PRIVATE_ONBOARDING_BUILD not true"
  FAIL=1
fi
if rg -q 'version/code=4' export_presets.cfg && rg -q '0.1.3-secure-session' export_presets.cfg; then
  echo "PASS: export version code/name bumped for secure-session"
else
  echo "FAIL: export version not bumped"
  FAIL=1
fi
if rg -q 'ChestOfLoveNotes-secure-session-debug.apk' export_presets.cfg; then
  echo "PASS: export path targets secure-session APK"
else
  echo "FAIL: export path incorrect"
  FAIL=1
fi
# Session persistence must not use plaintext user:// token files in client sources.
if rg -n -g 'scripts/**/*.gd' -e 'user://.*session\.(json|cfg)|user://supabase_session' scripts >/dev/null; then
  echo "FAIL: plaintext session path referenced in scripts"
  FAIL=1
else
  echo "PASS: no plaintext session path in scripts"
fi
if rg -q 'ChestSecureStorage' scripts/network/android_secure_store.gd \
  && rg -q 'ChestOfLoveNotesSessionKey' android/plugins/chest_secure_storage/ChestSecureStoragePlugin.kt; then
  echo "PASS: ChestSecureStorage Keystore plugin wired in sources"
else
  echo "FAIL: ChestSecureStorage plugin missing"
  FAIL=1
fi
if rg -q 'com.charoitegames.chestoflovenotes' export_presets.cfg; then
  echo "PASS: package remains Chest of Love Notes"
else
  echo "FAIL: package name wrong"
  FAIL=1
fi
if rg -q 'com\.charoitegames\.anniversary' export_presets.cfg; then
  echo "FAIL: Anniversary Gift package referenced"
  FAIL=1
else
  echo "PASS: Anniversary Gift package not referenced"
fi

exit "$FAIL"
