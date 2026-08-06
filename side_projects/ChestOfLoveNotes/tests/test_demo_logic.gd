extends SceneTree
## Headless tests for LOCAL DEMO MODE chest/friend/scroll logic.

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
	var chest := demo.get_chest_items("all")
	_assert(chest.size() >= 4, "chest has multiple items")
	var locked := demo.get_chest_items("locked")
	_assert(locked.size() >= 1, "has locked scroll")
	var locked_id := str(locked[0].id)
	var early := demo.open_scroll(locked_id)
	_assert(bool(early.get("locked", false)), "locked scroll rejects early open")
	_assert(not early.has("message") or str(early.get("message", "")).is_empty(), "no body before unlock")

	demo.advance_minutes(120)
	var unlocked_now := demo.open_scroll(locked_id)
	_assert(bool(unlocked_now.get("ok", false)), "scroll opens after demo time advance")

	var magic_id := ""
	for item in demo.get_chest_items("all"):
		if bool(item.get("has_magic_password", false)):
			magic_id = str(item.id)
			break
	_assert(not magic_id.is_empty(), "password scroll present")
	var bad := demo.open_scroll(magic_id, "wrong")
	_assert(not bool(bad.get("ok", false)), "wrong password rejected")
	var good := demo.open_scroll(magic_id, DemoSession.DEMO_PASSWORD)
	_assert(bool(good.get("ok", false)), "correct password accepted")
	_assert(bool(good.get("ephemeral", false)), "password scroll marked ephemeral")

	var again_bad := demo.open_scroll(magic_id, "nope")
	_assert(not bool(again_bad.get("ok", false)), "reopen still requires password")

	var self_req := demo.send_friend_request("robert_demo")
	_assert(not bool(self_req.get("ok", false)), "cannot friend self")

	for i in 5:
		demo.open_scroll(magic_id, "bad-%d" % i)
	var limited := demo.open_scroll(magic_id, DemoSession.DEMO_PASSWORD)
	_assert(not bool(limited.get("ok", false)), "password attempts rate-limited")

	# Ensure main script parses / global classes resolve.
	_assert(ClassDB.class_exists("HTTPRequest"), "engine HTTPRequest available")
	_assert(ResourceLoader.exists("res://scenes/Main.tscn"), "Main.tscn exists")
	_assert(ResourceLoader.exists("res://assets/icons/app_icon_1024.png"), "app icon exists")
	_assert(not ResourceLoader.exists("res://assets/documents/anniversary_gift.pdf"), "anniversary PDF not present in COLN")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
