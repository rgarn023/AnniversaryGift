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
		var err := str(result.get("error", ""))
		if not err.is_empty():
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
	var url := str(data.get("supabase_url", "")).strip_edges()
	var key := str(data.get("supabase_publishable_key", "")).strip_edges()
	var env := str(data.get("environment", "development")).strip_edges()
	if url.is_empty() or url.contains("YOUR_SUPABASE"):
		return {"ok": false, "error": "Supabase URL is not configured."}
	if key.is_empty() or key.contains("YOUR_SUPABASE"):
		return {"ok": false, "error": "Supabase publishable key is not configured."}
	supabase_url = url
	supabase_publishable_key = key
	environment = env if not env.is_empty() else "development"
	loaded = true
	load_error = ""
	return {"ok": true, "error": ""}


func is_configured() -> bool:
	return loaded and not supabase_url.is_empty() and not supabase_publishable_key.is_empty()
