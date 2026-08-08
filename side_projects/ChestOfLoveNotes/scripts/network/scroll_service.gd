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


func mark_activity_lock_progress(scroll_id: String, distance_km: float, completed: bool = false) -> Dictionary:
	## Minimal progress only — never a GPS trail.
	return await api.rest_rpc("mark_activity_lock_progress", {
		"p_scroll_id": scroll_id,
		"p_distance_km": distance_km,
		"p_completed": completed,
	})


func mark_focus_lock_started(scroll_id: String) -> Dictionary:
	return await api.rest_rpc("mark_focus_lock_started", {"p_scroll_id": scroll_id})


func mark_focus_lock_complete(scroll_id: String) -> Dictionary:
	return await api.rest_rpc("mark_focus_lock_complete", {"p_scroll_id": scroll_id})


func mark_focus_lock_interrupted(scroll_id: String) -> Dictionary:
	return await api.rest_rpc("mark_focus_lock_interrupted", {"p_scroll_id": scroll_id})


func open_scroll(
	scroll_id: String,
	password: String = "",
	location_lat: float = NAN,
	location_lng: float = NAN,
	location_accuracy_m: float = NAN
) -> Dictionary:
	var body := {"scroll_id": scroll_id}
	if not password.is_empty():
		body["password"] = password
	if not is_nan(location_lat) and not is_nan(location_lng):
		body["location_lat"] = location_lat
		body["location_lng"] = location_lng
	if not is_nan(location_accuracy_m):
		body["location_accuracy_m"] = location_accuracy_m
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


func prepare_attachment_uploads(items: Array) -> Dictionary:
	return await api.call_edge_function("prepare-attachment-uploads", {"items": items}, "POST")


func get_scroll_attachments(scroll_id: String) -> Dictionary:
	return await api.call_edge_function("get-scroll-attachments", {"scroll_id": scroll_id}, "POST")


func upload_to_signed_url(signed_url: String, file_path: String, mime: String, token: String = "") -> Dictionary:
	## PUT compressed bytes to a Supabase signed upload URL.
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "error": "Photo file missing."}
	var bytes := FileAccess.get_file_as_bytes(file_path)
	var http := HTTPRequest.new()
	http.timeout = 60.0
	Engine.get_main_loop().root.add_child(http)
	var headers := PackedStringArray([
		"Content-Type: %s" % mime,
		"x-upsert: true",
	])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var err := http.request_raw(signed_url, headers, HTTPClient.METHOD_PUT, bytes)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Could not start photo upload."}
	var completed: Array = await http.request_completed
	http.queue_free()
	if completed.is_empty() or int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Photo upload failed. Check your connection."}
	var status := int(completed[1])
	if status < 200 or status >= 300:
		return {"ok": false, "error": "Photo upload was rejected (%d)." % status}
	return {"ok": true}
