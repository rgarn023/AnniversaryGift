extends RefCounted
class_name ScrollService

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func get_chest() -> Dictionary:
	return await api.call_edge_function("get-chest", {}, "GET")


func send_scroll(payload: Dictionary) -> Dictionary:
	return await api.call_edge_function("send-scroll", payload, "POST")


func open_scroll(scroll_id: String, magic_password: String = "") -> Dictionary:
	var body := {"scroll_id": scroll_id}
	if not magic_password.is_empty():
		body["magic_password"] = magic_password
	return await api.call_edge_function("open-scroll", body, "POST")


func get_sent_scrolls() -> Dictionary:
	return await api.call_edge_function("get-sent-scrolls", {}, "GET")
