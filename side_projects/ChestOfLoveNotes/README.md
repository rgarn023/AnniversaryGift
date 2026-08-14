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

**Always use the export wrapper.** Do not call `godot --export-debug` directly for private-online APKs.

`config/backend_config.json` is gitignored. Raw Godot export skips staging and produces APKs that show **Backend is not configured** on device (this is what broke v70).

```bash
cd side_projects/ChestOfLoveNotes
# Requires SUPABASE_URL + SUPABASE_ANON_KEY in the environment.
bash tools/export_android_apk.sh ChestOfLoveNotes-v71-android-backend-config-fix-debug.apk
```

The wrapper:

1. Writes gitignored `config/backend_config.json` from env (URL + publishable/anon key only)
2. Hard-fails if that config is missing or still a placeholder
3. Exports the Android debug APK
4. Hard-fails if the APK does not pack a live `assets/config/backend_config.json`
5. Validates the packed bytes against the same runtime load rules as `BackendConfig`

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
