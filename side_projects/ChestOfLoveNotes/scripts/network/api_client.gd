extends RefCounted
class_name ApiClient
## Central HTTP helper for Supabase REST / Edge Functions.

signal request_finished(ok: bool, status: int, data: Variant, error: String)

var config: BackendConfig
var tokens: SecureTokenService
var timeout_sec: float = 25.0


func _init(p_config: BackendConfig = null, p_tokens: SecureTokenService = null) -> void:
	config = p_config if p_config != null else BackendConfig.new()
	tokens = p_tokens if p_tokens != null else SecureTokenService.new()


func call_edge_function(function_name: String, body: Dictionary = {}, method: String = "POST") -> Dictionary:
	if config == null or not config.is_configured():
		return {"ok": false, "error": "Backend is not configured.", "status": 0, "data": {}}
	var url := "%s/functions/v1/%s" % [config.supabase_url.rstrip("/"), function_name]
	return await request(url, method, body, true)


func rest_get(path: String, query: String = "") -> Dictionary:
	if config == null or not config.is_configured():
		return {"ok": false, "error": "Backend is not configured.", "status": 0, "data": {}}
	var url := "%s/rest/v1/%s" % [config.supabase_url.rstrip("/"), path.lstrip("/")]
	if not query.is_empty():
		url += "?" + query
	return await request(url, "GET", {}, true)


func request(url: String, method: String, body: Dictionary, authed: bool) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	# Caller must add to tree; SceneTree-less fallback uses temporary Engine root.
	var host: Node = Engine.get_main_loop().root
	host.add_child(http)
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"apikey: %s" % config.supabase_publishable_key,
	]
	if authed:
		var auth := tokens.authorization_header()
		if auth.is_empty():
			http.queue_free()
			return {"ok": false, "error": "Not signed in.", "status": 401, "data": {}}
		headers.append("Authorization: %s" % auth)
	var payload := "" if method == "GET" else JSON.stringify(body)
	var err := http.request(url, headers, _http_method(method), payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Network request failed to start.", "status": 0, "data": {}}
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
	# Never log tokens, passwords, or message bodies.
	return {"ok": ok, "status": status, "data": data, "error": error}


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
		if d.has("error") and typeof(d["error"]) == TYPE_STRING:
			return str(d["error"])
		if d.has("message") and typeof(d["message"]) == TYPE_STRING:
			return str(d["message"])
	return "Request failed (%d)." % status
