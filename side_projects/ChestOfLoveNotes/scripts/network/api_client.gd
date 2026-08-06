extends RefCounted
class_name ApiClient
## Central HTTP helper for Supabase REST / Edge Functions.
## Always sends apikey = publishable key.
## Authenticated calls send Authorization = Bearer <user access token>.
## Never uses the publishable key as a user Bearer token.

signal request_finished(ok: bool, status: int, data: Variant, error: String)

var config: BackendConfig
var tokens: SecureTokenService
var timeout_sec: float = 25.0
var last_function_name: String = ""
var last_http_status: int = 0
var last_safe_error: String = ""


func _init(p_config: BackendConfig = null, p_tokens: SecureTokenService = null) -> void:
	config = p_config if p_config != null else BackendConfig.new()
	tokens = p_tokens if p_tokens != null else SecureTokenService.new()


func call_edge_function(function_name: String, body: Dictionary = {}, method: String = "POST") -> Dictionary:
	if config == null or not config.is_configured():
		return _fail("Backend is not configured.", 0)
	last_function_name = function_name
	if not await _ensure_user_bearer_ready():
		return _fail("Not signed in.", 401)
	var url := "%s/functions/v1/%s" % [config.supabase_url.rstrip("/"), function_name]
	return await request(url, method, body, true)


func rest_get(path: String, query: String = "") -> Dictionary:
	if config == null or not config.is_configured():
		return _fail("Backend is not configured.", 0)
	last_function_name = "rest:" + path
	if not await _ensure_user_bearer_ready():
		return _fail("Not signed in.", 401)
	var url := "%s/rest/v1/%s" % [config.supabase_url.rstrip("/"), path.lstrip("/")]
	if not query.is_empty():
		url += "?" + query
	return await request(url, "GET", {}, true)


func rest_post(path: String, body: Dictionary, prefer: String = "return=representation") -> Dictionary:
	if config == null or not config.is_configured():
		return _fail("Backend is not configured.", 0)
	last_function_name = "rest:" + path
	if not await _ensure_user_bearer_ready():
		return _fail("Not signed in.", 401)
	var url := "%s/rest/v1/%s" % [config.supabase_url.rstrip("/"), path.lstrip("/")]
	return await request(url, "POST", body, true, prefer)


func rest_rpc(fn_name: String, args: Dictionary = {}) -> Dictionary:
	if config == null or not config.is_configured():
		return _fail("Backend is not configured.", 0)
	last_function_name = "rpc:" + fn_name
	if not await _ensure_user_bearer_ready():
		return _fail("Not signed in.", 401)
	var url := "%s/rest/v1/rpc/%s" % [config.supabase_url.rstrip("/"), fn_name]
	return await request(url, "POST", args, true)


func _ensure_user_bearer_ready() -> bool:
	if tokens == null or not tokens.has_session():
		return false
	if tokens.is_expired() and not tokens.refresh_token.is_empty():
		var url := "%s/auth/v1/token?grant_type=refresh_token" % config.supabase_url.rstrip("/")
		var result: Dictionary = await request(
			url,
			"POST",
			{"refresh_token": tokens.refresh_token},
			false
		)
		if not bool(result.get("ok", false)):
			return false
		var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
		var access := str(data.get("access_token", ""))
		if access.is_empty():
			return false
		# Never treat the publishable key as a user access token.
		if access == config.supabase_publishable_key:
			return false
		tokens.set_session(
			access,
			str(data.get("refresh_token", tokens.refresh_token)),
			int(Time.get_unix_time_from_system()) + int(data.get("expires_in", 3600))
		)
	return tokens.has_session() and tokens.access_token != config.supabase_publishable_key


func request(
	url: String,
	method: String,
	body: Dictionary,
	authed: bool,
	prefer: String = ""
) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	var host: Node = Engine.get_main_loop().root
	host.add_child(http)
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"apikey: %s" % config.supabase_publishable_key,
	]
	if not prefer.is_empty():
		headers.append("Prefer: %s" % prefer)
	if authed:
		var auth := tokens.authorization_header()
		if auth.is_empty():
			http.queue_free()
			return _fail("Not signed in.", 401)
		# Must be the signed-in user JWT — never the publishable key.
		headers.append("Authorization: %s" % auth)
	else:
		# Unauthenticated Auth endpoints still need apikey; optional anon bearer for GoTrue.
		headers.append("Authorization: Bearer %s" % config.supabase_publishable_key)
	var payload := "" if method.to_upper() == "GET" else JSON.stringify(body)
	var err := http.request(url, headers, _http_method(method), payload)
	if err != OK:
		http.queue_free()
		return _fail("Network request failed to start.", 0)
	var result: Array = await http.request_completed
	http.queue_free()
	var status: int = int(result[1])
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8()
	var data: Variant = {}
	if not text.is_empty():
		var parsed: Variant = JSON.parse_string(text)
		if parsed != null:
			data = parsed
		else:
			data = {"raw": text}
	var ok := status >= 200 and status < 300
	var error := ""
	if not ok:
		error = _safe_error(data, status)
	last_http_status = status
	last_safe_error = error
	# Never log tokens, passwords, or message bodies.
	return {"ok": ok, "status": status, "data": data, "error": error}


func _fail(message: String, status: int) -> Dictionary:
	last_http_status = status
	last_safe_error = message
	return {"ok": false, "status": status, "data": {}, "error": message}


func _http_method(method: String) -> int:
	match method.to_upper():
		"GET":
			return HTTPClient.METHOD_GET
		"PUT":
			return HTTPClient.METHOD_PUT
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"DELETE":
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_POST


func _safe_error(data: Variant, status: int) -> String:
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		if d.has("error"):
			var err_v: Variant = d["error"]
			if typeof(err_v) == TYPE_STRING:
				return str(err_v)
			if typeof(err_v) == TYPE_DICTIONARY:
				var err_d: Dictionary = err_v
				if err_d.has("message"):
					return str(err_d["message"])
				if err_d.has("code"):
					return str(err_d["code"])
		if d.has("msg") and typeof(d["msg"]) == TYPE_STRING:
			return str(d["msg"])
		if d.has("message") and typeof(d["message"]) == TYPE_STRING:
			return str(d["message"])
		if d.has("error_description") and typeof(d["error_description"]) == TYPE_STRING:
			return str(d["error_description"])
	return "Request failed (%d)." % status
