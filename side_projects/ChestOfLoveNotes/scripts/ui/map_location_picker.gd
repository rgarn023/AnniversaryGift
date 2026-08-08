extends Control
class_name MapLocationPicker
## Lightweight OSM tile map for Location Lock selection.
## Created only when Choose on Map opens; frees tile HTTP on close.

signal confirmed(place: Dictionary)
signal cancelled

const TILE_URL := "https://tile.openstreetmap.org/%d/%d/%d.png"
const USER_AGENT := "ChestOfLoveNotes/1.0 (Charoite Games; map-picker)"
const MIN_ZOOM := 3
const MAX_ZOOM := 18

var radius_m: int = 500
var _center_lat: float = 37.5407
var _center_lng: float = -77.4360
var _zoom: int = 13
var _selected_lat: float = NAN
var _selected_lng: float = NAN
var _selected_name: String = ""
var _selected_address: String = ""
var _tile_layer: Control
var _overlay: Control
var _status: Label
var _search: LineEdit
var _http: HTTPRequest
var _tile_cache: Dictionary = {}
var _loading_tiles: Dictionary = {}
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
var _pending_tile_count: int = 0
var _map_host: Control
var _retry_btn: Button
var _layout_ready: bool = false
var _load_failed: bool = false


func setup(initial: Dictionary = {}, p_radius_m: int = 500, search_service: LocationSearchService = null) -> void:
	radius_m = clampi(p_radius_m, LocationHelper.MIN_RADIUS_M, LocationHelper.MAX_RADIUS_M)
	_search_service = search_service if search_service != null else LocationSearchService.new()
	if bool(initial.get("ok", false)) or (initial.has("lat") and initial.has("lng")):
		_selected_lat = float(initial.get("lat", _center_lat))
		_selected_lng = float(initial.get("lng", _center_lng))
		_center_lat = _selected_lat
		_center_lng = _selected_lng
		_selected_name = str(initial.get("name", "Selected place"))
		_selected_address = str(initial.get("address", ""))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	_build_ui()
	_set_loading(true)
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
	root.add_child(_map_host)

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
		_set_loading(true)
		if _layout_ready:
			_refresh_tiles()
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
		_zoom = mini(_zoom + 1, MAX_ZOOM)
		_set_loading(true)
		_refresh_tiles()
	)
	zoom_row.add_child(zin)
	var zout := Button.new()
	zout.text = "−"
	zout.custom_minimum_size = Vector2(52, 52)
	MobileUi.style_button(zout, 52)
	zout.pressed.connect(func() -> void:
		_zoom = maxi(_zoom - 1, MIN_ZOOM)
		_set_loading(true)
		_refresh_tiles()
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

	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.35
	_debounce.timeout.connect(_run_search)
	add_child(_debounce)

	_map_host.resized.connect(func() -> void:
		if _layout_ready and _map_host.size.x > 8.0:
			_refresh_tiles()
			_overlay.queue_redraw()
	)


func set_radius(m: int) -> void:
	radius_m = clampi(m, LocationHelper.MIN_RADIUS_M, LocationHelper.MAX_RADIUS_M)
	if _status:
		_status.text = "Unlock within %s of the pin." % LocationHelper.format_radius(radius_m)
	if _overlay:
		_overlay.queue_redraw()


func _bootstrap_map_after_layout() -> void:
	## Wait until the map host has a real non-zero size before first tile request.
	## Initializing against a zero-size viewport is the black-until-pan bug.
	if not _alive:
		return
	_set_loading(true)
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
		_load_failed = true
		_tiles_ready = false
		if _loading_overlay:
			_loading_overlay.visible = true
			_loading_overlay.modulate.a = 1.0
		if _loading_label:
			_loading_label.text = "Couldn't load the map."
		if _retry_btn:
			_retry_btn.visible = true
		_sync_action_enabled()
		return
	_layout_ready = true
	## One extra frame after size settles, then center/zoom + first tiles.
	await get_tree().process_frame
	if not _alive:
		return
	_refresh_tiles()
	if _overlay:
		_overlay.queue_redraw()


func _set_loading(on: bool) -> void:
	_tiles_ready = not on
	if _loading_overlay:
		_loading_overlay.visible = on
		_loading_overlay.modulate.a = 1.0 if on else 0.0
	_sync_action_enabled()


func _sync_action_enabled() -> void:
	var has_pin := is_finite(_selected_lat) and is_finite(_selected_lng)
	if _confirm_btn:
		_confirm_btn.disabled = not (has_pin and _tiles_ready)
	if _drop_btn:
		_drop_btn.disabled = not _tiles_ready


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
	_refresh_tiles()
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
	queue_free()


func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_active = mb.pressed
			_drag_last = mb.position
			if not mb.pressed:
				## Tap without drag drops pin.
				pass
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = mini(_zoom + 1, MAX_ZOOM)
			_refresh_tiles()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = maxi(_zoom - 1, MIN_ZOOM)
			_refresh_tiles()
	elif ev is InputEventMouseMotion and _drag_active:
		var mm := ev as InputEventMouseMotion
		var delta := mm.position - _drag_last
		_drag_last = mm.position
		_pan_by_pixels(delta)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		_drag_active = st.pressed
		_drag_last = st.position
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_pan_by_pixels(sd.relative)


func _pan_by_pixels(delta: Vector2) -> void:
	var n := pow(2.0, float(_zoom))
	var world_x := (_center_lng + 180.0) / 360.0 * n
	var lat_rad := deg_to_rad(_center_lat)
	var world_y := (1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * n
	world_x -= delta.x / 256.0
	world_y -= delta.y / 256.0
	_center_lng = world_x / n * 360.0 - 180.0
	var y := world_y / n
	var lat_r := atan(sinh(PI * (1.0 - 2.0 * y)))
	_center_lat = rad_to_deg(lat_r)
	_center_lat = clampf(_center_lat, -85.0, 85.0)
	_refresh_tiles()
	_overlay.queue_redraw()


func _lon_to_x(lon: float, zoom: int) -> float:
	return (lon + 180.0) / 360.0 * pow(2.0, float(zoom))


func _lat_to_y(lat: float, zoom: int) -> float:
	var lat_rad := deg_to_rad(clampf(lat, -85.0511, 85.0511))
	return (1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * pow(2.0, float(zoom))


func _refresh_tiles() -> void:
	if _tile_layer == null or _map_host == null:
		return
	var area := _map_host.size
	if area.x < 64.0 or area.y < 64.0:
		## Zero-size viewport — wait for layout bootstrap.
		return
	for c in _tile_layer.get_children():
		c.queue_free()
	_pending_tile_count = 0
	var center_x := _lon_to_x(_center_lng, _zoom)
	var center_y := _lat_to_y(_center_lat, _zoom)
	var tiles_x := int(ceil(area.x / 256.0)) + 2
	var tiles_y := int(ceil(area.y / 256.0)) + 2
	var start_tx := int(floor(center_x - tiles_x * 0.5))
	var start_ty := int(floor(center_y - tiles_y * 0.5))
	var cached_hits := 0
	var requested := 0
	for ty in range(start_ty, start_ty + tiles_y + 1):
		for tx in range(start_tx, start_tx + tiles_x + 1):
			var max_t := int(pow(2.0, float(_zoom)))
			if ty < 0 or ty >= max_t:
				continue
			var wrapped_x := posmod(tx, max_t)
			var px := (float(tx) - center_x) * 256.0 + area.x * 0.5
			var py := (float(ty) - center_y) * 256.0 + area.y * 0.5
			var key := "%d/%d/%d" % [_zoom, wrapped_x, ty]
			var tr := TextureRect.new()
			tr.position = Vector2(px, py)
			tr.size = Vector2(256, 256)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tile_layer.add_child(tr)
			if _tile_cache.has(key):
				tr.texture = _tile_cache[key]
				cached_hits += 1
			else:
				requested += 1
				_pending_tile_count += 1
				_request_tile(key, _zoom, wrapped_x, ty, tr)
	if requested == 0 and cached_hits > 0:
		_finish_loading_if_ready()
	elif requested > 0:
		## Failsafe: never leave Loading map forever.
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if _alive and not _tiles_ready:
				_finish_loading_if_ready(true)
		, CONNECT_ONE_SHOT)
	_overlay.queue_redraw()
	_sync_action_enabled()


func _finish_loading_if_ready(force: bool = false) -> void:
	if not _alive:
		return
	if not force and _pending_tile_count > 0:
		return
	var painted := 0
	if _tile_layer:
		for c in _tile_layer.get_children():
			if c is TextureRect and (c as TextureRect).texture != null:
				painted += 1
	if painted <= 0 and not force:
		## Tiles requested but none painted yet — keep loading.
		return
	if painted <= 0 and force:
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
		return
	_load_failed = false
	_tiles_ready = true
	## Force a real redraw — tiles can arrive before first paint without interaction.
	if _tile_layer:
		_tile_layer.visible = false
		await get_tree().process_frame
		if not _alive:
			return
		_tile_layer.visible = true
		_tile_layer.queue_redraw()
		for c in _tile_layer.get_children():
			if c is CanvasItem:
				(c as CanvasItem).queue_redraw()
	if _overlay:
		_overlay.queue_redraw()
	if _map_host:
		_map_host.queue_redraw()
	if _loading_overlay and _loading_overlay.visible:
		var tw := create_tween()
		tw.tween_property(_loading_overlay, "modulate:a", 0.0, 0.28)
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


func _request_tile(key: String, z: int, x: int, y: int, tr: TextureRect) -> void:
	if _loading_tiles.has(key):
		_pending_tile_count = maxi(0, _pending_tile_count - 1)
		return
	_loading_tiles[key] = true
	var url := TILE_URL % [z, x, y]
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % USER_AGENT]))
	if err != OK:
		_loading_tiles.erase(key)
		_pending_tile_count = maxi(0, _pending_tile_count - 1)
		http.queue_free()
		_finish_loading_if_ready()
		return
	var completed: Array = await http.request_completed
	if is_instance_valid(http):
		http.queue_free()
	_loading_tiles.erase(key)
	_pending_tile_count = maxi(0, _pending_tile_count - 1)
	if not _alive or completed.size() < 4:
		_finish_loading_if_ready()
		return
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS or int(completed[1]) != 200:
		_finish_loading_if_ready()
		return
	var body: PackedByteArray = completed[3]
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		_finish_loading_if_ready()
		return
	var tex := ImageTexture.create_from_image(img)
	_tile_cache[key] = tex
	if is_instance_valid(tr):
		tr.texture = tex
		tr.queue_redraw()
	if _tile_layer:
		_tile_layer.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()
	_finish_loading_if_ready()


func _draw_overlay() -> void:
	if _overlay == null:
		return
	var area := _overlay.size
	## Center crosshair
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
	return Vector2((x - cx) * 256.0 + area.x * 0.5, (y - cy) * 256.0 + area.y * 0.5)


func _meters_to_pixels(meters: float, lat: float) -> float:
	var m_per_px := cos(deg_to_rad(lat)) * 40075016.686 / (256.0 * pow(2.0, float(_zoom)))
	if m_per_px <= 0.001:
		return 20.0
	return clampf(meters / m_per_px, 12.0, 2000.0)
