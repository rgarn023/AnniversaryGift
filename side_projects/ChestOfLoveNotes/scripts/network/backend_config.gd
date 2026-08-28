extends RefCounted
class_name BackendConfig
## Loads Supabase URL + publishable key. Never holds service-role secrets.

const EXAMPLE_PATH := "res://config/backend_config.example.json"
const USER_PATH := "user://backend_config.json"
const RES_PATH := "res://config/backend_config.json"

var supabase_url: String = ""
var supabase_publishable_key: String = ""
var environment: String = "development"
var loaded: bool = false
var load_error: String = ""


func load_config() -> bool:
	loaded = false
	load_error = ""
	supabase_url = ""
	supabase_publishable_key = ""
	## Prefer packed project config, then writable user override.
	## Try open() even when file_exists() is false — some Android exports
	## report exists inconsistently for non-imported JSON in the PCK.
	var candidates: PackedStringArray = PackedStringArray([RES_PATH, USER_PATH])
	var last_read_error := "No backend_config.json found. Copy config/backend_config.example.json."
	for path in candidates:
		var result := _load_from_path(str(path))
		if bool(result.get("ok", false)):
			return true
		var err_v: Variant = result.get("error", "")
		var err := "" if err_v == null else str(err_v).strip_edges()
		if not err.is_empty() and err != "<null>":
			last_read_error = err
	load_error = last_read_error
	return false


func _load_from_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		## Keep searching other candidates when the file is simply absent.
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": ""}
		return {"ok": false, "error": "Could not read backend config at %s." % path}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Backend config JSON is invalid."}
	var data: Dictionary = parsed
	var url_v: Variant = data.get("supabase_url", null)
	var key_v: Variant = data.get("supabase_publishable_key", null)
	var env_v: Variant = data.get("environment", "development")
	if url_v == null or key_v == null:
		return {"ok": false, "error": "Backend config is missing its Supabase URL or publishable key."}
	var url := str(url_v).strip_edges()
	var key := str(key_v).strip_edges()
	var env := "development" if env_v == null else str(env_v).strip_edges()
	if url.is_empty() or url == "<null>" or url.contains("YOUR_SUPABASE"):
		return {"ok": false, "error": "Supabase URL is not configured."}
	if key.is_empty() or key == "<null>" or key.contains("YOUR_SUPABASE"):
		return {"ok": false, "error": "Supabase publishable key is not configured."}
	if not url.begins_with("https://") or not url.contains(".supabase.co"):
		return {"ok": false, "error": "Supabase URL is invalid."}
	supabase_url = url.rstrip("/")
	supabase_publishable_key = key
	environment = env if not env.is_empty() else "development"
	loaded = true
	load_error = ""
	return {"ok": true, "error": ""}


func is_configured() -> bool:
	return (
		loaded
		and not supabase_url.is_empty()
		and supabase_url != "<null>"
		and not supabase_publishable_key.is_empty()
		and supabase_publishable_key != "<null>"
	)
