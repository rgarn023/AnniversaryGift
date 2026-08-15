#!/usr/bin/env bash
# Compatibility wrapper — prefer tools/ci_export_android_artifacts.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/tools/ci_export_android_artifacts.sh" "$@"
