extends Control
class_name LoveNotesChest
## Hybrid game-feel chest open.
## Architecture C: same-canvas authored plates drive lid silhouette (body planted);
## layered interior / glow / rim light / particles / clipped scroll add depth.
## No lid scale.y squash, no dual-chest crossfade ghosts, no whole-chest zoom open.

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged(global_pos: Vector2)
## Future audio hooks (no assets required this pass).
signal sfx_open_start
signal sfx_latch_release
signal sfx_fully_open
signal sfx_magical_swell
signal sfx_scroll_emerge

## Authoritative logical states — never infer from sprite frame alone.
enum ChestState {
	LOCKED_SILHOUETTE,
	AVAILABLE, ## CLOSED
	OPENING,
	OPEN_EMPTY,
	OPEN_WAITING_FOR_SCROLL,
	OPEN_SCROLL_EMERGING,
	OPENED, ## compat alias for empty-open
	READY,
	CLOSING,
	TRANSITIONING,
}

const ART := "res://assets/art/chest/"
const SCROLL_ART := "res://assets/art/scroll/"
## Shared source canvas for every open plate (1200×820).
const FRAME_SIZE := Vector2(220, 150)
## Valid same-canvas plates only — never invent warped intermediates.
const FRAME_FILES := [
	"chest_closed.png",
	"chest_open_10.png",
	"chest_open_25.png",
	"chest_ajar.png",
	"chest_half.png",
	"chest_open.png",
]
## Wall-clock open_amount thresholds (after custom easing). Bias early frames for lid break.
const FRAME_STOPS: Array[float] = [0.0, 0.14, 0.30, 0.48, 0.68, 1.0]
## Full open phase (after anticipation). Settle + magical swell follow.
const OPEN_DURATION_SEC := 0.88
const OPEN_DURATION_RM := 0.34
const ANTICIPATION_SEC := 0.12
const SETTLE_SEC := 0.12
const MAGICAL_SWELL_SEC := 0.18
const SCROLL_EMERGE_SEC := 0.68
const EMPHASIS_SCALE := 1.012

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _input_locked: bool = false
var _label: Label
var _root_visual: Control
var _contact_shadow: TextureRect
var _frame_plate: TextureRect
var _interior: TextureRect
var _interior_glow: TextureRect
var _rim_light: TextureRect
var _front_lip: TextureRect
var _highlight: TextureRect
var _scroll_spawn: Control
var _rolled_scroll: TextureRect
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _motes: CPUParticles2D
var _button: Button
var _ready_visuals: bool = false
var _badge: Label
var _unread_count: int = 0
var _open_amount: float = 0.0
var _show_scroll_on_finish: bool = false
var _anchor_rect: Rect2 = Rect2()
var _frame_index: int = 0
var _frame_textures: Array[Texture2D] = []
var _anticipation_y: float = 0.0
var _emphasis_scale: float = 1.0
var _particles_armed: bool = false

## Process-wide preload so the first tap never decompresses textures.
static var _tex_cache: Dictionary = {}
static var _preloaded: bool = false


static func preload_assets() -> void:
	if _preloaded:
		return
	for fname in FRAME_FILES:
		_load_cached(ART + fname)
	for path in [
		ART + "chest_inner_glow.png",
		ART + "chest_interior.png",
		ART + "chest_contact_shadow.png",
		ART + "chest_front_lip.png",
		ART + "chest_highlight.png",
		SCROLL_ART + "scroll_rolled.png",
	]:
		_load_cached(path)
	_preloaded = true


static func _load_cached(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(FRAME_SIZE.x, FRAME_SIZE.x)
	modulate.a = 1.0
	visible = true
	preload_assets()
	_cache_frame_textures()
	_build_visuals()
	_ready_visuals = true
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = "Open your chest"
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	set_process(not reduced_motion)
	resized.connect(_layout_frames)
	_layout_frames()
	_show_frame_progress(0.0)


func _cache_frame_textures() -> void:
	_frame_textures.clear()
	for fname in FRAME_FILES:
		_frame_textures.append(_load_cached(ART + fname))


func _tex(fname: String) -> Texture2D:
	return _load_cached(ART + fname)


func _make_tr(tex: Texture2D, z: int, name: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = name
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = z
	return tr


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.name = "ChestAnimationRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_visual)

	_contact_shadow = _make_tr(_tex("chest_contact_shadow.png"), 0, "ContactShadow")
	_contact_shadow.modulate = Color(1, 1, 1, 0.88)
	_root_visual.add_child(_contact_shadow)

	## Single plate — swap texture by index (never two full chests / ghost crossfade).
	var first: Texture2D = _frame_textures[0] if not _frame_textures.is_empty() else null
	_frame_plate = _make_tr(first, 2, "ChestFrame")
	_root_visual.add_child(_frame_plate)

	## Dark/warm cavity deepen (cavity-focused; invisible when closed).
	_interior = _make_tr(_tex("chest_interior.png"), 3, "InteriorCavity")
	_interior.modulate = Color(0.55, 0.38, 0.22, 0.0)
	_root_visual.add_child(_interior)

	## Magical light escaping through the opening.
	_interior_glow = _make_tr(_tex("chest_inner_glow.png"), 4, "InteriorGlow")
	_interior_glow.modulate = Color(1.15, 0.9, 0.55, 0.0)
	_root_visual.add_child(_interior_glow)

	## Soft spill onto rim / upper edge as light grows.
	_rim_light = _make_tr(_tex("chest_highlight.png"), 5, "RimLight")
	_rim_light.modulate = Color(1.2, 0.92, 0.55, 0.0)
	_root_visual.add_child(_rim_light)

	_scroll_spawn = Control.new()
	_scroll_spawn.name = "ScrollSpawnPoint"
	_scroll_spawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_spawn.z_index = 6
	_scroll_spawn.visible = false
	_scroll_spawn.clip_contents = true
	_root_visual.add_child(_scroll_spawn)

	_rolled_scroll = TextureRect.new()
	_rolled_scroll.texture = _load_cached(SCROLL_ART + "scroll_rolled.png")
	_rolled_scroll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rolled_scroll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rolled_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rolled_scroll.modulate = Color(1, 1, 1, 0)
	_rolled_scroll.visible = false
	_scroll_spawn.add_child(_rolled_scroll)

	## Front rim occludes emerging scroll (depth).
	_front_lip = _make_tr(_tex("chest_front_lip.png"), 7, "ForegroundLip")
	_front_lip.modulate.a = 0.0
	_root_visual.add_child(_front_lip)

	_highlight = _make_tr(_tex("chest_highlight.png"), 8, "Highlight")
	_highlight.modulate = Color(1, 1, 1, 0.28)
	_root_visual.add_child(_highlight)

	_dust = _make_particles(Color(0.90, 0.78, 0.48, 0.40), 4, Vector2(0, -1), 14.0, 0.70)
	_dust.z_index = 7
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.84, 0.48, 0.50), 2, Vector2(0, -1), 22.0, 0.55)
	_sparks.z_index = 7
	_root_visual.add_child(_sparks)
	## Soft continuous motes once interior is visible (low count).
	_motes = _make_particles(Color(1.0, 0.86, 0.55, 0.35), 5, Vector2(0, -1), 10.0, 1.1)
	_motes.one_shot = false
	_motes.explosiveness = 0.0
	_motes.z_index = 7
	_root_visual.add_child(_motes)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 15)
	_badge.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1))
	_badge.visible = false
	_badge.z_index = 20
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 17)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 12
	add_child(_label)


func _make_particles(
	color: Color,
	amount: int,
	dir: Vector2,
	speed: float,
	lifetime: float = 0.55
) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.15
	p.local_coords = true
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = speed * 0.10
	p.initial_velocity_max = speed * 0.42
	p.gravity = Vector2(0, 14)
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.52
	p.color = color
	return p


func _layout_frames() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(FRAME_SIZE.x, FRAME_SIZE.x)
	_root_visual.pivot_offset = area * 0.5
	var frame_h: float = area.x * (FRAME_SIZE.y / FRAME_SIZE.x)
	var top: float = (area.y - frame_h) * 0.42
	_anchor_rect = Rect2(0, top, area.x, frame_h)

	## Every plate shares identical rect — base stays planted across frames.
	_place_rect(_frame_plate, _anchor_rect)
	## Interior + glow focused on cavity / opening (not whole-sprite flood).
	var cavity := Rect2(
		_anchor_rect.position.x + _anchor_rect.size.x * 0.18,
		_anchor_rect.position.y + frame_h * 0.24,
		_anchor_rect.size.x * 0.64,
		frame_h * 0.44
	)
	_place_rect(_interior, cavity)
	_place_rect(_interior_glow, cavity)
	_place_rect(_rim_light, Rect2(
		_anchor_rect.position.x + _anchor_rect.size.x * 0.12,
		_anchor_rect.position.y + frame_h * 0.18,
		_anchor_rect.size.x * 0.76,
		frame_h * 0.38
	))
	_place_rect(_highlight, _anchor_rect)
	_place_rect(_contact_shadow, Rect2(
		_anchor_rect.position.x,
		_anchor_rect.position.y + frame_h * 0.72,
		_anchor_rect.size.x,
		frame_h * 0.35
	))
	_place_rect(_front_lip, Rect2(
		_anchor_rect.position.x,
		_anchor_rect.position.y + frame_h * 0.52,
		_anchor_rect.size.x,
		frame_h * 0.48
	))

	var cavity_center := Vector2(area.x * 0.5, _anchor_rect.position.y + frame_h * 0.40)
	_dust.position = cavity_center
	_sparks.position = cavity_center
	_motes.position = cavity_center
	var scroll_w := area.x * 0.50
	var scroll_h := scroll_w * 0.30
	var spawn_h := scroll_h * 2.8
	## Origin inside open cavity; front lip occludes until rise clears rim.
	var rim_y := _anchor_rect.position.y + frame_h * 0.36
	_scroll_spawn.position = Vector2(area.x * 0.5 - scroll_w * 0.5, rim_y - scroll_h * 0.10)
	_scroll_spawn.size = Vector2(scroll_w, spawn_h)
	_rolled_scroll.size = Vector2(scroll_w, scroll_h)
	_rolled_scroll.pivot_offset = Vector2(scroll_w * 0.5, scroll_h * 0.5)
	_apply_root_transform()
	if _badge:
		_badge.position = Vector2(area.x * 0.72, top + frame_h * 0.08)
		_badge.size = Vector2(40, 40)


func _place_rect(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.position = rect.position
	node.size = rect.size


func _apply_root_transform() -> void:
	## Anticipation = tiny Y only. Emphasis = optional 1–2% settle pulse. Never open via scale.y.
	if _root_visual == null:
		return
	var z := _emphasis_scale
	_root_visual.scale = Vector2(z, z)
	_root_visual.rotation = 0.0
	_root_visual.position = Vector2(
		(1.0 - z) * size.x * 0.5,
		_anticipation_y + (1.0 - z) * size.y * 0.5
	)


func set_unread_badge(count: int) -> void:
	_unread_count = count
	if _badge == null:
		return
	if count <= 0:
		_badge.visible = false
		_badge.text = ""
		return
	_badge.visible = true
	_badge.text = str(mini(count, 99))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.98, 0.78, 0.42, 1.0)
	bg.set_corner_radius_all(20)
	_badge.add_theme_stylebox_override("normal", bg)


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_input_locked = false
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_stop_motes()
	_reset_pose()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			self_modulate = Color(0.55, 0.55, 0.75, 0.9)
			_interior_glow.modulate.a = 0.0
			_label.visible = false
			_show_frame_progress(0.0)
			set_process(false)
		ChestState.AVAILABLE, ChestState.READY:
			self_modulate = Color.WHITE
			_interior_glow.modulate.a = 0.0
			_label.visible = show_final_label
			_label.text = "Your Chest"
			_show_frame_progress(0.0)
			set_process(not reduced_motion)
		ChestState.OPENED, ChestState.OPEN_EMPTY:
			self_modulate = Color.WHITE
			_show_frame_progress(1.0)
			_label.visible = false
			_interior_glow.modulate.a = 0.68
			_front_lip.modulate.a = 0.10
			set_process(false)
		_:
			set_process(false)


func _ease_open_curve(t: float) -> float:
	## Slight resistance → smooth acceleration → gentle deceleration (no bounce).
	t = clampf(t, 0.0, 1.0)
	## Smoothstep-ish cubic bias toward ease-in-out with a touch more early resistance.
	var s := t * t * (3.0 - 2.0 * t)
	var early := t * t * t
	return lerpf(early, s, 0.72)


func _show_frame_progress(raw_amount: float) -> void:
	## Map eased open amount to ONE discrete plate + layered FX.
	var linear := clampf(raw_amount, 0.0, 1.0)
	_open_amount = linear
	var eased := _ease_open_curve(linear)
	var idx := _frame_index_for_amount(eased)
	_set_frame_index(idx)

	## Interior depth reveal — invisible when closed; grows with lid clearance.
	var interior_a := 0.0
	if linear > 0.10:
		interior_a = clampf((linear - 0.10) * 0.95, 0.0, 0.55)
	if _interior:
		_interior.modulate = Color(0.62, 0.42, 0.24, interior_a)

	## Warm magical light from inside — subtle at first crack, swells open.
	var glow_a := 0.0
	if linear < 0.10:
		glow_a = linear * 0.35
	elif linear < 0.45:
		glow_a = 0.035 + (linear - 0.10) * 1.15
	else:
		glow_a = 0.44 + (linear - 0.45) * 0.72
	if _interior_glow:
		_interior_glow.modulate = Color(1.20, 0.90, 0.52, clampf(glow_a, 0.0, 0.86))

	## Soft spill on rim / upper edge as interior light grows.
	if _rim_light:
		_rim_light.modulate = Color(1.25, 0.94, 0.58, clampf(glow_a * 0.42, 0.0, 0.38))

	if _contact_shadow:
		_contact_shadow.modulate.a = 0.78 + linear * 0.12

	## Front lip peek once ajar (helps sell depth even before scroll).
	if _front_lip and chest_state == ChestState.OPENING:
		_front_lip.modulate.a = clampf((linear - 0.35) * 0.55, 0.0, 0.28)

	## Particles only after interior is visible.
	if not reduced_motion and linear >= 0.32 and not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()


func _frame_index_for_amount(amount: float) -> int:
	var count := maxi(_frame_textures.size(), 1)
	if amount >= 0.999:
		return count - 1
	if amount <= 0.0:
		return 0
	var stops := FRAME_STOPS
	var last := mini(count, stops.size()) - 1
	for i in range(1, last + 1):
		if amount < float(stops[i]):
			return i - 1
	return last


func _set_frame_index(idx: int) -> void:
	if _frame_textures.is_empty() or _frame_plate == null:
		return
	idx = clampi(idx, 0, _frame_textures.size() - 1)
	_frame_index = idx
	var tex: Texture2D = _frame_textures[idx]
	if tex != null and _frame_plate.texture != tex:
		_frame_plate.texture = tex
	_frame_plate.modulate.a = 1.0
	_frame_plate.visible = true


func _reset_pose() -> void:
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
		_root_visual.modulate = Color.WHITE
	_layout_frames()
	if _rolled_scroll:
		_rolled_scroll.modulate = Color(1, 1, 1, 0)
		_rolled_scroll.visible = false
		_rolled_scroll.scale = Vector2.ONE
		_rolled_scroll.rotation_degrees = 0.0
	if _scroll_spawn:
		_scroll_spawn.visible = false
	if _front_lip:
		_front_lip.modulate.a = 0.0
	if _interior:
		_interior.modulate.a = 0.0
	if _rim_light:
		_rim_light.modulate.a = 0.0


func _process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
		return
	if animating or reduced_motion or not _ready_visuals:
		return
	if chest_state != ChestState.AVAILABLE and chest_state != ChestState.READY:
		return
	_idle_time += delta
	## Idle shimmer only — no breathing scale on the chest body.
	if _highlight:
		_highlight.modulate.a = 0.16 + 0.08 * sin(_idle_time * 1.4)


func set_active_processing(enabled: bool) -> void:
	set_process(enabled)


func _on_pressed() -> void:
	if _input_locked or animating:
		_skip = true
		skip_requested.emit()
		return
	if chest_state == ChestState.OPENING \
			or chest_state == ChestState.OPEN_WAITING_FOR_SCROLL \
			or chest_state == ChestState.OPEN_SCROLL_EMERGING \
			or chest_state == ChestState.TRANSITIONING \
			or chest_state == ChestState.CLOSING:
		return
	tapped.emit()


func play_press_feedback() -> void:
	## Tiny planted response (2–4 px) — not a button bounce.
	HapticHelper.light_tap()
	if reduced_motion:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_anticipation_y = v
		_apply_root_transform()
	, 0.0, 3.0, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float) -> void:
		_anticipation_y = v
		_apply_root_transform()
	, 3.0, 0.0, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func play_empty_feedback() -> void:
	await play_open_empty_pulse()


func play_open_empty_pulse() -> void:
	## Retap on open empty: glow/motes/shimmer only — lid stays open.
	if animating:
		return
	if chest_state != ChestState.OPENED and chest_state != ChestState.OPEN_EMPTY:
		if _open_amount < 0.95:
			return
	animating = true
	_input_locked = true
	HapticHelper.light_tap()
	var base_a := 0.68
	if _interior_glow:
		base_a = _interior_glow.modulate.a
	var glow := create_tween()
	glow.tween_property(_interior_glow, "modulate:a", minf(base_a + 0.20, 0.94), 0.14).set_trans(Tween.TRANS_SINE)
	glow.tween_property(_interior_glow, "modulate:a", base_a, 0.30).set_trans(Tween.TRANS_SINE)
	if _highlight:
		var shimmer := create_tween()
		shimmer.tween_property(_highlight, "modulate:a", 0.44, 0.12).set_trans(Tween.TRANS_SINE)
		shimmer.tween_property(_highlight, "modulate:a", 0.22, 0.24).set_trans(Tween.TRANS_SINE)
	if _rim_light:
		var rim := create_tween()
		rim.tween_property(_rim_light, "modulate:a", 0.34, 0.12)
		rim.tween_property(_rim_light, "modulate:a", 0.18, 0.26)
	if not reduced_motion:
		_emit_burst()
	await glow.finished
	animating = false
	_input_locked = false


func play_open_animation(short: bool = false, emerge_scroll: bool = false) -> void:
	if animating \
			or chest_state == ChestState.OPENING \
			or chest_state == ChestState.OPEN_WAITING_FOR_SCROLL \
			or chest_state == ChestState.OPEN_SCROLL_EMERGING \
			or chest_state == ChestState.TRANSITIONING \
			or chest_state == ChestState.CLOSING:
		return
	if (chest_state == ChestState.OPENED or chest_state == ChestState.OPEN_EMPTY) and not emerge_scroll:
		await play_open_empty_pulse()
		return
	animating = true
	_input_locked = true
	_skip = false
	_particles_armed = false
	set_process(false)
	_show_scroll_on_finish = emerge_scroll
	chest_state = ChestState.OPENING
	sfx_open_start.emit()
	play_press_feedback()
	if reduced_motion or short:
		await _open_short()
	else:
		await _open_full()
	_apply_finished_state()
	if emerge_scroll:
		chest_state = ChestState.TRANSITIONING
	else:
		chest_state = ChestState.OPENED
	animating = false
	_input_locked = false
	sfx_fully_open.emit()
	open_finished.emit()


func play_close_animation() -> void:
	if animating or chest_state == ChestState.OPENING or chest_state == ChestState.OPEN_SCROLL_EMERGING:
		return
	animating = true
	_input_locked = true
	chest_state = ChestState.CLOSING
	_stop_motes()
	hide_rolled_scroll()
	var dur := 0.28 if reduced_motion else 0.55
	var tw := create_tween()
	tw.tween_method(_show_frame_progress, _open_amount, 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_show_frame_progress(0.0)
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	chest_state = ChestState.READY
	animating = false
	_input_locked = false


func play_final_reopen_animation() -> void:
	await play_open_animation(true, false)


func set_interaction_enabled(enabled: bool) -> void:
	_input_locked = not enabled
	if _button != null and is_instance_valid(_button):
		_button.disabled = not enabled
		_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func finish_opening_safely() -> void:
	if not animating:
		return
	_skip = true
	_apply_finished_state()
	animating = false
	_input_locked = false
	chest_state = ChestState.OPENED if not _show_scroll_on_finish else ChestState.TRANSITIONING
	open_finished.emit()


func apply_ready_idle_state() -> void:
	animating = false
	_skip = false
	_idle_time = 0.0
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_stop_motes()
	if _dust != null:
		_dust.emitting = false
	if _sparks != null:
		_sparks.emitting = false
	hide_rolled_scroll()
	_reset_pose()
	configure(ChestState.READY, true)
	set_interaction_enabled(true)
	modulate = Color(1, 1, 1, 1)
	visible = true


func _open_short() -> void:
	## Reduced motion: closed → brief glow → open pose. Same logical outcomes.
	_show_frame_progress(0.0)
	_layout_frames()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_show_frame_progress, 0.0, 1.0, OPEN_DURATION_RM).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_interior_glow, "modulate:a", 0.72, OPEN_DURATION_RM).set_trans(Tween.TRANS_SINE)
	await tw.finished
	if _show_scroll_on_finish and not _skip:
		await _emerge_scroll()
	else:
		await get_tree().create_timer(0.08).timeout


func _open_full() -> void:
	_layout_frames()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	## Anticipation / latch (press feedback runs in parallel).
	await get_tree().create_timer(ANTICIPATION_SEC).timeout
	if _skip:
		_apply_finished_state()
		return

	sfx_latch_release.emit()
	HapticHelper.lock_release()

	## Main lid opening — elapsed-time tween; visual amount runs through custom curve.
	var lid := create_tween()
	lid.tween_method(_show_frame_progress, 0.0, 1.0, OPEN_DURATION_SEC).set_trans(Tween.TRANS_LINEAR)
	await lid.finished
	if _skip:
		_apply_finished_state()
		return

	## Settle into fully open + tiny emphasis (not screen shake).
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_interior_glow, "modulate:a", 0.84, SETTLE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, 1.0, EMPHASIS_SCALE, SETTLE_SEC * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await settle.finished

	sfx_magical_swell.emit()
	var swell := create_tween()
	swell.set_parallel(true)
	swell.tween_property(_interior_glow, "modulate:a", 0.92, MAGICAL_SWELL_SEC).set_trans(Tween.TRANS_SINE)
	swell.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, EMPHASIS_SCALE, 1.0, MAGICAL_SWELL_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await swell.finished
	_emphasis_scale = 1.0
	_apply_root_transform()

	if _show_scroll_on_finish and not _skip:
		chest_state = ChestState.OPEN_WAITING_FOR_SCROLL
		await get_tree().create_timer(0.10).timeout
		await _emerge_scroll()
		scroll_emerged.emit(get_scroll_global_center())
	else:
		await get_tree().create_timer(0.06).timeout
		_stop_motes()
	_anticipation_y = 0.0
	_apply_root_transform()


func _emerge_scroll() -> void:
	if _rolled_scroll == null:
		return
	## Scroll only after lid is substantially / fully open.
	if _open_amount < 0.95:
		var catchup := create_tween()
		catchup.tween_method(_show_frame_progress, _open_amount, 1.0, 0.08)
		await catchup.finished
	chest_state = ChestState.OPEN_SCROLL_EMERGING
	sfx_scroll_emerge.emit()
	_scroll_spawn.visible = true
	_rolled_scroll.visible = true
	## Warm glow on parchment while inside, then settle to normal.
	_rolled_scroll.modulate = Color(1.15, 0.95, 0.70, 0.0)
	_rolled_scroll.scale = Vector2(0.84, 0.84)
	var start_y := _scroll_spawn.size.y * 0.68
	var end_y := 4.0
	_rolled_scroll.position = Vector2(0, start_y)
	_rolled_scroll.rotation_degrees = -2.5
	_front_lip.modulate.a = 0.92
	var glow_up := create_tween()
	glow_up.tween_property(_interior_glow, "modulate:a", 0.95, 0.16).set_trans(Tween.TRANS_SINE)
	await glow_up.finished
	if _skip:
		return
	## Polished rise: slow lift → accelerate → slight enlarge → settle.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rolled_scroll, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "position:y", end_y, SCROLL_EMERGE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "scale", Vector2(1.02, 1.02), SCROLL_EMERGE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "rotation_degrees", 0.0, SCROLL_EMERGE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rolled_scroll, "modulate", Color(1, 1, 1, 1), SCROLL_EMERGE_SEC * 0.85).set_trans(Tween.TRANS_SINE)
	await tw.finished
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_rolled_scroll, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	settle.tween_property(_front_lip, "modulate:a", 0.14, 0.16)
	await settle.finished
	_stop_motes()


func get_scroll_global_center() -> Vector2:
	if _rolled_scroll and is_instance_valid(_rolled_scroll) and _rolled_scroll.visible:
		return _rolled_scroll.global_position + _rolled_scroll.size * 0.5
	return global_position + size * 0.5


func hide_rolled_scroll() -> void:
	if _rolled_scroll:
		_rolled_scroll.modulate = Color(1, 1, 1, 0)
		_rolled_scroll.visible = false
	if _scroll_spawn:
		_scroll_spawn.visible = false
	if _front_lip:
		_front_lip.modulate.a = 0.0


func _apply_finished_state() -> void:
	_show_frame_progress(1.0)
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	if not _show_scroll_on_finish:
		_front_lip.modulate.a = 0.10
	if _show_scroll_on_finish and _rolled_scroll:
		_scroll_spawn.visible = true
		_rolled_scroll.visible = true
		_rolled_scroll.modulate = Color(1, 1, 1, 1)
		_rolled_scroll.position = Vector2(0, 4.0)
		_rolled_scroll.scale = Vector2.ONE
		_rolled_scroll.rotation_degrees = 0.0
	else:
		hide_rolled_scroll()


func _emit_burst() -> void:
	if reduced_motion:
		return
	_dust.restart()
	_dust.emitting = true
	_sparks.restart()
	_sparks.emitting = true


func _start_motes() -> void:
	if reduced_motion or _motes == null:
		return
	_motes.emitting = true


func _stop_motes() -> void:
	if _motes != null:
		_motes.emitting = false


func request_skip() -> void:
	_skip = true


func frame_count() -> int:
	return _frame_textures.size()
