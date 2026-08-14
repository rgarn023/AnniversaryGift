#!/usr/bin/env python3
"""Prove the APK-packed backend_config.json is loadable by the same rules as runtime.

Extracts assets/config/backend_config.json from the APK and validates shape using the
same acceptance rules as scripts/network/backend_config.gd (no secret values printed).
"""

from __future__ import annotations

import json
import sys
import tempfile
import zipfile
from pathlib import Path

PACKED = "assets/config/backend_config.json"


def _fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def _runtime_compatible(data: dict) -> None:
    """Mirror BackendConfig._load_from_path acceptance rules (no secrets printed)."""
    url = str(data.get("supabase_url", "")).strip()
    key = str(data.get("supabase_publishable_key", "")).strip()
    env = str(data.get("environment", "development")).strip() or "development"
    if not url or "YOUR_SUPABASE" in url:
        _fail("runtime reject: supabase_url missing/placeholder")
    if not key or "YOUR_SUPABASE" in key:
        _fail("runtime reject: supabase_publishable_key missing/placeholder")
    print(
        "OK: exported runtime backend load would succeed "
        f"(url_len={len(url)} key_len={len(key)} env={env!r})"
    )


def main() -> None:
    if len(sys.argv) != 2:
        _fail("usage: validate_exported_backend_runtime.py <apk-path>")
    apk = Path(sys.argv[1])
    if not apk.is_file():
        _fail(f"APK not found: {apk}")

    with zipfile.ZipFile(apk) as zf:
        if PACKED not in zf.namelist():
            _fail(f"{PACKED} missing — cannot validate exported runtime load")
        raw = zf.read(PACKED)

    with tempfile.TemporaryDirectory(prefix="coln-apk-cfg-") as tmp:
        out = Path(tmp) / "backend_config.json"
        out.write_bytes(raw)
        data = json.loads(out.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            _fail("packed config is not a JSON object")
        if not out.is_file():
            _fail("extracted config missing on disk")
        _runtime_compatible(data)


if __name__ == "__main__":
    main()
