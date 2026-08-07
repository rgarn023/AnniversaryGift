extends RefCounted
class_name ScrollService
## Online scroll APIs for permanent Current / Saved / Sent state.
## Never logs passwords, tokens, or message bodies.

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func get_chest() -> Dictionary:
	return await api.call_edge_function("get-chest", {}, "GET")


func get_saved_scrolls(filters: Dictionary = {}) -> Dictionary:
	return await api.call_edge_function("get-saved-scrolls", filters, "POST")


func get_sent_scrolls() -> Dictionary:
	return await api.call_edge_function("get-sent-scrolls", {}, "GET")


func send_scroll(payload: Dictionary) -> Dictionary:
	# sender_id is never accepted from the client; edge derives it from the JWT.
	var body := payload.duplicate(true)
	body.erase("sender_id")
	return await api.call_edge_function("send-scroll", body, "POST")


func open_scroll(
	scroll_id: String,
	password: String = "",
	location_lat: float = NAN,
	location_lng: float = NAN
) -> Dictionary:
	var body := {"scroll_id": scroll_id}
	if not password.is_empty():
		body["password"] = password
	if not is_nan(location_lat) and not is_nan(location_lng):
		body["location_lat"] = location_lat
		body["location_lng"] = location_lng
	return await api.call_edge_function("open-scroll", body, "POST")


func set_scroll_favorite(scroll_id: String, is_favorite: bool) -> Dictionary:
	return await api.call_edge_function("update-scroll-favorite", {
		"scroll_id": scroll_id,
		"is_favorite": is_favorite,
	}, "POST")


func delete_received_scroll(scroll_id: String) -> Dictionary:
	return await api.call_edge_function("delete-received-scroll", {
		"scroll_id": scroll_id,
	}, "POST")


func delete_sent_scroll(scroll_id: String) -> Dictionary:
	return await api.call_edge_function("delete-sent-scroll", {
		"scroll_id": scroll_id,
	}, "POST")


func reveal_sent_scroll_password(scroll_id: String) -> Dictionary:
	## Sender-only Magical Password recovery. Never log the returned password.
	return await api.call_edge_function("reveal-sent-scroll-password", {
		"scroll_id": scroll_id,
	}, "POST")
