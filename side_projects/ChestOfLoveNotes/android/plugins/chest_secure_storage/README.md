# ChestSecureStorage Android plugin

Godot 4.7.1 v2 Android plugin that encrypts Supabase session JSON with an
**Android Keystore** AES-256-GCM key (non-exportable).

## Identity

| Item | Value |
|------|--------|
| Singleton name | `ChestSecureStorage` |
| Class | `ChestSecureStoragePlugin` |
| Package | `com.charoitegames.chestoflovenotes.securestorage` |
| Key alias | `ChestOfLoveNotesSessionKey` |
| Prefs file | `coln_chest_secure_session_prefs` |

## Methods (GDScript)

| Method | Purpose |
|--------|---------|
| `secure_storage_available()` | Keystore usable |
| `secure_storage_version()` | Storage format version |
| `secure_store_session(json_string)` | Encrypt + persist session |
| `secure_load_session()` | Decrypt session JSON (or `""`) |
| `secure_delete_session()` | Remove ciphertext/IV |
| `secure_has_session()` | Whether ciphertext exists |
| `secure_export_keystore_key()` | Always `""` (key never exported) |

## Install into Godot Gradle template

```bash
bash android/plugins/chest_secure_storage/install_into_android_build.sh
```

This copies the Kotlin source, backup XML rules, and registers the plugin
meta-data in `android/build/src/main/AndroidManifest.xml`.

Re-run after reinstalling the Android export template.

## Security notes

- Never stores access/refresh tokens in plaintext under `user://`.
- Never exposes Keystore key bytes to GDScript.
- Account passwords and Magic Passwords are never persisted here.
- Session SharedPreferences are excluded from Auto Backup / device transfer.
