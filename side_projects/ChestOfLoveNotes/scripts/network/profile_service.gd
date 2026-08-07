extends RefCounted
class_name ProfileService
## Profile load / create via secured REST (RLS: own row insert/update).
## Distinguishes UNKNOWN / LOADING / EXISTS / NOT_CREATED / ERROR so a soft
## fetch failure never looks like "Create Your Profile".

enum ProfileState { UNKNOWN, LOADING, EXISTS, NOT_CREATED, ERROR }

const CACHE_PATH := "user://coln_profile_cache.json"

var api: ApiClient
var tokens: SecureTokenService

var profile: Dictionary = {}
var profile_state: ProfileState = ProfileState.UNKNOWN
var last_error: String = ""


func _init(p_api: ApiClient, p_tokens: SecureTokenService) -> void:
	api = p_api
	tokens = p_tokens


func clear() -> void:
	## Clears in-memory state only. Disk cache stays keyed by user id for resume.
	profile.clear()
	profile_state = ProfileState.UNKNOWN
	last_error = ""


func has_known_profile() -> bool:
	return profile_state == ProfileState.EXISTS or (
		not profile.is_empty()
		and str(profile.get("username", "")).strip_edges() != ""
	)


func is_definitively_missing() -> bool:
	return profile_state == ProfileState.NOT_CREATED


func hydrate_from_cache() -> bool:
	## Restore non-sensitive username/display_name immediately on resume.
	if tokens.user_id.is_empty():
		return false
	var cached := _read_cache_for_user(tokens.user_id)
	if cached.is_empty():
		return false
	profile = cached
	profile_state = ProfileState.EXISTS
	return true


func fetch_own_profile() -> Dictionary:
	## Never treat timeout / soft failure / unfinished request as NOT_CREATED.
	last_error = ""
	if tokens.user_id.is_empty():
		profile_state = ProfileState.UNKNOWN
		return {"ok": false, "error": "Not signed in.", "exists": false, "state": "UNKNOWN", "definitive": false}

	## Keep showing known profile while refreshing — do not blank fields first.
	if profile.is_empty():
		hydrate_from_cache()
	profile_state = ProfileState.LOADING

	var q := "select=id,username,display_name,friend_code,avatar_url,bio,created_at&id=eq.%s" % tokens.user_id
	var result: Dictionary = await api.rest_get("profiles", q)
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "Could not load profile."))
		## Soft/network failure: restore cache, keep EXISTS if we already knew it.
		if hydrate_from_cache() or has_known_profile():
			profile_state = ProfileState.EXISTS
			return {
				"ok": false,
				"error": last_error,
				"exists": true,
				"state": "EXISTS",
				"definitive": false,
				"soft_fail": true,
				"profile": profile,
			}
		profile_state = ProfileState.ERROR
		return {
			"ok": false,
			"error": last_error,
			"exists": false,
			"state": "ERROR",
			"definitive": false,
			"soft_fail": true,
			"profile": {},
		}

	var rows: Array = result.data if typeof(result.get("data")) == TYPE_ARRAY else []
	if rows.is_empty():
		## Backend definitively confirmed no profile row for this account.
		profile.clear()
		profile_state = ProfileState.NOT_CREATED
		_clear_cache_for_user(tokens.user_id)
		return {
			"ok": true,
			"exists": false,
			"state": "NOT_CREATED",
			"definitive": true,
			"profile": {},
		}

	profile = rows[0]
	profile_state = ProfileState.EXISTS
	_write_cache(profile)
	return {
		"ok": true,
		"exists": true,
		"state": "EXISTS",
		"definitive": true,
		"profile": profile,
	}


func create_profile(username: String, display_name: String) -> Dictionary:
	if tokens.user_id.is_empty():
		return {"ok": false, "error": "Not signed in."}
	## Avoid duplicate creates when we already have a profile.
	if profile_state == ProfileState.EXISTS and has_known_profile():
		return {"ok": true, "profile": profile, "already_exists": true}
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
	profile_state = ProfileState.EXISTS
	_write_cache(profile)
	return {"ok": true, "profile": profile}


func _public_cache_slice(p: Dictionary) -> Dictionary:
	## Non-sensitive fields only — never tokens or secrets.
	return {
		"id": str(p.get("id", "")),
		"username": str(p.get("username", "")),
		"display_name": str(p.get("display_name", "")),
		"friend_code": str(p.get("friend_code", "")),
		"avatar_url": str(p.get("avatar_url", "")),
		"bio": str(p.get("bio", "")),
	}


func _read_all_cache() -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var raw := FileAccess.get_file_as_string(CACHE_PATH)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _read_cache_for_user(user_id: String) -> Dictionary:
	var all := _read_all_cache()
	var entry: Variant = all.get(user_id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = entry
	if str(d.get("username", "")).strip_edges().is_empty():
		return {}
	return d


func _write_cache(p: Dictionary) -> void:
	var uid := str(p.get("id", tokens.user_id))
	if uid.is_empty():
		return
	var all := _read_all_cache()
	all[uid] = _public_cache_slice(p)
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(all))
	f.close()


func _clear_cache_for_user(user_id: String) -> void:
	if user_id.is_empty():
		return
	var all := _read_all_cache()
	if all.has(user_id):
		all.erase(user_id)
		var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(all))
			f.close()
