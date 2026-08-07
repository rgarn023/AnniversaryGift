extends Control
class_name CharoiteBoot
## Cold-start Charoite Games brand presentation (≥5 seconds).
## ONE centered official CG logo. No chest, no "Presents", no duplicate labels.

signal finished

const MIN_DURATION_SEC := 5.0
const FADE_IN_SEC := 0.6
const FADE_OUT_SEC := 0.6
## Official CG monogram — source of truth when present on disk (kept byte-identical).
const OFFICIAL_CG := "res://assets/branding/charoite_games_cg_logo.png"
## Interim single mark if official file is not yet packaged (never use PRESENTS splash).
const FALLBACK_WORDMARK := "res://assets/art/brand/charoite_games_wordmark.png"
## Portrait official mark fits ~72% of the 390-wide logical viewport.
const LOGO_DISPLAY := Vector2(280, 372)

var _started_usec: int = 0
var _logo: TextureRect
var _done: bool = false
var _used_official: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_started_usec = Time.get_ticks_usec()
	_build()
	_play()


func _load_official_texture() -> Texture2D:
	## Official asset is kept as raw bytes (may be JPEG content with a .png name).
	## Load via buffer so the source file is never rewritten/recompressed.
	if not FileAccess.file_exists(OFFICIAL_CG):
		return null
	var fa := FileAccess.open(OFFICIAL_CG, FileAccess.READ)
	if fa == null:
		return null
	var buf: PackedByteArray = fa.get_buffer(fa.get_length())
	fa.close()
	if buf.is_empty():
		return null
	var img := Image.new()
	var err := img.load_jpg_from_buffer(buf)
	if err != OK:
		err = img.load_png_from_buffer(buf)
	if err != OK:
		err = img.load_webp_from_buffer(buf)
	if err != OK:
		push_warning("CharoiteBoot: could not decode official CG logo bytes")
		return null
	return ImageTexture.create_from_image(img)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.05, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	## Solid black/cosmic plane only — no second brand mark / wordmark / chest.
	## Official logo already includes its own black field + glow.

	_logo = TextureRect.new()
	var tex: Texture2D = _load_official_texture()
	if tex != null:
		_logo.texture = tex
		_used_official = true
	elif ResourceLoader.exists(FALLBACK_WORDMARK):
		_logo.texture = load(FALLBACK_WORDMARK)
		_used_official = false
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = LOGO_DISPLAY
	_logo.size = LOGO_DISPLAY
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.position = Vector2(-LOGO_DISPLAY.x * 0.5, -LOGO_DISPLAY.y * 0.5)
	_logo.modulate.a = 0.0
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	## Intentionally NO Label, NO "Charoite Games Presents", NO second logo, NO chest.


func _play() -> void:
	var fade_in := create_tween()
	fade_in.tween_property(_logo, "modulate:a", 1.0, FADE_IN_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fade_in.finished
	## Hold until total duration reaches MIN_DURATION_SEC including fade-out window.
	var elapsed := (Time.get_ticks_usec() - _started_usec) / 1_000_000.0
	var hold := maxf(0.05, MIN_DURATION_SEC - elapsed - FADE_OUT_SEC)
	await get_tree().create_timer(hold).timeout
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
