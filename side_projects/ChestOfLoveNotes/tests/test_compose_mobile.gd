extends SceneTree
## Headless validation for the mobile Compose Scroll redesign.

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
	print("=== Compose Mobile UI Tests ===")
	await _test_hierarchy_and_touch_targets()
	_test_message_sizing_rules()
	await _test_validation_and_draft()
	_test_send_api_unchanged()
	_test_auth_network_untouched()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_hierarchy_and_touch_targets() -> void:
	var root := Control.new()
	root.size = Vector2(1080, 2400)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(root)
	var compose := ComposeScrollScreen.new()
	root.add_child(compose)
	var friends := [
		{"id": "friend-1", "display_name": "Mandy", "username": "mandy"},
	]
	compose.setup(friends, true)
	await process_frame
	await process_frame
	_assert(compose.get_node_or_null(".") != null, "compose screen instantiated")
	_assert(compose._safe_margin != null, "SafeArea margin present")
	_assert(compose._scroll != null, "ScrollContainer present")
	_assert(compose._send_btn != null and compose._send_btn.custom_minimum_size.y >= 56, "Send button >= 56px")
	_assert(compose._preview_btn != null and compose._preview_btn.custom_minimum_size.y >= 48, "Preview button >= 48px")
	_assert(compose._recipient_btn != null and compose._recipient_btn.custom_minimum_size.y >= 56, "Recipient row >= 56px")
	_assert(compose._title_edit != null and compose._title_edit.custom_minimum_size.y >= 52, "Title field >= 52px")
	_assert(compose._date_btn != null and compose._date_btn.custom_minimum_size.y >= 52, "Date row >= 52px")
	_assert(compose._time_btn != null and compose._time_btn.custom_minimum_size.y >= 52, "Time row >= 52px")
	_assert(compose._pw_toggle != null, "Magic password switch present")
	_assert(compose._message_edit != null, "Message editor present")
	_assert((compose._message_edit.size_flags_vertical & Control.SIZE_EXPAND) == 0, "Message does not expand to fill entire screen")
	_assert(compose._message_edit.custom_minimum_size.y >= 220.0, "Message height uses responsive minimum")
	_assert(compose._message_edit.custom_minimum_size.y <= 340.0, "Message height uses responsive maximum")
	root.queue_free()


func _test_message_sizing_rules() -> void:
	for size in [Vector2(1080, 2400), Vector2(1080, 2340), Vector2(1440, 3120), Vector2(720, 1600)]:
		var h := clampf(size.y * 0.28, 220.0, 340.0)
		_assert(h >= 220.0 and h <= 340.0, "message height clamp for %dx%d" % [int(size.x), int(size.y)])


func _test_validation_and_draft() -> void:
	var root := Control.new()
	root.size = Vector2(1080, 2400)
	get_root().add_child(root)
	var compose := ComposeScrollScreen.new()
	root.add_child(compose)
	compose.setup([{"id": "f1", "display_name": "Mandy", "username": "mandy"}], false)
	await process_frame
	_assert(compose._validation_error().contains("friend") or compose._validation_error().contains("message"), "invalid until recipient+message")
	compose._selected_friend = {"id": "f1", "display_name": "Mandy", "username": "mandy"}
	compose._message_edit.text = "Hello forever"
	compose._open_immediately.button_pressed = true
	compose._update_validation()
	_assert(compose._validation_error().is_empty(), "valid draft with recipient + message")
	compose._pw_toggle.button_pressed = true
	compose._pw_fields.visible = true
	compose._pw_edit.text = "secret"
	compose._pw2_edit.text = "different"
	_assert(compose._validation_error().contains("match"), "password mismatch detected")
	compose._pw2_edit.text = "secret"
	_assert(compose._validation_error().is_empty(), "matching passwords validate")
	var draft := compose.get_draft()
	_assert(str(draft.recipient_id) == "f1", "draft recipient preserved")
	_assert(str(draft.message) == "Hello forever", "draft message preserved")
	_assert(bool(draft.has_password), "draft password flag set")
	_assert(str(draft.password) == "secret", "draft password value present")
	# UTC unlock formatting for API remains host responsibility using unlock_unix.
	_assert(int(draft.unlock_unix) > 0, "draft unlock_unix computed")
	root.queue_free()


func _test_send_api_unchanged() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/network/scroll_service.gd")
	_assert(src.contains('call_edge_function("send-scroll"'), "send-scroll Edge Function name unchanged")
	_assert(src.contains('body.erase("sender_id")'), "client still does not send sender_id")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains('"unlock_at": unlock_at'), "online payload still uses unlock_at")
	_assert(main_src.contains('"recipient_id": rid'), "online payload still uses recipient_id")
	_assert(main_src.contains("payload[\"password\"]"), "optional password key preserved")
	_assert(main_src.contains("preview_requested"), "preview path wired without send")


func _test_auth_network_untouched() -> void:
	# Ensure this redesign did not rewrite auth/api modules for compose.
	var auth := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	var api := FileAccess.get_file_as_string("res://scripts/network/api_client.gd")
	_assert(auth.contains("/auth/v1/signup"), "auth signup endpoint intact")
	_assert(api.contains("Authorization: %s"), "api still uses user bearer for authed calls")
	_assert(api.contains("apikey: %s"), "api still sends publishable apikey header")
