extends SceneTree

## Headless visual validation: renders chest/scroll frames to artifacts.

const OUT := "/opt/cursor/artifacts/validation"
const VIEW := Vector2i(1080, 1920)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_capture_boot_and_icons()
	await _capture_chest_sequence()
	await _capture_scroll_sequence()
	await _capture_archive_mini()
	print("VALIDATION_OK wrote frames to ", OUT)
	quit(0)


func _capture_boot_and_icons() -> void:
	_copy_if("res://assets/art/boot_splash.png", OUT + "/01_first_frame_boot_splash.png")
	_copy_if("res://assets/icons/app_icon_1024.png", OUT + "/12_app_icon_1024.png")
	_copy_if("res://assets/icons/adaptive_foreground.png", OUT + "/12_adaptive_foreground.png")
	_copy_if("res://assets/icons/adaptive_background.png", OUT + "/12_adaptive_background.png")
	_copy_if("res://assets/icons/app_icon_round.png", OUT + "/12_app_icon_round.png")
	_copy_if("res://assets/art/chest/chest_closed.png", OUT + "/02_closed_realistic_chest.png")


func _copy_if(src: String, dst: String) -> void:
	if ResourceLoader.exists(src):
		var img: Image = (load(src) as Texture2D).get_image()
		if img:
			img.save_png(dst)
			print("wrote ", dst)


func _capture_chest_sequence() -> void:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.size = Vector2(VIEW)
	vp.add_child(bg)

	var chest: TreasureChest = (load("res://scenes/Chest.tscn") as PackedScene).instantiate()
	chest.position = Vector2(280, 600)
	chest.size = Vector2(520, 520)
	chest.custom_minimum_size = Vector2(520, 520)
	vp.add_child(chest)
	await process_frame
	await process_frame
	# Wait fade-in
	await self.create_timer(0.4).timeout
	_shot(vp, "02_closed_chest_in_scene.png")

	chest.configure(TreasureChest.ChestState.AVAILABLE)
	# Latch/lock visible mid sequence via private-ish finished states using tween method
	chest._latch.modulate.a = 1.0
	chest._lock.modulate.a = 1.0
	chest._lock.rotation = deg_to_rad(10.0)
	await process_frame
	_shot(vp, "03_latch_releasing.png")

	chest._show_frame_state(0.5)
	chest._interior_glow.modulate.a = 0.6
	chest._front_lip.modulate.a = 1.0
	await process_frame
	_shot(vp, "04_chest_half_open.png")

	chest._show_frame_state(1.0)
	chest._interior_glow.modulate.a = 0.85
	chest._latch.modulate.a = 0.0
	chest._lock.modulate.a = 0.0
	await process_frame
	_shot(vp, "05_chest_fully_open.png")

	chest._rolled_scroll.modulate.a = 1.0
	chest._rolled_scroll.position = Vector2(0, 20)
	chest._front_lip.modulate.a = 1.0
	await process_frame
	_shot(vp, "06_rolled_scroll_partial_inside.png")

	chest._rolled_scroll.position = Vector2(0, -55)
	chest._front_lip.modulate.a = 0.35
	await process_frame
	_shot(vp, "07_rolled_scroll_clearing_rim.png")

	vp.queue_free()
	await process_frame


func _capture_scroll_sequence() -> void:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12, 0.85)
	bg.size = Vector2(VIEW)
	vp.add_child(bg)

	var viewer: ScrollViewer = ScrollViewer.new()
	var mgr := AnniversaryManager.new()
	viewer.manager = mgr
	vp.add_child(viewer)
	await process_frame

	# Force visible layout without full async open
	viewer.visible = true
	viewer._fit_panel()
	viewer._set_rolled_at_start()
	viewer._rolled.modulate.a = 1.0
	viewer._dim.color.a = 0.72
	await process_frame
	_shot(vp, "08_scroll_begin_unroll_rolled.png")

	viewer._unrolled_root.visible = true
	var mid_y: float = viewer._panel_size.y * 0.5
	viewer._top_roller.position = Vector2(0, mid_y - 120)
	viewer._bottom_roller.position = Vector2(0, mid_y + 80)
	viewer._parchment_clip.offset_top = mid_y - 100
	viewer._parchment_clip.offset_bottom = -(viewer._panel_size.y - mid_y - 100)
	viewer._rolled.modulate.a = 0.2
	await process_frame
	_shot(vp, "09_scroll_halfway_unrolled.png")

	viewer._set_fully_unrolled()
	viewer._date_label.text = "August 6, 2026"
	viewer._heading.text = "Validation"
	viewer._message.text = "This parchment should stay readable inside the scroll bounds."
	viewer._text_zoom.modulate.a = 1.0
	await process_frame
	_shot(vp, "10_fully_open_readable_scroll.png")

	vp.queue_free()
	await process_frame


func _capture_archive_mini() -> void:
	_copy_if("res://assets/art/scroll/scroll_mini.png", OUT + "/11_archived_scroll_mini.png")
	_copy_if("res://assets/art/scroll/scroll_mini_unread.png", OUT + "/11_archived_scroll_mini_unread.png")


func _shot(vp: SubViewport, name: String) -> void:
	await process_frame
	await process_frame
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		print("FAIL no texture ", name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("FAIL no image ", name)
		return
	img.save_png(OUT + "/" + name)
	print("wrote ", OUT + "/" + name)
