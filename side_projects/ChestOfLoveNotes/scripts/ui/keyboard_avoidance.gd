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


func _exit_tree() -> void:
	## Auth screens own this helper. A successful email/password sign-in used to
	## destroy the form while its infinite spinner Tween was still running. That
	## stale SceneTree Tween could survive into the first Chest paint and leave
	## the transition visually dim/stalled until the app was restarted.
	set_process(false)
	if pad != null and is_instance_valid(pad):
		pad.custom_minimum_size.y = 0.0
	_cleanup_auth_transition_if_needed()


func _cleanup_auth_transition_if_needed() -> void:
	## Keep this helper generic for normal screens, but when it is leaving the
	## root Main auth form we can safely retire the auth-only spinner reference.
	## We intentionally key off the live Tween reference: non-auth keyboard
	## screens do not have one, so their navigation remains untouched.
	var node: Node = get_parent()
	while node != null:
		var script: Script = node.get_script() as Script
		if script != null and script.resource_path == "res://scripts/main.gd":
			var auth_tween: Variant = node.get("_auth_spinner_tween")
			if auth_tween == null:
				return
			if auth_tween is Tween and (auth_tween as Tween).is_valid():
				(auth_tween as Tween).kill()
			node.set("_auth_spinner_tween", null)
			## _begin_nav_transition() intentionally fades ScreenHost from zero.
			## If teardown lands between that zeroing and the fade Tween, guarantee
			## one fully-visible frame so Android cannot be stranded at partial alpha.
			var screen_host: Variant = node.get("_screen_host")
			if screen_host is Control and is_instance_valid(screen_host):
				var tint: Color = (screen_host as Control).modulate
				tint.a = 1.0
				(screen_host as Control).modulate = tint
			return
		node = node.get_parent()


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
