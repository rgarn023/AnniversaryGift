extends Control
class_name MapLocationPicker
## Long-lived OSM tile map for one Choose-on-Map session.
## Gestures mutate camera state on THIS instance — never recreate the picker/provider.
## After first successful paint, pan/pinch never blank the map or show a fatal overlay.

signal confirmed(place: Dictionary)
signal cancelled

const TILE_URL := "https://tile.openstreetmap.org/%d/%d/%d.png"
const USER_AGENT := "ChestOfLoveNotes/1.0 (Charoite Games; map-picker)"
const MIN_ZOOM := 3
const MAX_ZOOM := 18
const TILE_PX := 256.0
const MAX_TILE_RETRIES := 3

var radius_m: int = 500
## Canonical camera state for the whole picker session.
## Default is a broad continental overview — not an unrelated specific city.
## Prefer selected target / current location when available (see setup()).
var _center_lat: float = 39.8283
var _center_lng: float = -98.5795
var _zoom: int = 4
var _selected_lat: float = NAN
var _selected_lng: float = NAN
var _selected_name: String = ""
var _selected_address: String = ""
var _tile_layer: Control
var _overlay: Control
var _status: Label
var _search: LineEdit
var _tile_cache: Dictionary = {} ## key -> ImageTexture
var _tile_nodes: Dictionary = {} ## key -> TextureRect (current zoom layer)
var _loading_tiles: Dictionary = {} ## key -> true
var _tile_waiters: Dictionary = {} ## key -> Array[TextureRect]
var _tile_retry_counts: Dictionary = {} ## key -> int
var _drag_active: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _search_service: LocationSearchService
var _search_token: int = 0
var _suggestions: VBoxContainer
var _debounce: Timer
var _alive: bool = true
var _loading_overlay: Control
var _loading_label: Label
var _confirm_btn: Button
var _drop_btn: Button
var _tiles_ready: bool = false
var _initial_paint_done: bool = false
var _map_host: Control
var _retry_btn: Button
var _layout_ready: bool = false
var _load_failed: bool = false
var _pinch_touches: Dictionary = {}
var _pinch_last_dist: float = 0.0
var _pinch_active: bool = false
## Fractional zoom accumulator — pinch uses continuous scale, not raw ±1 jumps.
var _pinch_zoom_frac: float = 0.0
var _refresh_queued: bool = false
var _last_refresh_msec: int = 0
var _pinch_tile_debounce: Timer
## Previous-zoom tiles kept visible/scaled while the new zoom level loads (no black flash).
var _hold_tile_layer: Control
const PINCH_DAMPING := 0.42
const PINCH_MAX_DELTA_PER_EVENT := 0.12
const PINCH_MIN_DIST := 16.0


func setup(initial: Dictionary = {}, p_radius_m: int = 500, search_service: LocationSearchService = null) -> void:
	radius_m = clampi(p_radius_m, LocationHelper.MIN_RADIUS_M, LocationHelper.MAX_RADIUS_M)
	_search_service = search_service if search_service != null else LocationSearchService.new()
	if bool(initial.get("ok", false)) or (initial.has("lat") and initial.has("lng")):
		var lat0 := float(initial.get("lat", _center_lat))
		var lng0 := float(initial.get("lng", _center_lng))
		_center_lat = lat0
		_center_lng = lng0
		## center_only: use GPS/search as camera start without dropping a pin.
		if not bool(initial.get("center_only", false)) and bool(initial.get("ok", false)):
			_selected_lat = lat0
			_selected_lng = lng0
			_selected_name = str(initial.get("name", "Selected place"))
			_selected_address = str(initial.get("address", ""))
			_zoom = 13
		elif not bool(initial.get("center_only", false)) and initial.has("lat"):
			_selected_lat = lat0
			_selected_lng = lng0
			_selected_name = str(initial.get("name", "Selected place"))
			_selected_address = str(initial.get("address", ""))
			_zoom = 13
		elif bool(initial.get("center_only", false)):
			_zoom = 14
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	## Android multitouch often bypasses Control.gui_input — capture via _input.
	set_process_input(true)
	_build_ui()
	_show_initial_loading(true)
	_sync_action_enabled()
	call_deferred("_bootstrap_map_after_layout")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Choose on Map"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE, false)
	root.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = "Search map…"
	_search.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.INPUT_H))
	MobileUi.style_line_edit(_search)
	_search.text_changed.connect(_on_search_changed)
	root.add_child(_search)

	_suggestions = VBoxContainer.new()
	_suggestions.visible = false
	_suggestions.add_theme_constant_override("separation", 4)
	root.add_child(_suggestions)

	_map_host = Control.new()
	_map_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_host.custom_minimum_size = Vector2(0, 280)
	_map_host.clip_contents = true
	_map_host.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_map_host)

	## Hold layer stays under the live tile layer so prior zoom tiles remain visible
	## (scaled) while higher/lower zoom tiles load — prevents black flashes.
	_hold_tile_layer = Control.new()
	_hold_tile_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hold_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_host.add_child(_hold_tile_layer)

	_tile_layer = Control.new()
	_tile_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_host.add_child(_tile_layer)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_map_input)
	_overlay.draw.connect(_draw_overlay)
	_map_host.add_child(_overlay)

	_loading_overlay = Control.new()
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.z_index = 20
	_map_host.add_child(_loading_overlay)
	var load_bg := ColorRect.new()
	load_bg.color = Color(0.08, 0.06, 0.14, 0.94)
	load_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(load_bg)
	var load_col := VBoxContainer.new()
	load_col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	load_col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	load_col.grow_vertical = Control.GROW_DIRECTION_BOTH
	load_col.add_theme_constant_override("separation", 10)
	_loading_overlay.add_child(load_col)
	_loading_label = Label.new()
	_loading_label.text = "Loading map…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 20)
	_loading_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.98))
	load_col.add_child(_loading_label)
	var spin := Label.new()
	spin.text = "◌"
	spin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.add_theme_font_size_override("font_size", 28)
	spin.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	load_col.add_child(spin)
	_retry_btn = Button.new()
	_retry_btn.text = "Retry"
	_retry_btn.visible = false
	_retry_btn.custom_minimum_size = Vector2(160, 48)
	_retry_btn.focus_mode = Control.FOCUS_NONE
	MobileUi.style_button(_retry_btn, 48)
	_retry_btn.pressed.connect(func() -> void:
		_load_failed = false
		_retry_btn.visible = false
		_loading_label.text = "Loading map…"
		_show_initial_loading(true)
		if _layout_ready:
			_refresh_tiles(true)
		else:
			call_deferred("_bootstrap_map_after_layout")
	)
	load_col.add_child(_retry_btn)
	var search_instead := Button.new()
	search_instead.text = "Search for a place instead"
	search_instead.visible = false
	search_instead.focus_mode = Control.FOCUS_NONE
	search_instead.custom_minimum_size = Vector2(220, 44)
	MobileUi.style_button(search_instead, 44)
	search_instead.pressed.connect(func() -> void:
		cancelled.emit()
		_shutdown()
	)
	load_col.add_child(search_instead)
	_retry_btn.set_meta("_search_instead", search_instead)

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 8)
	root.add_child(zoom_row)
	var zin := Button.new()
	zin.text = "+"
	zin.custom_minimum_size = Vector2(52, 52)
	MobileUi.style_button(zin, 52)
	zin.pressed.connect(func() -> void:
		_set_zoom_level(_zoom + 1)
	)
	zoom_row.add_child(zin)
	var zout := Button.new()
	zout.text = "−"
	zout.custom_minimum_size = Vector2(52, 52)
	MobileUi.style_button(zout, 52)
	zout.pressed.connect(func() -> void:
		_set_zoom_level(_zoom - 1)
	)
	zoom_row.add_child(zout)
	_drop_btn = Button.new()
	_drop_btn.text = "Drop Pin Here"
	_drop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_btn.custom_minimum_size = Vector2(0, 52)
	MobileUi.style_button(_drop_btn, 52)
	_drop_btn.pressed.connect(_drop_pin_center)
	zoom_row.add_child(_drop_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(_status, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
	_status.text = "Pan, zoom, then drop a pin. Radius: %s" % LocationHelper.format_radius(radius_m)
	root.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, MobileUi.TOUCH_PRIMARY_H)
	MobileUi.style_button(cancel, MobileUi.TOUCH_PRIMARY_H)
	cancel.pressed.connect(func() -> void:
		cancelled.emit()
		_shutdown()
	)
	actions.add_child(cancel)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Location"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.custom_minimum_size = Vector2(0, MobileUi.TOUCH_CTA_H)
	MobileUi.style_button(_confirm_btn, MobileUi.TOUCH_CTA_H)
	_confirm_btn.pressed.connect(_confirm)
	actions.add_child(_confirm_btn)

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.35
	_debounce.timeout.connect(_run_search)
	add_child(_debounce)

	_pinch_tile_debounce = Timer.new()
	_pinch_tile_debounce.one_shot = true
	_pinch_tile_debounce.wait_time = 0.12
	_pinch_tile_debounce.timeout.connect(func() -> void:
		if _alive and not _pinch_active:
			_refresh_tiles(false)
	)
	add_child(_pinch_tile_debounce)

	_map_host.resized.connect(func() -> void:
		if _layout_ready and _map_host.size.x > 8.0:
			_queue_refresh_tiles()
			_overlay.queue_redraw()
	)


func set_radius(m: int) -> void:
	radius_m = clampi(m, LocationHelper.MIN_RADIUS_M, LocationHelper.MAX_RADIUS_M)
	if _status:
		_status.text = "Unlock within %s of the pin." % LocationHelper.format_radius(radius_m)
	if _overlay:
		_overlay.queue_redraw()


func _bootstrap_map_after_layout() -> void:
	if not _alive:
		return
	_show_initial_loading(true)
	if _loading_label:
		_loading_label.text = "Loading map…"
	if _retry_btn:
		_retry_btn.visible = false
	var attempts := 0
	while _alive and attempts < 24:
		await get_tree().process_frame
		attempts += 1
		if _map_host != null and _map_host.size.x >= 64.0 and _map_host.size.y >= 64.0:
			break
	if not _alive:
		return
	if _map_host == null or _map_host.size.x < 64.0 or _map_host.size.y < 64.0:
		_show_fatal_map_error()
		return
	_layout_ready = true
	await get_tree().process_frame
	if not _alive:
		return
	_refresh_tiles(true)
	if _overlay:
		_overlay.queue_redraw()
	## Only for INITIAL load — never after first paint.
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if _alive and not _initial_paint_done:
			_show_fatal_map_error()
	, CONNECT_ONE_SHOT)


func _show_initial_loading(on: bool) -> void:
	## Full-screen overlay is ONLY for first open / fatal retry — never for pan/pinch.
	if _initial_paint_done and on:
		return
	_tiles_ready = not on
	if _loading_overlay:
		_loading_overlay.visible = on
		_loading_overlay.modulate.a = 1.0 if on else 0.0
	_sync_action_enabled()


func _show_fatal_map_error() -> void:
	## Only when no usable initial map could be shown.
	if _initial_paint_done:
		return
	_load_failed = true
	_tiles_ready = false
	if _loading_overlay:
		_loading_overlay.visible = true
		_loading_overlay.modulate.a = 1.0
	if _loading_label:
		_loading_label.text = "Couldn't load the map."
	if _retry_btn:
		_retry_btn.visible = true
		var alt: Variant = _retry_btn.get_meta("_search_instead", null)
		if alt is Control:
			(alt as Control).visible = true
	_sync_action_enabled()


func _hide_loading_overlay() -> void:
	_tiles_ready = true
	_load_failed = false
	_initial_paint_done = true
	if _loading_overlay and _loading_overlay.visible:
		var tw := create_tween()
		tw.tween_property(_loading_overlay, "modulate:a", 0.0, 0.22)
		tw.finished.connect(func() -> void:
			if is_instance_valid(_loading_overlay):
				_loading_overlay.visible = false
				_loading_overlay.modulate.a = 1.0
		)
	if _retry_btn:
		_retry_btn.visible = false
		var alt2: Variant = _retry_btn.get_meta("_search_instead", null)
		if alt2 is Control:
			(alt2 as Control).visible = false
	_sync_action_enabled()


func _sync_action_enabled() -> void:
	var has_pin := is_finite(_selected_lat) and is_finite(_selected_lng)
	var usable := _tiles_ready or _initial_paint_done
	if _confirm_btn:
		_confirm_btn.disabled = not (has_pin and usable)
	if _drop_btn:
		_drop_btn.disabled = not usable


func _on_search_changed(_t: String) -> void:
	_debounce.start()


func _run_search() -> void:
	var q := _search.text.strip_edges()
	if q.length() < LocationSearchService.MIN_QUERY_LEN:
		_suggestions.visible = false
		return
	_search_token = _search_service.next_token()
	var token := _search_token
	_status.text = "Searching…"
	var result: Dictionary = await _search_service.search_places(q, token)
	if not _alive or not _search_service.is_current(token):
		return
	for c in _suggestions.get_children():
		c.queue_free()
	if not bool(result.get("ok", false)):
		_status.text = "Couldn't search locations. Try again."
		_suggestions.visible = false
		return
	var results: Array = result.get("results", [])
	if results.is_empty():
		_status.text = "No places found."
		_suggestions.visible = false
		return
	for place in results:
		if typeof(place) != TYPE_DICTIONARY:
			continue
		var btn := Button.new()
		btn.text = "%s\n%s" % [str(place.get("name", "")), str(place.get("address", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 56)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MobileUi.style_button(btn, 56)
		var captured: Dictionary = (place as Dictionary).duplicate(true)
		btn.pressed.connect(func() -> void:
			_apply_place(captured)
			_suggestions.visible = false
			_search.release_focus()
		)
		_suggestions.add_child(btn)
	_suggestions.visible = true
	_status.text = "Tap a result or drop a pin."


func _apply_place(place: Dictionary) -> void:
	_selected_lat = float(place.get("lat", 0.0))
	_selected_lng = float(place.get("lng", 0.0))
	_center_lat = _selected_lat
	_center_lng = _selected_lng
	_selected_name = str(place.get("name", "Selected place"))
	_selected_address = str(place.get("address", ""))
	_status.text = "%s · unlock within %s" % [_selected_name, LocationHelper.format_radius(radius_m)]
	_refresh_tiles(true)
	_overlay.queue_redraw()


func _drop_pin_center() -> void:
	_selected_lat = _center_lat
	_selected_lng = _center_lng
	_status.text = "Resolving place…"
	var token := _search_service.next_token()
	var rev: Dictionary = await _search_service.reverse_geocode(_selected_lat, _selected_lng, token)
	if not _alive:
		return
	if bool(rev.get("ok", false)) and typeof(rev.get("place")) == TYPE_DICTIONARY:
		var place: Dictionary = rev.get("place")
		_selected_name = str(place.get("name", "Selected place"))
		_selected_address = str(place.get("address", ""))
	else:
		_selected_name = "Selected place"
		_selected_address = ""
	_status.text = "%s · unlock within %s" % [_selected_name, LocationHelper.format_radius(radius_m)]
	_overlay.queue_redraw()


func _confirm() -> void:
	if not is_finite(_selected_lat) or not is_finite(_selected_lng):
		_status.text = "Drop a pin or choose a search result first."
		return
	confirmed.emit({
		"name": _selected_name if not _selected_name.is_empty() else "Selected place",
		"address": _selected_address,
		"lat": _selected_lat,
		"lng": _selected_lng,
		"display": _selected_name,
		"ok": true,
	})
	_shutdown()


func _shutdown() -> void:
	_alive = false
	if _debounce:
		_debounce.stop()
	_loading_tiles.clear()
	_tile_waiters.clear()
	queue_free()


func _map_host_global_rect() -> Rect2:
	if _map_host == null:
		return Rect2()
	return _map_host.get_global_rect()


func _to_map_local(global_pos: Vector2) -> Vector2:
	if _overlay == null:
		return global_pos
	return _overlay.get_global_transform_with_canvas().affine_inverse() * global_pos


func _input(event: InputEvent) -> void:
	## Critical for Android: multitouch ScreenTouch/Drag often never reach gui_input.
	if not _alive or not visible or _map_host == null or _overlay == null:
		return
	if not _initial_paint_done and not _tiles_ready and _loading_overlay != null and _loading_overlay.visible:
		## Still allow gestures once layout exists — but prefer after first paint.
		pass
	var area := _map_host_global_rect()
	if area.size.x < 8.0:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var inside := area.has_point(st.position)
		if st.pressed:
			if not inside and not _pinch_touches.has(st.index):
				return
			_pinch_touches[st.index] = _to_map_local(st.position)
		else:
			if not _pinch_touches.has(st.index) and not inside:
				return
			_pinch_touches.erase(st.index)
			if _pinch_touches.size() < 2:
				_end_pinch_gesture()
		_drag_active = st.pressed and _pinch_touches.size() == 1
		_drag_last = _to_map_local(st.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _pinch_touches.is_empty() and not area.has_point(sd.position):
			return
		_pinch_touches[sd.index] = _to_map_local(sd.position)
		if _pinch_touches.size() >= 2:
			_handle_map_pinch()
		elif not _pinch_active:
			_pan_by_pixels(sd.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		if not area.has_point(mag.position) and _pinch_touches.is_empty():
			return
		## Desktop magnify: convert scale factor to damped fractional zoom.
		var factor := maxf(float(mag.factor), 0.01)
		var delta := clampf(log(factor) / log(2.0) * PINCH_DAMPING, -PINCH_MAX_DELTA_PER_EVENT, PINCH_MAX_DELTA_PER_EVENT)
		_apply_fractional_zoom(delta, _to_map_local(mag.position))
		get_viewport().set_input_as_handled()


func _on_map_input(ev: InputEvent) -> void:
	## Mouse / emulator path via gui_input (desktop + single-finger).
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_active = mb.pressed and not _pinch_active
			_drag_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom_level(_zoom + 1, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom_level(_zoom - 1, mb.position)
		_overlay.accept_event()
	elif ev is InputEventMouseMotion and _drag_active and not _pinch_active:
		var mm := ev as InputEventMouseMotion
		var delta := mm.position - _drag_last
		_drag_last = mm.position
		_pan_by_pixels(delta)
		_overlay.accept_event()
	elif ev is InputEventScreenTouch or ev is InputEventScreenDrag or ev is InputEventMagnifyGesture:
		## Prefer _input path for multitouch; still consume so parent scroll stops.
		_overlay.accept_event()


func _end_pinch_gesture() -> void:
	_pinch_active = false
	_pinch_last_dist = 0.0
	_pinch_zoom_frac = 0.0
	## Settle: fetch any remaining tiles for the final canonical zoom.
	if _pinch_tile_debounce != null:
		_pinch_tile_debounce.start()


func _handle_map_pinch() -> void:
	var keys: Array = _pinch_touches.keys()
	keys.sort()
	if keys.size() < 2:
		return
	var a: Vector2 = _pinch_touches[keys[0]]
	var b: Vector2 = _pinch_touches[keys[1]]
	var dist := a.distance_to(b)
	if dist < PINCH_MIN_DIST:
		return
	var mid := (a + b) * 0.5
	if not _pinch_active:
		_pinch_active = true
		_pinch_last_dist = dist
		_pinch_zoom_frac = 0.0
		_drag_active = false
		return
	## Normalized pinch scale ratio → gradual zoom delta (not raw discrete jumps).
	var ratio := dist / maxf(_pinch_last_dist, 1.0)
	_pinch_last_dist = dist
	if ratio < 0.01:
		return
	var raw_delta := log(ratio) / log(2.0)
	var delta := clampf(raw_delta * PINCH_DAMPING, -PINCH_MAX_DELTA_PER_EVENT, PINCH_MAX_DELTA_PER_EVENT)
	_apply_fractional_zoom(delta, mid)


func _apply_fractional_zoom(delta: float, focal_screen: Vector2) -> void:
	if absf(delta) < 0.0001:
		return
	_pinch_zoom_frac += delta
	## Cross integer OSM zoom levels only after enough accumulated pinch motion.
	while _pinch_zoom_frac >= 1.0:
		_pinch_zoom_frac -= 1.0
		_set_zoom_level(_zoom + 1, focal_screen, true)
	while _pinch_zoom_frac <= -1.0:
		_pinch_zoom_frac += 1.0
		_set_zoom_level(_zoom - 1, focal_screen, true)


func _set_zoom_level(z: int, focal_screen: Vector2 = Vector2.INF, from_pinch: bool = false) -> void:
	var nz := clampi(z, MIN_ZOOM, MAX_ZOOM)
	if nz == _zoom:
		return
	var area := _map_host.size if _map_host else Vector2(400, 400)
	var focus := focal_screen
	if not is_finite(focus.x) or not is_finite(focus.y):
		focus = area * 0.5
	var keep := _screen_to_latlng(focus, area)
	## Preserve currently painted tiles (scaled) under the new zoom level.
	_snapshot_tiles_to_hold(_zoom, nz, focus, area)
	_zoom = nz
	## Keep the focal lat/lng under the same screen point after zoom.
	_recenter_so_latlng_at_screen(keep.x, keep.y, focus, area)
	## During active pinch, debounce tile network fetches to avoid thrashing.
	if from_pinch and _pinch_active:
		_refresh_tiles(false)
		if _pinch_tile_debounce != null:
			_pinch_tile_debounce.start()
	else:
		_refresh_tiles(true)
	_overlay.queue_redraw()


func _snapshot_tiles_to_hold(old_zoom: int, new_zoom: int, focus: Vector2, area: Vector2) -> void:
	if _hold_tile_layer == null or _tile_layer == null or not _initial_paint_done:
		return
	## Clear previous hold snapshot.
	for c in _hold_tile_layer.get_children():
		(c as Node).queue_free()
	var scale_factor := pow(2.0, float(new_zoom - old_zoom))
	## Copy textured tiles into hold layer, scaled around the pinch midpoint.
	for k in _tile_nodes.keys():
		var src = _tile_nodes[k]
		if not (src is TextureRect) or not is_instance_valid(src):
			continue
		var tr := src as TextureRect
		if tr.texture == null:
			continue
		var copy := TextureRect.new()
		copy.texture = tr.texture
		copy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		copy.stretch_mode = TextureRect.STRETCH_SCALE
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rel := tr.position - focus
		copy.position = focus + rel * scale_factor
		copy.size = Vector2(TILE_PX, TILE_PX) * scale_factor
		copy.modulate = Color(1, 1, 1, 0.92)
		_hold_tile_layer.add_child(copy)
	## Fade hold layer out once new tiles have had a moment to arrive.
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if not _alive or _hold_tile_layer == null:
			return
		## Only clear if we have some live textures at the new zoom.
		var painted := 0
		for n in _tile_nodes.values():
			if n is TextureRect and (n as TextureRect).texture != null:
				painted += 1
		if painted >= 2:
			for c2 in _hold_tile_layer.get_children():
				(c2 as Node).queue_free()
	, CONNECT_ONE_SHOT)


func _pan_by_pixels(delta: Vector2) -> void:
	var n := pow(2.0, float(_zoom))
	var world_x := (_center_lng + 180.0) / 360.0 * n
	var lat_rad := deg_to_rad(_center_lat)
	var world_y := (1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * n
	world_x -= delta.x / TILE_PX
	world_y -= delta.y / TILE_PX
	_center_lng = world_x / n * 360.0 - 180.0
	var y := world_y / n
	var lat_r := atan(sinh(PI * (1.0 - 2.0 * y)))
	_center_lat = rad_to_deg(lat_r)
	_center_lat = clampf(_center_lat, -85.0, 85.0)
	_queue_refresh_tiles()
	_overlay.queue_redraw()


func _queue_refresh_tiles() -> void:
	## Throttle pan refreshes so we don't thrash HTTP / node churn.
	var now := Time.get_ticks_msec()
	if now - _last_refresh_msec < 32:
		if _refresh_queued:
			return
		_refresh_queued = true
		get_tree().create_timer(0.034).timeout.connect(func() -> void:
			_refresh_queued = false
			if _alive:
				_refresh_tiles(false)
		, CONNECT_ONE_SHOT)
		return
	_refresh_tiles(false)


func _lon_to_x(lon: float, zoom: int) -> float:
	return (lon + 180.0) / 360.0 * pow(2.0, float(zoom))


func _lat_to_y(lat: float, zoom: int) -> float:
	var lat_rad := deg_to_rad(clampf(lat, -85.0511, 85.0511))
	return (1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * pow(2.0, float(zoom))


func _screen_to_latlng(screen: Vector2, area: Vector2) -> Vector2:
	var cx := _lon_to_x(_center_lng, _zoom)
	var cy := _lat_to_y(_center_lat, _zoom)
	var wx := cx + (screen.x - area.x * 0.5) / TILE_PX
	var wy := cy + (screen.y - area.y * 0.5) / TILE_PX
	var n := pow(2.0, float(_zoom))
	var lng := wx / n * 360.0 - 180.0
	var y := wy / n
	var lat_r := atan(sinh(PI * (1.0 - 2.0 * y)))
	return Vector2(rad_to_deg(lat_r), lng)


func _recenter_so_latlng_at_screen(lat: float, lng: float, screen: Vector2, area: Vector2) -> void:
	var wx := _lon_to_x(lng, _zoom)
	var wy := _lat_to_y(lat, _zoom)
	var cx := wx - (screen.x - area.x * 0.5) / TILE_PX
	var cy := wy - (screen.y - area.y * 0.5) / TILE_PX
	var n := pow(2.0, float(_zoom))
	_center_lng = cx / n * 360.0 - 180.0
	var y := cy / n
	var lat_r := atan(sinh(PI * (1.0 - 2.0 * y)))
	_center_lat = clampf(rad_to_deg(lat_r), -85.0, 85.0)


func _refresh_tiles(force: bool = false) -> void:
	if _tile_layer == null or _map_host == null:
		return
	var area := _map_host.size
	if area.x < 64.0 or area.y < 64.0:
		return
	_last_refresh_msec = Time.get_ticks_msec()
	var center_x := _lon_to_x(_center_lng, _zoom)
	var center_y := _lat_to_y(_center_lat, _zoom)
	var tiles_x := int(ceil(area.x / TILE_PX)) + 2
	var tiles_y := int(ceil(area.y / TILE_PX)) + 2
	var start_tx := int(floor(center_x - tiles_x * 0.5))
	var start_ty := int(floor(center_y - tiles_y * 0.5))
	var needed: Dictionary = {}
	var painted := 0
	var max_t := int(pow(2.0, float(_zoom)))
	for ty in range(start_ty, start_ty + tiles_y + 1):
		for tx in range(start_tx, start_tx + tiles_x + 1):
			if ty < 0 or ty >= max_t:
				continue
			var wrapped_x := posmod(tx, max_t)
			var key := "%d/%d/%d" % [_zoom, wrapped_x, ty]
			needed[key] = true
			var px := (float(tx) - center_x) * TILE_PX + area.x * 0.5
			var py := (float(ty) - center_y) * TILE_PX + area.y * 0.5
			var tr: TextureRect = null
			if _tile_nodes.has(key) and is_instance_valid(_tile_nodes[key]):
				tr = _tile_nodes[key]
			else:
				tr = TextureRect.new()
				tr.size = Vector2(TILE_PX, TILE_PX)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_SCALE
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr.set_meta("tile_key", key)
				_tile_layer.add_child(tr)
				_tile_nodes[key] = tr
				if _tile_cache.has(key):
					tr.texture = _tile_cache[key]
				else:
					## Subtle placeholder — keep prior tiles elsewhere visible.
					tr.modulate = Color(0.12, 0.1, 0.18, 1.0)
					_request_tile(key, _zoom, wrapped_x, ty, tr)
			tr.position = Vector2(px, py)
			tr.visible = true
			if tr.texture != null:
				tr.modulate = Color.WHITE
				painted += 1
	## Remove nodes for tiles no longer in view / different zoom.
	var stale: Array = []
	for k in _tile_nodes.keys():
		if not needed.has(k):
			stale.append(k)
	for k2 in stale:
		var node = _tile_nodes[k2]
		_tile_nodes.erase(k2)
		if is_instance_valid(node):
			node.queue_free()
	if painted > 0 and not _initial_paint_done:
		_hide_loading_overlay()
	elif painted > 0:
		_tiles_ready = true
		_sync_action_enabled()
	_overlay.queue_redraw()
	if force:
		pass


func _request_tile(key: String, z: int, x: int, y: int, tr: TextureRect) -> void:
	if not _tile_waiters.has(key):
		_tile_waiters[key] = []
	(_tile_waiters[key] as Array).append(tr)
	if _loading_tiles.has(key):
		return
	_loading_tiles[key] = true
	var url := TILE_URL % [z, x, y]
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % USER_AGENT]))
	if err != OK:
		_loading_tiles.erase(key)
		http.queue_free()
		_schedule_tile_retry(key, z, x, y)
		return
	var completed: Array = await http.request_completed
	if is_instance_valid(http):
		http.queue_free()
	_loading_tiles.erase(key)
	if not _alive:
		_tile_waiters.erase(key)
		return
	if completed.size() < 4 or int(completed[0]) != HTTPRequest.RESULT_SUCCESS or int(completed[1]) != 200:
		## Quiet retry — NEVER escalate a single tile failure to full-map error after paint.
		_schedule_tile_retry(key, z, x, y)
		return
	var body: PackedByteArray = completed[3]
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		_schedule_tile_retry(key, z, x, y)
		return
	var tex := ImageTexture.create_from_image(img)
	_tile_cache[key] = tex
	_tile_retry_counts.erase(key)
	var waiters: Array = _tile_waiters.get(key, [])
	_tile_waiters.erase(key)
	for w in waiters:
		if w is TextureRect and is_instance_valid(w):
			(w as TextureRect).texture = tex
			(w as TextureRect).modulate = Color.WHITE
			(w as TextureRect).queue_redraw()
	## Also update live node map if present.
	if _tile_nodes.has(key) and is_instance_valid(_tile_nodes[key]):
		(_tile_nodes[key] as TextureRect).texture = tex
		(_tile_nodes[key] as TextureRect).modulate = Color.WHITE
	if _tile_layer:
		_tile_layer.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()
	if not _initial_paint_done:
		var any := 0
		for n in _tile_nodes.values():
			if n is TextureRect and (n as TextureRect).texture != null:
				any += 1
		if any > 0:
			_hide_loading_overlay()


func _schedule_tile_retry(key: String, z: int, x: int, y: int) -> void:
	var n := int(_tile_retry_counts.get(key, 0)) + 1
	_tile_retry_counts[key] = n
	if n > MAX_TILE_RETRIES:
		_tile_waiters.erase(key)
		return
	var delay := 0.4 * float(n)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not _alive:
			return
		if not _tile_nodes.has(key) or not is_instance_valid(_tile_nodes[key]):
			_tile_waiters.erase(key)
			return
		_request_tile(key, z, x, y, _tile_nodes[key])
	, CONNECT_ONE_SHOT)


func _draw_overlay() -> void:
	if _overlay == null:
		return
	var area := _overlay.size
	_overlay.draw_circle(area * 0.5, 5.0, Color(0.98, 0.86, 0.45, 0.95))
	if is_finite(_selected_lat) and is_finite(_selected_lng):
		var pt := _latlng_to_screen(_selected_lat, _selected_lng, area)
		var r_px := _meters_to_pixels(radius_m, _selected_lat)
		_overlay.draw_circle(pt, r_px, Color(0.35, 0.55, 0.95, 0.18))
		_overlay.draw_arc(pt, r_px, 0, TAU, 64, Color(0.55, 0.75, 1.0, 0.75), 2.0, true)
		_overlay.draw_circle(pt, 8.0, Color(0.85, 0.2, 0.28, 0.95))


func _latlng_to_screen(lat: float, lng: float, area: Vector2) -> Vector2:
	var cx := _lon_to_x(_center_lng, _zoom)
	var cy := _lat_to_y(_center_lat, _zoom)
	var x := _lon_to_x(lng, _zoom)
	var y := _lat_to_y(lat, _zoom)
	return Vector2((x - cx) * TILE_PX + area.x * 0.5, (y - cy) * TILE_PX + area.y * 0.5)


func _meters_to_pixels(meters: float, lat: float) -> float:
	var m_per_px := cos(deg_to_rad(lat)) * 40075016.686 / (TILE_PX * pow(2.0, float(_zoom)))
	if m_per_px <= 0.001:
		return 20.0
	return clampf(meters / m_per_px, 12.0, 2000.0)
