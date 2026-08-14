# Android test signing (Chest of Love Notes)

## Purpose

All **debug/test** APKs intended to update an existing install must share one stable signing certificate.

Cursor cloud VMs previously generated a **new Godot/Android debug keystore per environment**. That produced a different certificate on nearly every release and caused Samsung Galaxy installs to fail with **"App not installed"** when updating over an existing APK.

## Canonical test identity

| Field | Value |
| --- | --- |
| Keystore (tracked) | `android/signing/chest_test_debug.keystore` |
| Alias | `androiddebugkey` |
| Expected package ID | see `EXPECTED_PACKAGE_ID` |
| Expected cert SHA-256 | see `EXPECTED_TEST_CERT_SHA256` |
| Last released versionCode pin | see `LAST_RELEASED_VERSION_CODE` |

Credentials for this **test-only** keystore are supplied to Godot via environment variables inside `tools/export_android_apk.sh` (never printed). They are not release/Play Store secrets.

## One-time device migration

Any APK built **before** this stable keystore (including known-good v61 and releases through v71) used ephemeral per-machine certificates.

Android **cannot** update an app in place when the signing certificate differs.

**Action on device once:** uninstall the old Chest of Love Notes install, then install the new stably-signed APK. After that, future builds from this keystore can update normally (provided `versionCode` increases).

## Do not

- Generate a new keystore per build
- Rely on `~/.android/debug.keystore` or Godot’s machine-local debug key
- Bypass `tools/export_android_apk.sh`
- Publish an APK whose cert SHA-256 differs from `EXPECTED_TEST_CERT_SHA256`
