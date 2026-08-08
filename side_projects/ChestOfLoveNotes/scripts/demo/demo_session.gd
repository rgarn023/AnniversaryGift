extends RefCounted
class_name DemoSession
## LOCAL DEMO MODE — fictional accounts and permanent-scroll state for offline UI.
## Never mixed with production Supabase data. Disabled in release exports.

const DEMO_PASSWORD := "starlight"

var active: bool = false
var current_user_id: String = "demo-robert"
var simulated_now_unix: int = 0
var profiles: Dictionary = {}
var friendships: Array[Dictionary] = []
var friend_requests: Array[Dictionary] = []
var blocks: Array[Dictionary] = []
var scrolls: Array[Dictionary] = []
var scroll_bodies: Dictionary = {} ## id -> plaintext (demo only; never used online)
## Permanent per-party state (mirrors scroll_recipient_states / scroll_sender_states).
var recipient_states: Dictionary = {} ## scroll_id -> Dictionary
var sender_states: Dictionary = {} ## scroll_id -> Dictionary
var password_attempts: Dictionary = {} ## scroll_id -> Array[unix]
var open_message_plaintext: String = ""


func enable() -> void:
	active = true
	_seed()


func disable() -> void:
	active = false
	clear_sensitive()


func clear_sensitive() -> void:
	scroll_bodies.clear()
	password_attempts.clear()
	open_message_plaintext = ""


func _seed() -> void:
	simulated_now_unix = int(Time.get_unix_time_from_system())
	profiles = {
		"demo-robert": {
			"id": "demo-robert",
			"username": "robert_demo",
			"display_name": "Robert Demo",
			"friend_code": "ROBT-LOVE",
		},
		"demo-mandy": {
			"id": "demo-mandy",
			"username": "mandy_demo",
			"display_name": "Mandy Demo",
			"friend_code": "MNDY-NOTE",
		},
		"demo-friend": {
			"id": "demo-friend",
			"username": "celeste_demo",
			"display_name": "Celeste Demo",
			"friend_code": "CLST-STAR",
		},
	}
	friendships = [{
		"user_one_id": "demo-robert",
		"user_two_id": "demo-mandy",
		"created_at": _iso(-86400 * 3),
	}]
	friend_requests = [{
		"id": "req-1",
		"sender_id": "demo-friend",
		"recipient_id": "demo-robert",
		"status": "pending",
		"created_at": _iso(-3600),
		"kind": "friend_request",
	}]
	blocks = []
	recipient_states.clear()
	sender_states.clear()
	var unlocked_id := "scroll-open-now"
	var locked_id := "scroll-locked-soon"
	var protected_id := "scroll-magic"
	var opened_id := "scroll-opened"
	scrolls = [
		_meta(unlocked_id, "demo-mandy", "demo-robert", "For tonight", simulated_now_unix - 120, false, -7200),
		_meta(locked_id, "demo-mandy", "demo-robert", "A tomorrow note", simulated_now_unix + 3600, false, -5400),
		_meta(protected_id, "demo-mandy", "demo-robert", "Sealed with starlight", simulated_now_unix - 60, true, -4000),
		_meta(opened_id, "demo-mandy", "demo-robert", "Yesterday's note", simulated_now_unix - 86400, false, -90000),
	]
	for s in scrolls:
		_ensure_party_states(str(s.id), str(s.sender_id), str(s.recipient_id))
	# Already-opened scroll lives under Saved, not Current.
	var opened_state: Dictionary = recipient_states[opened_id]
	opened_state["is_read"] = true
	opened_state["is_saved"] = true
	opened_state["first_opened_at"] = _iso(-80000)
	opened_state["last_opened_at"] = _iso(-70000)
	opened_state["opened_count"] = 2
	recipient_states[opened_id] = opened_state
	scroll_bodies = {
		unlocked_id: "This note is available now. The chest can hold many scrolls at once — unlocked, locked, and sealed.",
		locked_id: "You should not see this body until the simulated unlock time advances.",
		protected_id: "The magic password worked. In production this text is decrypted only after server checks.",
		opened_id: "An older note that was already opened. It remains in Saved Scrolls.",
	}
	# Sent history for Robert
	var sent_id := "sent-1"
	scrolls.append(_meta(sent_id, "demo-robert", "demo-mandy", "From Robert", simulated_now_unix + 7200, false, -600))
	_ensure_party_states(sent_id, "demo-robert", "demo-mandy")
	scroll_bodies[sent_id] = "A note waiting for Mandy."


func _meta(id: String, sender: String, recipient: String, title: String, unlock_unix: int, has_pw: bool, created_offset: int) -> Dictionary:
	return {
		"id": id,
		"sender_id": sender,
		"recipient_id": recipient,
		"title": title,
		"unlock_at_unix": unlock_unix,
		"has_magic_password": has_pw,
		"has_password": has_pw,
		"created_at": _iso(created_offset),
		"kind": "love_note",
		"_demo_password": DEMO_PASSWORD if has_pw else "",
	}


func _ensure_party_states(scroll_id: String, sender_id: String, recipient_id: String) -> void:
	if not recipient_states.has(scroll_id):
		recipient_states[scroll_id] = {
			"scroll_id": scroll_id,
			"recipient_id": recipient_id,
			"is_read": false,
			"is_saved": false,
			"is_favorite": false,
			"first_opened_at": null,
			"last_opened_at": null,
			"opened_count": 0,
			"deleted_at": null,
		}
	if not sender_states.has(scroll_id):
		sender_states[scroll_id] = {
			"scroll_id": scroll_id,
			"sender_id": sender_id,
			"deleted_at": null,
		}


func _iso(offset_sec: int) -> String:
	return Time.get_datetime_string_from_unix_time(simulated_now_unix + offset_sec, true)


func now_unix() -> int:
	return simulated_now_unix


func advance_minutes(minutes: int) -> void:
	simulated_now_unix += minutes * 60


func get_profile(user_id: String = "") -> Dictionary:
	var id := user_id if not user_id.is_empty() else current_user_id
	return profiles.get(id, {}).duplicate(true)


func search_profiles(query: String) -> Array[Dictionary]:
	var q := query.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for id in profiles.keys():
		if id == current_user_id:
			continue
		var p: Dictionary = profiles[id]
		if str(p.username).to_lower() == q or str(p.friend_code).to_lower() == q:
			out.append({
				"id": p.id,
				"username": p.username,
				"display_name": p.display_name,
				"friend_code": p.friend_code,
			})
	return out


func get_friends() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in friendships:
		var other := str(f.user_two_id) if str(f.user_one_id) == current_user_id else str(f.user_one_id)
		if str(f.user_one_id) != current_user_id and str(f.user_two_id) != current_user_id:
			continue
		var p := get_profile(other)
		if not p.is_empty():
			out.append(p)
	return out


func get_chest_items(filter_name: String = "all") -> Array[Dictionary]:
	## Current Scrolls: not recipient-deleted and not yet saved.
	var items: Array[Dictionary] = []
	for req in friend_requests:
		if str(req.recipient_id) == current_user_id and str(req.status) == "pending":
			var sender := get_profile(str(req.sender_id))
			items.append({
				"id": req.id,
				"kind": "friend_request",
				"state": "friend_request",
				"sender_display_name": sender.get("display_name", "Someone"),
				"title": "Friend Request",
				"unlock_at_unix": 0,
				"has_magic_password": false,
			})
	for s in scrolls:
		if str(s.recipient_id) != current_user_id:
			continue
		var st: Dictionary = recipient_states.get(str(s.id), {})
		if st.is_empty():
			continue
		if st.get("deleted_at") != null:
			continue
		if bool(st.get("is_saved", false)):
			continue
		items.append(_public_recipient_item(s, st))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sort_rank(a) < _sort_rank(b)
	)
	if filter_name == "all":
		return items
	var filtered: Array[Dictionary] = []
	for item in items:
		var state_name := str(item.get("state", ""))
		match filter_name:
			"unread":
				if state_name in ["unlocked_unread", "password_unlocked_unread"]:
					filtered.append(item)
			"locked":
				if state_name == "locked":
					filtered.append(item)
			"requests":
				if state_name == "friend_request":
					filtered.append(item)
	return filtered


func get_saved_scrolls(filters: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in scrolls:
		if str(s.recipient_id) != current_user_id:
			continue
		var st: Dictionary = recipient_states.get(str(s.id), {})
		if st.is_empty():
			continue
		if not bool(st.get("is_saved", false)):
			continue
		if st.get("deleted_at") != null:
			continue
		if bool(filters.get("favorites_only", false)) and not bool(st.get("is_favorite", false)):
			continue
		if bool(filters.get("password_protected_only", false)) and not bool(s.get("has_magic_password", false)):
			continue
		if filters.has("sender_id") and str(filters.sender_id) != str(s.sender_id):
			continue
		var title_q := str(filters.get("title_query", "")).strip_edges().to_lower()
		if not title_q.is_empty() and not str(s.title).to_lower().contains(title_q):
			continue
		out.append(_public_recipient_item(s, st))
	if str(filters.get("sort", "newest")) == "oldest":
		out.reverse()
	return out


func get_sent_scrolls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in scrolls:
		if str(s.sender_id) != current_user_id:
			continue
		var sst: Dictionary = sender_states.get(str(s.id), {})
		if sst.is_empty() or sst.get("deleted_at") != null:
			continue
		var rst: Dictionary = recipient_states.get(str(s.id), {})
		var recip := get_profile(str(s.recipient_id))
		out.append({
			"id": s.id,
			"sender_id": s.sender_id,
			"recipient_id": s.recipient_id,
			"title": s.title,
			"created_at": s.created_at,
			"unlock_at_unix": s.unlock_at_unix,
			"has_password": bool(s.get("has_magic_password", false)),
			"recipient_opened": bool(rst.get("is_read", false)),
			"first_opened_at": rst.get("first_opened_at", null),
			"last_opened_at": rst.get("last_opened_at", null),
			"opened_count": int(rst.get("opened_count", 0)),
			"recipient_display_name": recip.get("display_name", "Friend"),
		})
	return out


func _public_recipient_item(s: Dictionary, st: Dictionary) -> Dictionary:
	var item := {
		"id": s.id,
		"sender_id": s.sender_id,
		"recipient_id": s.recipient_id,
		"title": s.title,
		"unlock_at_unix": s.unlock_at_unix,
		"has_magic_password": bool(s.get("has_magic_password", false)),
		"has_password": bool(s.get("has_magic_password", false)),
		"has_location_lock": bool(s.get("has_location_lock", false)),
		"location_name": str(s.get("location_name", "")),
		"created_at": s.created_at,
		"kind": "love_note",
		"is_read": bool(st.get("is_read", false)),
		"is_saved": bool(st.get("is_saved", false)),
		"is_favorite": bool(st.get("is_favorite", false)),
		"first_opened_at": st.get("first_opened_at", null),
		"last_opened_at": st.get("last_opened_at", null),
		"opened_count": int(st.get("opened_count", 0)),
		"sender_display_name": get_profile(str(s.sender_id)).get("display_name", "Friend"),
	}
	item["state"] = _derive_state(s, st)
	return item


func _derive_state(s: Dictionary, st: Dictionary) -> String:
	if bool(st.get("is_saved", false)) or bool(st.get("is_read", false)):
		return "opened"
	if int(s.get("unlock_at_unix", 0)) > now_unix():
		return "locked"
	if bool(s.get("has_location_lock", false)):
		return "locked"
	if bool(s.get("has_magic_password", false)):
		return "password_unlocked_unread"
	return "unlocked_unread"


func _sort_rank(item: Dictionary) -> int:
	match str(item.get("state", "")):
		"friend_request":
			return 0
		"unlocked_unread", "password_unlocked_unread":
			return 1
		"locked":
			return 2
		_:
			return 3


func respond_friend_request(request_id: String, accept: bool) -> Dictionary:
	for i in friend_requests.size():
		var req: Dictionary = friend_requests[i]
		if str(req.id) != request_id:
			continue
		if str(req.recipient_id) != current_user_id:
			return {"ok": false, "error": "Not your request."}
		req.status = "accepted" if accept else "declined"
		friend_requests[i] = req
		if accept:
			friendships.append({
				"user_one_id": "demo-friend",
				"user_two_id": "demo-robert",
				"created_at": _iso(0),
			})
		return {"ok": true, "status": req.status}
	return {"ok": false, "error": "Request not found."}


func send_friend_request(query: String) -> Dictionary:
	var found := search_profiles(query)
	if found.is_empty():
		return {"ok": false, "error": "No matching user."}
	var target: Dictionary = found[0]
	if str(target.id) == current_user_id:
		return {"ok": false, "error": "You cannot friend yourself."}
	friend_requests.append({
		"id": "req-%d" % (friend_requests.size() + 1),
		"sender_id": current_user_id,
		"recipient_id": target.id,
		"status": "pending",
		"created_at": _iso(0),
		"kind": "friend_request",
	})
	return {"ok": true, "recipient": target}


func send_scroll(
	recipient_id: String,
	title: String,
	body: String,
	unlock_unix: int,
	magic_password: String = "",
	has_location_lock: bool = false,
	location_name: String = "",
	location_lat: float = 0.0,
	location_lng: float = 0.0,
	location_radius_m: int = 500,
	location_address: String = ""
) -> Dictionary:
	if body.strip_edges().is_empty() or body.length() > 5000:
		return {"ok": false, "error": "Invalid message length."}
	if unlock_unix < now_unix() - 5 or unlock_unix > now_unix() + 86400 * 365 * 5:
		return {"ok": false, "error": "Invalid unlock time."}
	if has_location_lock:
		if location_name.strip_edges().is_empty():
			return {"ok": false, "error": "Select a location from the search results or choose one on the map."}
		if absf(location_lat) > 90.0 or absf(location_lng) > 180.0:
			return {"ok": false, "error": "Invalid Location Lock coordinates."}
	var ok_friend := recipient_id == current_user_id
	if not ok_friend:
		var friends := get_friends()
		for f in friends:
			if str(f.id) == recipient_id:
				ok_friend = true
				break
	if not ok_friend:
		return {"ok": false, "error": "Recipient is not an accepted friend."}
	var id := "scroll-%d" % (scrolls.size() + 10)
	var meta := _meta(id, current_user_id, recipient_id, title.substr(0, 80), unlock_unix, not magic_password.is_empty(), 0)
	if not magic_password.is_empty():
		meta["_demo_password"] = magic_password
	meta["has_location_lock"] = has_location_lock
	meta["location_name"] = location_name.strip_edges()
	meta["location_address"] = location_address.strip_edges()
	meta["location_lat"] = location_lat
	meta["location_lng"] = location_lng
	meta["location_radius_m"] = location_radius_m
	scrolls.append(meta)
	scroll_bodies[id] = body
	_ensure_party_states(id, current_user_id, recipient_id)
	# Idempotent re-init must not duplicate.
	_ensure_party_states(id, current_user_id, recipient_id)
	var safe := _public_recipient_item(meta, recipient_states[id])
	safe.erase("_demo_password")
	return {"ok": true, "scroll": safe}


func open_scroll(
	scroll_id: String,
	magic_password: String = "",
	location_lat: float = NAN,
	location_lng: float = NAN
) -> Dictionary:
	for s in scrolls:
		if str(s.id) != scroll_id:
			continue
		if str(s.recipient_id) != current_user_id:
			return {"ok": false, "error": "Not your scroll.", "locked": false}
		var st: Dictionary = recipient_states.get(scroll_id, {})
		if st.is_empty():
			_ensure_party_states(scroll_id, str(s.sender_id), str(s.recipient_id))
			st = recipient_states[scroll_id]
		if st.get("deleted_at") != null:
			return {"ok": false, "error": "This scroll is no longer available."}
		if int(s.unlock_at_unix) > now_unix():
			return {
				"ok": false,
				"locked": true,
				"error": "This scroll is still sealed.",
				"unlock_at_unix": int(s.unlock_at_unix),
				"server_now_unix": now_unix(),
			}
		if bool(s.get("has_location_lock", false)):
			if is_nan(location_lat) or is_nan(location_lng):
				return {
					"ok": false,
					"locked": true,
					"location_required": true,
					"error": "Move near the locked place and allow location access to open this scroll.",
				}
			var tlat := float(s.get("location_lat", 0.0))
			var tlng := float(s.get("location_lng", 0.0))
			var radius := int(s.get("location_radius_m", 500))
			var dist := LocationHelper.haversine_m(location_lat, location_lng, tlat, tlng)
			if dist > float(radius):
				return {
					"ok": false,
					"locked": true,
					"location_locked": true,
					"distance_m": dist,
					"error": "You're %s from the unlock location." % LocationHelper.format_distance_away(dist),
				}
		if bool(s.has_magic_password):
			if not _password_allowed(scroll_id):
				return {"ok": false, "locked": false, "error": "Too many attempts. Try again later."}
			var expected := str(s.get("_demo_password", DEMO_PASSWORD))
			if magic_password != expected:
				_record_attempt(scroll_id, false)
				return {"ok": false, "locked": false, "error": "That magic password did not work."}
		_record_attempt(scroll_id, true)
		# Atomic permanent-state open: read + saved; first_opened once; last_opened always; count++
		if st.get("first_opened_at") == null:
			st["first_opened_at"] = _iso(0)
		st["last_opened_at"] = _iso(0)
		st["opened_count"] = int(st.get("opened_count", 0)) + 1
		st["is_read"] = true
		st["is_saved"] = true
		recipient_states[scroll_id] = st
		var body := str(scroll_bodies.get(scroll_id, ""))
		open_message_plaintext = body
		return {
			"ok": true,
			"locked": false,
			"message": body,
			"scroll": _public_recipient_item(s, st),
			"ephemeral": bool(s.has_magic_password),
		}
	return {"ok": false, "error": "Scroll not found."}


func set_scroll_favorite(scroll_id: String, is_favorite: bool) -> Dictionary:
	var st: Dictionary = recipient_states.get(scroll_id, {})
	if st.is_empty() or str(st.get("recipient_id", "")) != current_user_id:
		return {"ok": false, "error": "Not your scroll."}
	if st.get("deleted_at") != null:
		return {"ok": false, "error": "This scroll is no longer available."}
	st["is_favorite"] = is_favorite
	recipient_states[scroll_id] = st
	return {"ok": true, "recipient_state": st.duplicate(true)}


func delete_received_scroll(scroll_id: String) -> Dictionary:
	var st: Dictionary = recipient_states.get(scroll_id, {})
	if st.is_empty() or str(st.get("recipient_id", "")) != current_user_id:
		return {"ok": false, "error": "Not your scroll."}
	st["deleted_at"] = _iso(0)
	recipient_states[scroll_id] = st
	return {"ok": true, "soft_deleted": true, "physical_erasure": false}


func delete_sent_scroll(scroll_id: String) -> Dictionary:
	var st: Dictionary = sender_states.get(scroll_id, {})
	if st.is_empty() or str(st.get("sender_id", "")) != current_user_id:
		return {"ok": false, "error": "Not your sent scroll."}
	st["deleted_at"] = _iso(0)
	sender_states[scroll_id] = st
	return {"ok": true, "soft_deleted": true, "recalled": false, "physical_erasure": false}


func _password_allowed(scroll_id: String) -> bool:
	var arr: Array = password_attempts.get(scroll_id, [])
	var cutoff := now_unix() - 600
	var recent: Array = []
	for t in arr:
		if int(t) >= cutoff:
			recent.append(int(t))
	password_attempts[scroll_id] = recent
	return recent.size() < 5


func _record_attempt(scroll_id: String, success: bool) -> void:
	if success:
		return
	var arr: Array = password_attempts.get(scroll_id, [])
	arr.append(now_unix())
	password_attempts[scroll_id] = arr


func counts() -> Dictionary:
	var unread := 0
	var locked := 0
	var requests := 0
	for item in get_chest_items("all"):
		match str(item.get("state", "")):
			"unlocked_unread", "password_unlocked_unread":
				unread += 1
			"locked":
				locked += 1
			"friend_request":
				requests += 1
	return {
		"unread": unread,
		"locked": locked,
		"requests": requests,
		"saved": get_saved_scrolls().size(),
	}
