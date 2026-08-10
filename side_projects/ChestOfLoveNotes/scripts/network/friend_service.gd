extends RefCounted
class_name FriendService
## My Person connection APIs (edge function names retained for compatibility).

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func search_profiles(query: String) -> Dictionary:
	return await api.call_edge_function("search-profiles", {"query": query}, "POST")


func get_my_person() -> Dictionary:
	## Preferred: returns person (0|1), me token, incoming/outgoing requests.
	return await api.call_edge_function("get-friends", {}, "GET")


func get_friends() -> Dictionary:
	## Compat alias.
	return await get_my_person()


func resolve_connection_token(token_or_link: String) -> Dictionary:
	return await api.call_edge_function("resolve-connection-token", {
		"token": token_or_link.strip_edges(),
	}, "POST")


func send_connection_request(opts: Dictionary) -> Dictionary:
	## opts: recipient_id | connection_token | friend_code
	var body := {}
	if str(opts.get("recipient_id", "")) != "":
		body["recipient_id"] = str(opts.get("recipient_id"))
	if str(opts.get("connection_token", "")) != "":
		body["connection_token"] = str(opts.get("connection_token"))
	if str(opts.get("friend_code", "")) != "":
		body["friend_code"] = str(opts.get("friend_code"))
	if body.is_empty():
		return {"ok": false, "error": "Connection target required.", "status": 400, "data": {}}
	return await api.call_edge_function("send-friend-request", body, "POST")


func send_friend_request(recipient_id: String = "", friend_code: String = "") -> Dictionary:
	return await send_connection_request({
		"recipient_id": recipient_id,
		"friend_code": friend_code,
	})


func send_friend_request_query(query: String) -> Dictionary:
	## Treat deep-link/token, CHEST- codes, otherwise username search.
	var q := query.strip_edges()
	if q.is_empty():
		return {"ok": false, "error": "Enter a connection code or username.", "status": 400, "data": {}}
	var token := QrHelper.extract_token(q)
	if not token.is_empty() and token.length() >= 16 and not q.to_upper().begins_with("CHEST-"):
		return await send_connection_request({"connection_token": token})
	if q.to_upper().begins_with("CHEST-"):
		return await send_connection_request({"friend_code": q.to_upper()})
	var found: Dictionary = await search_profiles(q)
	if not bool(found.get("ok", false)):
		return found
	var data: Dictionary = found.data if typeof(found.get("data")) == TYPE_DICTIONARY else {}
	var profiles: Array = data.get("profiles", []) if typeof(data.get("profiles")) == TYPE_ARRAY else []
	if profiles.is_empty() and typeof(data.get("results")) == TYPE_ARRAY:
		profiles = data.get("results", [])
	if profiles.is_empty():
		return {"ok": false, "error": "No matching user.", "status": 404, "data": {}}
	var first: Dictionary = profiles[0]
	return await send_connection_request({"recipient_id": str(first.get("id", ""))})


func respond_to_friend_request(request_id: String, accept: bool) -> Dictionary:
	return await api.call_edge_function(
		"respond-to-friend-request",
		{"request_id": request_id, "action": "accept" if accept else "decline"},
		"POST"
	)


func disconnect_person() -> Dictionary:
	return await api.call_edge_function("disconnect-person", {}, "POST")


func regenerate_connection_token() -> Dictionary:
	return await api.rest_rpc("regenerate_my_connection_token", {})


func register_push_token(token: String, platform: String = "android") -> Dictionary:
	if token.strip_edges().is_empty():
		return {"ok": false, "error": "empty token"}
	return await api.call_edge_function("register-push-token", {
		"token": token.strip_edges(),
		"platform": platform,
		"active": true,
	}, "POST")


func deactivate_push_token(token: String) -> Dictionary:
	if token.strip_edges().is_empty():
		return {"ok": true}
	return await api.call_edge_function("register-push-token", {
		"token": token.strip_edges(),
		"platform": "android",
		"active": false,
	}, "POST")


func block_user(blocked_id: String) -> Dictionary:
	return await api.call_edge_function("block-user", {"blocked_id": blocked_id, "action": "block"}, "POST")
