extends RefCounted
class_name DemoSession
## LOCAL DEMO MODE — fictional accounts and scrolls for offline UI testing.
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
var sent_scrolls: Array[Dictionary] = []
var password_attempts: Dictionary = {} ## scroll_id -> Array[unix]


func enable() -> void:
	active = true
	_seed()


func disable() -> void:
	active = false
	clear_sensitive()


func clear_sensitive() -> void:
	scroll_bodies.clear()
	password_attempts.clear()


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
	var unlocked_id := "scroll-open-now"
	var locked_id := "scroll-locked-soon"
	var protected_id := "scroll-magic"
	var opened_id := "scroll-opened"
	scrolls = [
		{
			"id": unlocked_id,
			"sender_id": "demo-mandy",
			"recipient_id": "demo-robert",
			"title": "For tonight",
			"unlock_at_unix": simulated_now_unix - 120,
			"has_magic_password": false,
			"created_at": _iso(-7200),
			"first_opened_at": null,
			"opened_count": 0,
			"kind": "love_note",
			"state": "unlocked_unread",
		},
		{
			"id": locked_id,
			"sender_id": "demo-mandy",
			"recipient_id": "demo-robert",
			"title": "A tomorrow note",
			"unlock_at_unix": simulated_now_unix + 3600,
			"has_magic_password": false,
			"created_at": _iso(-5400),
			"first_opened_at": null,
			"opened_count": 0,
			"kind": "love_note",
			"state": "locked",
		},
		{
			"id": protected_id,
			"sender_id": "demo-mandy",
			"recipient_id": "demo-robert",
			"title": "Sealed with starlight",
			"unlock_at_unix": simulated_now_unix - 60,
			"has_magic_password": true,
			"created_at": _iso(-4000),
			"first_opened_at": null,
			"opened_count": 0,
			"kind": "love_note",
			"state": "password_unlocked_unread",
		},
		{
			"id": opened_id,
			"sender_id": "demo-mandy",
			"recipient_id": "demo-robert",
			"title": "Yesterday's note",
			"unlock_at_unix": simulated_now_unix - 86400,
			"has_magic_password": false,
			"created_at": _iso(-90000),
			"first_opened_at": _iso(-80000),
			"opened_count": 2,
			"kind": "love_note",
			"state": "opened",
		},
	]
	scroll_bodies = {
		unlocked_id: "This note is available now. The chest can hold many scrolls at once — unlocked, locked, and sealed.",
		locked_id: "You should not see this body until the simulated unlock time advances.",
		protected_id: "The magic password worked. In production this text is decrypted only after server checks.",
		opened_id: "An older note that was already opened. It remains in chest history.",
	}
	sent_scrolls = [
		{
			"id": "sent-1",
			"sender_id": "demo-robert",
			"recipient_id": "demo-mandy",
			"title": "From Robert",
			"unlock_at_unix": simulated_now_unix + 7200,
			"has_magic_password": false,
			"created_at": _iso(-600),
			"opened_count": 0,
		}
	]


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
		var item := s.duplicate(true)
		item["sender_display_name"] = get_profile(str(s.sender_id)).get("display_name", "Friend")
		item["state"] = _derive_state(s)
		items.append(item)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sort_rank(a) < _sort_rank(b)
	)
	if filter_name == "all":
		return items
	var filtered: Array[Dictionary] = []
	for item in items:
		var st := str(item.get("state", ""))
		match filter_name:
			"unread":
				if st in ["unlocked_unread", "password_unlocked_unread"]:
					filtered.append(item)
			"locked":
				if st == "locked":
					filtered.append(item)
			"opened":
				if st == "opened":
					filtered.append(item)
			"requests":
				if st == "friend_request":
					filtered.append(item)
	return filtered


func _derive_state(s: Dictionary) -> String:
	if int(s.get("opened_count", 0)) > 0 and s.get("first_opened_at") != null:
		return "opened"
	if int(s.get("unlock_at_unix", 0)) > now_unix():
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
				"user_one_id": "demo-friend" if current_user_id == "demo-robert" else current_user_id,
				"user_two_id": current_user_id if current_user_id != "demo-friend" else "demo-robert",
				"created_at": _iso(0),
			})
			# Normalize for demo-friend + robert
			friendships[friendships.size() - 1] = {
				"user_one_id": "demo-friend",
				"user_two_id": "demo-robert",
				"created_at": _iso(0),
			}
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


func send_scroll(recipient_id: String, title: String, body: String, unlock_unix: int, magic_password: String = "") -> Dictionary:
	if body.strip_edges().is_empty() or body.length() > 5000:
		return {"ok": false, "error": "Invalid message length."}
	if unlock_unix < now_unix() - 5 or unlock_unix > now_unix() + 86400 * 365 * 5:
		return {"ok": false, "error": "Invalid unlock time."}
	var friends := get_friends()
	var ok_friend := false
	for f in friends:
		if str(f.id) == recipient_id:
			ok_friend = true
			break
	if not ok_friend:
		return {"ok": false, "error": "Recipient is not an accepted friend."}
	var id := "scroll-%d" % (scrolls.size() + 10)
	var meta := {
		"id": id,
		"sender_id": current_user_id,
		"recipient_id": recipient_id,
		"title": title.substr(0, 80),
		"unlock_at_unix": unlock_unix,
		"has_magic_password": not magic_password.is_empty(),
		"created_at": _iso(0),
		"first_opened_at": null,
		"opened_count": 0,
		"kind": "love_note",
		"state": "locked" if unlock_unix > now_unix() else "unlocked_unread",
		"_demo_password": magic_password,
	}
	scrolls.append(meta)
	scroll_bodies[id] = body
	sent_scrolls.append(meta.duplicate(true))
	var safe := meta.duplicate(true)
	safe.erase("_demo_password")
	return {"ok": true, "scroll": safe}


func open_scroll(scroll_id: String, magic_password: String = "") -> Dictionary:
	for i in scrolls.size():
		var s: Dictionary = scrolls[i]
		if str(s.id) != scroll_id:
			continue
		if str(s.recipient_id) != current_user_id:
			return {"ok": false, "error": "Not your scroll.", "locked": false}
		if int(s.unlock_at_unix) > now_unix():
			return {
				"ok": false,
				"locked": true,
				"error": "This scroll is still sealed.",
				"unlock_at_unix": int(s.unlock_at_unix),
				"server_now_unix": now_unix(),
			}
		if bool(s.has_magic_password):
			if not _password_allowed(scroll_id):
				return {"ok": false, "locked": false, "error": "Too many attempts. Try again later."}
			var expected := str(s.get("_demo_password", DEMO_PASSWORD))
			if magic_password != expected:
				_record_attempt(scroll_id, false)
				return {"ok": false, "locked": false, "error": "That magic password did not work."}
		_record_attempt(scroll_id, true)
		if s.get("first_opened_at") == null:
			s.first_opened_at = _iso(0)
		s.opened_count = int(s.get("opened_count", 0)) + 1
		s.state = "opened"
		scrolls[i] = s
		var body := str(scroll_bodies.get(scroll_id, ""))
		return {
			"ok": true,
			"locked": false,
			"message": body,
			"scroll": _public_scroll(s),
			"ephemeral": bool(s.has_magic_password),
		}
	return {"ok": false, "error": "Scroll not found."}


func _public_scroll(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	out.erase("_demo_password")
	out["sender_display_name"] = get_profile(str(s.sender_id)).get("display_name", "Friend")
	out["state"] = _derive_state(out)
	return out


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
	return {"unread": unread, "locked": locked, "requests": requests}
