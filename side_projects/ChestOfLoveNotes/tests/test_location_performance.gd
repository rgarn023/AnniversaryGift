extends SceneTree
## Legacy + updated contracts for Location Lock / performance / UI polish.

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
	print("=== Location / Performance / UI Fix Tests ===")
	_test_location_lock_compose()
	await _test_location_draft_roundtrip()
	_test_chest_lid_animation()
	_test_ui_polish()
	_test_performance_contracts()
	_test_version()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_location_lock_compose() -> void:
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	_assert(compose.contains("_build_location_card"), "Compose Location Lock card present")
	_assert(compose.contains("has_location_lock"), "draft includes has_location_lock")
	_assert(compose.contains("location_lat"), "draft includes location_lat")
	_assert(compose.contains("Use Current Location"), "current location control")
	_assert(compose.contains("LocationSearchService"), "uses LocationSearchService")
	_assert(compose.contains("Unlock radius"), "Ready Check uses location summary")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains('"has_location_lock": has_location_lock'), "send payload includes location lock")
	_assert(main.contains("location_radius_m"), "send payload includes radius")
	var send := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	_assert(send.contains("has_location_lock"), "send-scroll accepts location lock")
	var open := FileAccess.get_file_as_string("res://supabase/functions/open-scroll/index.ts")
	_assert(open.contains("haversineMeters"), "open-scroll verifies proximity")
	_assert(open.contains("location_required"), "missing location does not unlock")
	_assert(FileAccess.file_exists("res://supabase/migrations/20260807220000_scroll_location_lock.sql"), "migration present")
	var helper := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	_assert(helper.contains("request_permission_if_needed"), "permission on demand")
	_assert(not helper.contains("cold start"), "docs avoid cold-start permission")
	var demo := FileAccess.get_file_as_string("res://scripts/demo/demo_session.gd")
	_assert(demo.contains("has_location_lock"), "demo supports location lock")


func _test_location_draft_roundtrip() -> void:
	var root := Control.new()
	root.size = Vector2(390, 844)
	get_root().add_child(root)
	var compose := ComposeScrollScreen.new()
	root.add_child(compose)
	var friends := [{"id": "f1", "display_name": "Mandy", "username": "mandycg93"}]
	compose.setup(friends, false)
	await process_frame
	compose._selected_friend = friends[0]
	compose._message_edit.text = "Meet me there"
	compose._location_toggle.button_pressed = true
	compose._sync_location_visibility()
	compose._apply_resolved_place({"name": "Favorite park", "address": "", "lat": 33.45, "lng": -112.07})
	compose._location_radius_m = 500
	compose._refresh_summary()
	var draft := compose.get_draft()
	_assert(bool(draft.has_location_lock), "draft location lock on")
	_assert(str(draft.location_name) == "Favorite park", "draft place name")
	_assert(compose._summary_label.text.contains("Favorite park") or compose._summary_label.text.contains("Location"), "summary reflects location lock")
	var compose2 := ComposeScrollScreen.new()
	root.add_child(compose2)
	compose2.setup(friends, false, draft)
	await process_frame
	var restored := compose2.get_draft()
	_assert(bool(restored.has_location_lock), "restored location lock")
	_assert(str(restored.location_name) == "Favorite park", "restored place name")
	_assert(is_equal_approx(float(restored.location_lat), 33.45), "restored lat")
	root.queue_free()


func _test_chest_lid_animation() -> void:
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_closed.png"), "closed plate packaged")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_open.png"), "open plate packaged")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest.contains("preload_assets"), "chest assets preloaded")
	_assert(chest.contains("FRAME_FILES"), "frame list present")
	_assert(chest.contains("_show_frame_progress"), "time-based frame progress")
	_assert(not chest.contains("LID_OPEN_SCALE_Y"), "broken foreshortening removed")
	_assert(chest.contains("_emerge_scroll"), "scroll emergence kept")
	_assert(chest.contains("play_open_empty_pulse"), "empty pulse kept")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads chest")
	_assert(main.contains("has_new"), "new-scroll gate kept")


func _test_ui_polish() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains('make_page_title("Friends"'), "Friends header standardized")
	_assert(main.contains('make_page_title("Sent"'), "Sent header standardized")
	_assert(main.contains('make_page_title("Profile"'), "Profile title in scroll")
	_assert(main.contains('make_page_title("Chest"'), "Chest header standardized")
	_assert(not main.contains('_make_button("Online Diagnostics"'), "Online Diagnostics removed from Profile")
	_assert(main.contains("_show_diagnostics"), "diagnostics code retained")
	_assert(main.contains("cache_is_fresh"), "soft cache on navigation")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	_assert(compose.contains("no redundant top Back"), "Compose back removed")
	_assert(not compose.contains('back.text = "←"'), "Compose dash/back icon removed")
	var ui := FileAccess.get_file_as_string("res://scripts/ui/mobile_ui.gd")
	_assert(ui.contains("TOUCH_NAV_H := 80"), "nav height increased")
	_assert(ui.contains("SIZE_NAV_LABEL := 16"), "nav label size increased")
	_assert(ui.contains("make_page_title"), "shared page title helper")


func _test_performance_contracts() -> void:
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_assert(proj.contains("run/max_fps=60"), "max fps 60")
	_assert(proj.contains("vsync_mode=1"), "vsync enabled")
	var celebration := FileAccess.get_file_as_string("res://scripts/ui/friends_celebration.gd")
	_assert(celebration.contains("PETAL_COUNT_NORMAL := 10"), "friends particles capped")
	_assert(celebration.contains("PETAL_COUNT_REDUCED := 0"), "reduced motion kills petals")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	_assert(compose.contains("shared chrome starfield"), "compose avoids second starfield blit")
	var plugin := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	_assert(plugin.contains("get_last_known_location"), "Android location plugin present")
	_assert(plugin.contains("Never polls GPS continuously") or plugin.contains("last-known"), "one-shot location")


func _test_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE >= 26, "versionCode >= 24")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("ChestOfLoveNotes-android-permissions-fix-debug.apk"), "APK filename")
	_assert(preset.contains("version/code=26"), "export versionCode 26")
	_assert(preset.contains("access_fine_location=true"), "fine location permission enabled")
