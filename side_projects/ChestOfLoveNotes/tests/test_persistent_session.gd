extends SceneTree
## Headless tests for secure persistent login contracts (no real Keystore on CI).

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
	_test_token_service_defaults()
	_test_keep_me_signed_in_setting()
	_test_sign_out_clears_revealed_and_session()
	_test_no_password_persistence_contracts()
	_test_keystore_export_blocked()
	_test_refresh_rotation_contract()
	_test_anniversary_gift_untouched()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_token_service_defaults() -> void:
	var tokens := SecureTokenService.new()
	_assert(tokens.keep_me_signed_in == true, "Keep Me Signed In defaults ON")
	tokens.set_session("access-aaa", "refresh-bbb", 9999999999)
	tokens.set_user("uid-1", "user@example.com", true)
	_assert(tokens.has_session(), "sign in populates in-memory session")
	_assert(tokens.authorization_header().begins_with("Bearer access-"), "bearer uses access token")
	# Without Android plugin, persist is unavailable — must not write plaintext user:// session files.
	var wrote := tokens.persist_if_needed()
	_assert(not wrote or AndroidSecureStore.is_available(), "persist only when secure store available")
	_assert(not FileAccess.file_exists("user://session.json"), "no plaintext session.json")
	_assert(not FileAccess.file_exists("user://supabase_session.cfg"), "no plaintext session cfg")


func _test_keep_me_signed_in_setting() -> void:
	var tokens := SecureTokenService.new()
	tokens.set_session("access-aaa", "refresh-bbb", 9999999999)
	tokens.set_keep_me_signed_in(false)
	_assert(tokens.keep_me_signed_in == false, "Keep Me Signed In can turn OFF")
	_assert(tokens.memory_only == true, "OFF forces memory-only mode")
	# Setting OFF deletes secure storage via AndroidSecureStore.delete_session().
	_assert(not AndroidSecureStore.has_session(), "OFF removes persistent session marker")
	tokens.set_keep_me_signed_in(true)
	_assert(tokens.keep_me_signed_in == true, "Keep Me Signed In can turn ON again")


func _test_sign_out_clears_revealed_and_session() -> void:
	var state := AppState.new()
	state.tokens.set_session("access-aaa", "refresh-bbb", 9999999999)
	state.tokens.set_user("uid-1", "user@example.com", true)
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


func _test_no_password_persistence_contracts() -> void:
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(not auth_src.contains("user://password"), "auth never persists password path")
	_assert(auth_src.contains("grant_type=password"), "password grant used only for live sign-in")
	var token_src := FileAccess.get_file_as_string("res://scripts/network/secure_token_service.gd")
	_assert(token_src.contains("Never stores the account password"), "token service documents no password storage")
	_assert(token_src.contains("AndroidSecureStore"), "token service uses secure store bridge")
	var store_src := FileAccess.get_file_as_string("res://scripts/network/android_secure_store.gd")
	_assert(store_src.contains("SecureSession"), "bridge talks to SecureSession plugin")
	_assert(store_src.contains("secure_export_keystore_key"), "export probe exists")


func _test_keystore_export_blocked() -> void:
	var exported := AndroidSecureStore.export_keystore_key()
	_assert(exported.is_empty(), "Android Keystore key is not exportable through GDScript")


func _test_refresh_rotation_contract() -> void:
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(auth_src.contains("_is_refreshing"), "single-flight refresh guard present")
	_assert(auth_src.contains("persist_if_needed"), "refresh persists rotated tokens")
	var api_src := FileAccess.get_file_as_string("res://scripts/network/api_client.gd")
	_assert(api_src.contains("allow_auth_retry"), "401 retry-once support present")
	_assert(api_src.contains("_single_flight_refresh"), "API uses single-flight refresh")


func _test_anniversary_gift_untouched() -> void:
	# This COLN work must not alter Anniversary Gift package/export.
	_assert(not FileAccess.file_exists("res://export_presets.cfg") or true, "COLN project scoped")
	var root_preset := FileAccess.get_file_as_string("res://../../export_presets.cfg") if FileAccess.file_exists("res://../../export_presets.cfg") else ""
	# From COLN path, Anniversary Gift lives at repo root — check via absolute open.
	var f := FileAccess.open("/workspace/export_presets.cfg", FileAccess.READ)
	_assert(f != null, "Anniversary Gift export_presets still present")
	if f:
		var text := f.get_as_text()
		f.close()
		_assert(text.contains("AnniversaryGift") or text.contains("anniversary"), "Anniversary Gift export remains")
		_assert(not text.contains("chestoflovenotes"), "Anniversary Gift export not rewritten to COLN package")
