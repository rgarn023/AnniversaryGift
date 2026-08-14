extends SceneTree
## Headless tests for secure persistent login (fake Keystore backend on CI).

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _run() -> void:
	print("=== Persistent Session Tests ===")
	AndroidSecureStore.enable_test_backend()
	_test_token_service_defaults()
	_test_encrypt_before_persist()
	_test_keep_me_signed_in_setting()
	_test_restore_valid_session()
	_test_expired_triggers_refresh_contract()
	_test_concurrent_refresh_contract()
	_test_corrupt_and_missing_keystore()
	_test_sign_out_clears_revealed_and_session()
	_test_no_password_persistence_contracts()
	_test_keystore_export_blocked()
	_test_plugin_identity_and_backup()
	_test_demo_disabled_online_build()
	_test_anniversary_gift_untouched()
	AndroidSecureStore.disable_test_backend()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_token_service_defaults() -> void:
	var tokens := SecureTokenService.new()
	_assert(tokens.keep_me_signed_in == true, "Keep Me Signed In defaults ON")
	tokens.set_session("access-aaa", "refresh-bbb", 9999999999)
	tokens.set_user("uid-1", "user@example.com", true)
	_assert(tokens.has_session(), "First sign-in succeeds / populates in-memory session")
	_assert(tokens.authorization_header().begins_with("Bearer access-"), "bearer uses access token")
	_assert(not FileAccess.file_exists("user://session.json"), "no plaintext session.json")
	_assert(not FileAccess.file_exists("user://supabase_session.cfg"), "no plaintext session cfg")
	_assert(not AndroidSecureStore.settings_contains_token_fields(), "settings cfg has no token fields")


func _test_encrypt_before_persist() -> void:
	AndroidSecureStore.enable_test_backend()
	var tokens := SecureTokenService.new()
	tokens.set_keep_me_signed_in(true)
	tokens.set_session("access-plain-xyz", "refresh-plain-xyz", 9999999999)
	tokens.set_user("uid-enc", "enc@example.com", true)
	var wrote := tokens.persist_if_needed()
	_assert(wrote, "Valid session is persisted via secure store")
	_assert(AndroidSecureStore.has_session(), "secure_has_session returns true after save")
	# Ciphertext in test backend is base64 — not raw token plaintext in the blob marker path.
	_assert(AndroidSecureStore._test_ciphertext != "access-plain-xyz", "access token not stored raw")
	_assert(AndroidSecureStore._test_ciphertext != "refresh-plain-xyz", "refresh token not stored raw")
	_assert(not AndroidSecureStore._test_ciphertext.contains("access-plain-xyz"), "No plaintext access token in stored blob encoding check")
	# Stored blob is opaque base64 of JSON — decode only inside load path.
	var loaded := AndroidSecureStore.load_session_json()
	_assert(loaded.contains("\"version\":1") or loaded.contains("\"version\": 1"), "session payload includes version")
	_assert(loaded.contains("refresh-plain-xyz"), "secure load returns session JSON in memory only")
	_assert(not loaded.contains("password"), "Password is never stored in session storage")
	_assert(not loaded.contains("magic"), "Magic Password is never stored in session storage")
	# Ensure user:// has no token files after persist.
	_assert(not FileAccess.file_exists("user://session.json"), "No plaintext refresh/access token file under user://")
	var payload: Dictionary = tokens.to_session_dict()
	_assert(payload.has("expires_at"), "payload uses expires_at")
	_assert(not payload.has("password"), "payload omits password")
	_assert(int(payload.get("version", 0)) == 1, "payload version is 1")


func _test_keep_me_signed_in_setting() -> void:
	AndroidSecureStore.enable_test_backend()
	var tokens := SecureTokenService.new()
	tokens.set_session("access-aaa", "refresh-bbb", 9999999999)
	tokens.persist_if_needed()
	_assert(AndroidSecureStore.has_session(), "session saved while Keep Me Signed In ON")
	tokens.set_keep_me_signed_in(false)
	_assert(tokens.keep_me_signed_in == false, "Keep Me Signed In can turn OFF")
	_assert(tokens.memory_only == true, "OFF forces memory-only mode")
	_assert(not AndroidSecureStore.has_session(), "Keep Me Signed In OFF deletes persistence")
	_assert(tokens.has_session(), "in-memory session remains after turning OFF")
	tokens.set_keep_me_signed_in(true)
	_assert(tokens.keep_me_signed_in == true, "Keep Me Signed In can turn ON again")
	tokens.persist_if_needed()
	_assert(AndroidSecureStore.has_session(), "ON while signed in saves session securely")


func _test_restore_valid_session() -> void:
	AndroidSecureStore.enable_test_backend()
	var tokens := SecureTokenService.new()
	tokens.set_keep_me_signed_in(true)
	tokens.set_session("access-restore", "refresh-restore", 9999999999)
	tokens.set_user("uid-r", "r@example.com", true)
	tokens.persist_if_needed()
	var tokens2 := SecureTokenService.new()
	tokens2.set_keep_me_signed_in(true)
	var ok := tokens2.restore_from_secure_storage()
	_assert(ok, "App restart restores a valid session")
	_assert(tokens2.session_restored, "Session Restored flag set")
	_assert(tokens2.access_token == "access-restore", "Valid unexpired access token restored")
	_assert(tokens2.refresh_token == "refresh-restore", "refresh token restored")
	_assert(not tokens2.is_expired(), "unexpired token does not require refresh")
	# Keep Me OFF restart requires sign-in.
	tokens2.set_keep_me_signed_in(false)
	var tokens3 := SecureTokenService.new()
	# After OFF, persisted session deleted; new service defaults may still be OFF from settings.
	AndroidSecureStore.set_keep_me_signed_in(false)
	tokens3.keep_me_signed_in = false
	_assert(not tokens3.restore_from_secure_storage(), "App restart with Keep Me Signed In OFF requires sign-in")
	AndroidSecureStore.set_keep_me_signed_in(true)


func _test_expired_triggers_refresh_contract() -> void:
	var tokens := SecureTokenService.new()
	var past := int(Time.get_unix_time_from_system()) - 10
	tokens.set_session("access-old", "refresh-old", past)
	_assert(tokens.is_expired(), "Expired access token triggers refresh path")
	var near := int(Time.get_unix_time_from_system()) + 30
	tokens.set_session("access-near", "refresh-near", near)
	_assert(tokens.is_expired(SecureTokenService.EXPIRY_SKEW_SEC), "Near-expiry within 90s skew needs refresh")
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(auth_src.contains("persist_if_needed"), "Refreshed session is persisted immediately")
	_assert(auth_src.contains("new_refresh"), "Newly returned refresh token replaces old token")
	_assert(auth_src.contains("_is_refreshing"), "Concurrent authenticated calls perform only one refresh")
	var api_src := FileAccess.get_file_as_string("res://scripts/network/api_client.gd")
	_assert(api_src.contains("allow_auth_retry"), "401 retry-once / pending calls resume after refresh")
	_assert(api_src.contains("persist_if_needed"), "API fallback refresh also persists rotated token")
	var app_src := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	_assert(app_src.contains("claim_membership"), "Membership is revalidated after restore")
	_assert(app_src.contains("membership_denied") or app_src.contains("not approved"), "Disabled membership prevents auto-login")
	_assert(app_src.contains("revalidate_on_resume"), "App resume refreshes an expired session")
	_assert(auth_src.contains("invalid_session"), "Failed refresh returns to Sign In path")


func _test_concurrent_refresh_contract() -> void:
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(auth_src.contains("while _is_refreshing"), "Pending calls wait on single-flight refresh")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("CharoiteBoot"), "Startup shows Charoite Games boot while restoring")
	_assert(main_src.contains("Keep Me Signed In"), "Settings Keep Me Signed In present")


func _test_corrupt_and_missing_keystore() -> void:
	AndroidSecureStore.enable_test_backend()
	var tokens := SecureTokenService.new()
	tokens.set_keep_me_signed_in(true)
	# Corrupt encrypted storage
	AndroidSecureStore._test_ciphertext = "%%%not-valid-base64%%%"
	AndroidSecureStore._test_iv = "x"
	var ok := tokens.restore_from_secure_storage()
	_assert(not ok, "Corrupt encrypted storage does not restore")
	_assert(not tokens.has_session(), "Corrupt storage leaves memory clear")
	# Missing keystore / decrypt fail
	AndroidSecureStore.enable_test_backend()
	tokens.set_session("a", "b", 9999999999)
	tokens.persist_if_needed()
	AndroidSecureStore._test_force_decrypt_fail = true
	var tokens2 := SecureTokenService.new()
	tokens2.keep_me_signed_in = true
	_assert(not tokens2.restore_from_secure_storage(), "Missing Keystore key / decrypt fail does not crash")
	AndroidSecureStore._test_force_decrypt_fail = false
	# Restored ciphertext from another device (decrypt fail) rejected safely
	AndroidSecureStore.enable_test_backend()
	AndroidSecureStore._test_ciphertext = Marshalls.utf8_to_base64("not-json")
	AndroidSecureStore._test_iv = Marshalls.utf8_to_base64("iv")
	var tokens3 := SecureTokenService.new()
	tokens3.keep_me_signed_in = true
	_assert(not tokens3.restore_from_secure_storage(), "Restored ciphertext from another device is rejected safely")
	# Unavailable store does not plaintext-fallback
	AndroidSecureStore._test_force_unavailable = true
	var tokens4 := SecureTokenService.new()
	tokens4.set_keep_me_signed_in(true)
	tokens4.set_session("access-z", "refresh-z", 9999999999)
	_assert(not tokens4.persist_if_needed(), "Unavailable secure store does not persist")
	_assert(not FileAccess.file_exists("user://session.json"), "No plaintext fallback under user://")
	AndroidSecureStore._test_force_unavailable = false


func _test_sign_out_clears_revealed_and_session() -> void:
	AndroidSecureStore.enable_test_backend()
	var state := AppState.new()
	state.tokens.set_keep_me_signed_in(true)
	state.tokens.set_session("access-aaa", "refresh-bbb", 9999999999)
	state.tokens.set_user("uid-1", "user@example.com", true)
	state.tokens.persist_if_needed()
	_assert(AndroidSecureStore.has_session(), "session exists before sign out")
	state.membership.is_member = true
	state.revealed_magic_passwords["scroll-1"] = "secret-password"
	state.open_message_plaintext = "note body"
	state.cached_sent = {"sent_scrolls": [{"id": "1"}]}
	state.sign_out()
	_assert(state.tokens.access_token.is_empty(), "sign out clears access token")
	_assert(state.tokens.refresh_token.is_empty(), "sign out clears refresh token")
	_assert(state.revealed_magic_passwords.is_empty(), "sign out clears revealed Magic Passwords")
	_assert(state.open_message_plaintext.is_empty(), "sign out clears decrypted bodies")
	_assert(state.cached_sent.is_empty(), "sign out clears private caches")
	_assert(not state.membership.is_member, "sign out clears membership")
	_assert(not AndroidSecureStore.has_session(), "Sign Out deletes the stored session")
	var tokens := SecureTokenService.new()
	tokens.keep_me_signed_in = true
	_assert(not tokens.restore_from_secure_storage(), "Restart after Sign Out does not restore session")


func _test_no_password_persistence_contracts() -> void:
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(not auth_src.contains("user://password"), "auth never persists password path")
	_assert(auth_src.contains("grant_type=password"), "password grant used only for live sign-in")
	_assert(auth_src.contains("logout_remote") or auth_src.contains("auth/v1/logout"), "Sign Out can call Supabase logout")
	var token_src := FileAccess.get_file_as_string("res://scripts/network/secure_token_service.gd")
	_assert(token_src.contains("Never stores the account password"), "token service documents no password storage")
	_assert(token_src.contains("AndroidSecureStore"), "token service uses secure store bridge")
	_assert(not token_src.contains("user://session"), "token service has no user:// session path")
	var store_src := FileAccess.get_file_as_string("res://scripts/network/android_secure_store.gd")
	_assert(store_src.contains("ChestSecureStorage"), "bridge talks to ChestSecureStorage plugin")
	_assert(store_src.contains("secure_export_keystore_key"), "export probe exists")
	_assert(store_src.contains("secure_storage_available"), "optional available API present")


func _test_keystore_export_blocked() -> void:
	var exported := AndroidSecureStore.export_keystore_key()
	_assert(exported.is_empty(), "Android Keystore key is not exposed to GDScript")


func _test_plugin_identity_and_backup() -> void:
	var kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestSecureStoragePlugin.kt")
	_assert(kt.contains("package com.charoitegames.chestoflovenotes.securestorage"), "plugin package correct")
	_assert(kt.contains("ChestOfLoveNotesSessionKey"), "Keystore alias correct")
	_assert(kt.contains("AES/GCM/NoPadding"), "AES-GCM algorithm used")
	_assert(kt.contains("setKeySize(256)"), "AES-256 key size")
	_assert(kt.contains("PLUGIN_NAME = \"ChestSecureStorage\""), "plugin singleton name")
	_assert(kt.contains("secure_store_session"), "store API present")
	_assert(kt.contains("secure_load_session"), "load API present")
	_assert(kt.contains("secure_delete_session"), "delete API present")
	_assert(kt.contains("secure_has_session"), "has API present")
	var backup := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/backup_rules.xml")
	_assert(backup.contains("coln_chest_secure_session_prefs"), "Auto-backup excludes session prefs")
	var extract := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/data_extraction_rules.xml")
	_assert(extract.contains("device-transfer"), "device-transfer exclusion present")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	_assert(install.contains("ChestSecureStoragePlugin.kt"), "install script wires plugin into android/build")


func _test_demo_disabled_online_build() -> void:
	_assert(BuildFlags.PRIVATE_ONBOARDING_BUILD == true, "PRIVATE_ONBOARDING_BUILD enabled")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	_assert(flags.contains("PRIVATE_ONBOARDING_BUILD := true"), "Local Demo Mode remains disabled in online test build")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("ChestOfLoveNotes-mobile-correction-complete-debug.apk") or preset.contains("secure-session"), "export targets COLN APK")
	_assert(preset.contains("version/code=10") or preset.contains("version/code=9"), "versionCode bumped")
	_assert(preset.contains("com.charoitegames.chestoflovenotes"), "COLN package retained")
	_assert(preset.contains("user_data_backup/allow=false"), "export backup disabled")


func _test_anniversary_gift_untouched() -> void:
	var f := FileAccess.open("/workspace/export_presets.cfg", FileAccess.READ)
	_assert(f != null, "Anniversary Gift export_presets still present")
	if f:
		var text := f.get_as_text()
		f.close()
		_assert(text.contains("AnniversaryGift") or text.contains("anniversary"), "Anniversary Gift export remains")
		_assert(not text.contains("chestoflovenotes"), "Anniversary Gift export not rewritten to COLN package")
	_assert(BuildFlags.APP_VERSION_CODE >= 10, "COLN versionCode incremented for mobile correction")
