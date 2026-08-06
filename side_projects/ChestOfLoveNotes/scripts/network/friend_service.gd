extends RefCounted
class_name FriendService

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func search_profiles(query: String) -> Dictionary:
	return await api.call_edge_function("search-profiles", {"query": query}, "POST")


func send_friend_request(query: String) -> Dictionary:
	return await api.call_edge_function("send-friend-request", {"query": query}, "POST")


func respond_to_friend_request(request_id: String, accept: bool) -> Dictionary:
	return await api.call_edge_function(
		"respond-to-friend-request",
		{"request_id": request_id, "action": "accept" if accept else "decline"},
		"POST"
	)


func get_friends() -> Dictionary:
	return await api.call_edge_function("get-friends", {}, "GET")


func block_user(user_id: String) -> Dictionary:
	return await api.call_edge_function("block-user", {"user_id": user_id}, "POST")
