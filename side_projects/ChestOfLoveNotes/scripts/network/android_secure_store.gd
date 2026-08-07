extends RefCounted
class_name AndroidSecureStore
## Thin GDScript bridge to the SecureSession Android Keystore plugin.
## Never stores plaintext tokens under user://.

const PLUGIN_NAME := "SecureSession"
const SETTINGS_PATH := "user://coln_settings.cfg"


static func is_available() -> bool:
	if OS.get_name() != "Android":
		return false
	return Engine.has_singleton(PLUGIN_NAME)


static func _plugin() -> Object:
	if not is_available():
		return null
	return Engine.get_singleton(PLUGIN_NAME)


static func store_session_json(json_string: String) -> bool:
	var p := _plugin()
	if p == null or json_string.is_empty():
		return false
	return bool(p.call("secure_store_session", json_string))


static func load_session_json() -> String:
	var p := _plugin()
	if p == null:
		return ""
	return str(p.call("secure_load_session"))


static func delete_session() -> bool:
	var p := _plugin()
	if p == null:
		return true
	return bool(p.call("secure_delete_session"))


static func has_session() -> bool:
	var p := _plugin()
	if p == null:
		return false
	return bool(p.call("secure_has_session"))


static func export_keystore_key() -> String:
	## Must always be empty — Keystore key is non-exportable to GDScript.
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
