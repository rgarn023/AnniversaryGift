extends Control
class_name CharoiteBoot
## Cold-start Charoite Games brand presentation.
## Plays the APPROVED animated splash derived from 154659_cursor_under4mb.gif
## (frame sequence preserves order/timing). Does not redraw or recolor the mark.
## Session/backend restore runs in parallel during this presentation.

signal finished

const MIN_DURATION_SEC := 1.75
const FADE_IN_SEC := 0.28
const FADE_OUT_SEC := 0.28
const SOURCE_GIF := "res://assets/branding/154659_cursor_under4mb.gif"
const FRAMES_META := "res://assets/branding/splash_frames_meta.json"
const STILL_FRAME := "res://assets/branding/splash_still.png"
## Legacy still mark if approved GIF/frames are not yet packaged.
const OFFICIAL_CG := "res://assets/branding/charoite_games_cg_logo.png"
const FALLBACK_WORDMARK := "res://assets/art/brand/charoite_games_wordmark.png"
## Portrait fit with edge padding on 390-wide logical viewport.
const LOGO_DISPLAY := Vector2(300, 400)

var _started_usec: int = 0
var _logo: TextureRect
var _done: bool = false
var _used_official: bool = false
var _used_animation: bool = false
var _anim_frames: Array[Texture2D] = []
var _anim_durations_sec: Array[float] = []
var _anim_index: int = 0
var _anim_accum: float = 0.0
var _anim_playing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_started_usec = Time.get_ticks_usec()
	_build()
	_play()


func _process(delta: float) -> void:
	if not _anim_playing or _anim_frames.is_empty() or _logo == null:
		return
	_anim_accum += delta
	var hold := _anim_durations_sec[_anim_index] if _anim_index < _anim_durations_sec.size() else 0.1
	if _anim_accum < hold:
		return
	_anim_accum = 0.0
	_anim_index = (_anim_index + 1) % _anim_frames.size()
	_logo.texture = _anim_frames[_anim_index]


func _load_frames_from_meta() -> bool:
	if not FileAccess.file_exists(FRAMES_META):
		return false
	var fa := FileAccess.open(FRAMES_META, FileAccess.READ)
	if fa == null:
		return false
	var parsed: Variant = JSON.parse_string(fa.get_as_text())
	fa.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var meta: Dictionary = parsed
	var count := int(meta.get("frame_count", 0))
	var durs: Array = meta.get("durations_ms", []) if typeof(meta.get("durations_ms")) == TYPE_ARRAY else []
	if count <= 0:
		return false
	_anim_frames.clear()
	_anim_durations_sec.clear()
	for i in range(count):
		var path := "res://assets/branding/splash_frames/frame_%04d.png" % i
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			_anim_frames.clear()
			return false
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		if tex == null:
			## Fallback: decode PNG bytes (unimported export edge cases).
			var fb := FileAccess.open(path, FileAccess.READ)
			if fb == null:
				_anim_frames.clear()
				return false
			var buf: PackedByteArray = fb.get_buffer(fb.get_length())
			fb.close()
			var img := Image.new()
			if img.load_png_from_buffer(buf) != OK:
				_anim_frames.clear()
				return false
			tex = ImageTexture.create_from_image(img)
		_anim_frames.append(tex)
		var ms := 100
		if i < durs.size():
			ms = int(durs[i])
		if ms <= 0:
			ms = 100
		_anim_durations_sec.append(float(ms) / 1000.0)
	return not _anim_frames.is_empty()


func _load_still_texture() -> Texture2D:
	if ResourceLoader.exists(STILL_FRAME):
		return load(STILL_FRAME) as Texture2D
	if FileAccess.file_exists(STILL_FRAME):
		var fa := FileAccess.open(STILL_FRAME, FileAccess.READ)
		if fa != null:
			var buf: PackedByteArray = fa.get_buffer(fa.get_length())
			fa.close()
			var img := Image.new()
			if img.load_png_from_buffer(buf) == OK:
				return ImageTexture.create_from_image(img)
	## Legacy official CG still (byte-identical source load).
	if FileAccess.file_exists(OFFICIAL_CG):
		var fa2 := FileAccess.open(OFFICIAL_CG, FileAccess.READ)
		if fa2 != null:
			var buf2: PackedByteArray = fa2.get_buffer(fa2.get_length())
			fa2.close()
			var img2 := Image.new()
			var err := img2.load_jpg_from_buffer(buf2)
			if err != OK:
				err = img2.load_png_from_buffer(buf2)
			if err != OK:
				err = img2.load_webp_from_buffer(buf2)
			if err == OK:
				return ImageTexture.create_from_image(img2)
	if ResourceLoader.exists(FALLBACK_WORDMARK):
		return load(FALLBACK_WORDMARK) as Texture2D
	return null


func _build() -> void:
	## Pure black plane matching the approved splash field.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_logo = TextureRect.new()
	var reduced := false
	if typeof(MobileUi) != TYPE_NIL:
		reduced = MobileUi.reduced_motion()
	var animated_ok := (not reduced) and _load_frames_from_meta()
	if animated_ok:
		_logo.texture = _anim_frames[0]
		_used_animation = true
		_used_official = true
		_anim_playing = true
		set_process(true)
	else:
		var tex := _load_still_texture()
		if tex != null:
			_logo.texture = tex
			_used_official = true
		_anim_playing = false
		set_process(false)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = LOGO_DISPLAY
	_logo.size = LOGO_DISPLAY
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.position = Vector2(-LOGO_DISPLAY.x * 0.5, -LOGO_DISPLAY.y * 0.5)
	_logo.modulate.a = 0.0
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	## Intentionally NO Label, NO "Charoite Games Presents", NO second logo, NO chest, NO starfield.


func _play() -> void:
	var fade_in := create_tween()
	fade_in.tween_property(_logo, "modulate:a", 1.0, FADE_IN_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fade_in.finished
	## Hold until total duration reaches MIN_DURATION_SEC including fade-out window.
	## Animated splash may naturally run longer; never cut below MIN_DURATION_SEC.
	var min_hold_target := MIN_DURATION_SEC
	if _used_animation and not _anim_durations_sec.is_empty():
		var loop_len := 0.0
		for d in _anim_durations_sec:
			loop_len += d
		## Show at least one full loop when short; cap presentation reasonably.
		min_hold_target = maxf(MIN_DURATION_SEC, minf(loop_len, 3.5))
	var elapsed := (Time.get_ticks_usec() - _started_usec) / 1_000_000.0
	var hold := maxf(0.05, min_hold_target - elapsed - FADE_OUT_SEC)
	await get_tree().create_timer(hold).timeout
	_anim_playing = false
	var fade_out := create_tween()
	fade_out.tween_property(_logo, "modulate:a", 0.0, FADE_OUT_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await fade_out.finished
	_done = true
	finished.emit()


func measured_duration_sec() -> float:
	return (Time.get_ticks_usec() - _started_usec) / 1_000_000.0


func is_finished() -> bool:
	return _done


func used_official_logo() -> bool:
	return _used_official


func used_animation() -> bool:
	return _used_animation
