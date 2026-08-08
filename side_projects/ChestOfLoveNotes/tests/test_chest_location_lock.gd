extends SceneTree
## Regression: frame-based chest + searchable Location Lock.

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
	print("=== Chest Frame + Location Lock Tests ===")
	_test_chest_frames()
	await _test_location_compose()
	_test_search_architecture()
	_test_version()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_chest_frames() -> void:
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	_assert(chest.contains("FRAME_FILES"), "frame file list present")
	_assert(chest.contains("chest_closed.png"), "closed plate")
	_assert(chest.contains("chest_open_10.png"), "10% plate")
	_assert(chest.contains("chest_open.png"), "open plate")
	_assert(chest.contains("_show_frame_progress"), "elapsed-time frame progress")
	_assert(chest.contains("ChestAnimationRoot"), "stable animation root")
	_assert(chest.contains("ScrollSpawnPoint"), "scroll spawn point")
	_assert(chest.contains("OPEN_FPS"), "nominal FPS constant")
	_assert(not chest.contains("LID_OPEN_SCALE_Y"), "broken lid foreshortening removed")
	_assert(not chest.contains("LID_OPEN_TILT_DEG"), "broken lid tilt removed")
	_assert(not chest.contains("chest_lid.png"), "detached lid plate unused")
	_assert(chest.contains("preload_assets"), "preload retained")
	_assert(chest.contains("play_open_empty_pulse"), "empty pulse retained")
	_assert(chest.contains("_emerge_scroll"), "scroll emergence retained")
	_assert(chest.contains("only ONE plate") or chest.contains("ONE full-chest") or chest.contains("never two full chests"), "single plate policy")
	for f in ["chest_closed.png", "chest_open_10.png", "chest_open_25.png", "chest_ajar.png", "chest_half.png", "chest_open.png"]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % f), "asset " + f)


func _test_location_compose() -> void:
	var compose_src := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	_assert(compose_src.contains("Search for a place or address"), "search field caption")
	_assert(compose_src.contains("Choose on Map"), "map picker action")
	_assert(compose_src.contains("Use Current Location"), "current location action")
	_assert(compose_src.contains("LocationSearchService"), "search service used")
	_assert(compose_src.contains("MapLocationPicker"), "map picker used")
	_assert(compose_src.contains("Select a location from the search results"), "unselected text invalid")
	_assert(compose_src.contains("location_address"), "address in draft")
	_assert(compose_src.contains("RADIUS_OPTIONS") or compose_src.contains("Unlock radius"), "radius UI")
	_assert(compose_src.contains("_location_debounce"), "search debounce")

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
	## Free text alone must not validate.
	compose._location_search.text = "chesapeake"
	compose._location_fix_ok = false
	compose._update_validation()
	_assert(compose._validation_error().contains("Select a valid location"), "free text not enough")
	compose._apply_resolved_place({
		"name": "Elevation 27",
		"address": "Virginia Beach, VA",
		"lat": 36.84,
		"lng": -76.13,
	})
	compose._location_radius_m = 500
	var draft := compose.get_draft()
	_assert(bool(draft.has_location_lock), "draft lock on")
	_assert(str(draft.location_name) == "Elevation 27", "draft name")
	_assert(str(draft.location_address).contains("Virginia"), "draft address")
	_assert(bool(draft.location_fix_ok), "draft resolved")
	_assert(compose._summary_label.text.contains("Elevation 27"), "ready check location")
	_assert(compose._summary_label.text.contains("500"), "ready check radius")
	var compose2 := ComposeScrollScreen.new()
	root.add_child(compose2)
	compose2.setup(friends, false, draft)
	await process_frame
	var restored := compose2.get_draft()
	_assert(bool(restored.has_location_lock), "restored lock")
	_assert(str(restored.location_name) == "Elevation 27", "restored name")
	_assert(is_equal_approx(float(restored.location_lat), 36.84), "restored lat")
	root.queue_free()


func _test_search_architecture() -> void:
	_assert(FileAccess.file_exists("res://scripts/network/location_search_service.gd"), "search service")
	_assert(FileAccess.file_exists("res://scripts/ui/map_location_picker.gd"), "map picker")
	var search := FileAccess.get_file_as_string("res://scripts/network/location_search_service.gd")
	_assert(search.contains("DEBOUNCE_MS"), "debounce constant")
	_assert(search.contains("next_token"), "stale-result cancellation")
	_assert(search.contains("photon") or search.contains("Photon") or search.contains("PHOTON"), "photon provider")
	var helper := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	_assert(helper.contains("RADIUS_OPTIONS"), "radius options")
	_assert(helper.contains("evaluate_unlock_requirements"), "central unlock eval")
	_assert(helper.contains("MAX_ACCEPTABLE_ACCURACY_M"), "accuracy gate")
	_assert(FileAccess.file_exists("res://supabase/functions/search-places/index.ts"), "edge search-places")
	var open := FileAccess.get_file_as_string("res://supabase/functions/open-scroll/index.ts")
	_assert(open.contains("km away") or open.contains("away from"), "distance guidance")
	var send := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	_assert(send.contains("location_address"), "send-scroll persists location_address")
	_assert(send.contains("do not fold into name"), "no address fold into location_name")
	_assert(not send.contains("locationName = `${locationName}"), "no template fold of address")
	var meta := FileAccess.get_file_as_string("res://supabase/functions/_shared/scroll_meta.ts")
	_assert(meta.contains("location_address"), "scroll_meta exposes address")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains("Location Lock · within") or main.contains("location locked"), "preview location wording")
	_assert(main.contains("location_address"), "preview/send uses address field")
	_assert(main.contains("_dev_force_chest_scroll"), "debug new-scroll retained")
	_assert(main.contains("Location Lock: near"), "locked details show place name")
	var compose_full := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	_assert(compose_full.contains("HSlider"), "radius slider")
	_assert(compose_full.contains("_location_radius_edit"), "radius numeric entry")
	_assert(compose_full.contains("Add Photo"), "attachments section")
	_assert(compose_full.contains("_make_optional_header"), "collapsible optional sections")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	_assert(viewer.contains("✕ Close") or viewer.contains("Close"), "preview close control")
	_assert(viewer.contains("_scroll_unit"), "unified scroll visual root")
	_assert(FileAccess.file_exists("res://supabase/migrations/20260808040000_scroll_attachments_and_radius.sql"), "attachments migration")


func _test_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE >= 18, "versionCode >= 18")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("ChestOfLoveNotes-send-map-preview-picker-fixes-debug.apk"), "APK name")
	_assert(preset.contains("version/code=18"), "export 18")
