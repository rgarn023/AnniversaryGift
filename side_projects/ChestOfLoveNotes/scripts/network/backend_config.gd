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
	var path := ""
	if FileAccess.file_exists(RES_PATH):
		path = RES_PATH
	elif FileAccess.file_exists(USER_PATH):
		path = USER_PATH
	else:
		load_error = "No backend_config.json found. Copy config/backend_config.example.json."
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_error = "Could not read backend config."
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error = "Backend config JSON is invalid."
		return false
	var data: Dictionary = parsed
	supabase_url = str(data.get("supabase_url", "")).strip_edges()
	supabase_publishable_key = str(data.get("supabase_publishable_key", "")).strip_edges()
	environment = str(data.get("environment", "development"))
	if supabase_url.is_empty() or supabase_url.contains("YOUR_SUPABASE"):
		load_error = "Supabase URL is not configured."
		return false
	if supabase_publishable_key.is_empty() or supabase_publishable_key.contains("YOUR_SUPABASE"):
		load_error = "Supabase publishable key is not configured."
		return false
	loaded = true
	return true


func is_configured() -> bool:
	return loaded
