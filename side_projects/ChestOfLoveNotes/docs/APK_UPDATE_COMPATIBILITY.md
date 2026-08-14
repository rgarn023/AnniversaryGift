# APK Update Compatibility (v72+)

## Inspected HEAD

| Field | Value |
| --- | --- |
| Branch | `cursor/mobile-production-polish-caa0` |
| Package ID | `com.charoitegames.chestoflovenotes` (stable across all inspected APKs) |

## Root cause of "App not installed" (Samsung Galaxy)

Evidence from `apksigner verify --print-certs` on GitHub Release assets:

| APK | versionCode | Signer DN | Cert SHA-256 |
| --- | ---: | --- | --- |
| v61 known-good | 61 | CN=Godot… | `35b68e3f19ca1fc47dce4f594be8919cefd14da2a9127f3b61927cd6d332b404` |
| v63 | 63 | CN=Godot… | `cbe24716d01a16be267288652ab735fcfd6e601691059364d2dc12ef95c0b010` |
| v65 | 65 | CN=Godot… | `54af8dbb4ccb95e47b6c0cf03413e1a955fd7028aeca10c307fe78ce1780d674` |
| v66 | 66 | CN=Godot… | `e75bb15e5cbaede1861fe731dc6cc23fbc5c69645d293a4fd8169da0691a6071` |
| v67 | 67 | CN=Godot… | `9ce7978b7faf45ede79cce16703877bbce0bc78aa5e365aa58512719808c7c7f` |
| v68 | 68 | CN=Godot… | `ed2b4d0925cd0ce4788dc338c875e0502d4cfae54dba78b37a905bd32c47f67e` |
| v70 | 70 | CN=Android Debug… | `83984bf95413a68088b5f752aac2ace9c3682554ce90164b8f376e88ca83ad7c` |
| v71 | 71 | CN=Godot… | `d222fd61c4a4a20bfbaa36d8f463e0811f3742891861d15adc8f75098fa7ad7a` |

**Finding:** package ID never changed; **signing certificate changed on essentially every release** because exports relied on ephemeral Godot/Android debug keystores that differ across Cursor environments. Android rejects updates when the cert does not match the installed app → **"App not installed"** (even with Auto Blocker off).

versionCode was monotonically increasing on published releases (not the primary failure mode for those tags).

## Dual / confusing APK filenames

GitHub Release tags inspected each had **one** asset. Confusion came from local/pipeline sources:

- Many differently named APKs under `build/` (including byte-identical copies under two names)
- Export wrapper also copying into `/opt/cursor/artifacts/`
- Historical force-tracked `build/*.apk` exceptions in `.gitignore`
- Optional direct `godot --export-debug` bypassing the wrapper and using alternate names

## Fix (v72+)

1. Tracked project test keystore: `android/signing/chest_test_debug.keystore`
2. Expected cert pin: `android/signing/EXPECTED_TEST_CERT_SHA256`
3. Package pin: `android/signing/EXPECTED_PACKAGE_ID`
4. versionCode floor: `android/signing/LAST_RELEASED_VERSION_CODE` (must build strictly greater)
5. Mandatory wrapper: `tools/export_android_apk.sh` → one canonical filename
6. Gate: `tools/verify_apk_update_compatibility.py`

## Built canonical APK (this change)

| Field | Value |
| --- | --- |
| Filename | `ChestOfLoveNotes-v72-apk-signing-pipeline-fix-debug.apk` |
| Path | `side_projects/ChestOfLoveNotes/build/ChestOfLoveNotes-v72-apk-signing-pipeline-fix-debug.apk` |
| versionCode | `72` |
| versionName | `0.1.72-apk-signing-pipeline-fix` |
| Package ID | `com.charoitegames.chestoflovenotes` |
| Signing cert SHA-256 | `5fbad9830b2a9827d2d1f7f8a38dafea0ae772793a99c4f4952a6b1d424f863b` |
| APK SHA-256 | `a9dc1b4b6d3dd3f80206242f6a48a81eb6a6d79fa0f9c629fe0cdc5348715319` |
| Same-version APK count in `build/` | **1** |

Compared to Samsung known-good v61: package ID matches; **signing certificate differs** (v61 was an ephemeral Godot debug cert). In-place update from v61–v71 is not possible — uninstall once, then install v72.
