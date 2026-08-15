extends RefCounted
class_name RelationshipLabelService
## CRUD for private per-user My Person relationship labels (Supabase RPC + REST).

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func fetch_for_friendship(friendship_id: String) -> Dictionary:
	if friendship_id.strip_edges().is_empty():
		return {"ok": false, "error": "Missing friendship id.", "label": _empty_label()}
	var q := (
		"select=id,friendship_id,owner_user_id,relationship_key,custom_label,updated_at"
		+ "&friendship_id=eq.%s&limit=1" % friendship_id.strip_edges()
	)
	var result: Dictionary = await api.rest_get("my_person_relationship_labels", q)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"error": str(result.get("error", "Could not load relationship.")),
			"label": _empty_label(),
			"status": int(result.get("status", 0)),
		}
	var data: Variant = result.get("data", [])
	if typeof(data) == TYPE_ARRAY and not (data as Array).is_empty():
		var row: Dictionary = (data as Array)[0]
		return {"ok": true, "label": _normalize_row(row), "status": int(result.get("status", 200))}
	return {"ok": true, "label": _empty_label(), "status": 200}


func upsert(friendship_id: String, relationship_key: String, custom_label: String = "") -> Dictionary:
	var key := RelationshipLabelHelper.normalize_key(relationship_key)
	var custom := RelationshipLabelHelper.sanitize_custom(custom_label)
	if not RelationshipLabelHelper.is_valid_selection(key, custom):
		return {"ok": false, "error": "Choose a relationship or enter a custom label.", "label": _empty_label()}
	if friendship_id.strip_edges().is_empty():
		return {"ok": false, "error": "Missing friendship id.", "label": _empty_label()}
	var result: Dictionary = await api.rest_rpc("upsert_my_person_relationship_label", {
		"p_friendship_id": friendship_id.strip_edges(),
		"p_relationship_key": key,
		"p_custom_label": custom if key == RelationshipLabelHelper.KEY_OTHER else null,
	})
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"error": str(result.get("error", "Could not save relationship.")),
			"label": _empty_label(),
			"status": int(result.get("status", 0)),
		}
	var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	return {"ok": true, "label": _normalize_row(data), "status": int(result.get("status", 200)), "data": data}


func clear(friendship_id: String) -> Dictionary:
	if friendship_id.strip_edges().is_empty():
		return {"ok": false, "error": "Missing friendship id.", "label": _empty_label()}
	var result: Dictionary = await api.rest_rpc("clear_my_person_relationship_label", {
		"p_friendship_id": friendship_id.strip_edges(),
	})
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"error": str(result.get("error", "Could not clear relationship.")),
			"label": _empty_label(),
			"status": int(result.get("status", 0)),
		}
	return {"ok": true, "label": _empty_label(), "status": int(result.get("status", 200))}


func _empty_label() -> Dictionary:
	return {
		"relationship_key": RelationshipLabelHelper.KEY_NOT_SET,
		"custom_label": "",
		"display_label": "Not set",
	}


func _normalize_row(row: Dictionary) -> Dictionary:
	var key := RelationshipLabelHelper.normalize_key(str(row.get("relationship_key", RelationshipLabelHelper.KEY_NOT_SET)))
	var custom := RelationshipLabelHelper.sanitize_custom(str(row.get("custom_label", "")))
	var display := str(row.get("display_label", "")).strip_edges()
	if display.is_empty():
		display = RelationshipLabelHelper.display_for_key(key, custom)
	return {
		"relationship_key": key,
		"custom_label": custom,
		"display_label": display,
		"friendship_id": str(row.get("friendship_id", "")),
		"id": str(row.get("id", "")),
	}
