extends RefCounted
class_name PetGiftService
## Store acquisition → recipient selection → pet delivery → claim.
## Online: Supabase RPCs. Demo/local: in-memory pending gifts (same conceptual path).
## No Google Play Billing — FREE pets satisfy entitlement immediately.

const REWARD_NORMAL_SCROLL := "NORMAL_SCROLL"
const REWARD_PET_GIFT := "PET_GIFT"
const STATUS_PENDING := "pending"
const STATUS_CLAIMED := "claimed"
const STATUS_CANCELLED := "cancelled"
const RECIPIENT_SELF := "self"
const RECIPIENT_PERSON := "person"

var api: ApiClient
## Demo / offline pending deliveries (dicts).
var local_deliveries: Array[Dictionary] = []
var local_ownership: Dictionary = {} ## user_id -> Array[String] pet ids


func _init(p_api: ApiClient = null) -> void:
	api = p_api


func clear_local() -> void:
	local_deliveries.clear()
	local_ownership.clear()


func send_pet_gift(
	pet_id: String,
	sender_user_id: String,
	recipient_user_id: String,
	use_local: bool = false
) -> Dictionary:
	## Creates a pending delivery. Does NOT grant ownership.
	var pid := pet_id.strip_edges()
	var sid := sender_user_id.strip_edges()
	var rid := recipient_user_id.strip_edges()
	if pid.is_empty() or sid.is_empty() or rid.is_empty():
		return {"ok": false, "code": "invalid_args", "error": "Missing pet or user."}
	if use_local or api == null:
		return _send_local(pid, sid, rid)
	var rpc: Dictionary = await api.rest_rpc("send_pet_gift", {
		"p_pet_id": pid,
		"p_recipient_user_id": rid,
	})
	return _normalize_rpc(rpc, "send")


func list_pending_pet_gifts(recipient_user_id: String = "", use_local: bool = false) -> Dictionary:
	if use_local or api == null:
		return _list_local(recipient_user_id)
	var rpc: Dictionary = await api.rest_rpc("list_pending_pet_gifts", {})
	return _normalize_list(rpc)


func claim_pet_gift(
	delivery_id: String,
	recipient_user_id: String = "",
	use_local: bool = false
) -> Dictionary:
	var did := delivery_id.strip_edges()
	if did.is_empty():
		return {"ok": false, "code": "invalid_delivery", "error": "Missing delivery."}
	if use_local or api == null:
		return _claim_local(did, recipient_user_id)
	var rpc: Dictionary = await api.rest_rpc("claim_pet_gift", {
		"p_delivery_id": did,
	})
	return _normalize_rpc(rpc, "claim")


func has_pending_for(recipient_user_id: String, pet_id: String = "") -> bool:
	var rid := recipient_user_id.strip_edges()
	for d in local_deliveries:
		if str(d.get("status", "")) != STATUS_PENDING:
			continue
		if str(d.get("recipient_user_id", "")) != rid:
			continue
		if not pet_id.is_empty() and str(d.get("pet_id", "")) != pet_id:
			continue
		return true
	return false


func pending_count_for(recipient_user_id: String) -> int:
	var n := 0
	var rid := recipient_user_id.strip_edges()
	for d in local_deliveries:
		if str(d.get("status", "")) == STATUS_PENDING \
			and str(d.get("recipient_user_id", "")) == rid:
			n += 1
	return n


func first_pending_for(recipient_user_id: String) -> Dictionary:
	var rid := recipient_user_id.strip_edges()
	for d in local_deliveries:
		if str(d.get("status", "")) == STATUS_PENDING \
			and str(d.get("recipient_user_id", "")) == rid:
			return d.duplicate(true)
	return {}


func _send_local(pet_id: String, sender_id: String, recipient_id: String) -> Dictionary:
	## Duplicate pending protection.
	for d in local_deliveries:
		if str(d.get("status", "")) != STATUS_PENDING:
			continue
		if str(d.get("sender_user_id", "")) == sender_id \
			and str(d.get("recipient_user_id", "")) == recipient_id \
			and str(d.get("pet_id", "")) == pet_id:
			var dup := d.duplicate(true)
			dup["ok"] = true
			dup["code"] = "already_pending"
			dup["duplicate"] = true
			dup["delivery_id"] = str(d.get("id", d.get("delivery_id", "")))
			return dup
	var id := "petgift-%s-%d" % [pet_id, Time.get_ticks_msec()]
	var row := {
		"id": id,
		"delivery_id": id,
		"pet_id": pet_id,
		"pet_display_name": "Parrot" if pet_id == PetCatalog.PET_PARROT else pet_id.capitalize(),
		"sender_user_id": sender_id,
		"recipient_user_id": recipient_id,
		"status": STATUS_PENDING,
		"created_at": Time.get_datetime_string_from_system(true),
		"reward_type": REWARD_PET_GIFT,
		"claimed_at": "",
	}
	local_deliveries.append(row)
	return {
		"ok": true,
		"code": "created",
		"delivery_id": id,
		"pet_id": pet_id,
		"sender_user_id": sender_id,
		"recipient_user_id": recipient_id,
		"status": STATUS_PENDING,
		"duplicate": false,
		"gift": row.duplicate(true),
	}


func _list_local(recipient_user_id: String) -> Dictionary:
	var rid := recipient_user_id.strip_edges()
	var gifts: Array = []
	for d in local_deliveries:
		if str(d.get("status", "")) != STATUS_PENDING:
			continue
		if not rid.is_empty() and str(d.get("recipient_user_id", "")) != rid:
			continue
		gifts.append(d.duplicate(true))
	return {"ok": true, "gifts": gifts}


func _claim_local(delivery_id: String, recipient_user_id: String) -> Dictionary:
	var rid := recipient_user_id.strip_edges()
	for i in range(local_deliveries.size()):
		var d: Dictionary = local_deliveries[i]
		var did := str(d.get("id", d.get("delivery_id", "")))
		if did != delivery_id:
			continue
		if not rid.is_empty() and str(d.get("recipient_user_id", "")) != rid:
			return {"ok": false, "code": "forbidden", "error": "Only the recipient may claim."}
		var pet_id := str(d.get("pet_id", ""))
		var owner := str(d.get("recipient_user_id", ""))
		if str(d.get("status", "")) == STATUS_CLAIMED:
			_ensure_local_owned(owner, pet_id)
			return {
				"ok": true,
				"code": "already_claimed",
				"delivery_id": did,
				"pet_id": pet_id,
				"status": STATUS_CLAIMED,
				"owned": true,
				"idempotent": true,
			}
		if str(d.get("status", "")) != STATUS_PENDING:
			return {"ok": false, "code": "not_claimable", "status": str(d.get("status", ""))}
		## Ownership first, then mark claimed.
		_ensure_local_owned(owner, pet_id)
		d["status"] = STATUS_CLAIMED
		d["claimed_at"] = Time.get_datetime_string_from_system(true)
		local_deliveries[i] = d
		return {
			"ok": true,
			"code": "claimed",
			"delivery_id": did,
			"pet_id": pet_id,
			"status": STATUS_CLAIMED,
			"owned": true,
			"idempotent": false,
		}
	return {"ok": false, "code": "not_found", "error": "Delivery not found."}


func _ensure_local_owned(user_id: String, pet_id: String) -> void:
	if user_id.is_empty() or pet_id.is_empty():
		return
	var arr: Array = local_ownership.get(user_id, [])
	if typeof(arr) != TYPE_ARRAY:
		arr = []
	if not arr.has(pet_id):
		arr.append(pet_id)
	local_ownership[user_id] = arr


func is_locally_owned(user_id: String, pet_id: String) -> bool:
	var arr: Variant = local_ownership.get(user_id, [])
	if typeof(arr) != TYPE_ARRAY:
		return false
	return (arr as Array).has(pet_id)


func _normalize_rpc(rpc: Dictionary, _kind: String) -> Dictionary:
	if not bool(rpc.get("ok", false)):
		return {
			"ok": false,
			"code": "rpc_failed",
			"error": str(rpc.get("error", "Request failed.")),
			"status": int(rpc.get("status", 0)),
		}
	var data: Variant = rpc.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "code": "bad_payload", "error": "Unexpected response."}
	var d: Dictionary = data
	## PostgREST may wrap scalar jsonb; accept nested.
	if d.has("ok"):
		return d
	return {"ok": true, "data": d}


func _normalize_list(rpc: Dictionary) -> Dictionary:
	if not bool(rpc.get("ok", false)):
		return {
			"ok": false,
			"code": "rpc_failed",
			"error": str(rpc.get("error", "Request failed.")),
			"gifts": [],
		}
	var data: Variant = rpc.get("data", {})
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		if d.has("gifts"):
			return d
		if bool(d.get("ok", false)):
			return d
	return {"ok": true, "gifts": []}
