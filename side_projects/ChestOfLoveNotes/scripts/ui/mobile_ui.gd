extends RefCounted
class_name MobileUi
## Central mobile accessibility scale + theme tokens for Chest of Love Notes.
## Adjusts font sizes via theme overrides; never applies node scale transforms for text.
##
## Android system font-scale is not reliably exposed through Godot 4.7.1 on all
## devices — the in-app Text Size setting is the supported accessibility path.

enum TextSize { STANDARD, LARGE, EXTRA_LARGE }

const SETTINGS_PATH := "user://coln_settings.cfg"
const PREF_TEXT_SIZE := "text_size"
const PREF_REDUCED_MOTION := "reduced_motion"

## Base sizes (Standard = 1.0). Scaled by text size preference.
const SIZE_SCREEN_TITLE := 30
const SIZE_MAJOR_HEADING := 26
const SIZE_SECTION := 22
const SIZE_BODY := 19
const SIZE_SECONDARY := 17
const SIZE_HELPER := 16
const SIZE_BUTTON := 19
const SIZE_STAT_NUMBER := 26
const SIZE_STAT_LABEL := 16
const SIZE_NAV_LABEL := 15
const SIZE_BADGE := 16

const TOUCH_MIN := 48
const TOUCH_PRIMARY_H := 60
const TOUCH_NAV_H := 78
const INPUT_H := 56

const COLOR_TITLE := Color(0.98, 0.86, 0.45)
const COLOR_BODY := Color(0.96, 0.92, 0.86)
const COLOR_SECONDARY := Color(0.90, 0.86, 0.94)
const COLOR_HELPER := Color(0.82, 0.78, 0.88)
const COLOR_DANGER := Color(1.0, 0.62, 0.52)
const COLOR_CARD := Color(0.12, 0.08, 0.20, 0.92)
const COLOR_CARD_BORDER := Color(0.55, 0.42, 0.72, 0.55)
const COLOR_NAV_BG := Color(0.08, 0.05, 0.14, 0.97)
const COLOR_NAV_SELECTED := Color(0.98, 0.86, 0.45)
const COLOR_NAV_IDLE := Color(0.78, 0.72, 0.86)
const COLOR_BTN := Color(0.42, 0.16, 0.28, 1.0)
const COLOR_BTN_BORDER := Color(0.72, 0.48, 0.28, 0.9)

static var _text_size: TextSize = TextSize.STANDARD
static var _reduced_motion: bool = false
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		_text_size = TextSize.STANDARD
		_reduced_motion = false
		return
	var raw := str(cfg.get_value("accessibility", PREF_TEXT_SIZE, "standard")).to_lower()
	match raw:
		"large":
			_text_size = TextSize.LARGE
		"extra_large", "xl", "extra-large":
			_text_size = TextSize.EXTRA_LARGE
		_:
			_text_size = TextSize.STANDARD
	_reduced_motion = bool(cfg.get_value("accessibility", PREF_REDUCED_MOTION, false))


static func scale_factor() -> float:
	ensure_loaded()
	match _text_size:
		TextSize.LARGE:
			return 1.20
		TextSize.EXTRA_LARGE:
			return 1.40
		_:
			return 1.0


static func font(base: int) -> int:
	return maxi(14, int(round(float(base) * scale_factor())))


static func text_size() -> TextSize:
	ensure_loaded()
	return _text_size


static func text_size_label() -> String:
	match text_size():
		TextSize.LARGE:
			return "Large"
		TextSize.EXTRA_LARGE:
			return "Extra Large"
		_:
			return "Standard"


static func set_text_size(size: TextSize) -> void:
	ensure_loaded()
	_text_size = size
	_save()


static func cycle_text_size() -> TextSize:
	var next: TextSize = TextSize.STANDARD
	match text_size():
		TextSize.STANDARD:
			next = TextSize.LARGE
		TextSize.LARGE:
			next = TextSize.EXTRA_LARGE
		_:
			next = TextSize.STANDARD
	set_text_size(next)
	return next


static func reduced_motion() -> bool:
	ensure_loaded()
	return _reduced_motion


static func set_reduced_motion(enabled: bool) -> void:
	ensure_loaded()
	_reduced_motion = enabled
	_save()


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var label := "standard"
	match _text_size:
		TextSize.LARGE:
			label = "large"
		TextSize.EXTRA_LARGE:
			label = "extra_large"
	cfg.set_value("accessibility", PREF_TEXT_SIZE, label)
	cfg.set_value("accessibility", PREF_REDUCED_MOTION, _reduced_motion)
	cfg.save(SETTINGS_PATH)


static func apply_label(lab: Label, base_size: int, color: Color = COLOR_BODY, autowrap: bool = false) -> void:
	## Default: no autowrap. Autowrap on short labels inside HBoxes collapses
	## width and stacks letters vertically on tall phones.
	lab.add_theme_font_size_override("font_size", font(base_size))
	lab.add_theme_color_override("font_color", color)
	if autowrap:
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF


static func card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CARD
	sb.border_color = COLOR_CARD_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


static func button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BTN
	sb.border_color = COLOR_BTN_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func style_button(btn: Button, min_h: int = TOUCH_PRIMARY_H) -> void:
	btn.custom_minimum_size = Vector2(maxi(TOUCH_MIN, int(btn.custom_minimum_size.x)), font_touch(min_h))
	btn.add_theme_font_size_override("font_size", font(SIZE_BUTTON))
	btn.add_theme_color_override("font_color", COLOR_BODY)
	btn.add_theme_stylebox_override("normal", button_style())
	var hover := button_style()
	hover.bg_color = Color(0.50, 0.20, 0.34, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.focus_mode = Control.FOCUS_NONE


static func font_touch(base_h: int) -> int:
	## Touch targets grow modestly with text size, capped to avoid layout blowups.
	return maxi(TOUCH_MIN, int(round(float(base_h) * minf(scale_factor(), 1.25))))


static func style_line_edit(edit: LineEdit) -> void:
	edit.custom_minimum_size.y = font_touch(INPUT_H)
	edit.add_theme_font_size_override("font_size", font(SIZE_BODY))
	edit.add_theme_color_override("font_color", COLOR_BODY)
	edit.add_theme_color_override("font_placeholder_color", COLOR_HELPER)


static func style_text_edit(edit: TextEdit) -> void:
	edit.add_theme_font_size_override("font_size", font(SIZE_BODY))
	edit.add_theme_color_override("font_color", COLOR_BODY)


static func apply_safe_margins(margin: MarginContainer, extra_bottom: int = 0) -> void:
	SafeAreaHelper.apply_to_margin(margin, 18, 12, 12 + extra_bottom)
