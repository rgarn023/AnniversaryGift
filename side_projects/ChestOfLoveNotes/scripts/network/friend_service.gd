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
	var result: Dictionary = await api.call_edge_function("send-friend-request", body, "POST")
	## Arm relationship prompt only after an explicit successful new-connection action.
	if bool(result.get("ok", false)):
		RelationshipLabelHelper.mark_explicit_connection_pending()
	return result


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
	var result: Dictionary = await api.call_edge_function(
		"respond-to-friend-request",
		{"request_id": request_id, "action": "accept" if accept else "decline"},
		"POST"
	)
	## Accepting is an explicit new-connection action — arm the relationship prompt.
	if accept and bool(result.get("ok", false)):
		RelationshipLabelHelper.mark_explicit_connection_pending()
	return result


func disconnect_person() -> Dictionary:
	## Preferred: authenticated PostgreSQL RPC (auth.uid(), transactional).
	## Fallback: Edge Function disconnect-person (same semantics).
	var rpc: Dictionary = await api.rest_rpc("disconnect_my_person", {})
	if bool(rpc.get("ok", false)):
		var data: Dictionary = rpc.get("data", {}) if typeof(rpc.get("data")) == TYPE_DICTIONARY else {}
		## PostgREST may return jsonb object directly as data.
		if data.is_empty() and typeof(rpc.get("data")) == TYPE_DICTIONARY:
			data = rpc.get("data")
		var success := bool(data.get("success", false)) or bool(data.get("verified_disconnected", false))
		var found := bool(data.get("relationship_found", false))
		if success and found:
			data["disconnect_mechanism"] = "RPC"
			data["failure_category"] = "None"
			data["active_pair_found"] = true
			data["ok"] = true
			data["verified_disconnected"] = true
			data["person"] = null
			return {"ok": true, "status": int(rpc.get("status", 200)), "data": data, "error": ""}
		## Visible My Person + not_connected means lookup mismatch — treat as failure.
		var category := str(data.get("failure_category", "No Row"))
		if category.is_empty():
			category = "No Row"
		return {
			"ok": false,
			"status": 404 if not found else 500,
			"data": {
				"ok": false,
				"verified_disconnected": false,
				"relationship_found": found,
				"disconnect_mechanism": "RPC",
				"failure_category": category,
				"active_pair_found": found,
				"error_code": str(data.get("error_code", "not_connected")),
			},
			"error": "Could not disconnect.",
		}
	## RPC missing / network / schema — try Edge Function.
	var rpc_err := str(rpc.get("error", "")).to_lower()
	var rpc_status := int(rpc.get("status", 0))
	var rpc_missing := (
		rpc_status == 404
		or rpc_err.contains("could not find")
		or rpc_err.contains("does not exist")
		or rpc_err.contains("pgrst202")
		or rpc_err.contains("schema cache")
	)
	var edge: Dictionary = await api.call_edge_function("disconnect-person", {}, "POST")
	if typeof(edge.get("data")) == TYPE_DICTIONARY:
		var edata: Dictionary = edge.get("data")
		if not edata.has("disconnect_mechanism"):
			edata["disconnect_mechanism"] = "Edge Function"
		if bool(edge.get("ok", false)):
			edata["failure_category"] = "None"
			edata["active_pair_found"] = true
		elif not edata.has("failure_category"):
			edata["failure_category"] = disconnect_failure_category(edge, rpc_missing)
		edge["data"] = edata
	return edge


func disconnect_failure_category(result: Dictionary, rpc_was_missing: bool = false) -> String:
	var status := int(result.get("status", 0))
	var err := str(result.get("error", "")).to_lower()
	var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	var code := ""
	if typeof(data.get("error")) == TYPE_DICTIONARY:
		code = str((data.get("error") as Dictionary).get("code", "")).to_lower()
	if status == 0:
		return "Network"
	if status == 401 or status == 403 or code == "unauthorized" or code == "forbidden":
		return "Unauthorized"
	if status == 404 or code == "not_connected":
		return "No Row"
	if err.contains("rls") or code.contains("rls") or err.contains("permission"):
		return "RLS"
	if rpc_was_missing or err.contains("could not find") or err.contains("does not exist"):
		return "RPC Missing"
	if err.contains("schema"):
		return "Schema"
	if status >= 500:
		return "Function Error"
	return "Unknown"


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
