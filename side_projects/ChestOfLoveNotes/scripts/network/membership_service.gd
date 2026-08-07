extends RefCounted
class_name MembershipService
## Private-app membership claim + status. Server derives identity from JWT.

var api: ApiClient
var tokens: SecureTokenService

var is_member: bool = false
var role: String = ""
var status: String = ""
var last_deny_message: String = ""

## Single-flight: concurrent resume + cold-restore must not clear membership mid-claim.
var _claim_inflight: bool = false
var _claim_result: Dictionary = {}


func _init(p_api: ApiClient, p_tokens: SecureTokenService) -> void:
	api = p_api
	tokens = p_tokens


func clear() -> void:
	is_member = false
	role = ""
	status = ""
	last_deny_message = ""


func claim_membership() -> Dictionary:
	if _claim_inflight:
		var tree := Engine.get_main_loop() as SceneTree
		while _claim_inflight and tree != null:
			await tree.process_frame
		return _claim_result.duplicate(true)
	_claim_inflight = true
	_claim_result = await _claim_membership_inner()
	_claim_inflight = false
	return _claim_result.duplicate(true)


func _claim_membership_inner() -> Dictionary:
	## Do not clear membership at the start — concurrent callers previously saw
	## is_member=false and treated soft failures as hard denials.
	if not tokens.has_session():
		return {"ok": false, "error": "Not signed in.", "forbidden": false}
	# Do not send caller-selected user_id — Edge Function uses JWT.
	var result: Dictionary = await api.call_edge_function("claim-private-membership", {}, "POST")
	if not bool(result.get("ok", false)):
		var status_code := int(result.get("status", 0))
		var err := str(result.get("error", "Membership claim failed."))
		var forbidden := status_code == 403 or err.to_lower().contains("not invited") or err.to_lower().contains("not approved") or err.to_lower().contains("allowlist")
		if forbidden:
			clear()
			last_deny_message = "This is a private app, and this account is not approved."
			err = last_deny_message
		return {"ok": false, "error": err, "forbidden": forbidden, "status": status_code}
	var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	var member: Dictionary = data.get("member", {}) if typeof(data.get("member")) == TYPE_DICTIONARY else {}
	role = str(member.get("role", "member"))
	status = str(member.get("status", "active"))
	is_member = status == "active"
	if not is_member:
		last_deny_message = "This is a private app, and this account is not approved."
		return {"ok": false, "error": last_deny_message, "forbidden": true}
	return {"ok": true, "role": role, "status": status}


func refresh_membership_row() -> Dictionary:
	if not tokens.has_session() or tokens.user_id.is_empty():
		return {"ok": false, "error": "Not signed in."}
	var q := "select=user_id,role,status&user_id=eq.%s" % tokens.user_id
	var result: Dictionary = await api.rest_get("private_app_members", q)
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "Could not load membership."))}
	var rows: Array = result.data if typeof(result.get("data")) == TYPE_ARRAY else []
	if rows.is_empty():
		is_member = false
		role = ""
		status = ""
		return {"ok": true, "is_member": false}
	var row: Dictionary = rows[0]
	role = str(row.get("role", ""))
	status = str(row.get("status", ""))
	is_member = status == "active"
	return {"ok": true, "is_member": is_member, "role": role, "status": status}
