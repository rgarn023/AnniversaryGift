#!/usr/bin/env python3
"""Fail private-online exports when gitignored backend config is missing/placeholder."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CFG = ROOT / "config" / "backend_config.json"
FLAGS = ROOT / "scripts" / "build_flags.gd"


def main() -> None:
    flags = FLAGS.read_text(encoding="utf-8")
    private = bool(re.search(r"const\s+PRIVATE_ONBOARDING_BUILD\s*:=\s*true", flags))
    if not private:
        print("PRIVATE_ONBOARDING_BUILD is false; skipping strict backend config check.")
        return

    if not CFG.is_file():
        print(
            "ERROR: config/backend_config.json is missing.\n"
            "Run: python3 tools/prepare_backend_config.py\n"
            "Private online APKs must pack real Supabase URL + publishable key.",
            file=sys.stderr,
        )
        sys.exit(2)

    data = json.loads(CFG.read_text(encoding="utf-8"))
    url = str(data.get("supabase_url", "")).strip()
    key = str(data.get("supabase_publishable_key", "")).strip()
    if not url or "YOUR_SUPABASE" in url:
        print("ERROR: supabase_url is missing or placeholder.", file=sys.stderr)
        sys.exit(2)
    if not key or "YOUR_SUPABASE" in key:
        print("ERROR: supabase_publishable_key is missing or placeholder.", file=sys.stderr)
        sys.exit(2)
    print(
        "OK: backend config ready for export "
        f"(url_len={len(url)} key_len={len(key)} env={data.get('environment')!r})"
    )


if __name__ == "__main__":
    main()
