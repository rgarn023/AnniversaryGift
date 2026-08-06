extends RefCounted
class_name ProfileService
## Profile load / create via secured REST (RLS: own row insert/update).

var api: ApiClient
var tokens: SecureTokenService

var profile: Dictionary = {}


func _init(p_api: ApiClient, p_tokens: SecureTokenService) -> void:
	api = p_api
	tokens = p_tokens


func clear() -> void:
	profile.clear()


func fetch_own_profile() -> Dictionary:
	profile.clear()
	if tokens.user_id.is_empty():
		return {"ok": false, "error": "Not signed in.", "exists": false}
	var q := "select=id,username,display_name,friend_code,avatar_url,bio,created_at&id=eq.%s" % tokens.user_id
	var result: Dictionary = await api.rest_get("profiles", q)
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "Could not load profile.")), "exists": false}
	var rows: Array = result.data if typeof(result.get("data")) == TYPE_ARRAY else []
	if rows.is_empty():
		return {"ok": true, "exists": false, "profile": {}}
	profile = rows[0]
	return {"ok": true, "exists": true, "profile": profile}


func create_profile(username: String, display_name: String) -> Dictionary:
	if tokens.user_id.is_empty():
		return {"ok": false, "error": "Not signed in."}
	var uname := username.strip_edges().to_lower()
	var dname := display_name.strip_edges()
	if uname.length() < 3 or uname.length() > 32:
		return {"ok": false, "error": "Username must be 3–32 characters."}
	if dname.is_empty():
		dname = uname
	var code_result: Dictionary = await api.rest_rpc("generate_friend_code", {})
	if not bool(code_result.get("ok", false)):
		return {"ok": false, "error": str(code_result.get("error", "Could not generate friend code."))}
	var friend_code := str(code_result.get("data", ""))
	# RPC may return a bare JSON string.
	if friend_code.begins_with("\"") and friend_code.ends_with("\""):
		friend_code = friend_code.substr(1, friend_code.length() - 2)
	if friend_code.is_empty():
		return {"ok": false, "error": "Friend code generation returned empty."}
	var body := {
		"id": tokens.user_id,
		"username": uname,
		"display_name": dname,
		"friend_code": friend_code,
	}
	var result: Dictionary = await api.rest_post("profiles", body, "return=representation,resolution=merge-duplicates")
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "Could not save profile."))}
	var data: Variant = result.get("data")
	if typeof(data) == TYPE_ARRAY and (data as Array).size() > 0:
		profile = (data as Array)[0]
	elif typeof(data) == TYPE_DICTIONARY:
		profile = data
	else:
		profile = body
	return {"ok": true, "profile": profile}
