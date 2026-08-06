extends RefCounted
class_name AuthService
## Supabase email/password auth. Requires configured BackendConfig.

var api: ApiClient
var config: BackendConfig
var tokens: SecureTokenService


func _init(p_api: ApiClient, p_config: BackendConfig, p_tokens: SecureTokenService) -> void:
	api = p_api
	config = p_config
	tokens = p_tokens


func sign_up(email: String, password: String) -> Dictionary:
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	var url := "%s/auth/v1/signup" % config.supabase_url.rstrip("/")
	return await api.request(url, "POST", {"email": email, "password": password}, false)


func sign_in(email: String, password: String) -> Dictionary:
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	var url := "%s/auth/v1/token?grant_type=password" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(url, "POST", {"email": email, "password": password}, false)
	if bool(result.get("ok", false)) and typeof(result.get("data")) == TYPE_DICTIONARY:
		var data: Dictionary = result.data
		tokens.set_session(
			str(data.get("access_token", "")),
			str(data.get("refresh_token", "")),
			int(Time.get_unix_time_from_system()) + int(data.get("expires_in", 3600))
		)
	return result


func sign_out() -> void:
	tokens.clear()
