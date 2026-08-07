extends Control
## Chest of Love Notes — root navigation and MVP screens.

var state: AppState
var _scroll_viewer: LoveNotesScrollViewer
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
var _empty_chest_hint: Label
var _dev_force_chest_scroll: bool = false
var _auth_spinner_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.ensure_loaded()
	state = AppState.new()
	state.bootstrap()
	state.reduced_motion = MobileUi.reduced_motion()
	_build_chrome()
	_scroll_viewer = LoveNotesScrollViewer.new()
	_scroll_viewer.set_reduced_motion(state.reduced_motion)
	_scroll_viewer.closed.connect(_on_scroll_closed)
	add_child(_scroll_viewer)
	if state.api:
		state.api.session_invalidated.connect(_on_session_invalidated)
	# Cold start: short Charoite boot while session/backend init runs in parallel.
	await _startup_navigate()


func _startup_navigate() -> void:
	## Charoite Games cold boot (~1.5–2s). Session restore runs during the hold.
	_startup_done = false
	var boot := CharoiteBoot.new()
	boot.z_index = 80
	add_child(boot)
	_log_secure_debug("startup_begin")
	_pending_restore = {"ok": false}
	if state.is_online():
		_pending_restore = await state.restore_session_if_possible()
		_log_secure_debug("startup_after_restore")
	if not boot.is_finished():
		await boot.finished
	_boot_duration_sec = boot.measured_duration_sec()
	boot.queue_free()
	_log_secure_debug("startup_after_boot")
	var restore := _pending_restore
	if bool(restore.get("ok", false)):
		if bool(restore.get("profile_exists", false)):
			await _show_main_chest()
		else:
			_show_profile_setup()
		_startup_done = true
		_log_secure_debug("startup_destination_chest")
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


func _on_session_invalidated() -> void:
	await state.sign_out_full()
	_show_toast("Your session has expired. Please sign in again.")
	_show_welcome()


func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if ResourceLoader.exists("res://assets/art/background/starfield.png"):
		var stars := TextureRect.new()
		stars.texture = load("res://assets/art/background/starfield.png")
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stars.stretch_mode = TextureRect.STRETCH_SCALE
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
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MobileUi.apply_label(_toast, MobileUi.SIZE_BODY, MobileUi.COLOR_TITLE)
	_toast_panel.add_child(_toast)
	add_child(_toast_panel)
	_position_snackbar()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.z_index = 55
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)


func _clear_screen() -> void:
	MobileUi.release_text_focus(self)
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
	## Temporary snackbar above bottom navigation — never permanent page text.
	_position_snackbar()
	_toast.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast_panel, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_toast_panel):
			_toast_panel.visible = false
	)


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
	sub.text = "Send sealed scrolls to friends.\nThey wait in the chest until their unlock time."
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
		var err := Label.new()
		err.text = "Backend is not configured.\nAdd config/backend_config.json (see example)."
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(err, MobileUi.SIZE_BODY, MobileUi.COLOR_DANGER)
		box.add_child(err)


func _enter_demo() -> void:
	if state.is_private_onboarding_build() and not state.is_demo():
		_show_toast("Local Demo Mode is disabled in this build.")
		return
	_show_main_chest()


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
	var profile_result: Dictionary = await state.profiles.fetch_own_profile()
	if not bool(profile_result.get("ok", false)):
		await state.sign_out_full()
		_show_toast(str(profile_result.get("error", "Could not load profile.")))
		_show_welcome()
		return
	# Hard-require Keystore persistence when Keep Me Signed In is ON.
	var persist: Dictionary = await state.persist_session_verified()
	_log_secure_debug("after_signin_persist")
	if not bool(persist.get("ok", false)):
		var warn := str(persist.get("warning", state.maybe_warn_persist_failure()))
		if warn.is_empty():
			warn = "Secure sign-in storage failed. You’ll need to sign in again after closing the app."
		_show_toast(warn)
	## Never toast "persisted successfully" — only warn on genuine failure.
	if not bool(profile_result.get("exists", false)):
		_show_profile_setup()
		return
	await _show_main_chest()


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
	info.text = "Choose a username and display name. Your friend code is generated securely."
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
		_show_main_chest()
	, Vector2(0, MobileUi.TOUCH_CTA_H)))
	box.add_child(_make_button("Sign Out", func() -> void:
		await state.sign_out_full()
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


func _show_main_chest() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "main_chest"
	## Fetch first so the destination appears fully prepared.
	var counts := {"unread": 0, "locked": 0, "requests": 0}
	var fetch_error := ""
	if state.is_demo():
		counts = state.demo.counts()
	elif state.is_online():
		var chest_result: Dictionary = await state.scrolls.get_chest()
		if bool(chest_result.get("ok", false)):
			state.cached_chest = chest_result.get("data", {}) if typeof(chest_result.get("data")) == TYPE_DICTIONARY else {}
			var chest: Dictionary = state.cached_chest.get("chest", {}) if typeof(state.cached_chest.get("chest")) == TYPE_DICTIONARY else {}
			counts.unread = int(chest.get("unread", chest.get("unopened", 0)))
			counts.locked = int(chest.get("locked", 0))
			var fr: Array = chest.get("friend_requests", []) if typeof(chest.get("friend_requests")) == TYPE_ARRAY else []
			counts.requests = fr.size()
		else:
			fetch_error = str(chest_result.get("error", "Could not refresh chest."))
	if _dev_force_chest_scroll and OS.is_debug_build():
		counts.unread = maxi(int(counts.unread), 1)
	_last_chest_counts = counts.duplicate()

	_begin_nav_transition()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = MobileUi.font_touch(48)
	root.add_child(header)
	var title := Label.new()
	title.text = "Chest of Love Notes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	header.add_child(title)
	var refresh_btn := Button.new()
	refresh_btn.text = "↻"
	refresh_btn.tooltip_text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(MobileUi.font_touch(48), MobileUi.font_touch(48))
	MobileUi.style_button(refresh_btn, 48)
	refresh_btn.pressed.connect(func() -> void: _show_main_chest())
	header.add_child(refresh_btn)

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", MobileUi.card_style())
	root.add_child(summary)
	var sum_row := HBoxContainer.new()
	sum_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sum_row.add_theme_constant_override("separation", 8)
	summary.add_child(sum_row)
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
	var chest_side := 252
	_chest.custom_minimum_size = Vector2(chest_side, chest_side)
	_chest.size = Vector2(chest_side, chest_side)
	_chest.position = Vector2(-chest_side * 0.5, -chest_side * 0.42)
	_chest.z_index = 5
	_chest.tapped.connect(_on_chest_tapped)
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
	if not fetch_error.is_empty():
		_show_toast(fetch_error)


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
	var tabs := [
		["chest", "▣", "Chest", _show_main_chest],
		["compose", "✎", "Compose", _show_compose],
		["friends", "♡", "Friends", _show_friends],
		["sent", "✉", "Sent", _show_sent],
		["profile", "◎", "Profile", _show_profile],
	]
	for t in tabs:
		var b := Button.new()
		b.text = "%s\n%s" % [str(t[1]), str(t[2])]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.TOUCH_NAV_H) - 2)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_NAV_LABEL))
		b.add_theme_constant_override("line_spacing", -2)
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
	## Already open empty chest: pulse only.
	if _chest.chest_state == LoveNotesChest.ChestState.OPENED and not has_new:
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
	if not bool(item.get("is_unlockable", true)):
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
	item["sender_display_name"] = str(sender.get("display_name", raw.get("sender_display_name", "Friend")))
	item["unlock_at_unix"] = unlock_unix
	item["kind"] = str(raw.get("kind", "love_note"))
	return item


func _normalize_friend_request_item(raw: Dictionary) -> Dictionary:
	var sender: Dictionary = raw.get("sender", {}) if typeof(raw.get("sender")) == TYPE_DICTIONARY else {}
	return {
		"id": str(raw.get("id", "")),
		"kind": "friend_request",
		"state": "friend_request",
		"title": "Friend request",
		"sender_display_name": str(sender.get("display_name", "Someone")),
		"sender_id": str(raw.get("sender_id", "")),
		"has_magic_password": false,
	}


func _load_online_chest_items(filter: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var result: Dictionary = await state.scrolls.get_chest()
	if not bool(result.get("ok", false)):
		_show_toast(str(result.get("error", "Could not load chest.")))
		return out
	var data: Dictionary = result.get("data", {}) if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	state.cached_chest = data
	var chest: Dictionary = data.get("chest", {}) if typeof(data.get("chest")) == TYPE_DICTIONARY else {}
	var scrolls: Array = chest.get("scrolls", []) if typeof(chest.get("scrolls")) == TYPE_ARRAY else []
	var requests: Array = chest.get("friend_requests", []) if typeof(chest.get("friend_requests")) == TYPE_ARRAY else []
	for s in scrolls:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var item := _normalize_online_scroll_item(s)
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


func _show_inventory() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "inventory"
	_clear_screen()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin)
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Your Chest"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(160, MobileUi.TOUCH_PRIMARY_H)))

	# Horizontally swipeable filter chips — tall enough not to clip, no scrollbar.
	var chip_scroll := _wire_scroll(ScrollContainer.new(), true)
	chip_scroll.custom_minimum_size.y = MobileUi.font_touch(MobileUi.FILTER_CHIP_H + 14)
	chip_scroll.clip_contents = true
	root.add_child(chip_scroll)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	chip_scroll.add_child(filters)
	var chip_pad := Control.new()
	chip_pad.custom_minimum_size = Vector2(4, 0)
	filters.add_child(chip_pad)
	for f in [
		["all", "Current"],
		["unread", "Unread"],
		["locked", "Locked"],
		["requests", "Requests"],
	]:
		var fname: String = str(f[0])
		var chip := _make_button(str(f[1]), func() -> void:
			_inventory_filter = fname
			_show_inventory()
		, Vector2(118, MobileUi.FILTER_CHIP_H))
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if _inventory_filter == fname:
			chip.add_theme_color_override("font_color", MobileUi.COLOR_TITLE)
		filters.add_child(chip)
	var saved_chip := _make_button("Saved", _show_saved, Vector2(110, MobileUi.FILTER_CHIP_H))
	saved_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	filters.add_child(saved_chip)
	var chip_pad2 := Control.new()
	chip_pad2.custom_minimum_size = Vector2(12, 0)
	filters.add_child(chip_pad2)

	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)

	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_chest_items(_inventory_filter)
	elif state.is_online():
		items = await _load_online_chest_items(_inventory_filter)
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
	match str(item.get("state", "")):
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
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var title := Label.new()
	title.text = str(item.get("title", "Scroll"))
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SECTION))
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.75))
	row.add_child(title)
	var meta := Label.new()
	var state_label := str(item.get("state", "")).replace("_", " ")
	meta.text = "%s  ·  %s" % [str(item.get("sender_display_name", "")), state_label]
	if bool(item.get("has_magic_password", false)):
		meta.text += "  ·  Magic Password Required"
	if str(item.get("state", "")) == "locked":
		var remain := int(item.get("unlock_at_unix", 0)) - _now_unix()
		meta.text += "  ·  unlocks in %dm" % maxi(int(ceil(remain / 60.0)), 0)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SECONDARY))
	meta.add_theme_color_override("font_color", Color(0.82, 0.76, 0.88))
	row.add_child(meta)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	var btn_h := MobileUi.font_touch(MobileUi.TOUCH_SECONDARY_H)
	actions.add_child(_make_button("Open", func() -> void: _open_chest_item(item), Vector2(120, btn_h)))
	if str(item.get("kind", "love_note")) != "friend_request":
		var fav := bool(item.get("is_favorite", false))
		actions.add_child(_make_button("★" if fav else "☆", func() -> void:
			_toggle_favorite(str(item.id), not fav)
		, Vector2(64, btn_h)))
		actions.add_child(_make_button("Delete", func() -> void:
			_confirm_delete_received(str(item.id))
		, Vector2(110, btn_h)))
	return panel


func _show_saved() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "saved"
	_clear_screen()
	var root := _make_screen_root(MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Saved Scrolls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE, false)
	header.add_child(title)
	header.add_child(_make_button("Back", _show_inventory, Vector2(100, MobileUi.TOUCH_SECONDARY_H)))
	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)
	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_saved_scrolls()
	elif state.is_online():
		items = await _load_online_saved_items()
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


func _confirm_delete_received(scroll_id: String) -> void:
	_overlay.visible = true
	for c in _overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	var modal_w := 354.0
	var modal_h := 280.0
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-modal_w * 0.5, -modal_h * 0.5)
	box.size = Vector2(modal_w, modal_h)
	box.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Hide this scroll?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var body := Label.new()
	body.text = "This hides the note from your Current and Saved views only. It does not erase the sender's history or permanently destroy the message."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_BODY))
	body.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	box.add_child(body)
	box.add_child(_make_button("Hide from my chest", func() -> void:
		_hide_overlay()
		_delete_received(scroll_id)
	))
	box.add_child(_make_button("Cancel", _hide_overlay, Vector2(180, MobileUi.font_touch(MobileUi.TOUCH_SECONDARY_H))))


func _delete_received(scroll_id: String) -> void:
	if state.is_demo():
		var result := state.demo.delete_received_scroll(scroll_id)
		if bool(result.get("ok", false)):
			_show_toast("Scroll hidden from your chest")
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
			_show_toast("Scroll hidden from your chest")
			if _current_screen == "saved":
				_show_saved()
			else:
				_show_inventory()
		else:
			_show_toast(str(result.get("error", "Could not delete.")))
		return
	_show_toast("Backend is not configured.")


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
	await _open_authorized_scroll(str(item.id), "")


func _show_locked_details(item: Dictionary) -> void:
	var unlock_note := "Unlock is authorized by server time."
	if state.is_demo():
		unlock_note = "Unlock is authorized by server time (demo clock here)."
	_show_modal_panel("Sealed Scroll", [
		"From: %s" % str(item.get("sender_display_name", "")),
		"Title: %s" % str(item.get("title", "")),
		"This message body is not available yet.",
		unlock_note,
		"Magic password: %s" % ("Yes" if bool(item.get("has_magic_password", false)) else "No"),
	], "Close", func() -> void: _hide_overlay())


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
	title.text = "Friend Request"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_SCREEN_TITLE))
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(title)
	var body := Label.new()
	body.text = "%s would like to become your friend." % str(item.get("sender_display_name", "Someone"))
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
			_show_toast("Friend request accepted")
			_show_inventory()
			return
		var result: Dictionary = await state.friends.respond_to_friend_request(str(item.id), true)
		_hide_overlay()
		if bool(result.get("ok", false)):
			_play_friends_celebration()
			_show_toast("Friend request accepted")
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
		await _open_authorized_scroll(str(item.id), pw)
	))
	box.add_child(_make_button("Cancel", func() -> void:
		field.text = ""
		_hide_overlay()
	, Vector2(220, 64)))


func _open_authorized_scroll(scroll_id: String, magic_password: String) -> void:
	var result: Dictionary = {}
	if state.is_demo():
		result = state.demo.open_scroll(scroll_id, magic_password)
	elif state.is_online():
		result = await state.scrolls.open_scroll(scroll_id, magic_password)
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			result = {
				"ok": true,
				"message": str(data.get("message", "")),
				"scroll": data.get("scroll", {}),
				"ephemeral": bool(data.get("ephemeral", false)),
			}
		else:
			result = {"ok": false, "error": str(result.get("error", "Could not open scroll."))}
	else:
		_show_toast("Backend is not configured.")
		return
	if not bool(result.get("ok", false)):
		if bool(result.get("locked", false)):
			_show_toast("Still locked on demo server clock.")
		else:
			_show_toast(str(result.get("error", "Could not open scroll.")))
		return
	var meta: Dictionary = result.get("scroll", {})
	var body := str(result.get("message", ""))
	state.open_message_plaintext = body
	var ephemeral := bool(result.get("ephemeral", false))
	var heading := str(meta.get("title", "A Love Note"))
	var meta_line := "From %s" % str(meta.get("sender_display_name", meta.get("sender_id", "Friend")))
	await _scroll_viewer.open_message(heading, meta_line, body, false, ephemeral)


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


func _show_compose() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "compose"
	_compose_screen = null

	var friends: Array = []
	var fetch_error := ""
	if state.is_demo():
		friends = state.demo.get_friends()
	elif state.is_online():
		var fr: Dictionary = await state.friends.get_friends()
		if bool(fr.get("ok", false)):
			var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
			state.cached_friends = data
			friends = data.get("friends", []) if typeof(data.get("friends")) == TYPE_ARRAY else []
		else:
			fetch_error = str(fr.get("error", "Could not load friends."))

	_begin_nav_transition()
	var compose := ComposeScrollScreen.new()
	compose.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := SafeAreaHelper.display_insets_viewport()
	compose.offset_bottom = -MobileUi.font_touch(MobileUi.TOUCH_NAV_H) - int(safe.w)
	_screen_host.add_child(compose)
	_compose_screen = compose
	compose.back_pressed.connect(_show_main_chest)
	compose.preview_requested.connect(_on_compose_preview)
	compose.send_requested.connect(_on_compose_send_requested)
	## Never show "Private Onboarding Build" chip in test APKs.
	compose.setup(friends, false)
	_add_bottom_nav("compose")
	_finish_nav_transition()
	if not fetch_error.is_empty():
		_show_toast(fetch_error)


func _on_compose_preview(draft: Dictionary) -> void:
	_compose_draft = draft.duplicate(true)
	var title := str(draft.get("title", "")).strip_edges()
	if title.is_empty():
		title = "A Love Note"
	var recipient := str(draft.get("recipient_display_name", "Friend"))
	if recipient.is_empty():
		recipient = "Friend"
	var when := "Opens immediately"
	if not bool(draft.get("open_immediately", true)):
		var unlock_unix := int(draft.get("unlock_unix", 0))
		when = "Opens %s" % Time.get_datetime_string_from_unix_time(unlock_unix, false)
	var pw_note := "Magic password required" if bool(draft.get("has_password", false)) else "No magic password"
	var meta := "To %s · %s · %s" % [recipient, when, pw_note]
	var body := str(draft.get("message", ""))
	await _scroll_viewer.open_message(title, meta, body, false, false)


func _on_compose_send_requested(draft: Dictionary) -> void:
	if _compose_screen == null:
		return
	_compose_draft = draft.duplicate(true)
	_compose_screen.set_sending(true)
	var rid := str(draft.get("recipient_id", ""))
	var body := str(draft.get("message", ""))
	var title := str(draft.get("title", "")).strip_edges()
	var magic := str(draft.get("password", ""))
	var unlock_unix := int(draft.get("unlock_unix", Time.get_unix_time_from_system()))
	var result: Dictionary = {}
	if state.is_demo():
		result = state.demo.send_scroll(rid, title, body, unlock_unix, magic)
	elif state.is_online():
		# Existing send-scroll contract: recipient_id, message, optional title/password/unlock_at (UTC ISO).
		var unlock_at := Time.get_datetime_string_from_unix_time(unlock_unix, true) + "Z"
		var payload := {
			"recipient_id": rid,
			"title": title,
			"message": body,
			"unlock_at": unlock_at,
		}
		if not magic.is_empty():
			payload["password"] = magic
		result = await state.scrolls.send_scroll(payload)
		if bool(result.get("ok", false)):
			result = {"ok": true}
		else:
			result = {"ok": false, "error": "Could not send your scroll. Please try again."}
	else:
		_compose_screen.restore_after_failed_send()
		_show_toast("Backend is not configured.")
		return
	if bool(result.get("ok", false)):
		_compose_screen.set_sending(false)
		_compose_draft.clear()
		_compose_screen = null
		_show_toast("Scroll sent.")
		_show_main_chest()
	else:
		_compose_screen.restore_after_failed_send()
		_show_toast(str(result.get("error", "Could not send your scroll. Please try again.")))


func _play_friends_celebration() -> void:
	## Restrained petal burst — behind content, never covering nav/buttons.
	var fx := FriendsCelebration.new()
	_screen_host.add_child(fx)
	fx.play(state.reduced_motion or MobileUi.reduced_motion())


func _show_friends() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "friends"
	var friends: Array = []
	var me: Dictionary = {}
	var fetch_error := ""
	if state.is_demo():
		friends = state.demo.get_friends()
		me = state.demo.get_profile()
	elif state.is_online():
		var fr: Dictionary = await state.friends.get_friends()
		if bool(fr.get("ok", false)):
			var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
			state.cached_friends = data
			friends = data.get("friends", []) if typeof(data.get("friends")) == TYPE_ARRAY else []
		else:
			fetch_error = str(fr.get("error", "Could not load friends."))
		me = state.profiles.profile

	_begin_nav_transition()
	var root := _make_screen_root(MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Friends"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE, false)
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(100, MobileUi.TOUCH_SECONDARY_H)))

	var search := LineEdit.new()
	search.placeholder_text = "Exact username or friend code"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_line_edit(search)
	root.add_child(search)
	var add_btn := Button.new()
	add_btn.text = "Add Friend"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.style_button(add_btn, MobileUi.TOUCH_PRIMARY_H)
	add_btn.disabled = true
	root.add_child(add_btn)
	var friend_status := Label.new()
	friend_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(friend_status, MobileUi.SIZE_HELPER, MobileUi.COLOR_HELPER)
	root.add_child(friend_status)
	var refresh_add := func(_t: String = "") -> void:
		var q := search.text.strip_edges()
		add_btn.disabled = q.is_empty() or _friend_action_busy
	search.text_changed.connect(refresh_add)
	add_btn.pressed.connect(func() -> void:
		var q := search.text.strip_edges()
		if q.is_empty() or _friend_action_busy:
			return
		_friend_action_busy = true
		add_btn.disabled = true
		friend_status.text = ""
		var result: Dictionary = {}
		if state.is_demo():
			result = state.demo.send_friend_request(q)
		elif state.is_online():
			result = await state.friends.send_friend_request_query(q)
		_friend_action_busy = false
		refresh_add.call()
		if bool(result.get("ok", false)):
			search.text = ""
			refresh_add.call()
			_show_toast("Friend request sent.")
			_show_friends()
		else:
			friend_status.add_theme_color_override("font_color", MobileUi.COLOR_DANGER)
			friend_status.text = str(result.get("error", "Could not send friend request."))
	)
	var kb_pad_f := Control.new()
	kb_pad_f.custom_minimum_size = Vector2(0, 0)

	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)
	root.add_child(kb_pad_f)
	MobileUi.wire_keyboard_avoidance(root, scroll, kb_pad_f)

	var section := Label.new()
	section.text = "Accepted friends"
	MobileUi.apply_label(section, MobileUi.SIZE_SECTION, MobileUi.COLOR_SECONDARY, false)
	list.add_child(section)
	for f in friends:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var card := _make_card()
		card.custom_minimum_size.y = MobileUi.font_touch(MobileUi.ROW_H)
		var row := Label.new()
		row.text = "%s  ·  @%s  ·  %s" % [
			str(f.get("display_name", "")),
			str(f.get("username", "")),
			str(f.get("friend_code", "")),
		]
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MobileUi.apply_label(row, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY, true)
		card.add_child(row)
		list.add_child(card)
	list.add_child(_settings_long_value_card("Your friend code", str(me.get("friend_code", "—")), true))
	_add_bottom_nav("friends")
	_finish_nav_transition()
	if not fetch_error.is_empty():
		_show_toast(fetch_error)


func _show_sent() -> void:
	if not _guard_private_chest():
		return
	# Leaving/rebuilding Sent clears any previously revealed passwords from memory.
	_clear_reveal_timers()
	state.clear_revealed_passwords()
	_current_screen = "sent"
	var sent_items: Array = []
	var fetch_error := ""
	if state.is_demo():
		sent_items = state.demo.get_sent_scrolls()
	elif state.is_online():
		var sent_result: Dictionary = await state.scrolls.get_sent_scrolls()
		if bool(sent_result.get("ok", false)):
			var data: Dictionary = sent_result.get("data", {}) if typeof(sent_result.get("data")) == TYPE_DICTIONARY else {}
			state.cached_sent = data
			sent_items = data.get("sent_scrolls", []) if typeof(data.get("sent_scrolls")) == TYPE_ARRAY else []
		else:
			fetch_error = str(sent_result.get("error", "Could not load sent scrolls."))

	_begin_nav_transition()
	var root := _make_screen_root(MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Sent Scrolls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE, false)
	header.add_child(title)
	header.add_child(_make_button("Back", func() -> void:
		_clear_reveal_timers()
		state.clear_revealed_passwords()
		_show_main_chest()
	, Vector2(100, MobileUi.TOUCH_SECONDARY_H)))
	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(list)
	MobileUi.enable_touch_scroll_on_tree(list)

	if sent_items.is_empty():
		var empty_wrap := VBoxContainer.new()
		empty_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_wrap.add_theme_constant_override("separation", 10)
		list.add_child(empty_wrap)
		var icon := Label.new()
		icon.text = "✉"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(icon, MobileUi.SIZE_APP_TITLE, MobileUi.COLOR_SECONDARY)
		empty_wrap.add_child(icon)
		var empty := Label.new()
		empty.text = "No sent scrolls yet"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(empty, MobileUi.SIZE_MAJOR_HEADING, MobileUi.COLOR_BODY)
		empty_wrap.add_child(empty)
		var hint := Label.new()
		hint.text = "Scrolls you send will appear here."
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MobileUi.apply_label(hint, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_HELPER)
		empty_wrap.add_child(hint)
	else:
		for s in sent_items:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var panel := _make_card()
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", MobileUi.GAP_RELATED)
			panel.add_child(col)
			var recipient: Dictionary = s.get("recipient", {}) if typeof(s.get("recipient")) == TYPE_DICTIONARY else {}
			var unlock_at := str(s.get("unlock_at", ""))
			var unlock_unix := int(s.get("unlock_at_unix", 0))
			if unlock_unix == 0 and not unlock_at.is_empty():
				unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))
			var title_lab := Label.new()
			title_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_lab.text = "%s → %s" % [
				str(s.get("title", "Love Note")),
				str(s.get("recipient_display_name", recipient.get("display_name", "Friend"))),
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
			if has_pw:
				col.add_child(_build_sent_password_reveal_row(sid, s))
			col.add_child(_make_button("Hide from Sent", func() -> void:
				if state.is_demo():
					var result := state.demo.delete_sent_scroll(sid)
					if bool(result.get("ok", false)):
						_show_toast("Hidden from Sent history")
						_show_sent()
					else:
						_show_toast(str(result.get("error", "Could not hide sent scroll.")))
				elif state.is_online():
					var result: Dictionary = await state.scrolls.delete_sent_scroll(sid)
					if bool(result.get("ok", false)):
						_show_toast("Hidden from Sent history")
						_show_sent()
					else:
						_show_toast(str(result.get("error", "Could not hide sent scroll.")))
				else:
					_show_toast("Backend is not configured.")
			, Vector2(0, MobileUi.TOUCH_SECONDARY_H)))
			list.add_child(panel)
	_add_bottom_nav("sent")
	_finish_nav_transition()
	if not fetch_error.is_empty():
		_show_toast(fetch_error)


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
	_current_screen = "profile"
	var me: Dictionary = {}
	if state.is_demo():
		me = state.demo.get_profile()
	elif state.is_online() and state.tokens.has_session():
		var pref: Dictionary = await state.profiles.fetch_own_profile()
		if bool(pref.get("ok", false)) and bool(pref.get("exists", false)):
			me = state.profiles.profile

	_begin_nav_transition()
	var root := _make_screen_root(MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	var title := Label.new()
	title.text = "Profile"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	root.add_child(title)

	var scroll := _wire_scroll(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", MobileUi.GAP_CARDS)
	scroll.add_child(col)
	MobileUi.enable_touch_scroll_on_tree(col)
	var kb_pad_p := Control.new()
	kb_pad_p.custom_minimum_size = Vector2(0, 0)
	root.add_child(kb_pad_p)
	MobileUi.wire_keyboard_avoidance(root, scroll, kb_pad_p)

	var section := Label.new()
	section.text = "ACCOUNT"
	MobileUi.apply_label(section, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	col.add_child(section)
	## Full username on its own wrapping line — no accidental ellipsis.
	col.add_child(_settings_long_value_card("Display Name", str(me.get("display_name", "—")), false))
	col.add_child(_settings_long_value_card("Username", "@" + str(me.get("username", "—")), false))
	col.add_child(_settings_long_value_card("Email", str(state.tokens.user_email if state.tokens.user_email != "" else "—"), false))
	col.add_child(_settings_long_value_card("Friend Code", str(me.get("friend_code", "—")), true))
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

	if OS.is_debug_build():
		col.add_child(_make_button("Online Diagnostics", _show_diagnostics))
	col.add_child(_make_button("Sign Out", func() -> void:
		_clear_reveal_timers()
		await state.sign_out_full()
		if state.is_demo():
			state.demo.enable()
		_show_welcome()
	, Vector2(0, MobileUi.TOUCH_CTA_H)))

	if state.membership.is_member or state.is_demo():
		_add_bottom_nav("profile")
	else:
		col.add_child(_make_button("Back", _show_welcome))
	_finish_nav_transition()


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
		await state.sign_out_full()
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


func _hide_overlay() -> void:
	_overlay.visible = false
	for c in _overlay.get_children():
		c.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
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
				state.cached_friends = fr.data
			var saved: Dictionary = await state.scrolls.get_saved_scrolls()
			if bool(saved.get("ok", false)) and typeof(saved.get("data")) == TYPE_DICTIONARY:
				state.cached_saved = saved.data
			_show_main_chest()
	_resume_inflight = false
