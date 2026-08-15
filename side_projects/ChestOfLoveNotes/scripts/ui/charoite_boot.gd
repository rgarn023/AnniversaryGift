extends Control
class_name CharoiteBoot
## Cold-start Charoite Games brand presentation (≥5 seconds).
## ONE centered official CG logo. No chest, no "Presents", no duplicate labels.

signal finished

const MIN_DURATION_SEC := 5.0
const FADE_IN_SEC := 0.6
const FADE_OUT_SEC := 0.6
## Official CG monogram — source of truth when present on disk.
const OFFICIAL_CG := "res://assets/branding/charoite_games_cg_logo.png"
## Interim single mark if official file is not yet packaged (never use PRESENTS splash).
const FALLBACK_WORDMARK := "res://assets/art/brand/charoite_games_wordmark.png"
const DARK_BG := "res://assets/branding/charoite_system_splash_dark.png"

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


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	if ResourceLoader.exists(DARK_BG):
		var stars := TextureRect.new()
		stars.texture = load(DARK_BG)
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stars)

	_logo = TextureRect.new()
	var logo_path := ""
	if ResourceLoader.exists(OFFICIAL_CG):
		logo_path = OFFICIAL_CG
		_used_official = true
	elif ResourceLoader.exists(FALLBACK_WORDMARK):
		logo_path = FALLBACK_WORDMARK
		_used_official = false
	if logo_path != "":
		_logo.texture = load(logo_path)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(280, 280)
	_logo.size = Vector2(280, 280)
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.position = Vector2(-140, -140)
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
