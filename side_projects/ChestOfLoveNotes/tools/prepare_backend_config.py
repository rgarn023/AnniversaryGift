#!/usr/bin/env python3
"""Write gitignored config/backend_config.json from env for private online exports.

Only packs the public Supabase URL + publishable/anon key.
Never reads or writes privileged secrets into the client config.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "config" / "backend_config.json"
EXAMPLE = ROOT / "config" / "backend_config.example.json"

FORBIDDEN_ENV = (
    "SUPABASE_ACCESS_TOKEN",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_DB_PASSWORD",
    "MESSAGE_ENCRYPTION_KEY",
    "MAGIC_PASSWORD_RECOVERY_KEY",
)


def _require_public_env() -> tuple[str, str]:
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = (
        os.environ.get("SUPABASE_ANON_KEY", "").strip()
        or os.environ.get("SUPABASE_PUBLISHABLE_KEY", "").strip()
    )
    if not url or "YOUR_SUPABASE" in url:
        print("ERROR: SUPABASE_URL is missing or still a placeholder.", file=sys.stderr)
        sys.exit(2)
    if not key or "YOUR_SUPABASE" in key:
        print(
            "ERROR: SUPABASE_ANON_KEY / SUPABASE_PUBLISHABLE_KEY is missing or placeholder.",
            file=sys.stderr,
        )
        sys.exit(2)
    if not url.startswith("https://") or "supabase.co" not in url:
        print("ERROR: SUPABASE_URL does not look like a Supabase project URL.", file=sys.stderr)
        sys.exit(2)
    return url, key


def main() -> None:
    url, key = _require_public_env()
    cfg = {
        "supabase_url": url,
        "supabase_publishable_key": key,
        "environment": os.environ.get("COLN_BACKEND_ENVIRONMENT", "private_online").strip()
        or "private_online",
    }

    # Refuse to embed privileged values if they accidentally match the anon key slot.
    for name in FORBIDDEN_ENV:
        secret = os.environ.get(name, "").strip()
        if secret and secret == key:
            print(f"ERROR: publishable key must not equal {name}.", file=sys.stderr)
            sys.exit(2)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    os.chmod(OUT, 0o600)

    # Validate shape without printing secrets.
    loaded = json.loads(OUT.read_text(encoding="utf-8"))
    assert loaded["supabase_url"] == url
    assert loaded["supabase_publishable_key"] == key
    assert "YOUR_SUPABASE" not in loaded["supabase_url"]
    assert "YOUR_SUPABASE" not in loaded["supabase_publishable_key"]
    if EXAMPLE.exists():
        example = json.loads(EXAMPLE.read_text(encoding="utf-8"))
        assert loaded != example

    print(f"Wrote {OUT.relative_to(ROOT)} (url_len={len(url)} key_len={len(key)})")


if __name__ == "__main__":
    main()
