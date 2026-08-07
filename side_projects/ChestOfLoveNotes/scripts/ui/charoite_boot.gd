extends Control
class_name CharoiteBoot
## Cold-start Charoite Games brand presentation (≥5 seconds).
## Does not include chest artwork.

signal finished

const MIN_DURATION_SEC := 5.0
const WORDMARK := "res://assets/art/brand/charoite_games_wordmark.png"
const BOOT_BG := "res://assets/art/charoite_boot_splash.png"

var _started_usec: int = 0
var _logo: TextureRect
var _label: Label
var _done: bool = false


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

	if ResourceLoader.exists(BOOT_BG):
		var splash := TextureRect.new()
		splash.texture = load(BOOT_BG)
		splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(splash)

	_logo = TextureRect.new()
	if ResourceLoader.exists(WORDMARK):
		_logo.texture = load(WORDMARK)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(260, 260)
	_logo.size = Vector2(260, 260)
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.position = Vector2(-130, -150)
	_logo.modulate.a = 0.0
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

	_label = Label.new()
	_label.text = "Charoite Games"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_label.add_theme_font_override("font", load("res://assets/fonts/Cinzel-Bold.ttf"))
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.position = Vector2(-160, 90)
	_label.size = Vector2(320, 40)
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _play() -> void:
	var fade_in := create_tween()
	fade_in.set_parallel(true)
	fade_in.tween_property(_logo, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_in.tween_property(_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fade_in.finished
	# Hold until minimum duration, then fade out.
	var elapsed := (Time.get_ticks_usec() - _started_usec) / 1_000_000.0
	var hold := maxf(0.05, MIN_DURATION_SEC - elapsed - 0.55)
	await get_tree().create_timer(hold).timeout
	var fade_out := create_tween()
	fade_out.set_parallel(true)
	fade_out.tween_property(_logo, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_out.tween_property(_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await fade_out.finished
	_done = true
	finished.emit()


func measured_duration_sec() -> float:
	return (Time.get_ticks_usec() - _started_usec) / 1_000_000.0


func is_finished() -> bool:
	return _done
