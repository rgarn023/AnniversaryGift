# SecureSession Android plugin

Godot v2 Android plugin that encrypts Supabase session JSON with an
**Android Keystore** AES-256-GCM key (non-exportable).

## Methods (GDScript singleton `SecureSession`)

| Method | Purpose |
|--------|---------|
| `secure_store_session(json_string)` | Encrypt + persist session |
| `secure_load_session()` | Decrypt session JSON (or `""`) |
| `secure_delete_session()` | Remove ciphertext/IV |
| `secure_has_session()` | Whether ciphertext exists |
| `secure_export_keystore_key()` | Always returns `""` (key never exported) |

## Source locations

- Canonical copy: `android/plugins/secure_session/SecureSessionPlugin.kt`
- Wired into Godot Gradle template: `android/build/src/main/java/com/charoitegames/chestoflovenotes/SecureSessionPlugin.kt`
- Manifest registration: `android/build/src/main/AndroidManifest.xml`

If the Android export template is reinstalled, re-copy the Kotlin file and
meta-data registration.

## Security notes

- Never stores access/refresh tokens in plaintext under `user://`.
- Never exposes Keystore key bytes to GDScript.
- Account passwords are never persisted.
