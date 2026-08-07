extends Control
class_name CharoiteBoot
## Cold-start Charoite Games brand presentation (~1.5–2.0 seconds).
## ONE centered official CG logo. No chest, no "Presents", no duplicate labels.
## Official logo artwork is never rewritten — display only crops near-black margins
## in memory so the mark sits cleanly on a matching black field.

signal finished

const MIN_DURATION_SEC := 1.75
const FADE_IN_SEC := 0.28
const FADE_OUT_SEC := 0.28
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
	## In-memory trim of near-black letterbox so the JPEG rectangle doesn't
	## read as a floating dark card on the purple app chrome underneath.
	img = _trim_near_black_margins(img)
	return ImageTexture.create_from_image(img)


func _trim_near_black_margins(img: Image) -> Image:
	if img == null or img.get_width() < 8 or img.get_height() < 8:
		return img
	var w := img.get_width()
	var h := img.get_height()
	var threshold := 18
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	## Sample every few pixels for speed on large logos.
	var step := maxi(1, int(mini(w, h) / 180.0))
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.r * 255.0 > threshold or c.g * 255.0 > threshold or c.b * 255.0 > threshold:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x <= min_x or max_y <= min_y:
		return img
	## Expand a little so we don't clip glow, then clamp.
	var pad := int(maxi(w, h) * 0.02)
	min_x = maxi(0, min_x - pad)
	min_y = maxi(0, min_y - pad)
	max_x = mini(w - 1, max_x + pad)
	max_y = mini(h - 1, max_y + pad)
	var cw := max_x - min_x + 1
	var ch := max_y - min_y + 1
	if cw < w * 0.35 or ch < h * 0.35:
		return img
	return img.get_region(Rect2i(min_x, min_y, cw, ch))


func _build() -> void:
	## Pure black plane matching the official logo field — eliminates the
	## "dark rectangle on purple" mismatch when boot sits over app chrome.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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
