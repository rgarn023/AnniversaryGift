extends SceneTree
## Headless validation for PDF preloads + scroll message layout widths.

const VIEWPORTS: Array[Vector2i] = [
	Vector2i(1080, 2400),
	Vector2i(1080, 2340),
	Vector2i(1440, 3120),
	Vector2i(720, 1600),
]

const LONG_DATES: Array[String] = [
	"2026-08-09",
	"2026-08-11",
	"2026-08-13",
]


func _initialize() -> void:
	var failed := 0
	print("=== Preview + Layout Validation ===")

	# Compile-time preload path.
	if GiftDocumentViewer.PDF_PAGE_TEXTURES.size() != 2:
		print("FAIL: PDF_PAGE_TEXTURES size")
		failed += 1
	for i in GiftDocumentViewer.PDF_PAGE_TEXTURES.size():
		var tex: Texture2D = GiftDocumentViewer.PDF_PAGE_TEXTURES[i]
		if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
			print("FAIL: preload page %d invalid" % (i + 1))
			failed += 1
		else:
			print(
				"OK: preload page %d = %dx%d"
				% [i + 1, tex.get_width(), tex.get_height()]
			)

	var pages_res := load("res://assets/documents/gift_document_pages.tres") as GiftDocumentPages
	if pages_res == null or pages_res.pages.size() != 2:
		print("FAIL: gift_document_pages.tres")
		failed += 1
	else:
		print("OK: gift_document_pages.tres assigned with 2 textures")

	var root_control := Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_control)

	var scene: PackedScene = load("res://scenes/GiftDocumentViewer.tscn")
	var viewer: GiftDocumentViewer = scene.instantiate()
	root_control.add_child(viewer)
	await process_frame
	viewer.load_pdf_previews()
	await process_frame
	if viewer.get_loaded_page_count() != 2:
		print("FAIL: gift viewer page count %d" % viewer.get_loaded_page_count())
		failed += 1
	elif viewer._error_panel.visible:
		print("FAIL: gift viewer error panel visible")
		failed += 1
	else:
		print("OK: gift viewer shows 2 pages; error panel hidden")

	var dates := DateService.new()
	var saves := SaveService.new()
	saves.reset_state(true)
	var manager := AnniversaryManager.new(dates, saves)
	manager.enter_developer_mode()

	var scroll := ScrollViewer.new()
	scroll.manager = manager
	root.add_child(scroll)
	await process_frame

	for vp in VIEWPORTS:
		# Simulate logical viewport sizes used by _fit_panel (stretch already applied).
		scroll._test_override_viewport = Vector2(vp)
		for date_iso in LONG_DATES:
			manager.developer_set_date(date_iso)
			await scroll.open_message(date_iso, true)
			await process_frame
			await process_frame
			scroll.apply_message_zoom()
			await process_frame
			var msg: RichTextLabel = scroll._message
			var parchment_w: float = scroll._parchment_size.x
			var usable: float = scroll._usable_message_width()
			var safe_w: float = float(vp.x) - scroll._safe_left - scroll._safe_right
			var ok := true
			if parchment_w > safe_w - 24.0 + 1.0:
				print(
					"FAIL: %s @%dx%d parchment %.1f exceeds safe %.1f"
					% [date_iso, vp.x, vp.y, parchment_w, safe_w]
				)
				ok = false
				failed += 1
			if msg.custom_minimum_size.x > usable + 1.0:
				print(
					"FAIL: %s @%dx%d message min %.1f > usable %.1f"
					% [date_iso, vp.x, vp.y, msg.custom_minimum_size.x, usable]
				)
				ok = false
				failed += 1
			if usable > parchment_w - 40.0 + 1.0:
				print(
					"FAIL: %s @%dx%d usable %.1f wider than parchment interior"
					% [date_iso, vp.x, vp.y, usable]
				)
				ok = false
				failed += 1
			# Zoom to max and re-check width containment.
			scroll.message_zoom = 1.9
			scroll.apply_message_zoom()
			await process_frame
			usable = scroll._usable_message_width()
			if msg.custom_minimum_size.x > usable + 1.0:
				print(
					"FAIL: %s @%dx%d max-zoom min %.1f > usable %.1f"
					% [date_iso, vp.x, vp.y, msg.custom_minimum_size.x, usable]
				)
				ok = false
				failed += 1
			if ok:
				print(
					"OK: %s @%dx%d parchment=%.0f usable=%.0f msg_min=%.0f font=%d"
					% [
						date_iso,
						vp.x,
						vp.y,
						parchment_w,
						usable,
						msg.custom_minimum_size.x,
						msg.get_theme_font_size("normal_font_size"),
					]
				)
			scroll.visible = false
	scroll._test_override_viewport = Vector2.ZERO

	print("=== Validation complete: %d failure(s) ===" % failed)
	quit(1 if failed > 0 else 0)
