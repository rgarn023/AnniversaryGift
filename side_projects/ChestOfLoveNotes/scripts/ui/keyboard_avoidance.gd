extends Node
class_name KeyboardAvoidance
## Pads a layout spacer for the virtual keyboard and gently scrolls the focused
## field into view. Does not use ScrollContainer.follow_focus (which jumps pages).

var scroll: ScrollContainer
var pad: Control
var _last_kb: float = -1.0
var _last_focus_id: int = 0
var _need_ensure: bool = false


func setup(p_scroll: ScrollContainer, p_pad: Control) -> void:
	scroll = p_scroll
	pad = p_pad
	set_process(true)


func _process(_delta: float) -> void:
	if scroll == null or pad == null or not is_instance_valid(scroll) or not is_instance_valid(pad):
		return
	var kb := SafeAreaHelper.keyboard_height_viewport()
	if not is_equal_approx(kb, _last_kb):
		pad.custom_minimum_size.y = kb
		_last_kb = kb
		_need_ensure = kb > 0.0
	var vp := get_viewport()
	if vp == null:
		return
	var focus := vp.gui_get_focus_owner()
	var fid := 0
	if focus != null and focus is Control:
		fid = (focus as Control).get_instance_id()
	if fid != _last_focus_id:
		_last_focus_id = fid
		_need_ensure = kb > 0.0 and fid != 0
	if not _need_ensure or kb <= 0.0:
		return
	if focus == null or not (focus is Control):
		return
	var ctrl := focus as Control
	if not scroll.is_ancestor_of(ctrl):
		return
	_need_ensure = false
	_ensure_visible(ctrl)


func _ensure_visible(ctrl: Control) -> void:
	var global_rect := ctrl.get_global_rect()
	var scroll_rect := scroll.get_global_rect()
	var margin := 16.0
	var visible_bottom := scroll_rect.position.y + scroll_rect.size.y
	if global_rect.position.y + global_rect.size.y > visible_bottom - margin:
		var delta := (global_rect.position.y + global_rect.size.y) - (visible_bottom - margin)
		scroll.scroll_vertical = int(scroll.scroll_vertical + delta)
	elif global_rect.position.y < scroll_rect.position.y + margin:
		var delta2 := (scroll_rect.position.y + margin) - global_rect.position.y
		scroll.scroll_vertical = int(maxi(scroll.scroll_vertical - int(delta2), 0))
