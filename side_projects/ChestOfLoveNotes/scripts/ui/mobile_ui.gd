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

## Balanced Standard sizes for ~390×844 logical mobile units (not oversized tablet-a11y).
const SIZE_APP_TITLE := 27
const SIZE_SCREEN_TITLE := 24
const SIZE_MAJOR_HEADING := 20
const SIZE_SECTION := 18
const SIZE_BODY := 17
const SIZE_SECONDARY := 15
const SIZE_HELPER := 14
const SIZE_BUTTON := 17
const SIZE_STAT_NUMBER := 22
const SIZE_STAT_LABEL := 14
const SIZE_NAV_LABEL := 15
const SIZE_NAV_ICON := 16
const SIZE_BADGE := 14
const SIZE_WELCOME := 17
const SIZE_INPUT := 17

const TOUCH_MIN := 48
const TOUCH_PRIMARY_H := 54
const TOUCH_CTA_H := 56
const TOUCH_SECONDARY_H := 50
const TOUCH_NAV_H := 74
const INPUT_H := 50
const ROW_H := 56
const FILTER_CHIP_H := 48
const CARD_PAD := 14
const SCREEN_GUTTER := 18
const GAP_RELATED := 9
const GAP_CARDS := 12

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

## Controls that must keep STOP so taps/focus still work during scroll gestures.
const _SCROLL_STOP_TYPES := [
	"Button", "LineEdit", "TextEdit", "CheckBox", "CheckButton",
	"OptionButton", "Slider", "HSlider", "VSlider", "SpinBox",
	"ItemList", "Tree", "CodeEdit", "LinkButton",
]

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


static func apply_label(lab: Label, base_size: int, color: Color = COLOR_BODY, allow_wrap: bool = true) -> void:
	lab.add_theme_font_size_override("font_size", font(base_size))
	lab.add_theme_color_override("font_color", color)
	if allow_wrap:
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.clip_text = false
		lab.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else:
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		lab.clip_text = true
		lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


static func card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CARD
	sb.border_color = COLOR_CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = CARD_PAD
	sb.content_margin_right = CARD_PAD
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BTN
	sb.border_color = COLOR_BTN_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
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
	edit.add_theme_font_size_override("font_size", font(SIZE_INPUT))
	edit.add_theme_color_override("font_color", COLOR_BODY)
	edit.add_theme_color_override("font_placeholder_color", COLOR_HELPER)


static func style_text_edit(edit: TextEdit) -> void:
	edit.add_theme_font_size_override("font_size", font(SIZE_INPUT))
	edit.add_theme_color_override("font_color", COLOR_BODY)


static func apply_safe_margins(margin: MarginContainer, extra_bottom: int = 0) -> void:
	SafeAreaHelper.apply_to_margin(margin, SCREEN_GUTTER, 10, 10 + extra_bottom)


static func configure_scroll(scroll: ScrollContainer, horizontal: bool = false) -> void:
	## Native finger-drag scrolling; hide persistent desktop-style scrollbars.
	if horizontal:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	## Small deadzone so intentional swipes start quickly without eating taps.
	scroll.scroll_deadzone = 12
	## follow_focus jumps the page while typing on mobile — keep OFF globally.
	scroll.follow_focus = false
	_hide_scrollbars(scroll)
	## After children exist, make non-interactive surfaces pass drag to ScrollContainer.
	if not scroll.has_meta("_coln_scroll_wired"):
		scroll.set_meta("_coln_scroll_wired", true)
		scroll.child_entered_tree.connect(func(node: Node) -> void:
			if node is Control:
				_pass_drag_through(node as Control)
		)
	for child in scroll.get_children():
		if child is Control:
			_pass_drag_through(child as Control)


static func _hide_scrollbars(scroll: ScrollContainer) -> void:
	var vbar := scroll.get_v_scroll_bar()
	if vbar:
		vbar.visible = false
		vbar.modulate.a = 0.0
		vbar.custom_minimum_size.x = 0
		vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var empty := StyleBoxEmpty.new()
		vbar.add_theme_stylebox_override("scroll", empty)
		vbar.add_theme_stylebox_override("grabber", empty)
		vbar.add_theme_stylebox_override("grabber_highlight", empty)
		vbar.add_theme_stylebox_override("grabber_pressed", empty)
	var hbar := scroll.get_h_scroll_bar()
	if hbar:
		hbar.visible = false
		hbar.modulate.a = 0.0
		hbar.custom_minimum_size.y = 0
		hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var empty_h := StyleBoxEmpty.new()
		hbar.add_theme_stylebox_override("scroll", empty_h)
		hbar.add_theme_stylebox_override("grabber", empty_h)
		hbar.add_theme_stylebox_override("grabber_highlight", empty_h)
		hbar.add_theme_stylebox_override("grabber_pressed", empty_h)


static func _pass_drag_through(node: Control) -> void:
	## Panels/labels/containers STOP by default and steal touch-drags from ScrollContainer.
	if _should_keep_stop(node):
		node.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		if node.mouse_filter == Control.MOUSE_FILTER_STOP:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		if child is Control:
			_pass_drag_through(child as Control)


static func _should_keep_stop(node: Control) -> bool:
	var n := node.get_class()
	if n in _SCROLL_STOP_TYPES:
		return true
	## Explicitly interactive subclasses / custom buttons.
	if node is BaseButton or node is Range or node is TextEdit or node is LineEdit:
		return true
	return false


static func enable_touch_scroll_on_tree(root: Control) -> void:
	_pass_drag_through(root)


static func release_text_focus(from: Node = null) -> void:
	var vp: Viewport = null
	if from != null and is_instance_valid(from):
		vp = from.get_viewport()
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			vp = tree.root
	if vp == null:
		return
	var focus := vp.gui_get_focus_owner()
	if focus != null and focus is Control:
		(focus as Control).release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()


static func wire_keyboard_avoidance(host: Node, scroll: ScrollContainer, pad: Control) -> Node:
	## Avoid typed KeyboardAvoidance return to keep MobileUi load-order independent.
	var avoid_script := load("res://scripts/ui/keyboard_avoidance.gd") as Script
	var avoid: Node = avoid_script.new() if avoid_script != null else Node.new()
	avoid.name = "KeyboardAvoidance"
	host.add_child(avoid)
	if avoid.has_method("setup"):
		avoid.call("setup", scroll, pad)
	return avoid
