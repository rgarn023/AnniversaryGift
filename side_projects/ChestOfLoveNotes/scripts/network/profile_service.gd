extends RefCounted
class_name ProfileService

var api: ApiClient


func _init(p_api: ApiClient) -> void:
	api = p_api


func upsert_profile(username: String, display_name: String) -> Dictionary:
	return await api.rest_get("profiles") # Placeholder; profile upsert goes through REST/RPC once online.
