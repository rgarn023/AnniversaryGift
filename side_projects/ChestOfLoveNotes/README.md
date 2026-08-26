# Chest of Love Notes

An online (and offline-demo) Godot 4.7.1 mobile app where friends send animated parchment scrolls that unlock at a chosen date and time.

**Package:** `com.charoitegames.chestoflovenotes`  
**Project path:** `side_projects/ChestOfLoveNotes/`  
**Engine:** Godot 4.7.1 (GDScript)

This is a **completely separate** side project from Anniversary Gift. It copies only reusable chest/scroll/background/font/shader art. It does **not** include Anniversary Gift messages, dates, PDF gift files, or that app’s package identity.

## MVP features

- Local Demo Mode (debug) with fictional accounts and multi-scroll chest states
- Email auth / profiles / friends / scrolls architecture for Supabase
- Compose scroll with unlock time + optional magic password
- Chest inventory with locked / unread / opened / friend-request states
- Secure open-scroll design (server time, no client `scroll_contents` access)
- Realistic chest + parchment presentation adapted from Anniversary Gift
- Android debug APK export

## How it differs from Anniversary Gift

| Anniversary Gift | Chest of Love Notes |
|---|---|
| Offline private anniversary experience | Online friend-to-friend messaging |
| Fixed 8 dates + final PDF gift | Many scrolls, scheduled unlocks |
| No accounts | Email auth + usernames + friend codes |
| Package `…anniversarygift` | Package `…chestoflovenotes` |

## Local Demo Mode

If `config/backend_config.json` is missing (debug builds only):

1. Launch the app
2. Tap **Enter Local Demo**
3. Use the chest, inventory filters, compose, friends, and magic password `starlight`
4. Use **+15 min** to advance the demo clock

Release builds never silently enter demo mode; they show a backend-configuration error instead.

## Run in Godot

```bash
godot --path side_projects/ChestOfLoveNotes
```

Headless demo tests:

```bash
godot --headless --path side_projects/ChestOfLoveNotes -s res://tests/test_demo_logic.gd
```

## Build Android APK

**Always use the export wrapper.** Do not call `godot --export-debug` directly.

Raw Godot export is unsupported because it can:

- skip gitignored `config/backend_config.json` staging (**Backend is not configured** — v70)
- sign with a machine-local debug keystore (certificate churn → **App not installed** on update)
- emit differently named duplicate APKs

```bash
cd side_projects/ChestOfLoveNotes
# Requires SUPABASE_URL + SUPABASE_ANON_KEY in the environment.
bash tools/export_android_apk.sh
```

The wrapper:

1. Signs with the **project-stable** test keystore (`android/signing/chest_test_debug.keystore`)
2. Writes gitignored `config/backend_config.json` from env (URL + publishable/anon key only)
3. Hard-fails if that config is missing or still a placeholder
4. Exports one temporary APK, validates it, then publishes **exactly one** canonical filename:
   `build/ChestOfLoveNotes-vXX-<version-slug>-debug.apk`
5. Hard-fails on package ID / versionCode / signing-cert mismatches
6. Removes temporary duplicates for the current version

See [docs/APK_UPDATE_COMPATIBILITY.md](docs/APK_UPDATE_COMPATIBILITY.md) and [android/signing/README.md](android/signing/README.md).

**Samsung / existing installs:** APKs before the stable keystore used one-off certs. Uninstall once, then install the new APK; later updates can replace in place.

Manual prepare/verify (debugging only; still finish with the wrapper):

```bash
python3 tools/prepare_backend_config.py
python3 tools/verify_backend_config_for_export.py
```

## Supabase

See [SETUP_SUPABASE.md](SETUP_SUPABASE.md).

Client config example: `config/backend_config.example.json`  
Copy to `config/backend_config.json` (gitignored) with your project URL + publishable key only, or run `python3 tools/prepare_backend_config.py`.

**Never** put the service-role key or `MESSAGE_ENCRYPTION_KEY` in the Godot project.

## Security limitations (v0.1)

- Demo mode stores fictional message bodies in memory on-device for UI testing only
- Online sessions persist via Android Keystore-backed `ChestSecureStorage` (AES-256-GCM; no plaintext tokens under `user://`)
- Server-side AES-GCM encryption is **not** end-to-end encryption
- Push notifications are not included yet (architecture allows adding later)

## Future

- Android Keystore-backed refresh tokens
- Push notifications for new scrolls / unlocks
- Optional end-to-end encryption upgrade path
