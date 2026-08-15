extends SceneTree
## Validates final-chest hide/show around the gift document viewer.


func _initialize() -> void:
	print("=== Chest Preview Visibility Validation ===")
	var failed := 0

	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if not main.has_method("open_gift_document_viewer"):
		print("FAIL: main missing open_gift_document_viewer")
		quit(1)
		return

	var presentation: Control = main.get_node_or_null("FinalChestPresentation") as Control
	if presentation == null:
		presentation = _find_named(main, "FinalChestPresentation") as Control
	if presentation == null:
		print("FAIL: FinalChestPresentation node missing")
		failed += 1
	else:
		print("OK: FinalChestPresentation present")

	var manager: AnniversaryManager = main.manager
	manager.enter_developer_mode()
	manager.developer_set_date("2026-08-13")
	# Mark prior chests/messages so final gift is ready.
	for iso in [
		"2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09",
		"2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13",
	]:
		manager.mark_chest_opened(iso)
		manager.mark_scroll_viewed(iso)
	main.call("_refresh_presentation")
	await process_frame

	if presentation != null and not presentation.visible:
		print("FAIL: final chest presentation should be visible before preview")
		failed += 1
	else:
		print("OK: final chest presentation visible before preview")

	await main.open_gift_document_viewer(true)
	await process_frame
	if not main.gift_viewer_open:
		print("FAIL: gift_viewer_open should be true")
		failed += 1
	if presentation != null and presentation.visible:
		print("FAIL: chest presentation still visible while preview open")
		failed += 1
	else:
		print("OK: chest presentation hidden while preview open")
	var gift_viewer: GiftDocumentViewer = main.get("_gift_viewer")
	if gift_viewer == null or not gift_viewer.visible:
		print("FAIL: gift viewer not visible")
		failed += 1
	else:
		print("OK: gift viewer visible")

	# Simulate returning from an external PDF focus event.
	main.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	if presentation != null and presentation.visible:
		print("FAIL: focus-in restored chest while preview still open")
		failed += 1
	else:
		print("OK: focus-in keeps chest hidden while preview open")

	# Duplicate open should be ignored.
	await main.open_gift_document_viewer(true)
	if gift_viewer.get_loaded_page_count() != 2:
		print("FAIL: unexpected page count after duplicate open")
		failed += 1
	else:
		print("OK: duplicate open ignored / pages still 2")

	gift_viewer.request_close()
	# Allow close_gift_document_viewer fade to finish.
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	if main.gift_viewer_open:
		print("FAIL: gift_viewer_open still true after close")
		failed += 1
	if presentation != null and not presentation.visible:
		print("FAIL: chest presentation not restored after close")
		failed += 1
	else:
		print("OK: chest presentation restored after close")
	var chest: TreasureChest = main.get("_chest")
	if chest == null or chest.chest_state != TreasureChest.ChestState.FINAL_GIFT:
		print("FAIL: chest not in FINAL_GIFT after close")
		failed += 1
	else:
		print("OK: chest restored to FINAL_GIFT idle")
	if chest == null or not chest._label.visible:
		print("FAIL: One More Surprise label missing after close")
		failed += 1
	else:
		print("OK: One More Surprise label visible after close")

	print("=== Validation complete: %d failure(s) ===" % failed)
	quit(1 if failed > 0 else 0)


func _find_named(node: Node, nom: String) -> Node:
	if node.name == nom:
		return node
	for child in node.get_children():
		var found := _find_named(child, nom)
		if found != null:
			return found
	return null
