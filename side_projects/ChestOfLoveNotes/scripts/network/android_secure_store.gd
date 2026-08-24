extends RefCounted
class_name AndroidSecureStore
## Thin GDScript bridge to the ChestSecureStorage Android Keystore plugin.
## Never stores plaintext tokens or OAuth verifiers under user://.
## Headless tests may enable an in-memory fake backend (still never writes secrets to disk).

const PLUGIN_NAME := "ChestSecureStorage"
const SETTINGS_PATH := "user://coln_settings.cfg"
const STORAGE_VERSION := 1

## Test-only in-memory backend (never used for real persistence paths).
static var _test_backend_enabled: bool = false
static var _test_ciphertext: String = ""
static var _test_iv: String = ""
static var _test_oauth_ciphertext: String = ""
static var _test_oauth_iv: String = ""
static var _test_version: int = STORAGE_VERSION
static var _test_force_unavailable: bool = false
static var _test_force_decrypt_fail: bool = false


static func enable_test_backend() -> void:
	_test_backend_enabled = true
	_test_force_unavailable = false
	_test_force_decrypt_fail = false
	_clear_test_backend()


static func disable_test_backend() -> void:
	_test_backend_enabled = false
	_test_force_unavailable = false
	_test_force_decrypt_fail = false
	_clear_test_backend()


static func _clear_test_backend() -> void:
	_clear_test_session_backend()
	_clear_test_oauth_backend()
	_test_version = STORAGE_VERSION


static func _clear_test_session_backend() -> void:
	_test_ciphertext = ""
	_test_iv = ""


static func _clear_test_oauth_backend() -> void:
	_test_oauth_ciphertext = ""
	_test_oauth_iv = ""


static func is_available() -> bool:
	if _test_force_unavailable:
		return false
	if _test_backend_enabled:
		return true
	if OS.get_name() != "Android":
		return false
	if not Engine.has_singleton(PLUGIN_NAME):
		return false
	var p := Engine.get_singleton(PLUGIN_NAME)
	if p == null:
		return false
	if p.has_method("secure_storage_available"):
		return bool(p.call("secure_storage_available"))
	return true


static func log_secure(tag: String) -> void:
	## Internal Android diagnosis only — never prints tokens/passwords/JSON.
	if not OS.is_debug_build():
		return
	if OS.get_name() != "Android" and not _test_backend_enabled:
		return
	var plugin := Engine.has_singleton(PLUGIN_NAME) if OS.get_name() == "Android" else _test_backend_enabled
	print(
		"[COLN-SECURE:%s] plugin=%s available=%s has_session=%s"
		% [
			tag,
			"YES" if plugin else "NO",
			"YES" if is_available() else "NO",
			"YES" if has_session() else "NO",
		]
	)


static func await_ready(tree: SceneTree, timeout_sec: float = 5.0) -> bool:
	## Cold-start Android plugins can lag singleton registration by many frames.
	if _test_backend_enabled:
		return not _test_force_unavailable
	if OS.get_name() != "Android":
		return is_available()
	if tree == null:
		return is_available()
	log_secure("await_ready_begin")
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if is_available():
			log_secure("await_ready_ok")
			return true
		await tree.process_frame
	var ready := is_available()
	log_secure("await_ready_timeout" if not ready else "await_ready_late_ok")
	return ready


static func storage_version() -> int:
	if _test_backend_enabled:
		return STORAGE_VERSION
	var p := _plugin()
	if p == null:
		return 0
	if p.has_method("secure_storage_version"):
		return int(p.call("secure_storage_version"))
	return STORAGE_VERSION


static func _plugin() -> Object:
	if _test_backend_enabled or OS.get_name() != "Android":
		return null
	if not Engine.has_singleton(PLUGIN_NAME):
		return null
	return Engine.get_singleton(PLUGIN_NAME)


static func store_session_json(json_string: String) -> bool:
	if json_string.is_empty():
		return false
	if _test_backend_enabled:
		if _test_force_unavailable:
			return false
		# Simulate encrypted persistence: store only opaque base64 blobs in memory.
		_test_ciphertext = Marshalls.utf8_to_base64(json_string)
		_test_iv = Marshalls.utf8_to_base64("test-iv-12b")
		_test_version = STORAGE_VERSION
		return true
	var p := _plugin()
	if p == null:
		return false
	return bool(p.call("secure_store_session", json_string))


static func load_session_json() -> String:
	if _test_backend_enabled:
		if _test_force_decrypt_fail or _test_ciphertext.is_empty() or _test_iv.is_empty():
			_clear_test_session_backend()
			return ""
		# Invalid base64 / corrupt blob → empty (same as Keystore decrypt failure).
		var raw := Marshalls.base64_to_utf8(_test_ciphertext)
		if str(raw).is_empty():
			_clear_test_session_backend()
			return ""
		return str(raw)
	var p := _plugin()
	if p == null:
		return ""
	return str(p.call("secure_load_session"))


static func delete_session() -> bool:
	if _test_backend_enabled:
		_clear_test_session_backend()
		return true
	var p := _plugin()
	if p == null:
		return true
	return bool(p.call("secure_delete_session"))


static func has_session() -> bool:
	if _test_backend_enabled:
		return not _test_ciphertext.is_empty() and not _test_iv.is_empty()
	var p := _plugin()
	if p == null:
		return false
	return bool(p.call("secure_has_session"))


static func store_oauth_state_json(json_string: String) -> bool:
	## Short-lived PKCE transaction state. Kept separate from the signed-in session
	## so process death during browser OAuth does not destroy the verifier.
	if json_string.is_empty():
		return false
	if _test_backend_enabled:
		if _test_force_unavailable:
			return false
		_test_oauth_ciphertext = Marshalls.utf8_to_base64(json_string)
		_test_oauth_iv = Marshalls.utf8_to_base64("oauth-iv-12b")
		return true
	var p := _plugin()
	if p == null:
		return false
	## Do not gate Android plugin methods with Object.has_method(). Godot's Android
	## singleton proxy may expose @UsedByGodot calls without reporting them through
	## has_method(), which previously caused a false "secure storage unavailable" error.
	return bool(p.call("secure_store_oauth_state", json_string))


static func load_oauth_state_json() -> String:
	if _test_backend_enabled:
		if _test_force_decrypt_fail or _test_oauth_ciphertext.is_empty() or _test_oauth_iv.is_empty():
			_clear_test_oauth_backend()
			return ""
		var raw := Marshalls.base64_to_utf8(_test_oauth_ciphertext)
		if str(raw).is_empty():
			_clear_test_oauth_backend()
			return ""
		return str(raw)
	var p := _plugin()
	if p == null:
		return ""
	return str(p.call("secure_load_oauth_state"))


static func delete_oauth_state() -> bool:
	if _test_backend_enabled:
		_clear_test_oauth_backend()
		return true
	var p := _plugin()
	if p == null:
		return true
	return bool(p.call("secure_delete_oauth_state"))


static func has_oauth_state() -> bool:
	if _test_backend_enabled:
		return not _test_oauth_ciphertext.is_empty() and not _test_oauth_iv.is_empty()
	var p := _plugin()
	if p == null:
		return false
	return bool(p.call("secure_has_oauth_state"))


static func export_keystore_key() -> String:
	## Must always be empty — Keystore key is non-exportable to GDScript.
	if _test_backend_enabled:
		return ""
	var p := _plugin()
	if p == null:
		return ""
	return str(p.call("secure_export_keystore_key"))


static func get_keep_me_signed_in() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return true # default ON for this private app
	return bool(cfg.get_value("session", "keep_me_signed_in", true))


static func set_keep_me_signed_in(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("session", "keep_me_signed_in", enabled)
	cfg.save(SETTINGS_PATH)
	if not enabled:
		delete_session()


static func settings_contains_token_fields() -> bool:
	## Safety helper for tests/scans — settings file must not hold tokens.
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	return text.contains("access_token") or text.contains("refresh_token")
