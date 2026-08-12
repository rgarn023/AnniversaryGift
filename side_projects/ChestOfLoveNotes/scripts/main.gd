extends Control
## Chest of Love Notes — root navigation and MVP screens.

var state: AppState
var _scroll_viewer: LoveNotesScrollViewer
var _image_preview: ImagePreviewOverlay
var _chest: LoveNotesChest
var _screen_host: Control
var _banner: Label
var _toast: Label
var _current_screen: String = ""
var _inventory_filter: String = "all"
var _compose_draft: Dictionary = {}
var _compose_screen: ComposeScrollScreen
var _password_target: Dictionary = {}
var _overlay: Control
var _reveal_timers: Dictionary = {}


var _boot_duration_sec: float = 0.0
var _pending_restore: Dictionary = {}
## Ignore APPLICATION_RESUMED / FOCUS_IN until cold-start navigation completes.
## Resume revalidation previously raced restore and wiped a valid session.
var _startup_done: bool = false
## FOCUS_IN + RESUMED can both fire; coalesce into one resume pass.
var _resume_inflight: bool = false
var _last_chest_counts: Dictionary = {"unread": 0, "locked": 0, "requests": 0}
var _auth_busy: bool = false
var _chest_action_busy: bool = false
var _friend_action_busy: bool = false
var _toast_panel: PanelContainer
var _toast_row: HBoxContainer
var _toast_action_btn: Button
var _toast_action: Callable = Callable()
var _toast_tween: Tween
var _empty_chest_hint: Label
var _dev_force_chest_scroll: bool = false
var _auth_spinner_tween: Tween
var _sent_show_hidden: bool = false
var _pending_hide_sent_id: String = ""
var _qr_helper: QrHelper = QrHelper.new()
var _req_notifier: RequirementNotifier = RequirementNotifier.new()
## Permissions Setup / Manage Permissions live UI handles (query Android; never fake state).
var _perm_setup_status: Dictionary = {} ## kind -> Label
var _perm_setup_actions: Dictionary = {} ## kind -> Button
var _perm_manage_live: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Dark plane first — prevent any engine clear-color / white flash before splash.
	var cold_bg := ColorRect.new()
	cold_bg.color = Color(0.0, 0.0, 0.0, 1.0)
	cold_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cold_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cold_bg.z_index = -10
	add_child(cold_bg)
	MobileUi.ensure_loaded()
	## Preload chest art before first tap to avoid decode hitch.
	LoveNotesChest.preload_assets()
	state = AppState.new()
	state.bootstrap()
	state.reduced_motion = MobileUi.reduced_motion()
	NotificationHelper.ensure_channels()
	NotificationHelper.reschedule_persisted()
	_build_chrome()
	_scroll_viewer = LoveNotesScrollViewer.new()
	_scroll_viewer.set_reduced_motion(state.reduced_motion)
	_scroll_viewer.closed.connect(_on_scroll_closed)
	_scroll_viewer.attachment_tapped.connect(_on_scroll_attachment_tapped)
	add_child(_scroll_viewer)
	_image_preview = ImagePreviewOverlay.new()
	add_child(_image_preview)
	if state.api:
		state.api.session_invalidated.connect(_on_session_invalidated)
	# Cold start: Charoite boot while session/backend init runs in parallel.
	await _startup_navigate()


func _startup_navigate() -> void:
	## Charoite Games cold boot: min ≈4.0s visible + app ready, then short fade.
	## Session restore runs concurrently; splash never force-closes early.
	_startup_done = false
	var boot := CharoiteBoot.new()
	boot.z_index = 80
	add_child(boot)
	_log_secure_debug("startup_begin")
	_pending_restore = {"ok": false}
	if state.is_online():
		_pending_restore = await state.restore_session_if_possible()
		_log_secure_debug("startup_after_restore")
	## Allow boot to leave only after restore/offline gate AND min visible time.
	if is_instance_valid(boot) and boot.has_method("mark_app_ready"):
		boot.mark_app_ready()
	if not boot.is_finished():
		await boot.finished
	_boot_duration_sec = boot.measured_duration_sec()
	boot.queue_free()
	_log_secure_debug("startup_after_boot")
	var restore := _pending_restore
	if bool(restore.get("ok", false)):
		## Create Your Profile only when backend definitively reports NOT_CREATED.
		if bool(restore.get("profile_exists", false)) or state.profiles.has_known_profile():
			await _enter_app_home()
		elif state.profiles.is_definitively_missing():
			_show_profile_setup()
		else:
			## Soft/unknown: stay in-app with cached/loading profile, never false onboarding.
			await _enter_app_home()
		_startup_done = true
		_log_secure_debug("startup_destination_chest")
		await _consume_notification_deeplink()
		return
	## Missing/expired/soft-fail/unconfirmed sessions are silent on the login form.
	## Only definitive membership denials toast.
	if not bool(restore.get("silent", true)):
		var msg := str(restore.get("message", ""))
		if not msg.is_empty() and str(restore.get("reason", "")) != "email_unconfirmed":
			_show_toast(msg)
	_show_welcome()
	_startup_done = true
	_log_secure_debug("startup_destination_login")
	await _consume_notification_deeplink()


func _log_secure_debug(tag: String) -> void:
	if not OS.is_debug_build():
		return
	var snap: Dictionary = state.diagnostics_snapshot()
	# Safe YES/NO only — never tokens/passwords/session JSON.
	print(
		"[COLN-SECURE:%s] backend=%s plugin=%s available=%s keep=%s has_session=%s decrypt=%s refresh_attempted=%s refresh_ok=%s membership=%s profile=%s signed_in=%s"
		% [
			tag,
			"YES" if bool(snap.get("backend_configured", false)) else "NO",
			"YES" if bool(snap.get("secure_plugin_found", false)) else "NO",
			"YES" if bool(snap.get("secure_storage_available", false)) else "NO",
			"ON" if bool(snap.get("keep_me_signed_in", false)) else "OFF",
			"YES" if bool(snap.get("saved_session_exists", false)) else "NO",
			"YES" if bool(snap.get("session_decrypt_ok", false)) else "NO",
			"YES" if bool(snap.get("refresh_attempted", false)) else "NO",
			"YES" if bool(snap.get("refresh_succeeded", false)) else "NO",
			"YES" if bool(snap.get("membership_revalidated", false)) else "NO",
			"YES" if bool(snap.get("profile_loaded", false)) else "NO",
			"YES" if bool(snap.get("signed_in", false)) else "NO",
		]
	)


func _log_relationship_debug(label: String) -> void:
	## STATE LABELS only — never UUIDs / JWTs / emails / secrets.
	if not OS.is_debug_build():
		return
	print("[COLN-REL:%s]" % label)


func _on_session_invalidated() -> void:
	_clear_compose_draft()
	await _sign_out_cleanup()
	_show_toast("Your session has expired. Please sign in again.")
	_show_welcome()


func _log_nav_paint(screen: String, t0_ms: int) -> void:
	if OS.is_debug_build():
		print("[COLN-NAV] %s first_paint_ms=%d" % [screen, Time.get_ticks_msec() - t0_ms])


func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if ResourceLoader.exists("res://assets/art/background/starfield.png"):
		## Single full-bleed texture (not per-star Control nodes).
		var stars := TextureRect.new()
		stars.texture = load("res://assets/art/background/starfield.png")
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stars.stretch_mode = TextureRect.STRETCH_SCALE
		stars.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stars)

	_banner = Label.new()
	## Never show "Private Onboarding Build" / demo watermarks in test APKs.
	_banner.visible = false
	if BuildFlags.SHOW_ONBOARDING_BANNER and state.is_demo() and OS.is_debug_build():
		_banner.text = "LOCAL DEMO MODE"
		_banner.visible = true
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 4
	_banner.offset_bottom = 28
	MobileUi.apply_label(_banner, MobileUi.SIZE_HELPER, MobileUi.COLOR_TITLE)
	_banner.z_index = 50
	add_child(_banner)

	_screen_host = Control.new()
	_screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_host.offset_top = 48 if _banner.visible else 0
	add_child(_screen_host)

	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.z_index = 70
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Color(0.10, 0.06, 0.16, 0.94)
	toast_style.border_color = Color(0.72, 0.52, 0.28, 0.85)
	toast_style.set_border_width_all(1)
	toast_style.set_corner_radius_all(14)
	toast_style.content_margin_left = 16
	toast_style.content_margin_right = 16
	toast_style.content_margin_top = 10
	toast_style.content_margin_bottom = 10
	_toast_panel.add_theme_stylebox_override("panel", toast_style)
	_toast_row = HBoxContainer.new()
	_toast_row.add_theme_constant_override("separation", 12)
	_toast_panel.add_child(_toast_row)
	_toast = Label.new()
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(_toast, MobileUi.SIZE_BODY, MobileUi.COLOR_TITLE)
	_toast_row.add_child(_toast)
	_toast_action_btn = Button.new()
	_toast_action_btn.text = "Undo"
	_toast_action_btn.visible = false
	_toast_action_btn.focus_mode = Control.FOCUS_NONE
	_toast_action_btn.custom_minimum_size = Vector2(72, 40)
	MobileUi.style_button(_toast_action_btn, 40)
	_toast_action_btn.pressed.connect(_on_toast_action_pressed)
	_toast_row.add_child(_toast_action_btn)
	add_child(_toast_panel)
	_position_snackbar()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.z_index = 55
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)


func _nav_content_inset() -> int:
	## Bottom padding so scrollable content clears nav + gesture safe area.
	var safe := SafeAreaHelper.display_insets_viewport()
	return MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + int(safe.w) + 16


func _persist_compose_draft_if_needed() -> void:
	if _current_screen == "compose" and _compose_screen != null and is_instance_valid(_compose_screen):
		_compose_draft = _compose_screen.get_draft()


func _clear_compose_draft() -> void:
	var atts = _compose_draft.get("attachments", [])
	if typeof(atts) == TYPE_ARRAY:
		for a in atts:
			if typeof(a) == TYPE_DICTIONARY:
				var path := str(a.get("path", ""))
				if path.begins_with(AttachmentHelper.DRAFT_DIR) and FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
	_compose_draft.clear()
	AttachmentHelper.clear_draft_dir()


func _clear_screen() -> void:
	MobileUi.release_text_focus(self)
	_persist_compose_draft_if_needed()
	_compose_screen = null
	_auth_busy = false
	_chest_action_busy = false
	_friend_action_busy = false
	for c in _screen_host.get_children():
		c.queue_free()


func _title_font() -> Font:
	if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		return load("res://assets/fonts/Cinzel-Bold.ttf")
	return null


func _body_font() -> Font:
	if ResourceLoader.exists("res://assets/fonts/CormorantGaramond-Regular.ttf"):
		return load("res://assets/fonts/CormorantGaramond-Regular.ttf")
	return null


func _make_button(text: String, cb: Callable, min_size: Vector2 = Vector2(0, 60)) -> Button:
	var b := Button.new()
	b.text = text
	var h := maxi(MobileUi.TOUCH_MIN, int(min_size.y))
	var w := int(min_size.x)
	b.custom_minimum_size = Vector2(maxi(0, w), MobileUi.font_touch(h))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if w <= 0 else Control.SIZE_FILL
	MobileUi.style_button(b, h)
	b.pressed.connect(cb)
	return b


func _make_screen_root(extra_bottom: int = 0) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, extra_bottom)
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	margin.add_child(root)
	return root


func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MobileUi.card_style())
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	return card


func _wire_scroll(scroll: ScrollContainer, horizontal: bool = false) -> ScrollContainer:
	MobileUi.configure_scroll(scroll, horizontal)
	return scroll


func _position_snackbar() -> void:
	if _toast_panel == null:
		return
	var safe := SafeAreaHelper.display_insets_viewport()
	var nav_h := MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + int(safe.w) + 12
	_toast_panel.anchor_left = 0.08
	_toast_panel.anchor_right = 0.92
	_toast_panel.anchor_top = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = 0
	_toast_panel.offset_right = 0
	_toast_panel.offset_top = -nav_h - 52
	_toast_panel.offset_bottom = -nav_h


func _show_toast(text: String) -> void:
	_show_snackbar(text, "", Callable())


func _show_snackbar(text: String, action_label: String = "", action: Callable = Callable()) -> void:
	## Temporary snackbar above bottom navigation — optional Undo action.
	_position_snackbar()
	_toast.text = text
	_toast_action = action
	if _toast_action_btn:
		_toast_action_btn.visible = not action_label.is_empty() and action.is_valid()
		_toast_action_btn.text = action_label if not action_label.is_empty() else "Undo"
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	if _toast_tween != null and is_instance_valid(_toast_tween):
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.2 if _toast_action_btn and _toast_action_btn.visible else 2.0)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.28)
	_toast_tween.tween_callback(func() -> void:
		if is_instance_valid(_toast_panel):
			_toast_panel.visible = false
		_toast_action = Callable()
		_pending_hide_sent_id = ""
		if _toast_action_btn:
			_toast_action_btn.visible = false
	)


func _on_toast_action_pressed() -> void:
	var action := _toast_action
	_toast_action = Callable()
	if _toast_tween != null and is_instance_valid(_toast_tween):
		_toast_tween.kill()
	if is_instance_valid(_toast_panel):
		_toast_panel.visible = false
	if _toast_action_btn:
		_toast_action_btn.visible = false
	if action.is_valid():
		action.call()


func _begin_nav_transition() -> void:
	MobileUi.release_text_focus(self)
	_clear_screen()
	_screen_host.modulate.a = 0.0
	_empty_chest_hint = null


func _finish_nav_transition() -> void:
	if state.reduced_motion or MobileUi.reduced_motion():
		_screen_host.modulate.a = 1.0
		return
	var tw := create_tween()
	tw.tween_property(_screen_host, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _show_welcome() -> void:
	_current_screen = "welcome"
	_clear_screen()
	var root := _make_screen_root()
	root.add_theme_constant_override("separation", 18)
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size.y = 24
	root.add_child(spacer_top)

	var card := _make_card()
	root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)

	var title := Label.new()
	title.text = "Chest of Love Notes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_APP_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Send sealed scrolls to your Person.\nThey wait in the chest until their unlock time."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(sub, MobileUi.SIZE_WELCOME, MobileUi.COLOR_BODY)
	if _body_font():
		sub.add_theme_font_override("font", _body_font())
	box.add_child(sub)

	if state.is_demo():
		box.add_child(_make_button("Enter Local Demo", _enter_demo, Vector2(0, MobileUi.TOUCH_CTA_H)))
		var note := Label.new()
		note.text = "No Supabase credentials found. Demo uses fictional accounts only."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(note, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
		box.add_child(note)
	elif state.is_online():
		box.add_child(_make_button("Sign In", func() -> void: _show_auth(false), Vector2(0, MobileUi.TOUCH_CTA_H)))
		if state.show_sign_up():
			box.add_child(_make_button("Sign Up", func() -> void: _show_auth(true), Vector2(0, MobileUi.TOUCH_PRIMARY_H)))
		var private_note := Label.new()
		private_note.text = "This is a private app. Only approved accounts can enter the chest."
		private_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(private_note, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_SECONDARY)
		box.add_child(private_note)
	else:
		## UNCONFIGURED: packed client config missing (not an init race — bootstrap is sync).
		var err := Label.new()
		err.text = "Backend is not configured.\nThis build is missing the Supabase client configuration."
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(err, MobileUi.SIZE_BODY, MobileUi.COLOR_DANGER)
		box.add_child(err)
		if OS.is_debug_build():
			var hint := Label.new()
			hint.text = "Debug: export must pack config/backend_config.json (see tools/export_android_apk.sh)."
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			MobileUi.apply_label(hint, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
			box.add_child(hint)


func _enter_demo() -> void:
	if state.is_private_onboarding_build() and not state.is_demo():
		_show_toast("Local Demo Mode is disabled in this build.")
		return
	await _enter_app_home()


func _show_auth(sign_up: bool) -> void:
	if sign_up and not state.show_sign_up():
		_show_toast("Sign Up is unavailable in this build.")
		_show_auth(false)
		return
	_current_screen = "auth_signup" if sign_up else "auth_signin"
	_clear_screen()
	var root := _make_screen_root()
	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var card := _make_card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var brand := Label.new()
	brand.text = "Chest of Love Notes"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(brand, MobileUi.SIZE_APP_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		brand.add_theme_font_override("font", _title_font())
	box.add_child(brand)

	var welcome := Label.new()
	welcome.text = "Create your account" if sign_up else "Welcome back"
	welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(welcome, MobileUi.SIZE_WELCOME, MobileUi.COLOR_BODY)
	box.add_child(welcome)

	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_line_edit(email)
	box.add_child(email)

	var pw_row := HBoxContainer.new()
	pw_row.add_theme_constant_override("separation", 8)
	box.add_child(pw_row)
	var password := LineEdit.new()
	password.placeholder_text = "Password"
	password.secret = true
	password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_line_edit(password)
	pw_row.add_child(password)
	var eye := Button.new()
	eye.text = "Show"
	eye.custom_minimum_size = Vector2(MobileUi.font_touch(72), MobileUi.font_touch(48))
	MobileUi.style_button(eye, 48)
	eye.pressed.connect(func() -> void:
		password.secret = not password.secret
		eye.text = "Hide" if not password.secret else "Show"
	)
	pw_row.add_child(eye)

	var confirm: LineEdit = null
	if sign_up:
		confirm = LineEdit.new()
		confirm.placeholder_text = "Confirm password"
		confirm.secret = true
		confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_line_edit(confirm)
		box.add_child(confirm)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(status, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
	box.add_child(status)

	var submit_row := HBoxContainer.new()
	submit_row.add_theme_constant_override("separation", 10)
	submit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(submit_row)
	var submit := Button.new()
	var idle_label := "Create Account" if sign_up else "Sign In"
	submit.text = idle_label
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_button(submit, MobileUi.TOUCH_CTA_H)
	submit_row.add_child(submit)
	## Circular spinner glyph — not a gray ProgressBar square.
	var spinner := Label.new()
	spinner.text = "◌"
	spinner.visible = false
	spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spinner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var spin_sz := MobileUi.font_touch(28)
	spinner.custom_minimum_size = Vector2(spin_sz, MobileUi.font_touch(MobileUi.TOUCH_CTA_H))
	spinner.size = Vector2(spin_sz, spin_sz)
	spinner.pivot_offset = Vector2(spin_sz * 0.5, spin_sz * 0.5)
	MobileUi.apply_label(spinner, MobileUi.SIZE_BUTTON, MobileUi.COLOR_TITLE, false)
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	submit_row.add_child(spinner)

	var kb_pad := Control.new()
	kb_pad.custom_minimum_size = Vector2(0, 0)
	box.add_child(kb_pad)
	MobileUi.wire_keyboard_avoidance(root, scroll, kb_pad)

	var set_busy := func(busy: bool) -> void:
		_auth_busy = busy
		submit.disabled = busy
		if busy:
			submit.text = "Creating…" if sign_up else "Signing In…"
			spinner.visible = true
			if _auth_spinner_tween != null and is_instance_valid(_auth_spinner_tween):
				_auth_spinner_tween.kill()
			_auth_spinner_tween = create_tween()
			_auth_spinner_tween.set_loops()
			_auth_spinner_tween.tween_property(spinner, "rotation", TAU, 0.85).from(0.0)
		else:
			submit.text = idle_label
			spinner.visible = false
			spinner.rotation = 0.0
			if _auth_spinner_tween != null and is_instance_valid(_auth_spinner_tween):
				_auth_spinner_tween.kill()
				_auth_spinner_tween = null

	submit.pressed.connect(func() -> void:
		if _auth_busy:
			return
		set_busy.call(true)
		status.text = ""
		status.add_theme_color_override("font_color", MobileUi.COLOR_HELPER)
		# Never log password values.
		if sign_up:
			var result: Dictionary = await state.auth.sign_up(
				email.text, password.text, confirm.text if confirm else ""
			)
			password.text = ""
			if confirm:
				confirm.text = ""
			if not bool(result.get("ok", false)):
				set_busy.call(false)
				status.add_theme_color_override("font_color", MobileUi.COLOR_DANGER)
				status.text = str(result.get("error", "Sign up failed."))
				return
			if bool(result.get("needs_confirmation", true)):
				state.pending_confirm_email = email.text.strip_edges().to_lower()
				_show_check_email()
				return
			await _after_verified_sign_in()
		else:
			var result: Dictionary = await state.auth.sign_in(email.text, password.text)
			password.text = ""
			if not bool(result.get("ok", false)):
				set_busy.call(false)
				status.add_theme_color_override("font_color", MobileUi.COLOR_DANGER)
				## Only show confirmation UI when the backend explicitly requires it.
				if bool(result.get("needs_confirmation", false)):
					status.text = str(result.get("error", "Please confirm your email before signing in."))
					state.pending_confirm_email = email.text.strip_edges().to_lower()
					box.add_child(_make_button("Go to Check Your Email", _show_check_email))
				else:
					status.text = str(result.get("error", "Sign in failed."))
				return
			await _after_verified_sign_in()
	)
	if sign_up:
		box.add_child(_make_button("Already have an account? Sign In", func() -> void: _show_auth(false)))
	elif state.show_sign_up():
		box.add_child(_make_button("Need an account? Sign Up", func() -> void: _show_auth(true)))
	box.add_child(_make_button("Back", _show_welcome))


func _show_check_email() -> void:
	_current_screen = "check_email"
	_clear_screen()
	var root := _make_screen_root()
	var card := _make_card()
	root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var title := Label.new()
	title.text = "Check Your Email"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	box.add_child(title)
	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.text = (
		"We sent a confirmation link to your email.\n\n"
		+ "1. Open the message in your phone browser.\n"
		+ "2. Tap the confirmation link.\n"
		+ "3. Return here and continue to Sign In.\n\n"
		+ "Membership is checked only after a verified sign-in."
	)
	MobileUi.apply_label(body, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	box.add_child(body)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(status, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
	box.add_child(status)
	box.add_child(_make_button("I’ve Confirmed My Email", func() -> void: _show_auth(false), Vector2(0, MobileUi.TOUCH_CTA_H)))
	box.add_child(_make_button("Return to Sign In", func() -> void: _show_auth(false)))
	box.add_child(_make_button("Resend Confirmation", func() -> void:
		var result: Dictionary = await state.auth.resend_confirmation(state.pending_confirm_email)
		if bool(result.get("ok", false)):
			status.text = "Confirmation email resent. Please wait before trying again."
		else:
			status.text = str(result.get("error", "Could not resend."))
	))
	box.add_child(_make_button("Back to Welcome", _show_welcome))


func _after_verified_sign_in() -> void:
	if not state.tokens.has_session():
		await state.sign_out_full()
		_show_welcome()
		return
	if not state.tokens.email_confirmed:
		## Backend explicitly reported unconfirmed — only then show check-email.
		await state.sign_out_full()
		_show_check_email()
		return
	var claim: Dictionary = await state.membership.claim_membership()
	if not bool(claim.get("ok", false)):
		var msg := str(claim.get("error", "This is a private app, and this account is not approved."))
		if bool(claim.get("forbidden", false)):
			msg = "This is a private app, and this account is not approved."
		await state.sign_out_full()
		_show_toast(msg)
		_show_welcome()
		return
	state.profiles.hydrate_from_cache()
	state.load_hidden_sent()
	var profile_result: Dictionary = await state.profiles.fetch_own_profile()
	if not bool(profile_result.get("ok", false)):
		var status := int(state.api.last_http_status)
		if status == 401 or status == 403:
			await state.sign_out_full()
			_show_toast(str(profile_result.get("error", "Could not load profile.")))
			_show_welcome()
			return
		## Soft fail: keep session; use cache / optimistic enter — never false Create Profile.
		if not state.profiles.has_known_profile():
			_show_toast("Could not refresh profile right now. Retrying later.")
	# Hard-require Keystore persistence when Keep Me Signed In is ON.
	var persist: Dictionary = await state.persist_session_verified()
	_log_secure_debug("after_signin_persist")
	if not bool(persist.get("ok", false)):
		var warn := str(persist.get("warning", state.maybe_warn_persist_failure()))
		if warn.is_empty():
			warn = "Secure sign-in storage failed. You’ll need to sign in again after closing the app."
		_show_toast(warn)
	## Never toast "persisted successfully" — only warn on genuine failure.
	if state.profiles.is_definitively_missing():
		_show_profile_setup()
		return
	await _enter_app_home()


func _enter_app_home() -> void:
	## First-run permissions once for online/demo members, then main chest.
	if not PermissionsHelper.setup_completed() and (state.is_demo() or (state.is_online() and state.membership.is_member)):
		_show_permissions_setup()
		return
	await _show_main_chest()
	_try_register_push_token()


func _show_profile_setup() -> void:
	_current_screen = "profile_setup"
	_clear_screen()
	var root := _make_screen_root()
	var card := _make_card()
	root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var title := Label.new()
	title.text = "Create Your Profile"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	box.add_child(title)
	var info := Label.new()
	info.text = "Choose a username and display name. Your connection code is generated securely."
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(info, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	box.add_child(info)
	var username := LineEdit.new()
	username.placeholder_text = "Username (3–32 characters)"
	username.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_line_edit(username)
	box.add_child(username)
	var display_name := LineEdit.new()
	display_name.placeholder_text = "Display name"
	display_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_line_edit(display_name)
	box.add_child(display_name)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(status, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
	box.add_child(status)
	box.add_child(_make_button("Save Profile", func() -> void:
		status.text = "Saving…"
		var result: Dictionary = await state.profiles.create_profile(username.text, display_name.text)
		if not bool(result.get("ok", false)):
			status.text = str(result.get("error", "Could not save profile."))
			return
		_show_toast("Profile ready.")
		await _enter_app_home()
	, Vector2(0, MobileUi.TOUCH_CTA_H)))
	box.add_child(_make_button("Sign Out", func() -> void:
		await _sign_out_cleanup()
		_show_welcome()
	))


func _guard_private_chest() -> bool:
	if state.is_demo():
		return true
	if not state.is_online():
		_show_toast("Backend is not configured.")
		_show_welcome()
		return false
	if not state.tokens.has_session() or not state.membership.is_member:
		# Fire-and-forget clear; navigation continues immediately.
		state.sign_out()
		_show_toast("This is a private app, and this account is not approved.")
		_show_welcome()
		return false
	return true


func _counts_from_chest_cache() -> Dictionary:
	var counts := {"unread": 0, "locked": 0, "requests": 0}
	if state.is_demo():
		return state.demo.counts()
	if not state.cached_chest.is_empty():
		var cached: Dictionary = state.cached_chest.get("chest", {}) if typeof(state.cached_chest.get("chest")) == TYPE_DICTIONARY else {}
		if not cached.is_empty():
			counts.unread = int(cached.get("unread", cached.get("unopened", 0)))
			counts.locked = int(cached.get("locked", 0))
			var cfr: Array = cached.get("friend_requests", []) if typeof(cached.get("friend_requests")) == TYPE_ARRAY else []
			counts.requests = cfr.size()
			return counts
	if not _last_chest_counts.is_empty():
		return _last_chest_counts.duplicate()
	return counts


func _show_main_chest() -> void:
	if not _guard_private_chest():
		return
	var nav_t0 := Time.get_ticks_msec()
	_current_screen = "main_chest"
	## Paint from cache immediately — refresh network after first paint.
	var counts := _counts_from_chest_cache()
	if state.is_demo():
		state.mark_cache_fresh("chest")
	if _dev_force_chest_scroll and OS.is_debug_build():
		counts.unread = maxi(int(counts.unread), 1)
	_last_chest_counts = counts.duplicate()

	_begin_nav_transition()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, _nav_content_inset())
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = MobileUi.font_touch(48)
	root.add_child(header)
	header.add_child(MobileUi.make_page_title("Chest", _title_font()))
	var refresh_btn := Button.new()
	refresh_btn.text = "↻"
	refresh_btn.tooltip_text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(MobileUi.font_touch(48), MobileUi.font_touch(48))
	MobileUi.style_button(refresh_btn, 48)
	refresh_btn.pressed.connect(func() -> void:
		state.invalidate_cache("chest")
		_show_main_chest()
	)
	header.add_child(refresh_btn)

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", MobileUi.card_style())
	root.add_child(summary)
	var sum_row := HBoxContainer.new()
	sum_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sum_row.add_theme_constant_override("separation", 8)
	summary.add_child(sum_row)
	var count_labels: Dictionary = {}
	for item in [
		["Unread", counts.unread],
		["Locked", counts.locked],
		["Requests", counts.requests],
	]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		var num := Label.new()
		num.text = str(item[1])
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(num, MobileUi.SIZE_STAT_NUMBER, MobileUi.COLOR_TITLE)
		cell.add_child(num)
		var lab := Label.new()
		lab.text = str(item[0])
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(lab, MobileUi.SIZE_STAT_LABEL, MobileUi.COLOR_SECONDARY)
		cell.add_child(lab)
		sum_row.add_child(cell)
		count_labels[str(item[0]).to_lower()] = num

	## Intentionally composed chest stage — less empty air, still chest-first.
	var chest_area := Control.new()
	chest_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(chest_area)
	var your := Label.new()
	your.text = "Your Chest"
	your.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	your.set_anchors_preset(Control.PRESET_CENTER_TOP)
	your.anchor_left = 0.0
	your.anchor_right = 1.0
	your.offset_top = 8
	your.offset_bottom = 36
	MobileUi.apply_label(your, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	chest_area.add_child(your)

	_chest = LoveNotesChest.new()
	_chest.reduced_motion = state.reduced_motion
	_chest.set_anchors_preset(Control.PRESET_CENTER)
	## Slightly taller host so the taller production canvas / rising scroll is not clipped.
	var chest_w := 252
	var chest_h := 292
	_chest.custom_minimum_size = Vector2(chest_w, chest_h)
	_chest.size = Vector2(chest_w, chest_h)
	_chest.clip_contents = false
	_chest.position = Vector2(-chest_w * 0.5, -chest_h * 0.46)
	_chest.z_index = 5
	_chest.tapped.connect(_on_chest_tapped)
	chest_area.clip_contents = false
	chest_area.add_child(_chest)
	_chest.configure(LoveNotesChest.ChestState.READY, false)
	_chest.set_unread_badge(int(counts.unread))

	_empty_chest_hint = Label.new()
	_empty_chest_hint.text = ""
	_empty_chest_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_chest_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_empty_chest_hint.anchor_left = 0.08
	_empty_chest_hint.anchor_right = 0.92
	_empty_chest_hint.offset_top = -48
	_empty_chest_hint.offset_bottom = -8
	_empty_chest_hint.modulate.a = 0.0
	MobileUi.apply_label(_empty_chest_hint, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_HELPER)
	chest_area.add_child(_empty_chest_hint)

	if state.is_demo():
		var demo_row := HBoxContainer.new()
		demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
		root.add_child(demo_row)
		var adv := _make_button("+15 min", func() -> void:
			state.demo.advance_minutes(15)
			_show_toast("Demo time advanced 15 minutes")
			_show_main_chest()
		, Vector2(200, MobileUi.TOUCH_PRIMARY_H))
		demo_row.add_child(adv)

	_add_bottom_nav("chest")
	_finish_nav_transition()
	_log_nav_paint("main_chest", nav_t0)
	## Async refresh when cache is stale (does not block first paint).
	if state.is_online() and not state.cache_is_fresh("chest"):
		var chest_result: Dictionary = await state.scrolls.get_chest()
		if _current_screen != "main_chest":
			return
		if bool(chest_result.get("ok", false)):
			state.cached_chest = chest_result.get("data", {}) if typeof(chest_result.get("data")) == TYPE_DICTIONARY else {}
			state.mark_cache_fresh("chest")
			var fresh := _counts_from_chest_cache()
			_last_chest_counts = fresh.duplicate()
			if count_labels.has("unread") and is_instance_valid(count_labels.unread):
				count_labels.unread.text = str(fresh.unread)
			if count_labels.has("locked") and is_instance_valid(count_labels.locked):
				count_labels.locked.text = str(fresh.locked)
			if count_labels.has("requests") and is_instance_valid(count_labels.requests):
				count_labels.requests.text = str(fresh.requests)
			if _chest != null and is_instance_valid(_chest):
				_chest.set_unread_badge(int(fresh.unread))
		else:
			var err := str(chest_result.get("error", "Could not refresh chest."))
			if not err.is_empty():
				_show_toast(err)
	_try_register_push_token()


func _add_bottom_nav(selected: String) -> void:
	var nav := PanelContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -MobileUi.font_touch(MobileUi.TOUCH_NAV_H)
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = MobileUi.COLOR_NAV_BG
	nav_style.set_border_width_all(0)
	nav_style.border_width_top = 2
	nav_style.border_color = Color(0.45, 0.34, 0.58, 0.7)
	nav.add_theme_stylebox_override("panel", nav_style)
	_screen_host.add_child(nav)
	var safe := SafeAreaHelper.display_insets_viewport()
	nav.offset_bottom = -int(safe.w)
	nav.offset_top = -MobileUi.font_touch(MobileUi.TOUCH_NAV_H) - int(safe.w)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	nav.add_child(row)
	## Nav uses short "Person" under heart to avoid crowding; screen title stays My Person.
	var tabs := [
		["chest", "▣", "Chest", _show_main_chest],
		["compose", "✎", "Compose", _show_compose],
		["friends", "♡", ProductStrings.PERSON, _show_friends],
		["sent", "✉", "Sent", _show_sent],
		["profile", "◎", "Profile", _show_profile],
	]
	for t in tabs:
		var b := Button.new()
		b.text = "%s\n%s" % [str(t[1]), str(t[2])]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.TOUCH_NAV_H) - 2)
		b.focus_mode = Control.FOCUS_NONE
		var nav_fs := MobileUi.SIZE_NAV_LABEL
		if str(t[0]) == "friends":
			nav_fs = maxi(13, MobileUi.SIZE_NAV_LABEL - 2)
		b.add_theme_font_size_override("font_size", MobileUi.font(nav_fs))
		b.add_theme_constant_override("line_spacing", -3 if str(t[0]) == "friends" else -2)
		var sel := str(t[0]) == selected
		b.add_theme_color_override("font_color", MobileUi.COLOR_NAV_SELECTED if sel else MobileUi.COLOR_NAV_IDLE)
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.22, 0.14, 0.32, 0.98) if sel else Color(0, 0, 0, 0)
		flat.set_corner_radius_all(14)
		flat.content_margin_top = 4
		flat.content_margin_bottom = 4
		if sel:
			flat.border_width_top = 3
			flat.border_color = MobileUi.COLOR_NAV_SELECTED
		b.add_theme_stylebox_override("normal", flat)
		b.add_theme_stylebox_override("hover", flat)
		b.add_theme_stylebox_override("pressed", flat)
		var cb: Callable = t[3]
		b.pressed.connect(func() -> void:
			MobileUi.release_text_focus(self)
			cb.call()
		)
		row.add_child(b)


func _on_chest_tapped() -> void:
	if not _guard_private_chest():
		return
	if _chest == null or _chest.animating or _chest_action_busy:
		return
	_chest_action_busy = true
	_chest.set_interaction_enabled(false)
	var has_new := (
		int(_last_chest_counts.get("unread", 0)) > 0
		or int(_last_chest_counts.get("requests", 0)) > 0
		or (_dev_force_chest_scroll and OS.is_debug_build())
	)
	## Already open empty chest: pulse only — never replay full open.
	if (
		(
			_chest.chest_state == LoveNotesChest.ChestState.OPENED
			or _chest.chest_state == LoveNotesChest.ChestState.OPEN_EMPTY
		)
		and not has_new
	):
		await _chest.play_open_empty_pulse()
		if _empty_chest_hint:
			_empty_chest_hint.text = "No new scrolls today."
			_empty_chest_hint.modulate.a = 1.0
		_chest.set_interaction_enabled(true)
		_chest_action_busy = false
		return

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 4
	_screen_host.add_child(dim)
	var dim_tw := create_tween()
	dim_tw.tween_property(dim, "color:a", 0.45 if not state.reduced_motion else 0.28, 0.28)

	## Always open — scroll emerges only when a new scroll exists.
	await _chest.play_open_animation(state.reduced_motion, has_new)

	if not has_new:
		if is_instance_valid(dim):
			var undim := create_tween()
			undim.tween_property(dim, "color:a", 0.0, 0.2)
			await undim.finished
			dim.queue_free()
		if _empty_chest_hint:
			_empty_chest_hint.text = "No new scrolls today."
			_empty_chest_hint.modulate.a = 1.0
		_chest.set_interaction_enabled(true)
		_chest_action_busy = false
		return

	var fade := create_tween()
	fade.tween_property(dim, "color:a", 0.85, 0.18)
	await fade.finished
	if is_instance_valid(dim):
		dim.queue_free()
	_dev_force_chest_scroll = false
	_chest_action_busy = false
	_show_inventory()


func _ui_state_for_online_scroll(item: Dictionary) -> String:
	if str(item.get("kind", "")) == "friend_request":
		return "friend_request"
	if bool(item.get("is_read", false)) or bool(item.get("is_opened", false)):
		return "opened"
	## Time gate first.
	if not bool(item.get("is_unlockable", true)):
		return "locked"
	## Activity / Focus incomplete → stay on lock checklist (AND with other locks).
	var sid := str(item.get("id", ""))
	if bool(item.get("activity_lock_enabled", false)) and not ActivityLockHelper.is_complete(sid, float(item.get("activity_target_km", 1.0))):
		return "locked"
	if bool(item.get("focus_lock_enabled", false)) and not FocusLockHelper.is_complete(sid):
		return "locked"
	if bool(item.get("has_location_lock", false)):
		return "locked"
	if bool(item.get("has_password", false)) or bool(item.get("has_magic_password", false)):
		return "password_unlocked_unread"
	return "unlocked_unread"


func _normalize_online_scroll_item(raw: Dictionary) -> Dictionary:
	var sender: Dictionary = raw.get("sender", {}) if typeof(raw.get("sender")) == TYPE_DICTIONARY else {}
	var unlock_at := str(raw.get("unlock_at", ""))
	var unlock_unix := 0
	if not unlock_at.is_empty():
		unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))
	var item := raw.duplicate(true)
	item["state"] = _ui_state_for_online_scroll(raw)
	item["has_magic_password"] = bool(raw.get("has_password", false)) or bool(raw.get("has_magic_password", false))
	item["activity_lock_enabled"] = bool(raw.get("activity_lock_enabled", false))
	item["activity_target_km"] = float(raw.get("activity_target_km", 0.0))
	item["focus_lock_enabled"] = bool(raw.get("focus_lock_enabled", false))
	item["focus_duration_hours"] = int(raw.get("focus_duration_hours", 0))
	item["sender_display_name"] = IdentityHelper.display_name_from_profile(
		sender if typeof(sender) == TYPE_DICTIONARY else {},
		IdentityHelper.safe_label(str(raw.get("sender_display_name", "")), IdentityHelper.UNKNOWN_SENDER)
	)
	item["sender_username"] = IdentityHelper.username_from_profile(sender if typeof(sender) == TYPE_DICTIONARY else {})
	item["unlock_at_unix"] = unlock_unix
	item["kind"] = str(raw.get("kind", "love_note"))
	return item


func _normalize_friend_request_item(raw: Dictionary) -> Dictionary:
	var sender: Dictionary = raw.get("sender", {}) if typeof(raw.get("sender")) == TYPE_DICTIONARY else {}
	return {
		"id": str(raw.get("id", "")),
		"kind": "friend_request",
		"state": "friend_request",
		"title": ProductStrings.CONNECTION_REQUEST,
		"sender_display_name": IdentityHelper.display_name_from_profile(sender, "Someone"),
		"sender_id": str(raw.get("sender_id", "")),
		"has_magic_password": false,
	}


func _load_online_chest_items(filter: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var view := "hidden" if filter == "hidden" else "current"
	var result: Dictionary = await state.scrolls.get_chest(view)
	if not bool(result.get("ok", false)):
		_show_toast(str(result.get("error", "Could not load chest.")))
		return out
	var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	if view != "hidden":
		state.cached_chest = data
	var chest: Dictionary = data.get("chest", {}) if typeof(data.get("chest")) == TYPE_DICTIONARY else {}
	var scrolls: Array = chest.get("scrolls", []) if typeof(chest.get("scrolls")) == TYPE_ARRAY else []
	var requests: Array = chest.get("friend_requests", []) if typeof(chest.get("friend_requests")) == TYPE_ARRAY else []
	## Keep scheduled-ready alarms in sync (works while app later closed).
	if view != "hidden":
		NotificationHelper.ensure_channels()
		NotificationHelper.sync_scheduled_from_chest(scrolls)
		## Central requirement-transition notifier (deduped local alerts).
		if _req_notifier != null:
			_req_notifier.evaluate_chest_items(scrolls)
	for s in scrolls:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var item := _normalize_online_scroll_item(s)
		if view == "hidden":
			item["is_hidden"] = true
		var st := str(item.get("state", ""))
		if filter == "unread" and st != "unlocked_unread" and st != "password_unlocked_unread":
			continue
		if filter == "locked" and st != "locked":
			continue
		if filter == "requests":
			continue
		out.append(item)
	if filter == "all" or filter == "requests":
		for r in requests:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			out.append(_normalize_friend_request_item(r))
	return out


func _load_online_saved_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var result: Dictionary = await state.scrolls.get_saved_scrolls({})
	if not bool(result.get("ok", false)):
		_show_toast(str(result.get("error", "Could not load saved scrolls.")))
		return out
	var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	state.cached_saved = data
	var items: Array = data.get("saved_scrolls", data.get("scrolls", [])) if typeof(data.get("saved_scrolls", data.get("scrolls", []))) == TYPE_ARRAY else []
	for s in items:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		out.append(_normalize_online_scroll_item(s))
	return out


func _now_unix() -> int:
	if state.is_demo():
		return state.demo.now_unix()
	return int(Time.get_unix_time_from_system())


func _format_unlock_countdown(remain_sec: int) -> String:
	if remain_sec <= 0:
		return "Ready to unlock"
	var unlock_unix := _now_unix() + remain_sec
	var now_dt := Time.get_datetime_dict_from_unix_time(_now_unix())
	var unlock_dt := Time.get_datetime_dict_from_unix_time(unlock_unix)
	var day_diff := int(unlock_dt.day) - int(now_dt.day)
	var same_month_year := int(unlock_dt.month) == int(now_dt.month) and int(unlock_dt.year) == int(now_dt.year)
	## Cross-day but within ~36h → “tomorrow at …”
	if remain_sec >= 12 * 3600 and ((same_month_year and day_diff == 1) or (not same_month_year and remain_sec < 36 * 3600)):
		var hour := int(unlock_dt.hour)
		var minute := int(unlock_dt.minute)
		var ampm := "AM" if hour < 12 else "PM"
		var h12 := hour % 12
		if h12 == 0:
			h12 = 12
		return "Unlocks tomorrow at %d:%02d %s" % [h12, minute, ampm]
	var hours := int(remain_sec / 3600)
	var mins := int((remain_sec % 3600) / 60)
	if hours >= 1:
		if mins > 0:
			return "Unlocks in %d hr %d min" % [hours, mins]
		return "Unlocks in %d hr" % hours
	return "Unlocks in %d min" % maxi(mins, 1)


func _style_inventory_filter_chip(chip: Button, selected: bool) -> void:
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected:
		chip.add_theme_color_override("font_color", MobileUi.COLOR_TITLE)
		var gold := StyleBoxFlat.new()
		gold.bg_color = Color(0.18, 0.12, 0.22, 0.95)
		gold.border_color = MobileUi.COLOR_TITLE
		gold.set_border_width_all(2)
		gold.set_corner_radius_all(12)
		gold.content_margin_left = 6
		gold.content_margin_right = 6
		gold.content_margin_top = 6
		gold.content_margin_bottom = 6
		chip.add_theme_stylebox_override("normal", gold)
		chip.add_theme_stylebox_override("hover", gold)
		chip.add_theme_stylebox_override("pressed", gold)


func _show_inventory() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "inventory"
	## Saved is its own screen — keep inventory filters coherent.
	if _inventory_filter == "saved":
		_show_saved()
		return
	_clear_screen()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, _nav_content_inset())
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	## Compact back + primary heading — fits phone width.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size.y = MobileUi.font_touch(48)
	root.add_child(header)
	var back := Button.new()
	back.text = "←"
	back.tooltip_text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(MobileUi.font_touch(48), MobileUi.font_touch(48))
	MobileUi.style_button(back, 48)
	back.pressed.connect(_show_main_chest)
	header.add_child(back)
	var title := Label.new()
	title.text = "YOUR CHEST"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	header.add_child(title)

	## Two-row filter grid — all categories visible without horizontal scroll.
	var chip_h := MobileUi.font_touch(MobileUi.FILTER_CHIP_H)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	root.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	root.add_child(row2)
	for f in [
		["all", "Current", row1],
		["unread", "Unread", row1],
		["locked", "Locked", row1],
		["requests", "Requests", row2],
		["saved", "Saved", row2],
		["hidden", "Hidden", row2],
	]:
		var fname: String = str(f[0])
		var parent: HBoxContainer = f[2]
		var chip := _make_button(str(f[1]), func() -> void:
			if fname == "saved":
				_inventory_filter = "saved"
				_show_saved()
			else:
				_inventory_filter = fname
				_show_inventory()
		, Vector2(0, chip_h))
		_style_inventory_filter_chip(chip, _inventory_filter == fname)
		parent.add_child(chip)

	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)

	## Paint shell first; fill items after (network may await).
	var loading := Label.new()
	loading.text = "Loading…"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(loading, MobileUi.SIZE_BODY, MobileUi.COLOR_HELPER)
	list.add_child(loading)

	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_chest_items(_inventory_filter)
	elif state.is_online():
		items = await _load_online_chest_items(_inventory_filter)
	if _current_screen != "inventory":
		return
	for c in list.get_children():
		c.queue_free()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Your chest is empty.\n\nNew love notes will appear here."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(empty, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
		list.add_child(empty)
		return
	for item in items:
		list.add_child(_make_chest_item_row(item))


func _make_chest_item_row(item: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.16, 0.92)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	var st := str(item.get("state", ""))
	match st:
		"friend_request":
			style.border_color = Color(0.55, 0.75, 1.0)
			style.set_border_width_all(2)
		"locked":
			style.border_color = Color(0.55, 0.45, 0.35)
			style.set_border_width_all(1)
		"unlocked_unread", "password_unlocked_unread":
			style.border_color = Color(0.95, 0.75, 0.35)
			style.set_border_width_all(2)
		"opened":
			style.bg_color = Color(0.1, 0.08, 0.12, 0.85)
	panel.add_theme_stylebox_override("panel", style)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)

	var title := Label.new()
	title.text = str(item.get("title", "Scroll"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SECTION))
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.75))
	row.add_child(title)

	var sender_prof: Dictionary = item.get("sender", {}) if typeof(item.get("sender")) == TYPE_DICTIONARY else {}
	var sender_name := IdentityHelper.display_name_from_profile(
		sender_prof,
		IdentityHelper.safe_label(str(item.get("sender_display_name", "")), IdentityHelper.UNKNOWN_SENDER)
	)
	var sender_lab := Label.new()
	sender_lab.text = "From %s" % sender_name
	sender_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(sender_lab, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_SECONDARY, true)
	row.add_child(sender_lab)

	var status_text := "Locked"
	match st:
		"friend_request":
			status_text = ProductStrings.CONNECTION_REQUEST
		"unlocked_unread", "password_unlocked_unread":
			status_text = "Ready to open"
		"opened":
			status_text = "Opened"
		"locked":
			status_text = "Locked"
		_:
			status_text = st.replace("_", " ").capitalize()
	var status_lab := Label.new()
	status_lab.text = "Status: %s" % status_text
	MobileUi.apply_label(status_lab, MobileUi.SIZE_SECONDARY, Color(0.82, 0.76, 0.88), true)
	row.add_child(status_lab)

	if st == "locked":
		var unlock_unix := int(item.get("unlock_at_unix", 0))
		if unlock_unix > 0:
			var time_lab := Label.new()
			time_lab.text = _format_unlock_countdown(unlock_unix - _now_unix())
			time_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			MobileUi.apply_label(time_lab, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_TITLE, true)
			row.add_child(time_lab)
		if bool(item.get("has_magic_password", false)):
			var pw := Label.new()
			pw.text = "Magic Password required"
			MobileUi.apply_label(pw, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, true)
			row.add_child(pw)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	var btn_h := MobileUi.font_touch(MobileUi.TOUCH_SECONDARY_H)
	var open_label := "View Locks" if st == "locked" else "Open"
	actions.add_child(_make_button(open_label, func() -> void: _open_chest_item(item), Vector2(0, btn_h)))
	if str(item.get("kind", "love_note")) != "friend_request":
		var fav := bool(item.get("is_favorite", false)) or bool(item.get("is_saved", false))
		var save_btn := _make_button("★ Saved" if fav else "☆ Save", func() -> void:
			_toggle_favorite(str(item.id), not fav)
		, Vector2(0, btn_h))
		save_btn.tooltip_text = "Remove from Saved" if fav else "Save this scroll"
		actions.add_child(save_btn)
		var is_hidden_item := bool(item.get("is_hidden", false))
		if is_hidden_item:
			actions.add_child(_make_button("Unhide", func() -> void:
				_unhide_received(str(item.id))
			, Vector2(0, btn_h)))
		else:
			actions.add_child(_make_button("Hide", func() -> void:
				_hide_received(str(item.id))
			, Vector2(0, btn_h)))
		actions.add_child(_make_button("Delete", func() -> void:
			_confirm_delete_received(str(item.id), item)
		, Vector2(0, btn_h)))
	return panel


func _show_saved() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "saved"
	_inventory_filter = "saved"
	_clear_screen()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, _nav_content_inset())
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size.y = MobileUi.font_touch(48)
	root.add_child(header)
	var back := Button.new()
	back.text = "←"
	back.tooltip_text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(MobileUi.font_touch(48), MobileUi.font_touch(48))
	MobileUi.style_button(back, 48)
	back.pressed.connect(func() -> void:
		_inventory_filter = "all"
		_show_inventory()
	)
	header.add_child(back)
	var title := Label.new()
	title.text = "YOUR CHEST"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	header.add_child(title)
	var chip_h := MobileUi.font_touch(MobileUi.FILTER_CHIP_H)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	root.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	root.add_child(row2)
	for f in [
		["all", "Current", row1],
		["unread", "Unread", row1],
		["locked", "Locked", row1],
		["requests", "Requests", row2],
		["saved", "Saved", row2],
	]:
		var fname: String = str(f[0])
		var parent: HBoxContainer = f[2]
		var chip := _make_button(str(f[1]), func() -> void:
			if fname == "saved":
				_inventory_filter = "saved"
				_show_saved()
			else:
				_inventory_filter = fname
				_show_inventory()
		, Vector2(0, chip_h))
		_style_inventory_filter_chip(chip, fname == "saved")
		parent.add_child(chip)
	var row2_pad := Control.new()
	row2_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(row2_pad)
	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)
	var loading := Label.new()
	loading.text = "Loading…"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(loading, MobileUi.SIZE_BODY, MobileUi.COLOR_HELPER)
	list.add_child(loading)
	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_saved_scrolls()
	elif state.is_online():
		items = await _load_online_saved_items()
	if _current_screen != "saved":
		return
	for c in list.get_children():
		c.queue_free()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No saved scrolls yet. Open a note to keep it here."
		MobileUi.apply_label(empty, MobileUi.SIZE_BODY, MobileUi.COLOR_HELPER)
		list.add_child(empty)
		return
	for item in items:
		list.add_child(_make_chest_item_row(item))


func _toggle_favorite(scroll_id: String, is_favorite: bool) -> void:
	if state.is_demo():
		var result := state.demo.set_scroll_favorite(scroll_id, is_favorite)
		if bool(result.get("ok", false)):
			_show_toast("Favorite updated")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not update favorite.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.set_scroll_favorite(scroll_id, is_favorite)
		if bool(result.get("ok", false)):
			_show_toast("Favorite updated")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not update favorite.")))
		return
	_show_toast("Backend is not configured.")


func _confirm_delete_received(scroll_id: String, item: Dictionary = {}) -> void:
	## Permanent per-user Delete — sender keeps their Sent copy.
	var sender_name := str(item.get("sender_display_name", ""))
	if sender_name.is_empty():
		var sender: Dictionary = item.get("sender", {}) if typeof(item.get("sender")) == TYPE_DICTIONARY else {}
		sender_name = IdentityHelper.display_name_from_profile(sender, "the sender")
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := 354.0
	var modal_h := 320.0
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Delete permanently?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var body := Label.new()
	body.text = "Delete this scroll permanently from your Chest? %s will still keep their Sent copy." % sender_name
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BODY))
	body.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	box.add_child(body)
	box.add_child(_make_button("Delete Permanently", func() -> void:
		_hide_overlay()
		_delete_received(scroll_id)
	))
	box.add_child(_make_button("Cancel", _hide_overlay, Vector2(180, MobileUi.font_touch(MobileUi.TOUCH_SECONDARY_H))))


func _hide_received(scroll_id: String) -> void:
	## Reversible Hide — no scary confirmation.
	if state.is_demo():
		var result := state.demo.hide_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			_show_snackbar("Scroll hidden", "Undo", func() -> void:
				_unhide_received(scroll_id)
			)
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not hide.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.hide_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			state.invalidate_cache("chest")
			_show_snackbar("Scroll hidden", "Undo", func() -> void:
				_unhide_received(scroll_id)
			)
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not hide.")))
		return
	_show_toast("Backend is not configured.")


func _unhide_received(scroll_id: String) -> void:
	if state.is_demo():
		var result := state.demo.unhide_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			_show_toast("Scroll restored")
			_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not unhide.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.unhide_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			state.invalidate_cache("chest")
			_show_toast("Scroll restored")
			_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not unhide.")))
		return
	_show_toast("Backend is not configured.")


func _delete_received(scroll_id: String) -> void:
	## Permanent per-user delete — cancel local lock work for this user's copy.
	if state.is_demo():
		var result := state.demo.delete_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			_cancel_local_work_for_scroll(scroll_id)
			_show_toast("Scroll deleted from your Chest")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not delete.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.delete_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			state.invalidate_cache("chest")
			_cancel_local_work_for_scroll(scroll_id)
			_show_toast("Scroll deleted from your Chest")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not delete.")))
		return
	_show_toast("Backend is not configured.")


func _cancel_local_work_for_scroll(scroll_id: String) -> void:
	## Recipient permanently deleted their copy — stop notifying this user only.
	if scroll_id.is_empty():
		return
	LocationHelper.remove_geofence(scroll_id)
	NotificationHelper.cancel_scheduled_ready(scroll_id)
	ActivityLockHelper.reset_challenge(scroll_id)


func _open_chest_item(item: Dictionary) -> void:
	var st := str(item.get("state", ""))
	if st == "friend_request":
		_show_friend_request(item)
		return
	if st == "locked":
		_show_locked_details(item)
		return
	if bool(item.get("has_magic_password", false)) and st != "opened":
		_show_password_dialog(item)
		return
	if st == "opened" and bool(item.get("has_magic_password", false)):
		_show_password_dialog(item)
		return
	await _open_authorized_scroll(
		str(item.id),
		"",
		bool(item.get("has_location_lock", false))
	)


func _show_locked_details(item: Dictionary) -> void:
	## Refresh Focus/Activity status before showing checklist.
	var sid := str(item.get("id", ""))
	if bool(item.get("focus_lock_enabled", false)) and not sid.is_empty():
		FocusLockHelper.evaluate(sid)
	var fix := {}
	if bool(item.get("has_location_lock", false)):
		fix = LocationHelper.get_current_fix(false)
	var eval := ScrollLockEvaluator.evaluate(item, int(Time.get_unix_time_from_system()), fix)
	var lines: PackedStringArray = PackedStringArray([
		"From: %s" % str(item.get("sender_display_name", "")),
		"Title: %s" % str(item.get("title", "")),
		"",
		"This scroll has %d locks" % int(eval.get("active_count", 0)),
		"",
	])
	for c in eval.get("checks", []):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var active := bool(c.get("active", false)) or str(c.get("id")) == "schedule"
		if not active:
			continue
		var mark := "✓" if bool(c.get("ok", false)) else "○"
		var label := str(c.get("label", ""))
		var detail := str(c.get("detail", "")).strip_edges()
		if not detail.is_empty() and not bool(c.get("ok", false)):
			lines.append("%s %s — %s" % [mark, label, detail])
		else:
			lines.append("%s %s" % [mark, label])
	_show_lock_actions_panel(item, lines, eval)


func _show_lock_actions_panel(item: Dictionary, lines: PackedStringArray, eval: Dictionary) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, 16)
	_overlay.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	MobileUi.configure_scroll(scroll)
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Sealed Scroll"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var body := Label.new()
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(0.94, 0.9, 0.96))
	box.add_child(body)
	var sid := str(item.get("id", ""))
	if bool(item.get("activity_lock_enabled", false)):
		var prog := ActivityLockHelper.get_progress(sid)
		var target := float(item.get("activity_target_km", ActivityLockHelper.DEFAULT_KM))
		if not bool(prog.get("started", false)) and not bool(prog.get("completed", false)):
			box.add_child(_make_button("Start Challenge", func() -> void:
				var fix2 := LocationHelper.get_current_fix(true)
				if not bool(fix2.get("ok", false)):
					_show_toast(str(fix2.get("error", "Location is needed to start Activity Lock.")))
					return
				## Uses while-in-use location + foreground service (not "Allow all the time").
				ActivityLockHelper.start_challenge(sid, target, float(fix2.lat), float(fix2.lng))
				if state.is_online():
					await state.scrolls.mark_activity_lock_progress(sid, 0.0, false)
				NotificationHelper.request_permission_contextual()
				NotificationHelper.notify_activity_progress(0.0, target)
				_hide_overlay()
				_show_locked_details(item)
			))
		elif not bool(prog.get("completed", false)):
			## Merge any background foreground-service progress before showing UI.
			ActivityLockHelper.sync_from_native_service(sid)
			box.add_child(_make_button("Update Activity Progress", func() -> void:
				ActivityLockHelper.sync_from_native_service(sid)
				var fix3 := LocationHelper.get_current_fix(true)
				if bool(fix3.get("ok", false)):
					var res := ActivityLockHelper.apply_sample(sid, float(fix3.lat), float(fix3.lng), float(fix3.get("accuracy_m", 25.0)))
					var st: Dictionary = res.get("state", {})
					var dist := float(st.get("distance_km", 0.0))
					var done := bool(st.get("completed", false))
					if state.is_online():
						await state.scrolls.mark_activity_lock_progress(sid, dist, done)
					NotificationHelper.notify_activity_progress(dist, target)
					if done:
						NotificationHelper.notify_activity_complete()
				_hide_overlay()
				_show_locked_details(item)
			))
			box.add_child(_make_button("Reset Activity Challenge", func() -> void:
				ActivityLockHelper.reset_challenge(sid)
				_hide_overlay()
				_show_locked_details(item)
			))
	if bool(item.get("focus_lock_enabled", false)):
		var fp := FocusLockHelper.get_progress(sid)
		if not FocusLockHelper.usage_access_granted() and OS.get_name() == "Android":
			var explain := Label.new()
			explain.text = "Focus Lock needs Usage Access so the app can verify that the focus period was uninterrupted. Chest of Love Notes does not use this to build an app-usage history."
			explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			explain.add_theme_font_size_override("font_size", 15)
			explain.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
			box.add_child(explain)
			box.add_child(_make_button("Allow Usage Access", func() -> void:
				FocusLockHelper.open_usage_access_settings()
			))
		elif not bool(fp.get("completed", false)):
			var btn_label := "Begin Focus Time"
			if bool(fp.get("interrupted", false)) or (bool(fp.get("started", false)) == false and bool(fp.get("interrupted", false))):
				btn_label = "Start Focus Again"
			elif bool(fp.get("started", false)):
				btn_label = "Check Focus Progress"
			box.add_child(_make_button(btn_label, func() -> void:
				if not bool(fp.get("started", false)) or bool(fp.get("interrupted", false)):
					FocusLockHelper.begin_focus(sid, int(item.get("focus_duration_hours", FocusLockHelper.DEFAULT_HOURS)))
					if state.is_online():
						await state.scrolls.mark_focus_lock_started(sid)
				var fr := FocusLockHelper.evaluate(sid)
				var status := str(fr.get("status", ""))
				if status == "complete":
					if state.is_online():
						await state.scrolls.mark_focus_lock_complete(sid)
					var all_ready := bool(ScrollLockEvaluator.evaluate(item).get("ok", false))
					NotificationHelper.notify_focus_complete(all_ready)
				elif status == "interrupted" or status == "reboot_reset":
					if state.is_online():
						await state.scrolls.mark_focus_lock_interrupted(sid)
					if str(fr.get("message", "")) != "":
						_show_toast(str(fr.get("message")))
				elif str(fr.get("message", "")) != "":
					_show_toast(str(fr.get("message")))
				_hide_overlay()
				_show_locked_details(item)
			))
	if bool(item.get("has_location_lock", false)):
		_add_geofence_opt_in(box, item)
	if bool(eval.get("ok", false)):
		box.add_child(_make_button("Open Scroll", func() -> void:
			_hide_overlay()
			item["password_ok"] = not (bool(item.get("has_magic_password", false)) or bool(item.get("has_password", false)))
			if bool(item.get("has_magic_password", false)) or bool(item.get("has_password", false)):
				_show_password_dialog(item)
			else:
				await _open_authorized_scroll(sid, "", bool(item.get("has_location_lock", false)))
		))
	box.add_child(_make_button("Close", func() -> void: _hide_overlay()))


func _show_friend_request(item: Dictionary) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := 354.0
	var modal_h := 320.0
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = ProductStrings.CONNECTION_REQUEST
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(title)
	var body := Label.new()
	body.text = ProductStrings.wants_to_connect(str(item.get("sender_display_name", "Someone")))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BODY))
	body.add_theme_color_override("font_color", Color(0.95, 0.9, 0.98))
	box.add_child(body)
	box.add_child(_make_button("Accept", func() -> void:
		if state.is_demo():
			state.demo.respond_friend_request(str(item.id), true)
			_hide_overlay()
			_play_friends_celebration()
			_show_toast(ProductStrings.CONNECTION_REQUEST_ACCEPTED)
			_show_inventory()
			return
		var result: Dictionary = await state.friends.respond_to_friend_request(str(item.id), true)
		_hide_overlay()
		if bool(result.get("ok", false)):
			_play_friends_celebration()
			_show_toast(ProductStrings.CONNECTION_REQUEST_ACCEPTED)
			_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not accept request.")))
	))
	box.add_child(_make_button("Decline", func() -> void:
		if state.is_demo():
			state.demo.respond_friend_request(str(item.id), false)
			_hide_overlay()
			_show_inventory()
			return
		var result: Dictionary = await state.friends.respond_to_friend_request(str(item.id), false)
		_hide_overlay()
		if bool(result.get("ok", false)):
			_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not decline request.")))
	))
	box.add_child(_make_button("Close", _hide_overlay, Vector2(220, 64)))


func _show_password_dialog(item: Dictionary) -> void:
	_password_target = item
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := 354.0
	var modal_h := 320.0
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Magic Password"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 1.0))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Demo password for the sealed note: starlight"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SECONDARY))
	hint.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
	box.add_child(hint)
	var field := LineEdit.new()
	field.placeholder_text = "Enter magic password"
	field.secret = true
	field.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.INPUT_H))
	box.add_child(field)
	var show_toggle := CheckBox.new()
	show_toggle.text = "Show password"
	show_toggle.toggled.connect(func(on: bool) -> void: field.secret = not on)
	box.add_child(show_toggle)
	box.add_child(_make_button("Submit", func() -> void:
		var pw := field.text
		field.text = ""
		_hide_overlay()
		await _open_authorized_scroll(
			str(item.id),
			pw,
			bool(item.get("has_location_lock", false))
		)
	))
	box.add_child(_make_button("Cancel", func() -> void:
		field.text = ""
		_hide_overlay()
	, Vector2(220, 64)))


func _open_authorized_scroll(scroll_id: String, magic_password: String, needs_location: bool = false) -> void:
	var lat := NAN
	var lng := NAN
	var accuracy := NAN
	if needs_location:
		if OS.get_name() == "Android":
			var status := LocationHelper.request_permission_if_needed()
			if status != "granted":
				await get_tree().create_timer(0.35).timeout
				status = LocationHelper.permission_status()
			if status != "granted":
				_show_toast("Location access is needed only to verify whether you're near the unlock location.")
				return
		var fix: Dictionary = LocationHelper.get_current_fix(true)
		if not bool(fix.get("ok", false)):
			## Never treat missing location as authorization to unlock.
			_show_toast(str(fix.get("error", "We couldn't verify your location. Try again.")))
			return
		lat = float(fix.get("lat", NAN))
		lng = float(fix.get("lng", NAN))
		accuracy = float(fix.get("accuracy_m", NAN))
	var result: Dictionary = {}
	if state.is_demo():
		result = state.demo.open_scroll(scroll_id, magic_password, lat, lng)
	elif state.is_online():
		result = await state.scrolls.open_scroll(scroll_id, magic_password, lat, lng, accuracy)
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			result = {
				"ok": true,
				"message": str(data.get("message", "")),
				"scroll": data.get("scroll", {}),
				"ephemeral": bool(data.get("ephemeral", false)),
			}
		else:
			result = {
				"ok": false,
				"error": str(result.get("error", "Could not open scroll.")),
				"locked": bool(result.get("locked", false)),
			}
	else:
		_show_toast("Backend is not configured.")
		return
	if not bool(result.get("ok", false)):
		_show_toast(str(result.get("error", "Could not open scroll.")))
		return
	var meta: Dictionary = result.get("scroll", {})
	var body := str(result.get("message", ""))
	state.open_message_plaintext = body
	var ephemeral := bool(result.get("ephemeral", false))
	var heading := str(meta.get("title", "A Love Note"))
	var sender_prof: Dictionary = {}
	if typeof(meta.get("sender")) == TYPE_DICTIONARY:
		sender_prof = meta.get("sender")
	var meta_line := IdentityHelper.format_from(
		sender_prof,
		str(meta.get("sender_display_name", "")),
		str(meta.get("sender_username", "")),
		str(meta.get("sender_id", ""))
	)
	var open_atts: Array = []
	if state.is_online():
		var att_res: Dictionary = await state.scrolls.get_scroll_attachments(scroll_id)
		if bool(att_res.get("ok", false)):
			var att_data: Dictionary = att_res.get("data", {})
			var rows = att_data.get("attachments", [])
			if typeof(rows) == TYPE_ARRAY:
				for row in rows:
					if typeof(row) == TYPE_DICTIONARY:
						open_atts.append({
							"id": str(row.get("id", "")),
							"signed_url": str(row.get("signed_url", "")),
							"mime": str(row.get("mime_type", "")),
						})
	await _scroll_viewer.open_message(heading, meta_line, body, true, ephemeral, open_atts, "Love Note")


func _on_scroll_attachment_tapped(attachment: Dictionary) -> void:
	var path := str(attachment.get("path", attachment.get("local_path", "")))
	if not path.is_empty() and FileAccess.file_exists(path):
		if _image_preview:
			_image_preview.open_path(path, "Attachment")
		return
	var url := str(attachment.get("signed_url", ""))
	if url.is_empty() or _image_preview == null:
		_show_toast("Photo unavailable.")
		return
	_show_toast("Loading photo…")
	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		_show_toast("Could not load photo.")
		return
	var completed: Array = await http.request_completed
	http.queue_free()
	if completed.is_empty() or int(completed[0]) != HTTPRequest.RESULT_SUCCESS or int(completed[1]) != 200:
		_show_toast("Could not load photo.")
		return
	var bytes: PackedByteArray = completed[3]
	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK and img.load_png_from_buffer(bytes) != OK and img.load_webp_from_buffer(bytes) != OK:
		_show_toast("Could not read photo.")
		return
	_image_preview.open_texture(ImageTexture.create_from_image(img), "Attachment")


func _on_scroll_closed() -> void:
	# Clear plaintext from memory when the viewer closes.
	state.clear_open_message()
	if state.is_demo():
		state.demo.open_message_plaintext = ""
	match _current_screen:
		"compose":
			# Preview returns to the live compose form — do not rebuild/wipe draft.
			pass
		"inventory":
			_show_inventory()
		"saved":
			_show_saved()
		"sent":
			_show_sent()
		_:
			_show_main_chest()


func _person_from_friends_cache() -> Dictionary:
	var person: Dictionary = {}
	if state.is_demo():
		var demo_friends: Array = state.demo.get_friends()
		if not demo_friends.is_empty() and typeof(demo_friends[0]) == TYPE_DICTIONARY:
			return demo_friends[0]
		return person
	var data: Dictionary = state.cached_friends if typeof(state.cached_friends) == TYPE_DICTIONARY else {}
	## Authoritative empty from backend — NEVER invent Person from sticky disk.
	if state.friends_backend_authoritative and data.has("person") and typeof(data.get("person")) != TYPE_DICTIONARY:
		return {}
	if typeof(data.get("person")) == TYPE_DICTIONARY:
		person = data.get("person")
	elif typeof(data.get("friends")) == TYPE_ARRAY and not (data.get("friends") as Array).is_empty():
		var arr: Array = data.get("friends")
		if typeof(arr[0]) == TYPE_DICTIONARY:
			person = arr[0]
	## Pairing existence ≠ profile hydration: enrich pending profiles from disk.
	if not person.is_empty() and str(person.get("id", "")).is_empty() == false:
		if bool(person.get("profile_pending", false)):
			var cached2 := state.load_last_person_cache()
			if str(cached2.get("id", "")) == str(person.get("id", "")):
				if str(person.get("display_name", "")).is_empty() or str(person.get("display_name")) == "My Person":
					person["display_name"] = str(cached2.get("display_name", "My Person"))
				if str(person.get("username", "")).is_empty():
					person["username"] = str(cached2.get("username", ""))
		return person
	## Sticky identity ONLY before the first authoritative backend friends payload.
	## After disconnect / get-friends(null), sticky must not resurrect Mandy.
	if state.friends_backend_authoritative:
		return {}
	var cached := state.load_last_person_cache()
	if not cached.is_empty() and not str(cached.get("id", "")).is_empty():
		return cached
	return person


func _show_compose() -> void:
	if not _guard_private_chest():
		return
	var nav_t0 := Time.get_ticks_msec()
	## Capture draft before screen teardown if we are leaving another compose instance.
	_persist_compose_draft_if_needed()
	_current_screen = "compose"
	_compose_screen = null

	## Paint with cached person first; refresh async if needed.
	var person: Dictionary = _person_from_friends_cache()
	if state.is_demo():
		state.mark_cache_fresh("friends")

	var draft_to_restore: Dictionary = _compose_draft.duplicate(true)
	_begin_nav_transition()
	var compose := ComposeScrollScreen.new()
	compose.bottom_chrome_inset = _nav_content_inset()
	compose.anchor_left = 0.0
	compose.anchor_top = 0.0
	compose.anchor_right = 1.0
	compose.anchor_bottom = 1.0
	compose.offset_left = 0.0
	compose.offset_top = 0.0
	compose.offset_right = 0.0
	compose.offset_bottom = -float(compose.bottom_chrome_inset)
	_screen_host.add_child(compose)
	_compose_screen = compose
	compose.back_pressed.connect(_show_main_chest)
	compose.preview_requested.connect(_on_compose_preview)
	compose.send_requested.connect(_on_compose_send_requested)
	compose.go_to_my_person_requested.connect(_show_friends)
	var me_profile: Dictionary = {}
	if state.is_demo():
		me_profile = state.demo.get_profile()
	elif state.is_online():
		me_profile = state.profiles.profile if typeof(state.profiles.profile) == TYPE_DICTIONARY else {}
		if me_profile.is_empty() and state.tokens != null and not str(state.tokens.user_id).is_empty():
			me_profile = {"id": state.tokens.user_id, "display_name": "Me", "username": ""}
	compose.setup_with_person(person, false, draft_to_restore, me_profile)
	_add_bottom_nav("compose")
	_finish_nav_transition()
	_log_nav_paint("compose", nav_t0)
	## Always refresh when person is empty — do not trust a fresh-but-empty friends cache.
	var need_person_refresh := state.is_online() and (
		person.is_empty() or str(person.get("id", "")).is_empty() or not state.cache_is_fresh("friends")
	)
	if need_person_refresh:
		var fr: Dictionary = await state.friends.get_my_person()
		if _current_screen != "compose" or _compose_screen == null or not is_instance_valid(_compose_screen):
			return
		if bool(fr.get("ok", false)):
			var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
			state.apply_friends_payload(data)
			state.mark_cache_fresh("friends")
			var fresh_person := _person_from_friends_cache()
			## Always rebind Compose to the active Person (canonical recipient), including empty.
			_compose_screen.setup_with_person(fresh_person, false, _compose_screen.get_draft(), me_profile)
		else:
			var err := str(fr.get("error", "Could not load My Person."))
			if not err.is_empty() and person.is_empty():
				_show_toast(err)


func _on_compose_preview(draft: Dictionary) -> void:
	_compose_draft = draft.duplicate(true)
	var title := str(draft.get("title", "")).strip_edges()
	if title.is_empty():
		title = "A Love Note"
	var recipient := str(draft.get("recipient_display_name", ProductStrings.PERSON))
	if recipient.is_empty():
		recipient = ProductStrings.PERSON
	var immediate := bool(draft.get("open_immediately", true))
	var when := "Opens immediately"
	if not immediate:
		var unlock_unix := int(draft.get("unlock_unix", 0))
		when = "Opens %s" % Time.get_datetime_string_from_unix_time(unlock_unix, false)
	var meta_bits: PackedStringArray = PackedStringArray(["To %s" % recipient])
	if immediate:
		meta_bits.append("Available immediately")
	else:
		meta_bits.append(when.replace("Opens ", "Available "))
	if bool(draft.get("has_location_lock", false)):
		var radius := int(draft.get("location_radius_m", LocationHelper.DEFAULT_RADIUS_M))
		meta_bits.append("Location Lock · %s" % LocationHelper.format_radius(radius))
	if bool(draft.get("activity_lock_enabled", false)):
		meta_bits.append("Activity Lock · %s" % ActivityLockHelper.format_km(float(draft.get("activity_target_km", 5.0))))
	if bool(draft.get("focus_lock_enabled", false)):
		var fh := int(draft.get("focus_duration_hours", 3))
		meta_bits.append("Focus Lock · 1 hr" if fh == 1 else "Focus Lock · %d hr" % fh)
	if bool(draft.get("has_password", false)):
		meta_bits.append("Magic Password required")
	var meta := "\n".join(meta_bits)
	var body := str(draft.get("message", ""))
	await _scroll_viewer.open_message(title, meta, body, true, false, [], "Scroll Preview")


func _on_compose_send_requested(draft: Dictionary) -> void:
	if _compose_screen == null:
		return
	_compose_draft = draft.duplicate(true)
	_compose_screen.set_sending(true)
	var rid := str(draft.get("recipient_id", ""))
	var body := str(draft.get("message", ""))
	var title := str(draft.get("title", "")).strip_edges()
	var magic := str(draft.get("password", ""))
	var open_immediately := bool(draft.get("open_immediately", true))
	## Immediate mode must not send a stale future unlock time.
	var unlock_unix := int(Time.get_unix_time_from_system())
	if not open_immediately:
		unlock_unix = int(draft.get("unlock_unix", unlock_unix))
	var has_location_lock := bool(draft.get("has_location_lock", false))
	var location_name := str(draft.get("location_name", "")).strip_edges()
	var location_address := str(draft.get("location_address", "")).strip_edges()
	var location_lat := float(draft.get("location_lat", 0.0))
	var location_lng := float(draft.get("location_lng", 0.0))
	var location_radius_m := int(draft.get("location_radius_m", LocationHelper.DEFAULT_RADIUS_M))
	if has_location_lock and (not bool(draft.get("location_fix_ok", false)) or not is_finite(location_lat) or not is_finite(location_lng)):
		## One user-facing error only (inline Ready Check) — no competing toast.
		_compose_screen.restore_after_failed_send("Select a location from the search results or choose one on the map.")
		return
	var result: Dictionary = {}
	if state.is_demo():
		result = state.demo.send_scroll(
			rid, title, body, unlock_unix, magic,
			has_location_lock, location_name, location_lat, location_lng, location_radius_m, location_address
		)
	elif state.is_online():
		# Existing send-scroll contract + optional Location Lock + photo attachments.
		var unlock_at := Time.get_datetime_string_from_unix_time(unlock_unix, true) + "Z"
		var payload := {
			"recipient_id": rid,
			"title": title,
			"message": body,
			"unlock_at": unlock_at,
			"has_location_lock": has_location_lock,
		}
		if not magic.is_empty():
			payload["password"] = magic
		if has_location_lock:
			payload["location_name"] = location_name
			payload["location_address"] = location_address
			payload["location_lat"] = location_lat
			payload["location_lng"] = location_lng
			payload["location_radius_m"] = location_radius_m
		if bool(draft.get("activity_lock_enabled", false)):
			payload["activity_lock_enabled"] = true
			payload["activity_target_km"] = float(draft.get("activity_target_km", ActivityLockHelper.DEFAULT_KM))
		if bool(draft.get("focus_lock_enabled", false)):
			payload["focus_lock_enabled"] = true
			payload["focus_duration_hours"] = int(draft.get("focus_duration_hours", FocusLockHelper.DEFAULT_HOURS))
		## Attachments intentionally omitted from active send path.
		result = await state.scrolls.send_scroll(payload)
		if bool(result.get("ok", false)):
			result = {"ok": true}
		else:
			## Map backend/schema failures to one simple user message; keep diagnostics in logs.
			var status := int(result.get("status", 0))
			var raw_err := str(result.get("error", ""))
			var code := ""
			var data: Variant = result.get("data", {})
			if typeof(data) == TYPE_DICTIONARY:
				code = str((data as Dictionary).get("code", (data as Dictionary).get("error", "")))
			print("send_scroll_failed status=%d code=%s err=%s" % [status, code, raw_err])
			var user_msg := "Could not send your scroll. Please try again."
			if status == 401:
				user_msg = "Your session expired. Please sign in again."
			elif raw_err.to_lower().contains("not friends"):
				user_msg = "You can only send scrolls to your Person."
			result = {"ok": false, "error": user_msg}
	else:
		_compose_screen.restore_after_failed_send("Backend is not configured.")
		return
	if bool(result.get("ok", false)):
		_compose_screen.set_sending(false)
		_clear_compose_draft()
		_compose_screen = null
		state.invalidate_cache("sent")
		state.invalidate_cache("chest")
		_show_toast("Scroll sent.")
		_show_main_chest()
	else:
		## Single inline error — do not also toast the same failure.
		_compose_screen.restore_after_failed_send(str(result.get("error", "Could not send your scroll. Please try again.")))


func _play_friends_celebration() -> void:
	## Restrained petal burst — behind content, never covering nav/buttons.
	var fx := FriendsCelebration.new()
	_screen_host.add_child(fx)
	fx.play(state.reduced_motion or MobileUi.reduced_motion())


func _show_friends() -> void:
	## My Person — strict one-to-one pairing (no multi-friend list).
	if not _guard_private_chest():
		return
	var nav_t0 := Time.get_ticks_msec()
	_current_screen = "friends"
	var person: Dictionary = {}
	var me: Dictionary = {}
	var incoming: Array = []
	if state.is_demo():
		var demo_friends: Array = state.demo.get_friends()
		if not demo_friends.is_empty() and typeof(demo_friends[0]) == TYPE_DICTIONARY:
			person = demo_friends[0]
		me = state.demo.get_profile()
		state.mark_cache_fresh("friends")
	elif state.is_online():
		## Same canonical active-Person resolver as Compose + Android Diagnostics.
		person = _person_from_friends_cache()
		var data: Dictionary = state.cached_friends if typeof(state.cached_friends) == TYPE_DICTIONARY else {}
		if typeof(data.get("me")) == TYPE_DICTIONARY:
			me = data.get("me")
		else:
			me = state.profiles.profile if typeof(state.profiles.profile) == TYPE_DICTIONARY else {}
		incoming = data.get("incoming_requests", []) if typeof(data.get("incoming_requests")) == TYPE_ARRAY else []

	_begin_nav_transition()
	var root := _make_screen_root(_nav_content_inset())
	root.add_child(MobileUi.make_page_title(ProductStrings.MY_PERSON, _title_font()))

	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)

	## Incoming connection requests
	for req in incoming:
		if typeof(req) != TYPE_DICTIONARY:
			continue
		var sender: Dictionary = req.get("sender", {}) if typeof(req.get("sender")) == TYPE_DICTIONARY else {}
		var sname := IdentityHelper.display_name_from_profile(sender, "Someone")
		var card_r := _make_card()
		var col_r := VBoxContainer.new()
		col_r.add_theme_constant_override("separation", 8)
		card_r.add_child(col_r)
		var lab_r := Label.new()
		lab_r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab_r.text = ProductStrings.wants_to_connect(sname)
		MobileUi.apply_label(lab_r, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
		col_r.add_child(lab_r)
		var row_r := HBoxContainer.new()
		row_r.add_theme_constant_override("separation", 10)
		col_r.add_child(row_r)
		var accept := Button.new()
		accept.text = "Accept"
		accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(accept, MobileUi.TOUCH_PRIMARY_H)
		var decline := Button.new()
		decline.text = "Decline"
		decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(decline, MobileUi.TOUCH_SECONDARY_H)
		var req_id := str(req.get("id", ""))
		accept.pressed.connect(func() -> void:
			if _friend_action_busy:
				return
			_friend_action_busy = true
			var result: Dictionary = await state.friends.respond_to_friend_request(req_id, true)
			_friend_action_busy = false
			if bool(result.get("ok", false)):
				_show_toast("You're now connected with %s." % sname)
				_play_friends_celebration()
				state.invalidate_cache("friends")
				_show_friends()
			else:
				_show_toast(str(result.get("error", "Could not accept.")))
		)
		decline.pressed.connect(func() -> void:
			if _friend_action_busy:
				return
			_friend_action_busy = true
			var result: Dictionary = await state.friends.respond_to_friend_request(req_id, false)
			_friend_action_busy = false
			state.invalidate_cache("friends")
			_show_friends()
			if not bool(result.get("ok", false)):
				_show_toast(str(result.get("error", "Could not decline.")))
		)
		row_r.add_child(accept)
		row_r.add_child(decline)
		list.add_child(card_r)

	if person.is_empty():
		var headline := Label.new()
		headline.text = ProductStrings.EMPTY_HEADLINE
		headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MobileUi.apply_label(headline, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE, true)
		list.add_child(headline)
		var support := Label.new()
		support.text = ProductStrings.EMPTY_SUPPORT
		support.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MobileUi.apply_label(support, MobileUi.SIZE_BODY, MobileUi.COLOR_HELPER, true)
		list.add_child(support)

		var scan_btn := Button.new()
		scan_btn.text = ProductStrings.SCAN_PERSON_CODE
		scan_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(scan_btn, MobileUi.TOUCH_CTA_H)
		scan_btn.pressed.connect(_on_scan_person_code)
		list.add_child(scan_btn)

		var show_btn := Button.new()
		show_btn.text = ProductStrings.SHOW_MY_CODE
		show_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(show_btn, MobileUi.TOUCH_PRIMARY_H)
		show_btn.pressed.connect(func() -> void:
			_show_my_connection_code(me)
		)
		list.add_child(show_btn)

		var enter_lab := Label.new()
		enter_lab.text = ProductStrings.ENTER_CODE
		MobileUi.apply_label(enter_lab, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, false)
		list.add_child(enter_lab)
		var search := LineEdit.new()
		search.placeholder_text = "Username or Connection Code"
		search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_line_edit(search)
		list.add_child(search)
		var connect_btn := Button.new()
		connect_btn.text = ProductStrings.CONNECT
		connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(connect_btn, MobileUi.TOUCH_PRIMARY_H)
		connect_btn.disabled = true
		list.add_child(connect_btn)
		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MobileUi.apply_label(status, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, true)
		list.add_child(status)
		search.text_changed.connect(func(_t: String) -> void:
			connect_btn.disabled = search.text.strip_edges().is_empty() or _friend_action_busy
		)
		connect_btn.pressed.connect(func() -> void:
			var q := search.text.strip_edges()
			if q.is_empty() or _friend_action_busy:
				return
			_friend_action_busy = true
			connect_btn.disabled = true
			status.text = ""
			var result: Dictionary = {}
			if state.is_demo():
				result = state.demo.send_friend_request(q)
			else:
				result = await state.friends.send_friend_request_query(q)
			_friend_action_busy = false
			connect_btn.disabled = search.text.strip_edges().is_empty()
			if bool(result.get("ok", false)):
				search.text = ""
				_show_toast("Connection request sent.")
				state.invalidate_cache("friends")
				_show_friends()
			else:
				status.add_theme_color_override("font_color", MobileUi.COLOR_DANGER)
				status.text = str(result.get("error", "Could not send connection request."))
		)
	else:
		var name_l := Label.new()
		name_l.text = IdentityHelper.display_name_from_profile(person)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MobileUi.apply_label(name_l, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE, true)
		list.add_child(name_l)
		var user := IdentityHelper.username_from_profile(person)
		if not user.is_empty():
			var user_l := Label.new()
			user_l.text = "@%s" % user
			MobileUi.apply_label(user_l, MobileUi.SIZE_BODY, MobileUi.COLOR_SECONDARY, false)
			list.add_child(user_l)
		var since := str(person.get("connected_at", ""))
		if not since.is_empty():
			var dt := since.substr(0, 10)
			var since_l := Label.new()
			since_l.text = ProductStrings.connected_since(dt)
			MobileUi.apply_label(since_l, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, false)
			list.add_child(since_l)
		var show_mine := Button.new()
		show_mine.text = ProductStrings.SHOW_MY_CODE
		show_mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(show_mine, MobileUi.TOUCH_PRIMARY_H)
		show_mine.pressed.connect(func() -> void:
			_show_my_connection_code(me)
		)
		list.add_child(show_mine)
		## Scan remains visible even when already paired; one-Person rule blocks a second connection.
		var scan_paired := Button.new()
		scan_paired.text = ProductStrings.SCAN_PERSON_CODE
		scan_paired.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(scan_paired, MobileUi.TOUCH_SECONDARY_H)
		scan_paired.pressed.connect(_on_scan_person_code)
		list.add_child(scan_paired)
		var disc := Button.new()
		disc.text = ProductStrings.DISCONNECT
		disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.style_button(disc, MobileUi.TOUCH_SECONDARY_H)
		disc.pressed.connect(func() -> void:
			_confirm_disconnect_person(person)
		)
		list.add_child(disc)

	_add_bottom_nav("friends")
	_finish_nav_transition()
	_log_nav_paint("friends", nav_t0)
	if state.is_online() and not state.cache_is_fresh("friends"):
		var fr: Dictionary = await state.friends.get_my_person()
		if _current_screen != "friends":
			return
		if bool(fr.get("ok", false)):
			var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
			state.apply_friends_payload(data)
			state.mark_cache_fresh("friends")
			## Rebuild once with fresh person data (still after first paint).
			_show_friends()
		elif person.is_empty():
			var err := str(fr.get("error", "Could not load My Person."))
			if not err.is_empty():
				_show_toast(err)


func _confirm_disconnect_person(person: Dictionary) -> void:
	var name := IdentityHelper.display_name_from_profile(person)
	_clear_overlay()
	if _overlay == null:
		return
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeAreaHelper.apply_to_margin(host, 24, 24, 24)
	_overlay.add_child(host)
	var panel := PanelContainer.new()
	host.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = ProductStrings.disconnect_confirm(name)
	MobileUi.apply_label(body, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	col.add_child(body)
	var yes := Button.new()
	yes.text = ProductStrings.DISCONNECT
	MobileUi.style_button(yes, MobileUi.TOUCH_CTA_H)
	yes.pressed.connect(func() -> void:
		_hide_overlay()
		if state.is_demo():
			_show_toast("Demo: disconnect not persisted.")
			return
		_log_relationship_debug("disconnect_requested")
		state.relationship_debug["last_event"] = "disconnect_requested"
		var had_local_person := not _person_from_friends_cache().is_empty()
		state.relationship_debug["active_pair_before"] = had_local_person
		state.record_disconnect_attempt_started("RPC")
		_log_relationship_debug("active_pair_found=%s" % ("true" if had_local_person else "false"))
		_log_relationship_debug("disconnect_backend_call_started")
		var result: Dictionary = await state.friends.disconnect_person()
		var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
		var mechanism := str(data.get("disconnect_mechanism", "Edge Function"))
		if mechanism.is_empty():
			mechanism = "Edge Function"
		state.relationship_debug["disconnect_mechanism"] = mechanism
		var http_status := int(result.get("status", 0))
		var safe_err := str(result.get("error", ""))
		_log_relationship_debug("disconnect_http_status=%d" % http_status)
		if not safe_err.is_empty():
			_log_relationship_debug("disconnect_safe_error=%s" % safe_err.substr(0, 120))
		## Success requires explicit verified disconnect — not merely HTTP 200 / null person.
		## If My Person UI showed an active pair, "not_connected" is a lookup failure.
		var verified := bool(result.get("ok", false)) and bool(data.get("verified_disconnected", false))
		if verified and had_local_person and data.has("relationship_found") and not bool(data.get("relationship_found", true)):
			verified = false
		_log_relationship_debug(
			"disconnect_backend_result=%s" % ("success" if verified else "failure")
		)
		if not verified:
			## Keep current pairing visible on failure — never optimistic clear.
			var category := str(data.get("failure_category", ""))
			if category.is_empty():
				category = state.friends.disconnect_failure_category(result, false)
			state.record_disconnect_failure(category, mechanism, had_local_person)
			_log_relationship_debug("disconnect_failure_category=%s" % category)
			_log_relationship_debug("disconnect_rows_affected=%s" % str(data.get("rows_affected", 0)))
			_log_relationship_debug("active_pair_after_backend=true")
			_show_toast("Couldn't disconnect right now. Please try again.")
			return
		## Only clear local Person after backend confirms durable disconnect.
		state.mark_verified_disconnected()
		state.relationship_debug["disconnect_mechanism"] = mechanism
		_log_relationship_debug("active_pair_after_backend=false")
		_log_relationship_debug("disconnect_rows_affected=%s" % str(data.get("rows_affected", 1)))
		## Immediate backend re-query — must still be None (proves no reconcile resurrect).
		var confirm: Dictionary = await state.friends.get_my_person()
		if bool(confirm.get("ok", false)):
			var cdata: Dictionary = confirm.get("data", {}) if typeof(confirm.get("data")) == TYPE_DICTIONARY else {}
			state.apply_friends_payload(cdata)
			var still := typeof(cdata.get("person")) == TYPE_DICTIONARY \
				and not str((cdata.get("person") as Dictionary).get("id", "")).is_empty()
			state.relationship_debug["post_disconnect_active_pair"] = still
			_log_relationship_debug("active_pair_after_refresh=%s" % ("true" if still else "false"))
			_log_relationship_debug(
				"reconciliation_ran=true result=%s" % str(cdata.get("reconciliation_last_result", "no_change"))
			)
			if still:
				_log_relationship_debug("pair_recreated=true recreation_source=get-friends")
				state.record_disconnect_failure("Function Error", mechanism, true)
				_show_toast("Couldn't disconnect right now. Please try again.")
				return
			_log_relationship_debug("pair_recreated=false")
			_log_relationship_debug(
				"legacy_friend_candidate=%s" % ("true" if bool(cdata.get("legacy_migration_eligible", false)) else "false")
			)
			_log_relationship_debug(
				"accepted_request_candidate=%s" % ("true" if bool(cdata.get("historical_accepted_request", false)) else "false")
			)
		else:
			state.relationship_debug["post_disconnect_active_pair"] = false
		_show_toast("Disconnected from %s" % name)
		_show_friends()
	)
	col.add_child(yes)
	var no := Button.new()
	no.text = "Cancel"
	MobileUi.style_button(no, MobileUi.TOUCH_SECONDARY_H)
	no.pressed.connect(_hide_overlay)
	col.add_child(no)


func _ensure_my_connection_token(me: Dictionary) -> Dictionary:
	## Load / backfill public_connection_token without touching active My Person pairing.
	var token := str(me.get("public_connection_token", "")).strip_edges()
	if not token.is_empty():
		return me
	if not state.is_online():
		return me
	var fr: Dictionary = await state.friends.get_my_person()
	if bool(fr.get("ok", false)):
		var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
		## Apply full payload (including person=null) — never patch sticky Mandy over a null backend.
		state.apply_friends_payload(data)
		if typeof(data.get("me")) == TYPE_DICTIONARY:
			me = (data.get("me") as Dictionary).duplicate(true)
			token = str(me.get("public_connection_token", "")).strip_edges()
	if token.is_empty():
		## Older accounts: generate via intended RPC — does not alter friendships.
		var rr: Dictionary = await state.friends.regenerate_connection_token()
		if bool(rr.get("ok", false)):
			var rd: Variant = rr.get("data")
			if typeof(rd) == TYPE_STRING and not str(rd).is_empty():
				me["public_connection_token"] = str(rd)
			elif typeof(rd) == TYPE_DICTIONARY:
				var tok2 := str((rd as Dictionary).get("public_connection_token", (rd as Dictionary).get("token", "")))
				if tok2.is_empty():
					## RPC may return bare token string nested.
					for k in (rd as Dictionary).keys():
						var v := str((rd as Dictionary).get(k, ""))
						if v.length() >= 16 and v.find("-") < 0:
							tok2 = v
							break
				if not tok2.is_empty():
					me["public_connection_token"] = tok2
			state.invalidate_cache("friends")
			var fr2: Dictionary = await state.friends.get_my_person()
			if bool(fr2.get("ok", false)):
				var data2: Dictionary = fr2.get("data", {}) if typeof(fr2.get("data")) == TYPE_DICTIONARY else {}
				if typeof(data2.get("me")) == TYPE_DICTIONARY:
					me = (data2.get("me") as Dictionary).duplicate(true)
	return me


func _show_my_connection_code(me: Dictionary) -> void:
	## Show My Code — no camera permission. Must not alter active My Person pairing.
	## Connection Code text must remain visible even if QR image encoding fails.
	me = await _ensure_my_connection_token(me)
	var token := str(me.get("public_connection_token", "")).strip_edges()
	var friend_code := str(me.get("friend_code", "")).strip_edges()
	if token.is_empty() and friend_code.is_empty():
		## Token/code failure must not disturb Mandy / active Person.
		_show_toast("Connection code unavailable. Your Person connection is unchanged.")
		return
	var link := ""
	if not token.is_empty():
		link = QrHelper.deep_link_for_token(token)
		if QrHelper.payload_contains_raw_uuid(link):
			_show_toast("Connection code unavailable. Your Person connection is unchanged.")
			return
	_clear_overlay()
	if _overlay == null:
		return
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.08, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeAreaHelper.apply_to_margin(host, 20, 20, 20)
	_overlay.add_child(host)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)
	var title := Label.new()
	title.text = IdentityHelper.display_name_from_profile(me, "You")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE, true)
	col.add_child(title)
	var user := IdentityHelper.username_from_profile(me)
	if not user.is_empty():
		var ul := Label.new()
		ul.text = "@%s" % user
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(ul, MobileUi.SIZE_BODY, MobileUi.COLOR_SECONDARY, false)
		col.add_child(ul)
	var help := Label.new()
	help.text = ProductStrings.SHOW_MY_CODE_HELP
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(help, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, true)
	col.add_child(help)
	## Encode once at display size. Do NOT re-verify at a different size (v28 discarded valid QR).
	## Use QrHelper.encoder_available() — never Object.has_method() alone (Android JNI quirk).
	var qr_tex: Texture2D = null
	var qr_diag := ""
	if link.is_empty():
		qr_diag = "no_public_token"
	elif not QrHelper.available():
		qr_diag = "ChestQr singleton missing"
		if OS.is_debug_build():
			print("[COLN-QR] ChestQr singleton found=false")
	else:
		var has_encode := QrHelper.encoder_available()
		if OS.is_debug_build():
			print("[COLN-QR] ChestQr singleton found=true encode_method=%s" % str(has_encode))
		if not has_encode:
			qr_diag = "encode method missing"
		else:
			var qr_b64 := QrHelper.encode_png_base64(link, 640)
			if OS.is_debug_build():
				print("[COLN-QR] encode call result bytes=%d" % (qr_b64.length() if not qr_b64.is_empty() else 0))
			if qr_b64.is_empty():
				qr_diag = "encode returned empty"
			else:
				qr_tex = QrHelper.texture_from_base64_png(qr_b64)
				if OS.is_debug_build():
					print("[COLN-QR] Texture creation success=%s" % str(qr_tex != null))
				if qr_tex == null:
					qr_diag = "texture create failed"
	if qr_tex != null:
		## High-contrast QR on white plate — no overlays on modules.
		var plate := PanelContainer.new()
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var plate_style := StyleBoxFlat.new()
		plate_style.bg_color = Color(1, 1, 1, 1)
		plate_style.set_content_margin_all(16)
		plate.add_theme_stylebox_override("panel", plate_style)
		col.add_child(plate)
		var tr := TextureRect.new()
		tr.texture = qr_tex
		tr.custom_minimum_size = Vector2(280, 280)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(tr)
	else:
		if OS.is_debug_build():
			var dbg := Label.new()
			dbg.text = "QR generation unavailable"
			if not qr_diag.is_empty():
				dbg.text = "QR generation unavailable (%s)" % qr_diag
			dbg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			MobileUi.apply_label(dbg, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, true)
			col.add_child(dbg)
		else:
			var fallback := Label.new()
			fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			fallback.text = "QR image unavailable on this device.\nShare this Connection Code:"
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			MobileUi.apply_label(fallback, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, true)
			col.add_child(fallback)
	## Human-readable Connection Code always visible when present (independent of QR encode).
	var code_heading := Label.new()
	code_heading.text = ProductStrings.CONNECTION_CODE
	code_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(code_heading, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE, true)
	col.add_child(code_heading)
	var display_code := friend_code if not friend_code.is_empty() else token
	## Never show a raw UUID as the Connection Code.
	if QrHelper.payload_contains_raw_uuid(display_code):
		display_code = friend_code if not friend_code.is_empty() and not QrHelper.payload_contains_raw_uuid(friend_code) else ""
	if display_code.is_empty():
		display_code = "Code unavailable"
	var code_l := Label.new()
	code_l.text = display_code
	code_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(code_l, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	col.add_child(code_l)
	var regen := Button.new()
	regen.text = ProductStrings.REGENERATE_CODE
	MobileUi.style_button(regen, MobileUi.TOUCH_SECONDARY_H)
	regen.pressed.connect(func() -> void:
		if state.is_demo():
			_show_toast("Demo: regenerate skipped.")
			return
		regen.disabled = true
		var rr: Dictionary = await state.friends.regenerate_connection_token()
		regen.disabled = false
		if bool(rr.get("ok", false)):
			state.invalidate_cache("friends")
			_hide_overlay()
			_show_toast("Connection code regenerated.")
			## Re-open with the new code (pairing unchanged).
			var fresh_me: Dictionary = me.duplicate(true)
			fresh_me.erase("public_connection_token")
			_show_my_connection_code(fresh_me)
		else:
			_show_toast(str(rr.get("error", "Could not regenerate code.")))
	)
	col.add_child(regen)
	var close := Button.new()
	close.text = "Close"
	MobileUi.style_button(close, MobileUi.TOUCH_PRIMARY_H)
	close.pressed.connect(_hide_overlay)
	col.add_child(close)


func _on_scan_person_code() -> void:
	## Camera permission only here — never at launch.
	## Query live Android CAMERA state every tap — never a saved boolean.
	if OS.get_name() != "Android":
		_show_toast("QR scanning requires the Android build.")
		return
	if not QrHelper.available():
		_show_toast("Camera scanner isn't available in this build.")
		if OS.is_debug_build():
			print("[COLN-QR] scan aborted: ChestQr bridge missing")
		return
	if not QrHelper.scanner_available():
		_show_toast("Camera scanner isn't available in this build.")
		if OS.is_debug_build():
			print("[COLN-QR] scan aborted: scanner capability missing")
		return
	## Refresh from OS in case user just granted Camera in App Settings.
	PermissionsHelper.log_resume_refresh()
	## Live CAMERA permission — when Granted, continue directly (no false permission error).
	if not QrHelper.has_camera_permission():
		_show_toast("Camera permission is required.")
		QrHelper.request_camera_permission()
		await get_tree().create_timer(0.8).timeout
		var waits := 0
		while not QrHelper.has_camera_permission() and waits < 20:
			await get_tree().create_timer(0.25).timeout
			waits += 1
		if not QrHelper.has_camera_permission():
			_show_toast("Camera permission is required.")
			## Offer settings after repeated denial.
			if waits >= 8:
				QrHelper.open_app_settings()
			return
	_qr_helper.ensure_signals()
	if not _qr_helper.qr_scanned.is_connected(_on_qr_scanned_payload):
		_qr_helper.qr_scanned.connect(_on_qr_scanned_payload)
	if not _qr_helper.qr_scan_cancelled.is_connected(_on_qr_scan_cancelled):
		_qr_helper.qr_scan_cancelled.connect(_on_qr_scan_cancelled)
	if not _qr_helper.qr_scan_error.is_connected(_on_qr_scan_error):
		_qr_helper.qr_scan_error.connect(_on_qr_scan_error)
	if not _qr_helper.start_scan():
		## Permission was granted — this is plugin/camera init failure, not a permission error.
		_show_toast("Camera scanner couldn't start.")
		if OS.is_debug_build():
			print("[COLN-QR] start_scan returned false with camera granted")


func _on_qr_scan_cancelled() -> void:
	pass


func _on_qr_scan_error(code: String) -> void:
	## Distinct error types — never label every failure as Camera permission.
	if code == "camera_permission":
		## Re-check live OS truth — plugin may have lied when Activity was null.
		if QrHelper.has_camera_permission():
			_show_toast("Camera scanner couldn't start.")
		else:
			_show_toast("Camera permission is required.")
	elif code == "unavailable":
		_show_toast("Camera scanner isn't available in this build.")
	elif code == "start_failed":
		_show_toast("Camera scanner couldn't start.")
	else:
		_show_toast("This isn't a valid Chest of Love Notes connection code.")


func _show_qr_scan_message(body: String, offer_scan_again: bool = false) -> void:
	_clear_overlay()
	if _overlay == null:
		return
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeAreaHelper.apply_to_margin(host, 24, 24, 24)
	_overlay.add_child(host)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	host.add_child(col)
	var lab := Label.new()
	lab.text = body
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	col.add_child(lab)
	if offer_scan_again:
		var again := Button.new()
		again.text = ProductStrings.SCAN_AGAIN
		MobileUi.style_button(again, MobileUi.TOUCH_CTA_H)
		again.pressed.connect(func() -> void:
			_hide_overlay()
			_on_scan_person_code()
		)
		col.add_child(again)
	var close := Button.new()
	close.text = "Close"
	MobileUi.style_button(close, MobileUi.TOUCH_SECONDARY_H)
	close.pressed.connect(_hide_overlay)
	col.add_child(close)


func _on_qr_scanned_payload(raw: String) -> void:
	if not QrHelper.is_coln_connect_payload(raw):
		_show_qr_scan_message(ProductStrings.INVALID_QR, true)
		return
	var token := QrHelper.extract_token(raw)
	if token.is_empty() or token.length() < 16:
		_show_qr_scan_message(ProductStrings.INVALID_QR, true)
		return
	if state.is_demo():
		_show_toast("Demo: QR connect preview only.")
		return
	## Own code — never create a self-pair. Active Person (Mandy) stays untouched.
	var my_tok := ""
	if typeof(state.cached_friends.get("me")) == TYPE_DICTIONARY:
		my_tok = str((state.cached_friends.get("me") as Dictionary).get("public_connection_token", "")).strip_edges().to_lower()
	if not my_tok.is_empty() and token == my_tok:
		_show_qr_scan_message(ProductStrings.OWN_CODE, true)
		return
	## Already connected — block new pairing; do not disconnect or replace Mandy.
	var cached_person: Dictionary = _person_from_friends_cache()
	if not cached_person.is_empty() and not str(cached_person.get("id", "")).is_empty():
		var pname := IdentityHelper.display_name_from_profile(cached_person)
		_show_qr_scan_message(
			"%s\n\n%s" % [
				ProductStrings.ALREADY_CONNECTED_FMT % pname,
				ProductStrings.DISCONNECT_FIRST,
			],
			false
		)
		return
	var resolved: Dictionary = await state.friends.resolve_connection_token(token)
	if not bool(resolved.get("ok", false)):
		var err := str(resolved.get("error", ProductStrings.INVALID_QR))
		if err.to_lower().contains("own"):
			_show_qr_scan_message(ProductStrings.OWN_CODE, true)
		else:
			_show_qr_scan_message(ProductStrings.INVALID_QR if err.is_empty() else err, true)
		return
	var data: Dictionary = resolved.get("data", {}) if typeof(resolved.get("data")) == TYPE_DICTIONARY else {}
	var profile: Dictionary = data.get("profile", {}) if typeof(data.get("profile")) == TYPE_DICTIONARY else {}
	if profile.is_empty():
		_show_qr_scan_message(ProductStrings.INVALID_QR, true)
		return
	_confirm_send_connection_from_scan(profile, token)


func _confirm_send_connection_from_scan(profile: Dictionary, token: String) -> void:
	var name := IdentityHelper.display_name_from_profile(profile)
	var user := IdentityHelper.username_from_profile(profile)
	_clear_overlay()
	if _overlay == null:
		return
	_overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeAreaHelper.apply_to_margin(host, 24, 24, 24)
	_overlay.add_child(host)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	host.add_child(col)
	var ask := Label.new()
	ask.text = ProductStrings.connect_with_confirm(name)
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(ask, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE, true)
	col.add_child(ask)
	var detail := Label.new()
	detail.text = name if user.is_empty() else "%s\n@%s" % [name, user]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(detail, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	col.add_child(detail)
	var send_btn := Button.new()
	send_btn.text = "Send Connection Request"
	MobileUi.style_button(send_btn, MobileUi.TOUCH_CTA_H)
	send_btn.pressed.connect(func() -> void:
		_hide_overlay()
		var result: Dictionary = await state.friends.send_connection_request({"connection_token": token})
		if bool(result.get("ok", false)):
			_show_toast("Connection request sent.")
			state.invalidate_cache("friends")
			_show_friends()
		else:
			_show_toast(str(result.get("error", "Could not send connection request.")))
	)
	col.add_child(send_btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	MobileUi.style_button(cancel, MobileUi.TOUCH_SECONDARY_H)
	cancel.pressed.connect(_hide_overlay)
	col.add_child(cancel)



func _show_sent() -> void:
	if not _guard_private_chest():
		return
	var nav_t0 := Time.get_ticks_msec()
	# Leaving/rebuilding Sent clears any previously revealed passwords from memory.
	_clear_reveal_timers()
	state.clear_revealed_passwords()
	_current_screen = "sent"
	var visible_items: Array = []
	var hidden_items: Array = []
	if state.is_demo():
		visible_items = state.demo.get_sent_scrolls(false)
		hidden_items = state.demo.get_sent_scrolls(true)
	elif state.is_online():
		## Cache-first current list; hidden loaded async / from cache key.
		if typeof(state.cached_sent.get("sent_scrolls")) == TYPE_ARRAY:
			visible_items = state.cached_sent.get("sent_scrolls", [])
		if typeof(state.cached_sent.get("hidden_sent_scrolls")) == TYPE_ARRAY:
			hidden_items = state.cached_sent.get("hidden_sent_scrolls", [])
	var showing: Array = hidden_items if _sent_show_hidden else visible_items

	_begin_nav_transition()
	var root := _make_screen_root(_nav_content_inset())
	root.add_child(MobileUi.make_page_title("Sent", _title_font()))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var active_btn := _make_button("Visible (%d)" % visible_items.size(), func() -> void:
		_sent_show_hidden = false
		_show_sent()
	, Vector2(0, MobileUi.TOUCH_SECONDARY_H))
	var hidden_btn := _make_button("Hidden (%d)" % hidden_items.size(), func() -> void:
		_sent_show_hidden = true
		_show_sent()
	, Vector2(0, MobileUi.TOUCH_SECONDARY_H))
	if _sent_show_hidden:
		active_btn.modulate.a = 0.65
	else:
		hidden_btn.modulate.a = 0.65
	tabs.add_child(active_btn)
	tabs.add_child(hidden_btn)

	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)

	if showing.is_empty():
		var empty_wrap := VBoxContainer.new()
		empty_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_wrap.add_theme_constant_override("separation", 12)
		list.add_child(empty_wrap)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(72, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(0.98, 0.86, 0.45, 0.9)
		if ResourceLoader.exists("res://assets/art/scroll/scroll_rolled.png"):
			icon.texture = load("res://assets/art/scroll/scroll_rolled.png")
		empty_wrap.add_child(icon)
		var empty := Label.new()
		empty.text = "No hidden scrolls" if _sent_show_hidden else "No sent scrolls yet"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(empty, MobileUi.SIZE_MAJOR_HEADING, MobileUi.COLOR_BODY)
		empty_wrap.add_child(empty)
		var hint := Label.new()
		hint.text = "Hidden scrolls stay recoverable here." if _sent_show_hidden else "Scrolls you send will appear here."
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(hint, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_HELPER)
		empty_wrap.add_child(hint)
	else:
		for s in showing:
			list.add_child(_build_sent_item_card(s, _sent_show_hidden))
	_add_bottom_nav("sent")
	_finish_nav_transition()
	_log_nav_paint("sent", nav_t0)
	if state.is_online() and not state.cache_is_fresh("sent"):
		var sent_result: Dictionary = await state.scrolls.get_sent_scrolls("current")
		var hidden_result: Dictionary = await state.scrolls.get_sent_scrolls("hidden")
		if _current_screen != "sent":
			return
		if bool(sent_result.get("ok", false)):
			var data: Dictionary = sent_result.get("data", {}) if typeof(sent_result.get("data")) == TYPE_DICTIONARY else {}
			state.cached_sent = data
			if bool(hidden_result.get("ok", false)):
				var hdata: Dictionary = hidden_result.get("data", {}) if typeof(hidden_result.get("data")) == TYPE_DICTIONARY else {}
				state.cached_sent["hidden_sent_scrolls"] = hdata.get("sent_scrolls", [])
			state.mark_cache_fresh("sent")
			_show_sent()
		elif visible_items.is_empty() and hidden_items.is_empty():
			var err := str(sent_result.get("error", "Could not load sent scrolls."))
			if not err.is_empty():
				_show_toast(err)


func _build_sent_item_card(s: Dictionary, is_hidden_view: bool) -> PanelContainer:
	var panel := _make_card()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	panel.add_child(col)
	var recipient: Dictionary = s.get("recipient", {}) if typeof(s.get("recipient")) == TYPE_DICTIONARY else {}
	var recip_name := str(s.get("recipient_display_name", recipient.get("display_name", ProductStrings.PERSON)))
	var unlock_at := str(s.get("unlock_at", ""))
	var unlock_unix := int(s.get("unlock_at_unix", 0))
	if unlock_unix == 0 and not unlock_at.is_empty():
		unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))
	var title_lab := Label.new()
	title_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lab.text = "%s → %s" % [
		str(s.get("title", "Love Note")),
		recip_name,
	]
	MobileUi.apply_label(title_lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	col.add_child(title_lab)
	var status_lab := Label.new()
	status_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lab.text = _format_sent_status(s, unlock_unix, unlock_at)
	MobileUi.apply_label(status_lab, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_SECONDARY, true)
	col.add_child(status_lab)
	var sid := str(s.get("id", ""))
	var has_pw := bool(s.get("has_password", false))
	if has_pw and not is_hidden_view:
		col.add_child(_build_sent_password_reveal_row(sid, s))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	if is_hidden_view:
		actions.add_child(_make_button("Unhide", func() -> void:
			_unhide_sent(sid)
		, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))
	else:
		actions.add_child(_make_button("Hide", func() -> void:
			_hide_sent_with_undo(sid)
		, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))
	actions.add_child(_make_button("Delete", func() -> void:
		_confirm_delete_sent(sid, recip_name)
	, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))
	return panel


func _hide_sent_with_undo(scroll_id: String) -> void:
	## Server-side Hide — recoverable via Unhide. Not permanent Delete.
	if scroll_id.is_empty():
		return
	if state.is_demo():
		var dr := state.demo.hide_sent_scroll(scroll_id)
		if bool(dr.get("ok", false)):
			_pending_hide_sent_id = scroll_id
			_show_snackbar("Scroll hidden", "Undo", func() -> void:
				_unhide_sent(scroll_id)
			)
			if _current_screen == "sent":
				_show_sent()
		else:
			_show_toast(str(dr.get("error", "Could not hide.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.hide_sent_scroll(scroll_id)
		if bool(result.get("ok", false)):
			state.invalidate_cache("sent")
			_pending_hide_sent_id = scroll_id
			_show_snackbar("Scroll hidden", "Undo", func() -> void:
				_unhide_sent(scroll_id)
			)
			if _current_screen == "sent":
				_show_sent()
		else:
			_show_toast(str(result.get("error", "Could not hide.")))
		return
	_show_toast("Backend is not configured.")


func _unhide_sent(scroll_id: String) -> void:
	if scroll_id.is_empty():
		return
	if state.is_demo():
		var dr := state.demo.unhide_sent_scroll(scroll_id)
		if bool(dr.get("ok", false)):
			_pending_hide_sent_id = ""
			_show_toast("Restored to Sent")
			_show_sent()
		else:
			_show_toast(str(dr.get("error", "Could not unhide.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.unhide_sent_scroll(scroll_id)
		if bool(result.get("ok", false)):
			state.invalidate_cache("sent")
			_pending_hide_sent_id = ""
			_show_toast("Restored to Sent")
			_show_sent()
		else:
			_show_toast(str(result.get("error", "Could not unhide.")))
		return
	_show_toast("Backend is not configured.")


func _confirm_delete_sent(scroll_id: String, recipient_name: String) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := 354.0
	var modal_h := 320.0
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Delete permanently?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var body := Label.new()
	body.text = "Delete this scroll permanently from your Sent history? %s will still keep their copy." % (
		recipient_name if not recipient_name.is_empty() else "Your Person"
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BODY))
	body.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	box.add_child(body)
	box.add_child(_make_button("Delete Permanently", func() -> void:
		_hide_overlay()
		_delete_sent(scroll_id)
	))
	box.add_child(_make_button("Cancel", _hide_overlay, Vector2(180, MobileUi.font_touch(MobileUi.TOUCH_SECONDARY_H))))


func _delete_sent(scroll_id: String) -> void:
	if scroll_id.is_empty():
		return
	if state.is_demo():
		var dr := state.demo.delete_sent_scroll(scroll_id)
		if bool(dr.get("ok", false)):
			_show_toast("Scroll deleted from your Sent history")
			_show_sent()
		else:
			_show_toast(str(dr.get("error", "Could not delete.")))
		return
	if state.is_online():
		var result: Dictionary = await state.scrolls.delete_sent_scroll(scroll_id)
		if bool(result.get("ok", false)):
			state.invalidate_cache("sent")
			_show_toast("Scroll deleted from your Sent history")
			_show_sent()
		else:
			_show_toast(str(result.get("error", "Could not delete.")))
		return
	_show_toast("Backend is not configured.")


func _build_sent_password_reveal_row(scroll_id: String, item: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.text = "Magic Password"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(caption)
	var value := Label.new()
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	box.add_child(value)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var reveal_btn := _make_button("Reveal Password", func() -> void: pass, Vector2(220, 56))
	var copy_btn := _make_button("Copy", func() -> void: pass, Vector2(140, 56))
	var hide_btn := _make_button("Hide", func() -> void: pass, Vector2(140, 56))
	actions.add_child(reveal_btn)
	actions.add_child(copy_btn)
	actions.add_child(hide_btn)

	var refresh_row := func() -> void:
		var revealed := str(state.revealed_magic_passwords.get(scroll_id, ""))
		if revealed.is_empty():
			value.text = "••••••••"
			reveal_btn.visible = true
			copy_btn.visible = false
			hide_btn.visible = false
		else:
			value.text = revealed
			reveal_btn.visible = false
			copy_btn.visible = true
			hide_btn.visible = true
	refresh_row.call()

	reveal_btn.pressed.connect(func() -> void:
		_confirm_reveal_password(scroll_id, item, refresh_row)
	)
	copy_btn.pressed.connect(func() -> void:
		var revealed := str(state.revealed_magic_passwords.get(scroll_id, ""))
		if revealed.is_empty():
			return
		DisplayServer.clipboard_set(revealed)
		_show_toast("Magic Password copied")
	)
	hide_btn.pressed.connect(func() -> void:
		_hide_revealed_password(scroll_id)
		refresh_row.call()
	)
	return box


func _confirm_reveal_password(scroll_id: String, item: Dictionary, refresh_row: Callable) -> void:
	_show_modal_panel(
		"Reveal Password?",
		[
			"Reveal the Magic Password for this scroll?",
			"Title: %s" % str(item.get("title", "A Love Note")),
		],
		"Reveal",
		func() -> void:
			_hide_overlay()
			SensitiveReveal.request_sensitive_reveal(func() -> void:
				await _reveal_sent_password(scroll_id, refresh_row)
			)
	)


func _reveal_sent_password(scroll_id: String, refresh_row: Callable) -> void:
	var password := ""
	if state.is_demo():
		for s in state.demo.scrolls:
			if str(s.get("id", "")) == scroll_id:
				password = str(s.get("_demo_password", ""))
				break
		if password.is_empty():
			_show_toast("No Magic Password is available for this scroll.")
			return
	elif state.is_online():
		var result: Dictionary = await state.scrolls.reveal_sent_scroll_password(scroll_id)
		if not bool(result.get("ok", false)):
			_show_toast(str(result.get("error", "Could not reveal Magic Password.")))
			return
		var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
		password = str(data.get("magic_password", ""))
		if password.is_empty():
			_show_toast("Could not reveal Magic Password.")
			return
	else:
		_show_toast("Backend is not configured.")
		return
	state.revealed_magic_passwords[scroll_id] = password
	password = ""
	refresh_row.call()
	_arm_reveal_timeout(scroll_id, refresh_row)


func _arm_reveal_timeout(scroll_id: String, refresh_row: Callable) -> void:
	if _reveal_timers.has(scroll_id):
		var old: SceneTreeTimer = _reveal_timers[scroll_id]
		# Previous timer will no-op if password already cleared.
	var timer := get_tree().create_timer(30.0)
	_reveal_timers[scroll_id] = timer
	await timer.timeout
	if str(state.revealed_magic_passwords.get(scroll_id, "")) != "":
		_hide_revealed_password(scroll_id)
		if refresh_row.is_valid():
			refresh_row.call()


func _hide_revealed_password(scroll_id: String) -> void:
	if state.revealed_magic_passwords.has(scroll_id):
		state.revealed_magic_passwords[scroll_id] = ""
		state.revealed_magic_passwords.erase(scroll_id)
	_reveal_timers.erase(scroll_id)


func _clear_reveal_timers() -> void:
	_reveal_timers.clear()


func _settings_row(label_text: String, value_control: Control) -> PanelContainer:
	## Label wraps naturally; value keeps a usable touch target on the right.
	var card := _make_card()
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = MobileUi.font_touch(MobileUi.ROW_H)
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_stretch_ratio = 1.4
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	row.add_child(lab)
	value_control.size_flags_horizontal = Control.SIZE_SHRINK_END
	value_control.size_flags_stretch_ratio = 1.0
	if value_control.custom_minimum_size.x < 72:
		value_control.custom_minimum_size.x = 72
	if value_control.custom_minimum_size.y < MobileUi.TOUCH_MIN:
		value_control.custom_minimum_size.y = MobileUi.font_touch(MobileUi.TOUCH_MIN)
	row.add_child(value_control)
	return card


func _format_friendly_datetime(unix_ts: int) -> String:
	if unix_ts <= 0:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(unix_ts)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month: String = months[clampi(int(dt.month) - 1, 0, 11)]
	var hour := int(dt.hour)
	var minute := int(dt.minute)
	var ampm := "AM" if hour < 12 else "PM"
	var hour12 := hour % 12
	if hour12 == 0:
		hour12 = 12
	return "%s %d, %d at %d:%02d %s" % [month, int(dt.day), int(dt.year), hour12, minute, ampm]


func _format_sent_status(item: Dictionary, unlock_unix: int, unlock_at: String) -> String:
	var opened_count := int(item.get("opened_count", 0))
	var opened_at := str(item.get("opened_at", item.get("first_opened_at", "")))
	var opened_unix := int(item.get("opened_at_unix", 0))
	if opened_unix <= 0 and not opened_at.is_empty():
		opened_unix = int(Time.get_unix_time_from_datetime_string(opened_at))
	if opened_count > 0 or opened_unix > 0:
		var when := _format_friendly_datetime(opened_unix)
		if when.is_empty():
			return "Opened"
		return "Opened\n%s" % when
	var now_u := _now_unix()
	if unlock_unix > now_u:
		var until := _format_friendly_datetime(unlock_unix)
		if until.is_empty() and not unlock_at.is_empty():
			return "Locked until %s" % unlock_at
		return "Locked until %s" % until
	if bool(item.get("delivered", true)):
		return "Delivered"
	return "Sent"


func _settings_value_label(text: String) -> Label:
	var v := Label.new()
	v.text = text
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Prefer single-line readable presentation; ellipsis if truly too long.
	MobileUi.apply_label(v, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_SECONDARY, false)
	return v


func _settings_long_value_card(label_text: String, value_text: String, copyable: bool = false) -> PanelContainer:
	## Vertical layout for email / friend code — full horizontal width, no 1-char columns.
	var card := _make_card()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var lab := Label.new()
	lab.text = label_text
	MobileUi.apply_label(lab, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER, false)
	col.add_child(lab)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var value := Label.new()
	value.text = value_text
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(value, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	row.add_child(value)
	if copyable and value_text != "" and value_text != "—":
		var copy_btn := _make_button("Copy", func() -> void:
			DisplayServer.clipboard_set(value_text)
			_show_toast("Copied")
		, Vector2(88, 44))
		copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(copy_btn)
	return card


func _show_profile() -> void:
	var nav_t0 := Time.get_ticks_msec()
	_current_screen = "profile"
	var me: Dictionary = {}
	if state.is_demo():
		me = state.demo.get_profile()
	elif state.is_online() and state.tokens.has_session():
		## Always start from known/cached profile so soft fetch cannot blank the UI.
		if state.profiles.profile.is_empty():
			state.profiles.hydrate_from_cache()
		me = state.profiles.profile.duplicate(true)

	_begin_nav_transition()
	var root := _make_screen_root(_nav_content_inset())
	## Title scrolls with content so nothing clips under a fixed PROFILE header.
	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.clip_contents = true
	root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(col)
	MobileUi.enable_touch_scroll_on_tree(col)
	col.add_child(MobileUi.make_page_title("Profile", _title_font()))
	var kb_pad_p := Control.new()
	kb_pad_p.custom_minimum_size = Vector2(0, 0)
	root.add_child(kb_pad_p)
	MobileUi.wire_keyboard_avoidance(root, scroll, kb_pad_p)

	var section := Label.new()
	section.text = "ACCOUNT"
	MobileUi.apply_label(section, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	col.add_child(section)
	## Full username on its own wrapping line — no accidental ellipsis.
	var display_card := _settings_long_value_card("Display Name", str(me.get("display_name", "—")), false)
	var user_card := _settings_long_value_card("Username", "@" + str(me.get("username", "—")), false)
	var email_card := _settings_long_value_card("Email", str(state.tokens.user_email if state.tokens.user_email != "" else "—"), false)
	var code_card := _settings_long_value_card(ProductStrings.CONNECTION_CODE, str(me.get("friend_code", me.get("public_connection_token", "—"))), true)
	col.add_child(display_card)
	col.add_child(user_card)
	col.add_child(email_card)
	col.add_child(code_card)
	var _dev_tap := {"n": 0}
	if OS.is_debug_build():
		var tip := Label.new()
		tip.text = ""
		tip.mouse_filter = Control.MOUSE_FILTER_STOP
		tip.custom_minimum_size = Vector2(0, 8)
		tip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_dev_tap.n = int(_dev_tap.n) + 1
				if int(_dev_tap.n) >= 7:
					_dev_tap.n = 0
					_show_diagnostics()
		)
		col.add_child(tip)
	var access := "Active" if state.membership.is_member or state.is_demo() else "—"
	col.add_child(_settings_row("Private Access", _settings_value_label(access)))

	var prefs := Label.new()
	prefs.text = "PREFERENCES"
	MobileUi.apply_label(prefs, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	col.add_child(prefs)

	var text_btn := _make_button(MobileUi.text_size_label() + "  >", func() -> void:
		MobileUi.cycle_text_size()
		_show_toast("Text Size: %s" % MobileUi.text_size_label())
		_show_profile()
	, Vector2(140, 48))
	text_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_settings_row("Text Size", text_btn))

	var motion_toggle := CheckButton.new()
	motion_toggle.button_pressed = MobileUi.reduced_motion()
	motion_toggle.custom_minimum_size = Vector2(72, 48)
	motion_toggle.focus_mode = Control.FOCUS_NONE
	motion_toggle.toggled.connect(func(on: bool) -> void:
		MobileUi.set_reduced_motion(on)
		state.reduced_motion = on
		if _scroll_viewer:
			_scroll_viewer.set_reduced_motion(on)
		_show_toast("Reduced Motion is %s" % ("ON" if on else "OFF"))
	)
	col.add_child(_settings_row("Reduced Motion", motion_toggle))

	if state.is_online():
		var keep_toggle := CheckButton.new()
		keep_toggle.button_pressed = state.tokens.keep_me_signed_in
		keep_toggle.custom_minimum_size = Vector2(72, 48)
		keep_toggle.focus_mode = Control.FOCUS_NONE
		keep_toggle.toggled.connect(func(on: bool) -> void:
			state.tokens.set_keep_me_signed_in(on)
			_show_toast("Keep Me Signed In is %s" % ("ON" if on else "OFF"))
		)
		col.add_child(_settings_row("Keep Me Signed In", keep_toggle))

	var perm_sec := Label.new()
	perm_sec.text = ProductStrings.PERMISSIONS_SECTION
	MobileUi.apply_label(perm_sec, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	col.add_child(perm_sec)
	## Full-width status rows — never clip "Not Allowed".
	col.add_child(_permission_status_row("Notifications", PermissionsHelper.notification_allowed()))
	col.add_child(_permission_status_row("Location", PermissionsHelper.location_allowed()))
	col.add_child(_permission_status_row("Camera", PermissionsHelper.camera_allowed()))
	col.add_child(_make_button("Manage Permissions", func() -> void:
		_show_permissions_manage_sheet()
	, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))

	## DEBUG-only Android bridge diagnostics for physical Galaxy testing (never in production).
	if OS.is_debug_build():
		col.add_child(_build_android_diagnostics_panel())

	## Online Diagnostics is not shown in normal Profile UI (7 silent taps above).
	col.add_child(_make_button("Sign Out", func() -> void:
		_clear_reveal_timers()
		_clear_compose_draft()
		await _sign_out_cleanup()
		if state.is_demo():
			state.demo.enable()
		_show_welcome()
	, Vector2(0, MobileUi.TOUCH_CTA_H)))

	if state.membership.is_member or state.is_demo():
		_add_bottom_nav("profile")
	else:
		col.add_child(_make_button("Back", _show_welcome))
	_finish_nav_transition()
	_log_nav_paint("profile", nav_t0)
	if state.is_online() and state.tokens.has_session():
		var pref: Dictionary = await state.profiles.fetch_own_profile()
		if _current_screen != "profile":
			return
		if bool(pref.get("ok", false)) and bool(pref.get("exists", false)):
			## Soft refresh — rebuild only when display fields changed.
			var fresh: Dictionary = state.profiles.profile
			if str(fresh.get("display_name", "")) != str(me.get("display_name", "")) \
				or str(fresh.get("username", "")) != str(me.get("username", "")) \
				or str(fresh.get("friend_code", fresh.get("public_connection_token", ""))) != str(me.get("friend_code", me.get("public_connection_token", ""))):
				_show_profile()


func _show_diagnostics() -> void:
	if not OS.is_debug_build():
		_show_toast("Diagnostics are debug-only.")
		return
	_current_screen = "diagnostics"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 36
	root.offset_right = -36
	root.offset_top = 28
	root.offset_bottom = -28
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var title := Label.new()
	title.text = "Online Diagnostics"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	root.add_child(title)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 24)
	status.add_theme_color_override("font_color", Color(0.92, 0.88, 0.96))
	root.add_child(status)
	var refresh_status := func() -> void:
		var snap: Dictionary = state.diagnostics_snapshot()
		status.text = (
			"Secure plugin found: %s\n"
			+ "Secure storage available: %s\n"
			+ "Secure session exists: %s\n"
			+ "Secure session decrypt succeeded: %s\n"
			+ "Refresh attempted: %s\n"
			+ "Refresh succeeded: %s\n"
			+ "Membership revalidated: %s\n"
			+ "Profile loaded: %s\n"
			+ "Keep Me Signed In: %s\n"
			+ "Text Size: %s\n"
			+ "Reduced Motion: %s\n"
			+ "Backend host: %s\n"
			+ "Last Auth HTTP Status: %s\n"
			+ "Last Safe Auth Error: %s\n"
			+ "Last persist error: %s"
		) % [
			"YES" if bool(snap.get("secure_plugin_found", false)) else "NO",
			"YES" if bool(snap.get("secure_storage_available", false)) else "NO",
			"YES" if bool(snap.get("saved_session_exists", false)) else "NO",
			"YES" if bool(snap.get("session_decrypt_ok", false)) else "NO",
			"YES" if bool(snap.get("refresh_attempted", false)) else "NO",
			"YES" if bool(snap.get("refresh_succeeded", false)) else "NO",
			"YES" if bool(snap.get("membership_revalidated", false)) else "NO",
			"YES" if bool(snap.get("profile_loaded", false)) else "NO",
			"ON" if bool(snap.get("keep_me_signed_in", false)) else "OFF",
			str(snap.get("text_size", "Standard")),
			"ON" if bool(snap.get("reduced_motion", false)) else "OFF",
			str(snap.get("backend_host", "")),
			str(snap.get("last_http_status", 0)),
			str(snap.get("last_safe_error", "")) if str(snap.get("last_safe_error", "")) != "" else "(none)",
			str(snap.get("last_persist_error", "")) if str(snap.get("last_persist_error", "")) != "" else "(none)",
		]
	refresh_status.call()
	var rel_title := Label.new()
	rel_title.text = "Relationship"
	rel_title.add_theme_font_size_override("font_size", 28)
	rel_title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	root.add_child(rel_title)
	var rel_status := Label.new()
	rel_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rel_status.add_theme_font_size_override("font_size", 22)
	rel_status.add_theme_color_override("font_color", Color(0.92, 0.88, 0.96))
	root.add_child(rel_status)
	var refresh_rel := func() -> void:
		rel_status.text = _relationship_diagnostics_text()
	refresh_rel.call()
	root.add_child(_make_button("Refresh My Person State", func() -> void:
		if not state.is_online():
			_show_toast("Backend is not configured.")
			return
		var fr: Dictionary = await state.friends.get_my_person()
		if bool(fr.get("ok", false)):
			var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
			state.apply_friends_payload(data)
			state.mark_cache_fresh("friends")
			_show_toast("My Person state refreshed")
		else:
			_show_toast(str(fr.get("error", "Could not refresh My Person.")))
		refresh_rel.call()
		refresh_status.call()
	))
	root.add_child(_make_button("Test Backend", func() -> void:
		if not state.config.is_configured():
			_show_toast("Backend is not configured.")
			refresh_status.call()
			return
		var url := "%s/auth/v1/health" % state.config.supabase_url.rstrip("/")
		var result: Dictionary = await state.api.request(url, "GET", {}, false)
		_show_toast("Backend reachable" if bool(result.get("ok", false)) else str(result.get("error", "Backend test failed.")))
		refresh_status.call()
	))
	root.add_child(_make_button("Refresh Session", func() -> void:
		var result: Dictionary = await state.auth.refresh_session()
		_show_toast("Session refreshed" if bool(result.get("ok", false)) else str(result.get("error", "Refresh failed.")))
		refresh_status.call()
	))
	root.add_child(_make_button("Claim Private Membership", func() -> void:
		var result: Dictionary = await state.membership.claim_membership()
		if bool(result.get("ok", false)):
			_show_toast("Membership approved")
		else:
			_show_toast(str(result.get("error", "Claim failed.")))
			if bool(result.get("forbidden", false)):
				await state.sign_out_full()
		refresh_status.call()
	))
	root.add_child(_make_button("Refresh Profile", func() -> void:
		var result: Dictionary = await state.profiles.fetch_own_profile()
		_show_toast("Profile refreshed" if bool(result.get("ok", false)) else str(result.get("error", "Profile refresh failed.")))
		refresh_status.call()
	))
	root.add_child(_make_button("Refresh Chest", func() -> void:
		var result: Dictionary = await state.scrolls.get_chest()
		if bool(result.get("ok", false)):
			state.cached_chest = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
			_show_toast("Chest refreshed")
		else:
			_show_toast(str(result.get("error", "Chest refresh failed.")))
		refresh_status.call()
	))
	if OS.is_debug_build():
		root.add_child(_make_button("Preview Chest Scroll Open", func() -> void:
			## Debug-only path to verify new-scroll cinematic without fake anniversary content.
			_dev_force_chest_scroll = true
			_show_toast("Opening chest with scroll preview")
			await _show_main_chest()
		))
	root.add_child(_make_button("Sign Out", func() -> void:
		await _sign_out_cleanup()
		_show_welcome()
	))
	root.add_child(_make_button("Back", _show_profile if state.tokens.has_session() else _show_welcome))


func _show_modal_panel(title_text: String, lines: Array, button_text: String, cb: Callable) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := 354.0
	var modal_h := 360.0
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	for line in lines:
		var lab := Label.new()
		lab.text = str(line)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BODY))
		lab.add_theme_color_override("font_color", Color(0.92, 0.88, 0.95))
		box.add_child(lab)
	box.add_child(_make_button(button_text, cb))


func _clear_overlay() -> void:
	_hide_overlay()


func _hide_overlay() -> void:
	if _overlay == null:
		return
	_perm_manage_live = false
	_overlay.visible = false
	for c in _overlay.get_children():
		c.queue_free()


func _android_diagnostics_my_person_label() -> String:
	var person := _person_from_friends_cache()
	if person.is_empty() or str(person.get("id", "")).is_empty():
		return "None"
	return IdentityHelper.display_name_from_profile(person, ProductStrings.PERSON)


func _relationship_diagnostics_text() -> String:
	## DEBUG only — safe labels, no UUIDs.
	var rd: Dictionary = state.relationship_debug if typeof(state.relationship_debug) == TYPE_DICTIONARY else {}
	var active_name := _android_diagnostics_my_person_label()
	var status := str(rd.get("relationship_status", "none"))
	if status.is_empty():
		status = "None"
	else:
		status = status.capitalize()
	var recon := str(rd.get("reconciliation_last_result", "no_change"))
	var recon_label := "No change"
	if recon == "created_pairing":
		recon_label = "Created pairing"
	elif recon == "error":
		recon_label = "Error"
	var mech := str(rd.get("disconnect_mechanism", "Edge Function"))
	if mech.is_empty():
		mech = "Edge Function"
	var last_req := str(rd.get("last_disconnect_request", "Not attempted"))
	if last_req.is_empty():
		last_req = "Not attempted"
	var fail_cat := str(rd.get("last_disconnect_failure_category", "None"))
	if fail_cat.is_empty():
		fail_cat = "None"
	var canonical := bool(rd.get("canonical_pair_found", false)) \
		or bool(rd.get("active_pair_backend", false)) \
		or active_name != "None"
	return (
		"Active Person: %s\n"
		+ "Active pairing backend: %s\n"
		+ "Active pair found by canonical query: %s\n"
		+ "Relationship status: %s\n"
		+ "Disconnect mechanism: %s\n"
		+ "Last disconnect request: %s\n"
		+ "Last disconnect failure category: %s\n"
		+ "Last disconnect affected relationship: %s\n"
		+ "Post-disconnect active pair: %s\n"
		+ "Legacy migration eligible: %s\n"
		+ "Historical accepted request: %s\n"
		+ "Reconciliation last result: %s"
	) % [
		active_name,
		"Yes" if bool(rd.get("active_pair_backend", false)) else "No",
		"Yes" if canonical else "No",
		status,
		mech,
		last_req,
		fail_cat,
		"Yes" if bool(rd.get("last_disconnect_affected_relationship", false)) else "No",
		"Yes" if bool(rd.get("post_disconnect_active_pair", false)) else "No",
		"Yes" if bool(rd.get("legacy_migration_eligible", false)) else "No",
		"Present" if bool(rd.get("historical_accepted_request", false)) else "None",
		recon_label,
	]


func _android_diagnostics_public_token_available() -> bool:
	var me: Dictionary = {}
	if typeof(state.cached_friends.get("me")) == TYPE_DICTIONARY:
		me = state.cached_friends.get("me")
	if me.is_empty() and not state.profiles.profile.is_empty():
		me = state.profiles.profile
	var tok := str(me.get("public_connection_token", "")).strip_edges()
	var code := str(me.get("friend_code", "")).strip_edges()
	if not tok.is_empty() and not QrHelper.payload_contains_raw_uuid(tok):
		return true
	return not code.is_empty() and not QrHelper.payload_contains_raw_uuid(code)


func _build_android_diagnostics_panel() -> VBoxContainer:
	## DEBUG-build only. Live Android bridge/permission values for Galaxy testing.
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	var sec := Label.new()
	sec.text = "Android Diagnostics"
	MobileUi.apply_label(sec, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	wrap.add_child(sec)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(status, MobileUi.SIZE_HELPER, MobileUi.COLOR_BODY, true)
	wrap.add_child(status)
	var refresh := func() -> void:
		PermissionsHelper.log_resume_refresh()
		var backend_ok := state != null and state.config != null and state.config.is_configured()
		var client_ok := backend_ok and state.api != null
		var session_ok := state != null and state.tokens != null and state.tokens.has_session()
		var token_svc := "Error"
		if not backend_ok:
			token_svc = "Error"
		elif state.friends != null:
			token_svc = "Available"
		var snap: Dictionary = PermissionsHelper.android_diagnostics_snapshot(
			_android_diagnostics_my_person_label(),
			_android_diagnostics_public_token_available(),
			backend_ok,
			client_ok,
			session_ok,
			token_svc
		)
		status.text = (
			"Backend configured: %s\n"
			+ "Supabase client: %s\n"
			+ "Authenticated session: %s\n"
			+ "Connection-token service: %s\n"
			+ "Public connection code: %s\n"
			+ "Location permission: %s\n"
			+ "Camera permission: %s\n"
			+ "Notification permission: %s\n"
			+ "Location Services: %s\n"
			+ "Location bridge: %s\n"
			+ "Location request state: %s\n"
			+ "Last native request: %s\n"
			+ "Last callback: %s\n"
			+ "Last failure stage: %s\n"
			+ "QR bridge: %s\n"
			+ "QR encoder: %s\n"
			+ "QR scanner: %s\n"
			+ "Active My Person: %s"
		) % [
			str(snap.get("backend_configured", "No")),
			str(snap.get("supabase_client", "Not Initialized")),
			str(snap.get("authenticated_session", "Missing")),
			str(snap.get("connection_token_service", "Error")),
			str(snap.get("public_connection_code", "Missing")),
			str(snap.get("location_permission", "Denied")),
			str(snap.get("camera_permission", "Denied")),
			str(snap.get("notification_permission", "Denied")),
			str(snap.get("location_services", "Off")),
			str(snap.get("location_bridge", "Missing")),
			str(snap.get("location_request_state", "Idle")),
			str(snap.get("last_native_request", "Not Started")),
			str(snap.get("last_callback", "Not Received")),
			str(snap.get("last_failure_stage", "None")),
			str(snap.get("qr_bridge", "Missing")),
			str(snap.get("qr_encoder", "Missing")),
			str(snap.get("qr_scanner", "Missing")),
			str(snap.get("active_my_person", "None")),
		]
	refresh.call()
	var refresh_btn := _make_button("Refresh Diagnostics", func() -> void:
		refresh.call()
		_show_toast("Diagnostics refreshed.")
	, Vector2(0, MobileUi.TOUCH_SECONDARY_H))
	wrap.add_child(refresh_btn)
	return wrap


func _permission_status_row(label_text: String, allowed: bool) -> PanelContainer:
	## Compact readable row: "Notifications          Not Allowed" — no clipping.
	var card := _make_card()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = MobileUi.font_touch(48)
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	row.add_child(lab)
	var status := Label.new()
	status.text = PermissionsHelper.status_label(allowed)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.size_flags_horizontal = Control.SIZE_SHRINK_END
	status.custom_minimum_size.x = 120
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.clip_text = false
	status.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	MobileUi.apply_label(status, MobileUi.SIZE_BODY, MobileUi.COLOR_TITLE if allowed else MobileUi.COLOR_SECONDARY, false)
	row.add_child(status)
	return card


func _finish_permissions_setup() -> void:
	## Only records that the explanation was shown — never fakes permission state.
	PermissionsHelper.mark_setup_completed()
	await _show_main_chest()
	_try_register_push_token()
	await _consume_notification_deeplink()


func _refresh_permissions_setup_ui() -> void:
	if _current_screen != "permissions_setup":
		return
	PermissionsHelper.log_resume_refresh()
	for kind in ["notifications", "location", "camera"]:
		var allowed := false
		match kind:
			"notifications":
				allowed = PermissionsHelper.notification_allowed()
			"location":
				allowed = PermissionsHelper.location_allowed()
			"camera":
				allowed = PermissionsHelper.camera_allowed()
		var status: Label = _perm_setup_status.get(kind) as Label
		if status != null and is_instance_valid(status):
			status.text = "Status: %s" % PermissionsHelper.status_label(allowed)
		var btn: Button = _perm_setup_actions.get(kind) as Button
		if btn != null and is_instance_valid(btn):
			if allowed:
				btn.text = "Allowed"
				btn.disabled = true
			elif PermissionsHelper.needs_settings(kind):
				btn.text = "Open App Settings"
				btn.disabled = false
			else:
				btn.text = "Allow"
				btn.disabled = false


func _on_permission_allow_tapped(kind: String) -> void:
	## User-initiated only — one permission at a time.
	var result: Dictionary = {}
	match kind:
		"notifications":
			if PermissionsHelper.needs_settings(kind):
				PermissionsHelper.open_app_settings()
				return
			result = PermissionsHelper.request_notifications()
		"location":
			if PermissionsHelper.needs_settings(kind):
				PermissionsHelper.open_app_settings()
				return
			result = PermissionsHelper.request_location()
		"camera":
			if PermissionsHelper.needs_settings(kind):
				PermissionsHelper.open_app_settings()
				return
			result = PermissionsHelper.request_camera()
		_:
			return
	if bool(result.get("needs_settings", false)):
		_show_toast("Permission must be enabled in Android Settings.")
		PermissionsHelper.open_app_settings()
		return
	## Wait for Android dialog result, then query real state.
	for _i in range(24):
		await get_tree().create_timer(0.25).timeout
		_refresh_permissions_setup_ui()
		if _perm_manage_live:
			_rebuild_permissions_manage_content()
		var granted := false
		match kind:
			"notifications":
				granted = PermissionsHelper.notification_allowed()
			"location":
				granted = PermissionsHelper.location_allowed()
			"camera":
				granted = PermissionsHelper.camera_allowed()
		if granted:
			if OS.is_debug_build():
				print("[COLN-PERM] permission %s result=true" % kind)
			return
	if OS.is_debug_build():
		print("[COLN-PERM] permission %s result=false" % kind)
	_refresh_permissions_setup_ui()
	if _perm_manage_live:
		_rebuild_permissions_manage_content()


func _show_permissions_setup() -> void:
	_current_screen = "permissions_setup"
	_perm_setup_status.clear()
	_perm_setup_actions.clear()
	_clear_screen()
	var root := _make_screen_root()
	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	MobileUi.enable_touch_scroll_on_tree(col)
	var title := Label.new()
	title.text = "Permissions Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	col.add_child(title)
	var why := Label.new()
	why.text = ProductStrings.PERMISSIONS_SETUP_WHY
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(why, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
	col.add_child(why)
	for row in [
		["notifications", "Notifications", ProductStrings.NOTIFY_RATIONALE],
		["location", "Location", ProductStrings.LOCATION_RATIONALE],
		["camera", "Camera", ProductStrings.CAMERA_SETUP_RATIONALE],
	]:
		var kind: String = str(row[0])
		var card := _make_card()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		card.add_child(box)
		var h := Label.new()
		h.text = str(row[1])
		MobileUi.apply_label(h, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
		box.add_child(h)
		var p := Label.new()
		p.text = str(row[2])
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MobileUi.apply_label(p, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_SECONDARY, true)
		box.add_child(p)
		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.clip_text = false
		MobileUi.apply_label(status, MobileUi.SIZE_BODY, MobileUi.COLOR_TITLE, true)
		box.add_child(status)
		_perm_setup_status[kind] = status
		var allow := _make_button("Allow", func() -> void:
			await _on_permission_allow_tapped(kind)
		, Vector2(0, MobileUi.TOUCH_SECONDARY_H))
		box.add_child(allow)
		_perm_setup_actions[kind] = allow
		col.add_child(card)
	_refresh_permissions_setup_ui()
	col.add_child(_make_button("Continue", func() -> void:
		## Optional — never trap the user; do not auto-fire three dialogs.
		await _finish_permissions_setup()
	, Vector2(0, MobileUi.TOUCH_CTA_H)))


func _rebuild_permissions_manage_content() -> void:
	## Live-refresh manage modal without closing it.
	if not _overlay.visible or not _perm_manage_live:
		return
	var host: VBoxContainer = null
	for c in _overlay.get_children():
		if c is VBoxContainer:
			host = c
			break
	if host == null:
		return
	## Keep title + rebuild rows below it.
	while host.get_child_count() > 1:
		var last := host.get_child(host.get_child_count() - 1)
		host.remove_child(last)
		last.queue_free()
	_fill_permissions_manage_rows(host)


func _fill_permissions_manage_rows(box: VBoxContainer) -> void:
	for row in [
		["notifications", "Notifications"],
		["location", "Location"],
		["camera", "Camera"],
	]:
		var kind: String = str(row[0])
		var allowed := false
		match kind:
			"notifications":
				allowed = PermissionsHelper.notification_allowed()
			"location":
				allowed = PermissionsHelper.location_allowed()
			"camera":
				allowed = PermissionsHelper.camera_allowed()
		var lab := Label.new()
		lab.text = "%s — %s" % [str(row[1]), PermissionsHelper.status_label(allowed)]
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.clip_text = false
		MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
		box.add_child(lab)
		if allowed:
			var ok := Label.new()
			ok.text = "Allowed"
			MobileUi.apply_label(ok, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_TITLE, false)
			box.add_child(ok)
		elif PermissionsHelper.needs_settings(kind):
			box.add_child(_make_button("Open App Settings", func() -> void:
				PermissionsHelper.open_app_settings()
			, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))
		else:
			box.add_child(_make_button("Allow %s" % str(row[1]), func() -> void:
				await _on_permission_allow_tapped(kind)
			, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))
	box.add_child(_make_button("Open App Settings", func() -> void:
		PermissionsHelper.open_app_settings()
	, Vector2(0, MobileUi.TOUCH_PRIMARY_H)))
	box.add_child(_make_button("Done", func() -> void:
		_perm_manage_live = false
		_hide_overlay()
		if _current_screen == "profile":
			_show_profile()
	))


func _show_permissions_manage_sheet() -> void:
	_overlay.visible = true
	_perm_manage_live = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_perm_manage_live = false
			_hide_overlay()
	)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := minf(360.0, get_viewport().get_visible_rect().size.x - 32.0)
	var modal_h := minf(480.0, get_viewport().get_visible_rect().size.y - 64.0)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Manage Permissions"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	box.add_child(title)
	_fill_permissions_manage_rows(box)

func _geofence_cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load("user://coln_geofence_optin.cfg")
	return c


func _is_geofence_opted_in(scroll_id: String) -> bool:
	if scroll_id.is_empty():
		return false
	return bool(_geofence_cfg().get_value("optin", scroll_id, false))


func _set_geofence_opted_in(scroll_id: String, on: bool) -> void:
	if scroll_id.is_empty():
		return
	var c := _geofence_cfg()
	c.set_value("optin", scroll_id, on)
	c.save("user://coln_geofence_optin.cfg")


func _add_geofence_opt_in(box: VBoxContainer, item: Dictionary) -> void:
	var sid := str(item.get("id", ""))
	if sid.is_empty():
		return
	var lat := float(item.get("location_lat", NAN))
	var lng := float(item.get("location_lng", NAN))
	var radius := float(item.get("location_radius_m", LocationHelper.DEFAULT_RADIUS_M))
	if not is_finite(lat) or not is_finite(lng):
		return
	var toggle := CheckButton.new()
	toggle.text = "Notify me when I'm close enough"
	toggle.button_pressed = _is_geofence_opted_in(sid)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(func(on: bool) -> void:
		if on:
			_show_toast(ProductStrings.GEOFENCE_RATIONALE)
			LocationHelper.request_background_location_permission()
			await get_tree().create_timer(0.35).timeout
			if LocationHelper.register_geofence(sid, lat, lng, radius):
				_set_geofence_opted_in(sid, true)
				_show_toast("You'll be notified when you're close enough.")
			else:
				toggle.set_pressed_no_signal(false)
				_set_geofence_opted_in(sid, false)
				_show_toast("Could not enable nearby unlock alerts. Check location permission.")
		else:
			LocationHelper.remove_geofence(sid)
			_set_geofence_opted_in(sid, false)
	)
	box.add_child(toggle)


func _try_register_push_token() -> void:
	if not state.is_online() or state.friends == null:
		return
	if not state.friends.has_method("register_push_token"):
		return
	var token := NotificationHelper.push_token_placeholder()
	if token.is_empty():
		return
	state.friends.register_push_token(token, "android")


func _sign_out_cleanup() -> void:
	LocationHelper.clear_all_geofences()
	if state.is_online() and state.friends != null and state.friends.has_method("deactivate_push_token"):
		var token := NotificationHelper.push_token_placeholder()
		if not token.is_empty():
			await state.friends.deactivate_push_token(token)
	await state.sign_out_full()


func _find_scroll_item_by_id(scroll_id: String) -> Dictionary:
	if scroll_id.is_empty():
		return {}
	## Prefer chest cache.
	if typeof(state.cached_chest) == TYPE_DICTIONARY:
		var chest: Dictionary = state.cached_chest.get("chest", {}) if typeof(state.cached_chest.get("chest")) == TYPE_DICTIONARY else {}
		var scrolls: Array = chest.get("scrolls", []) if typeof(chest.get("scrolls")) == TYPE_ARRAY else []
		for s in scrolls:
			if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == scroll_id:
				return _normalize_online_scroll_item(s)
	if state.is_demo():
		for it in state.demo.get_chest_items("all"):
			if str(it.get("id", "")) == scroll_id:
				return it
		for it in state.demo.get_saved_scrolls():
			if str(it.get("id", "")) == scroll_id:
				return it
	return {}


func _consume_notification_deeplink() -> void:
	## Don't steal first-run Permissions Setup; leave pending for next resume/chest.
	if _current_screen == "permissions_setup" or _current_screen == "profile_setup" or _current_screen == "welcome":
		return
	var link := NotificationHelper.consume_pending_deeplink().strip_edges().to_lower()
	if link.is_empty():
		return
	if not _guard_private_chest():
		return
	## person / person:request → My Person
	if link == "person" or link.begins_with("person:"):
		_show_friends()
		return
	## chest / chest:<id>
	if link == "chest":
		_show_inventory()
		return
	if link.begins_with("chest:"):
		var sid := link.get_slice(":", 1)
		var item := _find_scroll_item_by_id(sid)
		if item.is_empty() and state.is_online():
			var loaded: Array = await _load_online_chest_items("all")
			for it in loaded:
				if str(it.get("id", "")) == sid:
					item = it
					break
		if item.is_empty():
			_show_inventory()
			return
		if str(item.get("state", "")) == "locked":
			_show_locked_details(item)
		else:
			_open_chest_item(item)
		return
	## activity:<id> / focus:<id> → locked details
	if link.begins_with("activity:") or link.begins_with("focus:"):
		var sid2 := link.get_slice(":", 1)
		var item2 := _find_scroll_item_by_id(sid2)
		if item2.is_empty() and state.is_online():
			var loaded2: Array = await _load_online_chest_items("all")
			for it2 in loaded2:
				if str(it2.get("id", "")) == sid2:
					item2 = it2
					break
		if item2.is_empty():
			_show_inventory()
		else:
			_show_locked_details(item2)
		return
	if link == "activity" or link == "focus":
		_show_inventory()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _image_preview != null and _image_preview.visible:
			_image_preview.close_preview()
			return
		if _scroll_viewer.visible:
			_scroll_viewer.close_viewer()
			return
		if _overlay.visible:
			_hide_overlay()
			return
		match _current_screen:
			"compose":
				if _compose_screen != null and _compose_screen.handle_back():
					pass
				else:
					_show_main_chest()
			"sent":
				_clear_reveal_timers()
				state.clear_revealed_passwords()
				_show_main_chest()
			"permissions_setup":
				## Safe exit — mark explanation shown; never fake permission grants.
				_finish_permissions_setup()
			"inventory", "saved", "friends", "profile":
				_show_main_chest()
			"diagnostics":
				_show_profile()
			"profile_setup", "check_email", "auth_signin", "auth_signup":
				_show_welcome()
			"main_chest":
				_show_welcome()
			_:
				pass
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Clear revealed Magic Passwords when the app backgrounds.
		_clear_reveal_timers()
		state.clear_revealed_passwords()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		call_deferred("_on_app_resumed")


func _on_app_resumed() -> void:
	## Cold-start window: do not race secure session restore with resume revalidation.
	if not _startup_done:
		return
	if _resume_inflight:
		return
	_resume_inflight = true
	## Refresh live Android permission truth after App Settings / system dialogs.
	## Camera grant in Settings must be recognized immediately (no restart).
	PermissionsHelper.log_resume_refresh()
	_refresh_permissions_setup_ui()
	if _perm_manage_live:
		_rebuild_permissions_manage_content()
	## Consume notification deep links from warm resume / new intent.
	await _consume_notification_deeplink()
	## Profile permission rows + Android Diagnostics need a rebuild after Settings return.
	if _current_screen == "profile" and not _perm_manage_live:
		_show_profile()
		_resume_inflight = false
		return
	if state.is_online() and state.tokens.has_session():
		var resumed: Dictionary = await state.revalidate_on_resume()
		if not bool(resumed.get("ok", false)):
			var reason := str(resumed.get("reason", ""))
			## Soft/network failures keep the user in-app; only hard auth failures kick to Login.
			if reason in ["refresh_soft_fail", "membership_soft_fail", "not_signed_in"]:
				if reason != "not_signed_in":
					_show_toast(str(resumed.get("message", "Could not refresh session.")))
				_resume_inflight = false
				return
			_show_toast(str(resumed.get("message", "Your session has expired. Please sign in again.")))
			_show_welcome()
			_resume_inflight = false
			return
		# Refresh chest / friends / saved metadata when returning to Main Chest.
		if _current_screen == "main_chest":
			var chest: Dictionary = await state.scrolls.get_chest()
			if bool(chest.get("ok", false)) and typeof(chest.get("data")) == TYPE_DICTIONARY:
				state.cached_chest = chest.data
			var fr: Dictionary = await state.friends.get_friends()
			if bool(fr.get("ok", false)) and typeof(fr.get("data")) == TYPE_DICTIONARY:
				state.apply_friends_payload(fr.data)
			var saved: Dictionary = await state.scrolls.get_saved_scrolls()
			if bool(saved.get("ok", false)) and typeof(saved.get("data")) == TYPE_DICTIONARY:
				state.cached_saved = saved.data
			_show_main_chest()
	_resume_inflight = false
