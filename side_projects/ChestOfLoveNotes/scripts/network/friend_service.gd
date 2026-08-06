extends RefCounted
class_name FriendService

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func search_profiles(query: String) -> Dictionary:
	return await api.call_edge_function("search-profiles", {"query": query}, "POST")


func send_friend_request(recipient_id: String = "", friend_code: String = "") -> Dictionary:
	var body := {}
	if not recipient_id.is_empty():
		body["recipient_id"] = recipient_id
	elif not friend_code.is_empty():
		body["friend_code"] = friend_code
	else:
		return {"ok": false, "error": "recipient_id or friend_code required.", "status": 400, "data": {}}
	return await api.call_edge_function("send-friend-request", body, "POST")


func send_friend_request_query(query: String) -> Dictionary:
	## Convenience: treat CHEST- codes as friend_code, otherwise search then send.
	var q := query.strip_edges()
	if q.to_upper().begins_with("CHEST-"):
		return await send_friend_request("", q.to_upper())
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
	return await send_friend_request(str(first.get("id", "")), "")


func respond_to_friend_request(request_id: String, accept: bool) -> Dictionary:
	return await api.call_edge_function(
		"respond-to-friend-request",
		{"request_id": request_id, "action": "accept" if accept else "decline"},
		"POST"
	)


func get_friends() -> Dictionary:
	return await api.call_edge_function("get-friends", {}, "GET")


func block_user(blocked_id: String) -> Dictionary:
	return await api.call_edge_function("block-user", {"blocked_id": blocked_id, "action": "block"}, "POST")
