extends SceneTree
## Regression contracts for profile restore, Compose draft/scheduling, Sent hide, chest paths.

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
	print("=== Profile / Compose / Sent / Chest Fix Tests ===")
	_test_profile_state_machine()
	await _test_compose_draft_and_open_immediately()
	_test_sent_hide_restore_contracts()
	_test_chest_empty_and_new_scroll_contracts()
	_test_main_wiring()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_profile_state_machine() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/network/profile_service.gd")
	_assert(src.contains("enum ProfileState"), "ProfileState enum present")
	_assert(src.contains("UNKNOWN"), "UNKNOWN state")
	_assert(src.contains("LOADING"), "LOADING state")
	_assert(src.contains("EXISTS"), "EXISTS state")
	_assert(src.contains("NOT_CREATED"), "NOT_CREATED state")
	_assert(src.contains("ERROR"), "ERROR state")
	_assert(src.contains("hydrate_from_cache"), "local profile cache hydrate")
	_assert(src.contains("soft_fail"), "soft fail distinguished from missing")
	_assert(src.contains("definitive"), "definitive missing flag")
	_assert(src.contains("Keep showing known profile while refreshing"), "does not blank profile before every fetch")
	var app := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	_assert(app.contains("hydrate_from_cache"), "restore hydrates cache first")
	_assert(app.contains("profile_assumed_exists_soft_fail") or app.contains("has_known_profile"), "soft fail does not force onboarding")
	_assert(app.contains("is_definitively_missing") or app.contains("NOT_CREATED"), "only definitive miss → create profile")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("is_definitively_missing"), "startup/sign-in gate uses definitive miss")
	_assert(main.contains("has_known_profile"), "known profile bypasses Create screen")


func _test_compose_draft_and_open_immediately() -> void:
	var root := Control.new()
	root.size = Vector2(390, 844)
	get_root().add_child(root)
	var compose := ComposeScrollScreen.new()
	compose.bottom_chrome_inset = 90
	root.add_child(compose)
	var friends := [
		{"id": "f1", "display_name": "Mandy", "username": "mandycg93"},
		{
			"id": "f2",
			"display_name": "Very Long Display Name Example",
			"username": "super_long_username_that_should_ellipsis",
		},
	]
	compose.setup(friends, false)
	await process_frame
	compose._selected_friend = friends[1]
	compose._refresh_recipient_row()
	compose._title_edit.text = "Anniversary"
	compose._message_edit.text = "Line one\nLine two"
	compose._open_immediately.button_pressed = false
	compose._sync_delivery_visibility()
	compose._pw_toggle.button_pressed = true
	compose._pw_fields.visible = true
	compose._pw_edit.text = "rose"
	compose._pw2_edit.text = "rose"
	var draft := compose.get_draft()
	_assert(str(draft.recipient_id) == "f2", "draft stores selected recipient")
	_assert(str(draft.title) == "Anniversary", "draft stores title")
	_assert(str(draft.message).contains("Line two"), "draft stores body")
	_assert(not bool(draft.open_immediately), "draft stores scheduled mode")
	_assert(bool(draft.has_password), "draft stores magic password flag")
	_assert(compose._delivery_controls.visible == true, "schedule controls visible when not immediate")
	compose._open_immediately.button_pressed = true
	compose._sync_delivery_visibility()
	_assert(compose._delivery_controls.visible == false, "Open Immediately hides date/time")
	_assert(compose.get_draft().open_immediately == true, "immediate mode in draft")
	_assert(compose._summary_label.text.contains("Immediately"), "Ready Check says Immediately")
	_assert(compose._recipient_btn.clip_text == true, "recipient row clips/ellipsizes")
	_assert(compose.clip_contents == true, "compose clips horizontal overflow")

	var compose2 := ComposeScrollScreen.new()
	root.add_child(compose2)
	compose2.setup(friends, false, draft)
	await process_frame
	var restored := compose2.get_draft()
	_assert(str(restored.recipient_id) == "f2", "apply_draft restores recipient")
	_assert(str(restored.title) == "Anniversary", "apply_draft restores title")
	_assert(str(restored.message).contains("Line two"), "apply_draft restores message")
	_assert(bool(restored.has_password), "apply_draft restores password flag")
	_assert(str(restored.password) == "rose", "apply_draft restores password value")
	root.queue_free()

	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("_persist_compose_draft_if_needed"), "main persists compose draft on nav")
	_assert(main.contains("draft_to_restore"), "compose restores draft on show")
	_assert(main.contains("_clear_compose_draft"), "draft cleared after send/sign-out")
	_assert(main.contains("open_immediately"), "send path respects Open Immediately")


func _test_sent_hide_restore_contracts() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("_hide_sent_with_undo"), "hide with undo helper")
	_assert(main.contains('action_label: String = ""'), "snackbar action support")
	_assert(main.contains("Hidden (%d)") or main.contains("Hidden"), "Hidden Sent section")
	_assert(main.contains("unhide_sent_scroll_local"), "restore/unhide path")
	_assert(main.contains("hide_sent_scroll_local"), "local hide persistence")
	var app := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	_assert(app.contains("SENT_HIDDEN_PATH"), "hidden sent persisted path")
	_assert(app.contains("persist_hidden_sent"), "persist hidden sent")
	_assert(app.contains("load_hidden_sent"), "load hidden sent on restore")


func _test_chest_empty_and_new_scroll_contracts() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest.contains("emerge_scroll: bool = false"), "scroll emerge gated by flag")
	_assert(chest.contains("play_open_empty_pulse"), "empty already-open pulse")
	_assert(chest.contains("_show_frame_progress"), "frame progress open")
	_assert(chest.contains("FRAME_FILES"), "frame file list")
	_assert(not chest.contains("FRAME_KEYS"), "static pose table removed")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("has_new"), "main distinguishes new-scroll path")
	_assert(main.contains("_dev_force_chest_scroll"), "debug new-scroll test path")
	_assert(main.contains("Preview Chest Scroll Open"), "debug-only preview action")
	_assert(main.contains("OS.is_debug_build()"), "debug path gated")
	_assert(main.contains("No new scrolls today"), "empty message")
	_assert(BuildFlags.DEV_CHEST_SCROLL_PREVIEW == false, "fake scroll disabled in normal builds")


func _test_main_wiring() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("_nav_content_inset"), "global nav content inset")
	_assert(main.contains("bottom_chrome_inset"), "compose bottom chrome inset")
	_assert(BuildFlags.APP_VERSION_CODE >= 24, "versionCode bumped for this fix pass")
