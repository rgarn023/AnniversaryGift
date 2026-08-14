#!/usr/bin/env python3
"""Hard-gate: fail if an Android APK is missing a live packed backend config.

Does not print secret values — only sizes and pass/fail.
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

PACKED = "assets/config/backend_config.json"
PACKED_EXAMPLE = "assets/config/backend_config.example.json"


def _fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def main() -> None:
    if len(sys.argv) != 2:
        _fail("usage: verify_apk_packed_backend_config.py <apk-path>")
    apk = Path(sys.argv[1])
    if not apk.is_file():
        _fail(f"APK not found: {apk}")

    with zipfile.ZipFile(apk) as zf:
        names = set(zf.namelist())
        if PACKED not in names:
            _fail(
                f"{PACKED} missing from APK — device would show "
                "'Backend is not configured'. Use tools/export_android_apk.sh."
            )
        raw = zf.read(PACKED)
        example_raw = zf.read(PACKED_EXAMPLE) if PACKED_EXAMPLE in names else b""

    if len(raw) < 80:
        _fail(f"packed backend_config.json too small ({len(raw)} bytes)")
    if example_raw and len(raw) == len(example_raw):
        _fail("packed backend_config.json size matches example — likely placeholder")

    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        _fail(f"packed backend_config.json is not valid JSON ({exc.__class__.__name__})")

    if not isinstance(data, dict):
        _fail("packed backend_config.json root must be an object")

    url = str(data.get("supabase_url", "")).strip()
    key = str(data.get("supabase_publishable_key", "")).strip()
    if not url or "YOUR_SUPABASE" in url:
        _fail("packed supabase_url missing or placeholder")
    if not key or "YOUR_SUPABASE" in key:
        _fail("packed supabase_publishable_key missing or placeholder")
    if not url.startswith("https://") or "supabase.co" not in url:
        _fail("packed supabase_url does not look like a Supabase project URL")

    print(
        "OK: APK packs live backend_config.json "
        f"(bytes={len(raw)} url_len={len(url)} key_len={len(key)} "
        f"env={data.get('environment')!r})"
    )


if __name__ == "__main__":
    main()
