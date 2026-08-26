#!/usr/bin/env python3
"""Hard gate: package ID, versionCode, and signing cert for Chest of Love Notes APKs.

Fails the build when the APK is not update-compatible with the project's
stable test-signing identity and version policy.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIGNING = ROOT / "android" / "signing"
EXPECTED_PACKAGE = (SIGNING / "EXPECTED_PACKAGE_ID").read_text(encoding="utf-8").strip()
EXPECTED_CERT = (SIGNING / "EXPECTED_TEST_CERT_SHA256").read_text(encoding="utf-8").strip().lower()
LAST_RELEASED = int((SIGNING / "LAST_RELEASED_VERSION_CODE").read_text(encoding="utf-8").strip())


def _fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def _android_build_tools() -> Path:
    home = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or "")
    candidates: list[Path] = []
    if home:
        bt = home / "build-tools"
        if bt.is_dir():
            candidates.extend(sorted(bt.iterdir(), reverse=True))
    for base in candidates:
        aapt = base / "aapt"
        apksigner = base / "apksigner"
        if aapt.is_file() and apksigner.is_file():
            return base
    _fail("aapt/apksigner not found under ANDROID_HOME/build-tools")


def _run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if proc.returncode != 0:
        _fail(f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr or proc.stdout}")
    return proc.stdout


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_badging(aapt: Path, apk: Path) -> tuple[str, int, str]:
    out = _run([str(aapt), "dump", "badging", str(apk)])
    line = out.splitlines()[0] if out else ""
    pkg_m = re.search(r"name='([^']+)'", line)
    vc_m = re.search(r"versionCode='([^']+)'", line)
    vn_m = re.search(r"versionName='([^']+)'", line)
    if not (pkg_m and vc_m and vn_m):
        _fail(f"could not parse aapt badging from {apk}: {line!r}")
    return pkg_m.group(1), int(vc_m.group(1)), vn_m.group(1)


def parse_cert_sha256(apksigner: Path, apk: Path) -> str:
    out = _run([str(apksigner), "verify", "--print-certs", str(apk)])
    # Ensure verify succeeded (apksigner prints certs even on some soft issues;
    # require explicit success by re-running verify without print).
    verify = subprocess.run(
        [str(apksigner), "verify", str(apk)],
        check=False,
        capture_output=True,
        text=True,
    )
    if verify.returncode != 0:
        _fail(f"apksigner verify failed for {apk}:\n{verify.stderr or verify.stdout}")
    m = re.search(r"SHA-256 digest:\s*([0-9a-fA-F]+)", out)
    if not m:
        _fail(f"could not parse signing cert SHA-256 from apksigner output for {apk}")
    return m.group(1).lower()


def main() -> None:
    if len(sys.argv) != 2:
        _fail("usage: verify_apk_update_compatibility.py <apk-path>")
    apk = Path(sys.argv[1]).resolve()
    if not apk.is_file():
        _fail(f"APK not found: {apk}")

    if not EXPECTED_PACKAGE or not EXPECTED_CERT:
        _fail("missing EXPECTED_PACKAGE_ID or EXPECTED_TEST_CERT_SHA256 under android/signing/")

    tools = _android_build_tools()
    aapt = tools / "aapt"
    apksigner = tools / "apksigner"

    package_id, version_code, version_name = parse_badging(aapt, apk)
    cert = parse_cert_sha256(apksigner, apk)
    apk_sha = sha256_file(apk)

    print("== Update compatibility gate ==", flush=True)
    print(f"APK: {apk}", flush=True)
    print(f"PACKAGE ID: {package_id}", flush=True)
    print(f"VERSIONCODE: {version_code}", flush=True)
    print(f"VERSIONNAME: {version_name}", flush=True)
    print(f"SIGNING CERT SHA-256: {cert}", flush=True)
    print(f"APK SHA-256: {apk_sha}", flush=True)
    print(f"EXPECTED PACKAGE ID: {EXPECTED_PACKAGE}", flush=True)
    print(f"EXPECTED CERT SHA-256: {EXPECTED_CERT}", flush=True)
    print(f"LAST_RELEASED_VERSION_CODE pin: {LAST_RELEASED}", flush=True)

    errors: list[str] = []
    if package_id != EXPECTED_PACKAGE:
        errors.append(f"package ID mismatch: got {package_id}, expected {EXPECTED_PACKAGE}")
    if version_code <= LAST_RELEASED:
        errors.append(
            f"versionCode must be > last released ({LAST_RELEASED}); got {version_code}. "
            "Bump version/code in export_presets.cfg before exporting."
        )
    if cert != EXPECTED_CERT:
        errors.append(
            f"signing certificate mismatch: got {cert}, expected {EXPECTED_CERT}. "
            "Use the project test keystore via tools/export_android_apk.sh; do not release."
        )
    if errors:
        _fail("update compatibility gate failed:\n- " + "\n- ".join(errors))

    print("OK: package ID, versionCode, signature, and cert match project gates", flush=True)
    print(f"COMPAT_OK {apk}", flush=True)


if __name__ == "__main__":
    main()
