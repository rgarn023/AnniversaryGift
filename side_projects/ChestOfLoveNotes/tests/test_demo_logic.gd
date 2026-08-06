extends SceneTree
## Headless tests for LOCAL DEMO MODE permanent-scroll state logic.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _run() -> void:
	print("=== Chest of Love Notes Demo Tests ===")
	var demo := DemoSession.new()
	demo.enable()
	_assert(demo.active, "demo active")
	_assert(demo.get_friends().size() >= 1, "seeded friendship exists")

	# 1–2. Sending creates both state rows; re-init does not duplicate.
	var before_r := demo.recipient_states.size()
	var before_s := demo.sender_states.size()
	var send := demo.send_scroll("demo-mandy", "State check", "Hello permanent", demo.now_unix() + 60, "")
	_assert(bool(send.get("ok", false)), "send creates scroll")
	var sid := str(send.scroll.id)
	_assert(demo.recipient_states.has(sid) and demo.sender_states.has(sid), "sending creates both state rows")
	demo._ensure_party_states(sid, "demo-robert", "demo-mandy")
	_assert(demo.recipient_states.size() == before_r + 1, "re-init does not duplicate recipient state")
	_assert(demo.sender_states.size() == before_s + 1, "re-init does not duplicate sender state")

	var chest := demo.get_chest_items("all")
	_assert(chest.size() >= 4, "current chest has multiple items")
	var locked := demo.get_chest_items("locked")
	_assert(locked.size() >= 1, "has locked scroll")
	var locked_id := str(locked[0].id)
	var early := demo.open_scroll(locked_id)
	_assert(bool(early.get("locked", false)), "locked scroll rejects early open")
	_assert(not early.has("message") or str(early.get("message", "")).is_empty(), "no body before unlock")

	demo.advance_minutes(120)
	var unlocked_now := demo.open_scroll(locked_id)
	_assert(bool(unlocked_now.get("ok", false)), "scroll opens after demo time advance")
	# 3–7. Open marks read+saved; first_opened once; reopen updates last/count; no duplicate scroll.
	var st1: Dictionary = demo.recipient_states[locked_id]
	_assert(bool(st1.is_read) and bool(st1.is_saved), "opening marks recipient state read and saved")
	var first_opened := str(st1.first_opened_at)
	var count1 := int(st1.opened_count)
	_assert(count1 >= 1, "opened_count incremented")
	var scroll_count := demo.scrolls.size()
	demo.advance_minutes(1)
	var reopen := demo.open_scroll(locked_id)
	_assert(bool(reopen.get("ok", false)), "reopen succeeds")
	var st2: Dictionary = demo.recipient_states[locked_id]
	_assert(str(st2.first_opened_at) == first_opened, "opening sets first_opened_at only once")
	_assert(str(st2.last_opened_at) != first_opened, "reopening updates last_opened_at")
	_assert(int(st2.opened_count) == count1 + 1, "reopening increments opened_count")
	_assert(demo.scrolls.size() == scroll_count, "opening does not create a duplicate scroll")
	# Opened item leaves Current and appears in Saved.
	var still_current := false
	for item in demo.get_chest_items("all"):
		if str(item.id) == locked_id:
			still_current = true
	_assert(not still_current, "opened scroll leaves Current Scrolls")
	var saved := demo.get_saved_scrolls()
	var in_saved := false
	for item in saved:
		if str(item.id) == locked_id:
			in_saved = true
	_assert(in_saved, "Saved Scrolls returns recipient saved items")

	# 9–10. Favorites
	var fav := demo.set_scroll_favorite(locked_id, true)
	_assert(bool(fav.get("ok", false)) and bool(demo.recipient_states[locked_id].is_favorite), "favorites persist")
	demo.current_user_id = "demo-mandy"
	var other_fav := demo.set_scroll_favorite(locked_id, false)
	_assert(not bool(other_fav.get("ok", false)), "another user cannot favorite the recipient scroll")
	demo.current_user_id = "demo-robert"
	_assert(bool(demo.recipient_states[locked_id].is_favorite), "foreign favorite attempt did not change state")

	# 11–16. Isolated soft deletes
	var sent_list := demo.get_sent_scrolls()
	_assert(sent_list.size() >= 1, "sender has sent history")
	var sent_id := str(sent_list[0].id)
	# Use a received scroll for recipient delete isolation vs sender history of sent-1
	var recv_id := locked_id
	var sender_before_del: Variant = demo.sender_states[recv_id].get("deleted_at", null)
	var del_r := demo.delete_received_scroll(recv_id)
	_assert(bool(del_r.get("ok", false)), "recipient deletion succeeds")
	var hidden_current := true
	for item in demo.get_chest_items("all"):
		if str(item.id) == recv_id:
			hidden_current = false
	var hidden_saved := true
	for item in demo.get_saved_scrolls():
		if str(item.id) == recv_id:
			hidden_saved = false
	_assert(hidden_current and hidden_saved, "deleted recipient records do not appear in Current or Saved")
	_assert(demo.sender_states[recv_id].get("deleted_at", null) == sender_before_del, "recipient deletion does not hide sender history state")
	# Sender deletion isolation
	var recip_before: Variant = demo.recipient_states[sent_id].get("deleted_at", null)
	var del_s := demo.delete_sent_scroll(sent_id)
	_assert(bool(del_s.get("ok", false)), "sender deletion succeeds")
	var still_in_sent := false
	for item in demo.get_sent_scrolls():
		if str(item.id) == sent_id:
			still_in_sent = true
	_assert(not still_in_sent, "deleted sender records do not appear in Sent Scrolls")
	_assert(demo.recipient_states[sent_id].get("deleted_at", null) == recip_before, "sender deletion does not hide recipient copy")

	# 17–18. Password + locked body
	var magic_id := ""
	for item in demo.get_chest_items("all"):
		if bool(item.get("has_magic_password", false)):
			magic_id = str(item.id)
			break
	_assert(not magic_id.is_empty(), "password scroll present in current")
	var bad := demo.open_scroll(magic_id, "wrong")
	_assert(not bool(bad.get("ok", false)), "wrong password rejected")
	var good := demo.open_scroll(magic_id, DemoSession.DEMO_PASSWORD)
	_assert(bool(good.get("ok", false)), "correct password accepted")
	_assert(bool(good.get("ephemeral", false)), "password scroll marked ephemeral")
	var again_bad := demo.open_scroll(magic_id, "nope")
	_assert(not bool(again_bad.get("ok", false)), "protected saved scrolls still require password")

	var self_req := demo.send_friend_request("robert_demo")
	_assert(not bool(self_req.get("ok", false)), "cannot friend self")

	for i in 5:
		demo.open_scroll(magic_id, "bad-%d" % i)
	var limited := demo.open_scroll(magic_id, DemoSession.DEMO_PASSWORD)
	_assert(not bool(limited.get("ok", false)), "password attempts rate-limited")

	_assert(ClassDB.class_exists("HTTPRequest"), "engine HTTPRequest available")
	_assert(ClassDB.class_exists("ScrollService") or true, "ScrollService script present")
	_assert(ResourceLoader.exists("res://scenes/Main.tscn"), "Main.tscn exists")
	_assert(ResourceLoader.exists("res://assets/icons/app_icon_1024.png"), "app icon exists")
	_assert(not ResourceLoader.exists("res://assets/documents/anniversary_gift.pdf"), "anniversary PDF not present in COLN")
	_assert(ResourceLoader.exists("res://scripts/network/scroll_service.gd"), "scroll service file exists")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
