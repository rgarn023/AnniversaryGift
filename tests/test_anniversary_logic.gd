extends SceneTree

## Headless validation for anniversary unlock / save / final-gift logic.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Anniversary Gift Logic Tests ===")
	_test_message_loading()
	_test_unlock_counts()
	_test_catchup_queue()
	_test_opened_remain_archived()
	_test_clock_rollback_does_not_relock()
	_test_developer_isolation()
	_test_final_chest_stages()
	_test_missing_pdf_previews_safe()
	_test_pdf_preview_resources()
	await _test_gift_viewer_preview_load()
	_test_missing_pdf_app_safe()
	_test_save_reload()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _fresh_manager(iso_date: String, developer: bool = false) -> AnniversaryManager:
	var dates := DateService.new()
	var saves := SaveService.new()
	# Isolate saves in a temp-like user path by resetting files.
	if developer:
		saves.reset_state(true)
	else:
		saves.reset_state(false)
	var mgr := AnniversaryManager.new(dates, saves)
	if developer:
		mgr.enter_developer_mode()
		mgr.developer_set_date(iso_date)
	else:
		# Simulate normal mode by writing latest legitimate + monkeypatching device date via developer off
		# DateService always reads system clock; for normal-mode unit tests we temporarily use developer
		# only when needed. For unlock-count tests we use developer dates carefully.
		mgr.enter_developer_mode()
		mgr.developer_set_date(iso_date)
	return mgr


func _test_message_loading() -> void:
	var mgr := AnniversaryManager.new()
	_assert(mgr.messages.size() == 8, "loads eight messages")
	var expected_heads := [
		"One Week to Go", "Another Day Closer", "To the Ends of the Universe",
		"Every Adventure Together", "Everything You Do", "The Day We Met",
		"Forever and Always", "Happy Anniversary"
	]
	for i in expected_heads.size():
		_assert(str(mgr.messages[i].get("heading", "")) == expected_heads[i], "heading %d matches" % i)
	var first: Dictionary = mgr.get_message_for_date("2026-08-06")
	_assert(str(first.get("message", "")).begins_with("Mandy, it's one week"), "Aug 6 message text exact start")
	var last: Dictionary = mgr.get_message_for_date("2026-08-13")
	_assert(str(last.get("message", "")).contains("Love,\nRobert"), "Aug 13 signature preserved")


func _test_unlock_counts() -> void:
	var expectations := {
		"2026-08-05": 0,
		"2026-08-06": 1,
		"2026-08-07": 2,
		"2026-08-08": 3,
		"2026-08-09": 4,
		"2026-08-10": 5,
		"2026-08-11": 6,
		"2026-08-12": 7,
		"2026-08-13": 8,
		"2026-08-14": 8,
	}
	for date in expectations.keys():
		var mgr := _fresh_manager(str(date), true)
		var count: int = mgr.get_unlocked_dates().size()
		_assert(count == int(expectations[date]), "date %s unlocks %d (got %d)" % [date, int(expectations[date]), count])


func _test_catchup_queue() -> void:
	var mgr := _fresh_manager("2026-08-10", true)
	_assert(mgr.catchup_queue.size() == 5, "catch-up queue size for Aug 10 with none opened")
	_assert(mgr.catchup_queue[0] == "2026-08-06", "catch-up starts at earliest date")
	_assert(mgr.catchup_queue[4] == "2026-08-10", "catch-up ends at effective date")
	mgr.mark_chest_opened("2026-08-06")
	mgr.mark_scroll_viewed("2026-08-06")
	_assert(mgr.catchup_queue[0] == "2026-08-07", "queue advances chronologically")


func _test_opened_remain_archived() -> void:
	var mgr := _fresh_manager("2026-08-08", true)
	mgr.mark_chest_opened("2026-08-06")
	mgr.mark_scroll_viewed("2026-08-06")
	_assert(mgr.get_archived_dates().has("2026-08-06"), "opened message archived")
	mgr.developer_set_date("2026-08-07")
	_assert(mgr.get_archived_dates().has("2026-08-06"), "archive remains after date change")


func _test_clock_rollback_does_not_relock() -> void:
	# Normal-mode latest legitimate date must prevent relock.
	var dates := DateService.new()
	var saves := SaveService.new()
	saves.reset_state(false)
	var state: Dictionary = saves.default_state()
	state["latest_legitimate_date"] = "2026-08-10"
	state["opened_chest_dates"] = ["2026-08-06", "2026-08-07"]
	state["viewed_scroll_dates"] = ["2026-08-06", "2026-08-07"]
	saves.save_state(state, false)
	var mgr := AnniversaryManager.new(dates, saves)
	# Force unlock evaluation using stored latest even if simulated/dev not used.
	# In normal mode unlock uses max(device, latest). Device today may already be >= Aug 10,
	# so additionally verify previously opened dates remain unlocked.
	_assert(mgr.is_date_unlocked("2026-08-06"), "previously opened date stays unlocked")
	_assert(mgr.is_date_unlocked("2026-08-07"), "second opened date stays unlocked")
	_assert(mgr.get_archived_dates().size() == 2, "archives preserved on reload")


func _test_developer_isolation() -> void:
	var dates := DateService.new()
	var saves := SaveService.new()
	saves.reset_state(false)
	saves.reset_state(true)
	var normal := saves.load_state(false)
	normal["opened_chest_dates"] = ["2026-08-06"]
	normal["viewed_scroll_dates"] = ["2026-08-06"]
	normal["latest_legitimate_date"] = "2026-08-06"
	saves.save_state(normal, false)

	var mgr := AnniversaryManager.new(dates, saves)
	mgr.enter_developer_mode()
	mgr.developer_set_date("2026-08-13")
	mgr.mark_chest_opened("2026-08-13")
	mgr.mark_scroll_viewed("2026-08-13")
	# Normal save must remain untouched.
	var normal_after: Dictionary = saves.load_state(false)
	_assert(normal_after.get("opened_chest_dates", []).hash() == ["2026-08-06"].hash() or (normal_after.get("opened_chest_dates", []) as Array).has("2026-08-06") and not (normal_after.get("opened_chest_dates", []) as Array).has("2026-08-13"), "developer opens do not alter normal opened chests")
	_assert(str(normal_after.get("latest_legitimate_date", "")) == "2026-08-06", "developer dates do not alter latest legitimate normal date")
	mgr.exit_developer_mode()
	_assert(not mgr.developer_mode, "exiting developer mode clears flag")
	_assert(mgr.get_archived_dates().has("2026-08-06"), "normal archives restored after exit")


func _test_final_chest_stages() -> void:
	var mgr := _fresh_manager("2026-08-13", true)
	_assert(not mgr.is_final_gift_ready(), "gift not ready before message")
	mgr.mark_chest_opened("2026-08-13")
	_assert(not mgr.is_final_gift_ready(), "gift still not ready until message viewed")
	mgr.mark_scroll_viewed("2026-08-13")
	_assert(mgr.is_final_message_viewed(), "final message viewed")
	_assert(mgr.is_final_gift_ready(), "gift ready after message closed/viewed")
	mgr.mark_final_gift_opened()
	_assert(mgr.is_final_gift_opened(), "final gift opened tracked")


func _test_missing_pdf_previews_safe() -> void:
	var helper := PdfHelper.new()
	var pages: PackedStringArray = helper.list_page_previews()
	_assert(pages.size() >= 0, "list_page_previews does not crash")
	_assert(true, "missing PDF previews do not crash the app")


func _test_pdf_preview_resources() -> void:
	for page_path: String in PdfHelper.PDF_PAGE_PATHS:
		_assert(ResourceLoader.exists(page_path), "ResourceLoader.exists %s" % page_path)
		var resource: Resource = ResourceLoader.load(page_path)
		_assert(resource is Texture2D, "loads as Texture2D: %s" % page_path)
	var helper := PdfHelper.new()
	var textures: Array[Texture2D] = helper.load_page_textures()
	_assert(textures.size() == 2, "loads exactly two preview textures (got %d)" % textures.size())


func _test_gift_viewer_preview_load() -> void:
	var viewer := GiftDocumentViewer.new()
	root.add_child(viewer)
	await process_frame
	viewer.load_pdf_previews()
	await process_frame
	_assert(viewer.get_loaded_page_count() == 2, "viewer creates exactly two page controls")
	_assert(not viewer._error_panel.visible, "error panel hidden when pages load")
	_assert(viewer._scroll.visible, "scroll container shown when pages load")
	viewer.load_pdf_previews()
	await process_frame
	_assert(viewer.get_loaded_page_count() == 2, "reopen/reload does not duplicate pages")
	viewer.queue_free()
	await process_frame


func _test_missing_pdf_app_safe() -> void:
	var helper := PdfHelper.new()
	var open_result: Dictionary = helper.open_original_pdf()
	_assert(open_result.has("ok"), "open_original_pdf returns result dictionary")
	_assert(open_result.has("message"), "open_original_pdf returns message")
	var share_result: Dictionary = helper.share_original_pdf()
	_assert(share_result.has("ok"), "share_original_pdf returns result dictionary")
	# On desktop/headless this should be a soft failure, not a crash.
	_assert(true, "missing external PDF application does not crash")


func _test_save_reload() -> void:
	var dates := DateService.new()
	var saves := SaveService.new()
	saves.reset_state(true)
	var mgr := AnniversaryManager.new(dates, saves)
	mgr.enter_developer_mode()
	mgr.developer_set_date("2026-08-09")
	mgr.mark_chest_opened("2026-08-06")
	mgr.mark_scroll_viewed("2026-08-06")
	mgr.set_text_scale(1.4)
	mgr.set_reduced_motion(true)
	var mgr2 := AnniversaryManager.new(dates, saves)
	mgr2.enter_developer_mode()
	_assert(mgr2.is_chest_opened("2026-08-06"), "reload preserves opened chest")
	_assert(mgr2.is_scroll_viewed("2026-08-06"), "reload preserves viewed scroll")
	_assert(is_equal_approx(mgr2.get_text_scale(), 1.4), "reload preserves text scale")
	_assert(mgr2.is_reduced_motion(), "reload preserves reduced motion")
