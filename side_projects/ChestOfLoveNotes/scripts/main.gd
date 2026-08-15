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
	# Cold start: Charoite Games ≥5s while session/backend init runs in parallel.
	await _startup_navigate()


func _startup_navigate() -> void:
	## Charoite Games cold boot (≥5s). Session restore runs during the hold.
	var boot := CharoiteBoot.new()
	boot.z_index = 80
	add_child(boot)
	_log_secure_debug("startup_begin")
	_pending_restore = {"ok": false}
	if state.is_online():
		_pending_restore = await state.restore_session_if_possible()
		_log_secure_debug("startup_after_restore")
	# Keep brand on screen for the remaining time of the 5s presentation.
	if not boot.is_finished():
		await boot.finished
	_boot_duration_sec = boot.measured_duration_sec()
	boot.queue_free()
	_log_secure_debug("startup_after_boot")
	var restore := _pending_restore
	if bool(restore.get("ok", false)):
		if bool(restore.get("profile_exists", false)):
			_show_main_chest()
		else:
			_show_profile_setup()
		return
	if not str(restore.get("message", "")).is_empty():
		_show_toast(str(restore.message))
	_show_welcome()


func _log_secure_debug(tag: String) -> void:
	if not OS.is_debug_build():
		return
	var snap: Dictionary = state.diagnostics_snapshot()
	# Safe YES/NO only — never tokens/passwords/session JSON.
	print(
		"[COLN-SECURE:%s] plugin=%s available=%s has_session=%s decrypt=%s refresh_attempted=%s refresh_ok=%s membership=%s profile=%s"
		% [
			tag,
			"YES" if bool(snap.get("secure_plugin_found", false)) else "NO",
			"YES" if bool(snap.get("secure_storage_available", false)) else "NO",
			"YES" if bool(snap.get("saved_session_exists", false)) else "NO",
			"YES" if bool(snap.get("session_decrypt_ok", false)) else "NO",
			"YES" if bool(snap.get("refresh_attempted", false)) else "NO",
			"YES" if bool(snap.get("refresh_succeeded", false)) else "NO",
			"YES" if bool(snap.get("membership_revalidated", false)) else "NO",
			"YES" if bool(snap.get("profile_loaded", false)) else "NO",
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
	if state.is_demo():
		_banner.text = "LOCAL DEMO MODE"
		_banner.visible = true
	elif state.is_private_onboarding_build():
		_banner.text = "Private Onboarding Build"
		_banner.visible = true
	else:
		_banner.visible = false
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

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-160, -120)
	_toast.size = Vector2(320, 64)
	MobileUi.apply_label(_toast, MobileUi.SIZE_BODY, MobileUi.COLOR_TITLE)
	_toast.modulate.a = 0.0
	_toast.z_index = 60
	add_child(_toast)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.z_index = 55
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)


func _clear_screen() -> void:
	_compose_screen = null
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
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	return root


func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MobileUi.card_style())
	return card


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.35)


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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var card := _make_card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 320
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
	eye.text = "👁"
	eye.custom_minimum_size = Vector2(MobileUi.font_touch(48), MobileUi.font_touch(48))
	MobileUi.style_button(eye, 48)
	eye.pressed.connect(func() -> void:
		password.secret = not password.secret
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

	var submit_label := "Create Account" if sign_up else "Sign In"
	box.add_child(_make_button(submit_label, func() -> void:
		status.text = "Working…"
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
				status.add_theme_color_override("font_color", MobileUi.COLOR_DANGER)
				status.text = str(result.get("error", "Sign in failed."))
				if bool(result.get("needs_confirmation", false)):
					state.pending_confirm_email = email.text.strip_edges().to_lower()
					box.add_child(_make_button("Go to Check Your Email", _show_check_email))
				return
			await _after_verified_sign_in()
	, Vector2(0, MobileUi.TOUCH_CTA_H)))
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
	if not state.tokens.has_session() or not state.tokens.email_confirmed:
		await state.sign_out_full()
		_show_toast("Please confirm your email, then sign in.")
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
	var persist: Dictionary = state.persist_session_verified()
	_log_secure_debug("after_signin_persist")
	if not bool(persist.get("ok", false)):
		var warn := str(persist.get("warning", state.maybe_warn_persist_failure()))
		if warn.is_empty():
			warn = "Secure sign-in storage failed. You’ll need to sign in again after closing the app."
		_show_toast(warn)
	elif OS.is_debug_build() and bool(persist.get("persisted", false)):
		_show_toast("Secure session persisted successfully.")
	if not bool(profile_result.get("exists", false)):
		_show_profile_setup()
		return
	_show_main_chest()


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
	_clear_screen()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileUi.apply_safe_margins(margin, MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	_screen_host.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = MobileUi.font_touch(52)
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

	var counts := {"unread": 0, "locked": 0, "requests": 0}
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
			_show_toast(str(chest_result.get("error", "Could not refresh chest.")))

	# Summary card
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

	# Chest area (expands)
	var chest_area := Control.new()
	chest_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(chest_area)
	var your := Label.new()
	your.text = "Your Chest"
	your.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	your.set_anchors_preset(Control.PRESET_CENTER_TOP)
	your.position = Vector2(-200, 8)
	your.size = Vector2(400, 36)
	MobileUi.apply_label(your, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	chest_area.add_child(your)

	_chest = LoveNotesChest.new()
	_chest.reduced_motion = state.reduced_motion
	_chest.set_anchors_preset(Control.PRESET_CENTER)
	# ~65% of ~390 logical width — dominant home focal point.
	var chest_side := 260
	_chest.custom_minimum_size = Vector2(chest_side, chest_side)
	_chest.size = Vector2(chest_side, chest_side)
	_chest.position = Vector2(-chest_side * 0.5, -chest_side * 0.38)
	_chest.z_index = 5
	_chest.tapped.connect(_on_chest_tapped)
	chest_area.add_child(_chest)
	_chest.configure(LoveNotesChest.ChestState.READY, false)
	_chest.set_unread_badge(int(counts.unread))

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

	# Bottom navigation (outside margin bottom is reserved)
	_add_bottom_nav("chest")


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
	row.add_theme_constant_override("separation", 4)
	nav.add_child(row)
	var tabs := [
		["chest", "Chest", _show_main_chest],
		["compose", "Compose", _show_compose],
		["friends", "Friends", _show_friends],
		["sent", "Sent", _show_sent],
		["profile", "Profile", _show_profile],
	]
	for t in tabs:
		var b := Button.new()
		b.text = str(t[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, MobileUi.font_touch(MobileUi.TOUCH_NAV_H) - 8)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", MobileUi.font(MobileUi.SIZE_NAV_LABEL))
		var sel := str(t[0]) == selected
		b.add_theme_color_override("font_color", MobileUi.COLOR_NAV_SELECTED if sel else MobileUi.COLOR_NAV_IDLE)
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.18, 0.12, 0.28, 0.95) if sel else Color(0, 0, 0, 0)
		flat.set_corner_radius_all(12)
		b.add_theme_stylebox_override("normal", flat)
		b.add_theme_stylebox_override("hover", flat)
		b.add_theme_stylebox_override("pressed", flat)
		var cb: Callable = t[2]
		b.pressed.connect(cb)
		row.add_child(b)


func _on_chest_tapped() -> void:
	if not _guard_private_chest():
		return
	if _chest == null or _chest.animating:
		return
	# Full physical opening unless reduced motion.
	await _chest.play_open_animation(state.reduced_motion)
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

	# Large filter chips (horizontally scrollable)
	var chip_scroll := ScrollContainer.new()
	chip_scroll.custom_minimum_size.y = MobileUi.font_touch(56)
	chip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(chip_scroll)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	chip_scroll.add_child(filters)
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
		, Vector2(150, 52))
		if _inventory_filter == fname:
			chip.add_theme_color_override("font_color", MobileUi.COLOR_TITLE)
		filters.add_child(chip)
	filters.add_child(_make_button("Saved", _show_saved, Vector2(140, 52)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

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
	title.add_theme_font_size_override("font_size", 30)
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
	meta.add_theme_font_size_override("font_size", 22)
	meta.add_theme_color_override("font_color", Color(0.82, 0.76, 0.88))
	row.add_child(meta)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	actions.add_child(_make_button("Open", func() -> void: _open_chest_item(item), Vector2(160, 56)))
	if str(item.get("kind", "love_note")) != "friend_request":
		var fav := bool(item.get("is_favorite", false))
		actions.add_child(_make_button("★" if fav else "☆", func() -> void:
			_toggle_favorite(str(item.id), not fav)
		, Vector2(80, 56)))
		actions.add_child(_make_button("Delete", func() -> void:
			_confirm_delete_received(str(item.id))
		, Vector2(140, 56)))
	return panel


func _show_saved() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "saved"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28
	root.offset_right = -28
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Saved Scrolls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_inventory, Vector2(160, 64)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var items: Array[Dictionary] = []
	if state.is_demo():
		items = state.demo.get_saved_scrolls()
	elif state.is_online():
		items = await _load_online_saved_items()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No saved scrolls yet. Open a note to keep it here."
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
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
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-340, -220)
	box.size = Vector2(680, 420)
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Hide this scroll?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	var body := Label.new()
	body.text = "This hides the note from your Current and Saved views only. It does not erase the sender's history or permanently destroy the message."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	box.add_child(body)
	box.add_child(_make_button("Hide from my chest", func() -> void:
		_hide_overlay()
		_delete_received(scroll_id)
	))
	box.add_child(_make_button("Cancel", _hide_overlay, Vector2(220, 64)))


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
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-360, -280)
	box.size = Vector2(720, 560)
	box.add_theme_constant_override("separation", 16)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Friend Request"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(title)
	var body := Label.new()
	body.text = "%s would like to become your friend." % str(item.get("sender_display_name", "Someone"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 28)
	body.add_theme_color_override("font_color", Color(0.95, 0.9, 0.98))
	box.add_child(body)
	box.add_child(_make_button("Accept", func() -> void:
		if state.is_demo():
			state.demo.respond_friend_request(str(item.id), true)
			_hide_overlay()
			_show_toast("Friend request accepted")
			_show_inventory()
			return
		var result: Dictionary = await state.friends.respond_to_friend_request(str(item.id), true)
		_hide_overlay()
		if bool(result.get("ok", false)):
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
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-340, -260)
	box.size = Vector2(680, 520)
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = "Magic Password"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 1.0))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Demo password for the sealed note: starlight"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
	box.add_child(hint)
	var field := LineEdit.new()
	field.placeholder_text = "Enter magic password"
	field.secret = true
	field.custom_minimum_size = Vector2(0, 64)
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
	_clear_screen()
	_compose_screen = null

	var friends: Array = []
	if state.is_demo():
		friends = state.demo.get_friends()
	elif state.is_online():
		var fr: Dictionary = await state.friends.get_friends()
		if bool(fr.get("ok", false)):
			var data: Dictionary = fr.get("data", {}) if typeof(fr.get("data")) == TYPE_DICTIONARY else {}
			state.cached_friends = data
			friends = data.get("friends", []) if typeof(data.get("friends")) == TYPE_ARRAY else []
		else:
			_show_toast(str(fr.get("error", "Could not load friends.")))

	var compose := ComposeScrollScreen.new()
	compose.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_host.add_child(compose)
	_compose_screen = compose
	compose.back_pressed.connect(_show_main_chest)
	compose.preview_requested.connect(_on_compose_preview)
	compose.send_requested.connect(_on_compose_send_requested)
	compose.setup(friends, state.is_private_onboarding_build())


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


func _show_friends() -> void:
	if not _guard_private_chest():
		return
	_current_screen = "friends"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_right = -32
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Friends"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", _show_main_chest, Vector2(160, 64)))

	var search := LineEdit.new()
	search.placeholder_text = "Exact username or friend code"
	search.custom_minimum_size = Vector2(0, 60)
	root.add_child(search)
	root.add_child(_make_button("Add Friend", func() -> void:
		var result: Dictionary = {}
		if state.is_demo():
			result = state.demo.send_friend_request(search.text)
		elif state.is_online():
			result = await state.friends.send_friend_request_query(search.text)
		_show_toast("Friend request sent." if bool(result.get("ok", false)) else str(result.get("error", "Failed")))
	))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	root.add_child(list)
	var section := Label.new()
	section.text = "Accepted friends"
	section.add_theme_font_size_override("font_size", 28)
	section.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
	list.add_child(section)
	var friends: Array = []
	var me: Dictionary = {}
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
			_show_toast(str(fr.get("error", "Could not load friends.")))
		me = state.profiles.profile
	for f in friends:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var row := Label.new()
		row.text = "%s  ·  @%s  ·  %s" % [
			str(f.get("display_name", "")),
			str(f.get("username", "")),
			str(f.get("friend_code", "")),
		]
		row.add_theme_font_size_override("font_size", 24)
		row.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
		list.add_child(row)
	var code := Label.new()
	code.text = "Your friend code: %s" % str(me.get("friend_code", ""))
	code.add_theme_font_size_override("font_size", 24)
	code.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	root.add_child(code)


	_add_bottom_nav("friends")


func _show_sent() -> void:
	if not _guard_private_chest():
		return
	# Leaving/rebuilding Sent clears any previously revealed passwords from memory.
	_clear_reveal_timers()
	state.clear_revealed_passwords()
	_current_screen = "sent"
	_clear_screen()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_right = -32
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	_screen_host.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Sent Scrolls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	header.add_child(title)
	header.add_child(_make_button("Back", func() -> void:
		_clear_reveal_timers()
		state.clear_revealed_passwords()
		_show_main_chest()
	, Vector2(160, 64)))
	var sent_items: Array = []
	if state.is_demo():
		sent_items = state.demo.get_sent_scrolls()
	elif state.is_online():
		var sent_result: Dictionary = await state.scrolls.get_sent_scrolls()
		if bool(sent_result.get("ok", false)):
			var data: Dictionary = sent_result.get("data", {}) if typeof(sent_result.get("data")) == TYPE_DICTIONARY else {}
			state.cached_sent = data
			sent_items = data.get("sent_scrolls", []) if typeof(data.get("sent_scrolls")) == TYPE_ARRAY else []
		else:
			_show_toast(str(sent_result.get("error", "Could not load sent scrolls.")))
	if sent_items.is_empty():
		var empty := Label.new()
		empty.text = "No sent scrolls."
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color(0.85, 0.8, 0.9))
		root.add_child(empty)
	else:
		for s in sent_items:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var panel := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.12, 0.08, 0.16, 0.92)
			style.set_corner_radius_all(14)
			style.content_margin_left = 16
			style.content_margin_right = 16
			style.content_margin_top = 12
			style.content_margin_bottom = 12
			panel.add_theme_stylebox_override("panel", style)
			var col := VBoxContainer.new()
			panel.add_child(col)
			var recipient: Dictionary = s.get("recipient", {}) if typeof(s.get("recipient")) == TYPE_DICTIONARY else {}
			var unlock_at := str(s.get("unlock_at", ""))
			var unlock_unix := int(s.get("unlock_at_unix", 0))
			if unlock_unix == 0 and not unlock_at.is_empty():
				unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))
			var row := Label.new()
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.text = "%s → %s · opens %s · opened=%d" % [
				str(s.get("title", "")),
				str(s.get("recipient_display_name", recipient.get("display_name", ""))),
				Time.get_datetime_string_from_unix_time(unlock_unix, false) if unlock_unix > 0 else unlock_at,
				int(s.get("opened_count", 0)),
			]
			row.add_theme_font_size_override("font_size", 22)
			row.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95))
			col.add_child(row)
			var sid := str(s.get("id", ""))
			var has_pw := bool(s.get("has_password", false))
			if has_pw:
				col.add_child(_build_sent_password_reveal_row(sid, s))
			col.add_child(_make_button("Hide from Sent", func() -> void:
				if state.is_demo():
					var result := state.demo.delete_sent_scroll(sid)
					if bool(result.get("ok", false)):
						_show_toast("Hidden from your Sent history")
						_show_sent()
					else:
						_show_toast(str(result.get("error", "Could not hide sent scroll.")))
				elif state.is_online():
					var result: Dictionary = await state.scrolls.delete_sent_scroll(sid)
					if bool(result.get("ok", false)):
						_show_toast("Hidden from your Sent history")
						_show_sent()
					else:
						_show_toast(str(result.get("error", "Could not hide sent scroll.")))
				else:
					_show_toast("Backend is not configured.")
			, Vector2(240, 56)))
			root.add_child(panel)
	_add_bottom_nav("sent")


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
	var card := _make_card()
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = MobileUi.font_touch(56)
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileUi.apply_label(lab, MobileUi.SIZE_BODY, MobileUi.COLOR_BODY)
	row.add_child(lab)
	row.add_child(value_control)
	return card


func _settings_value_label(text: String) -> Label:
	var v := Label.new()
	v.text = text
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MobileUi.apply_label(v, MobileUi.SIZE_SECONDARY, MobileUi.COLOR_SECONDARY)
	return v


func _show_profile() -> void:
	_current_screen = "profile"
	_clear_screen()
	var root := _make_screen_root(MobileUi.font_touch(MobileUi.TOUCH_NAV_H) + 8)
	var title := Label.new()
	title.text = "Profile"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MobileUi.apply_label(title, MobileUi.SIZE_SCREEN_TITLE, MobileUi.COLOR_TITLE)
	if _title_font():
		title.add_theme_font_override("font", _title_font())
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	var me: Dictionary = {}
	if state.is_demo():
		me = state.demo.get_profile()
	elif state.is_online() and state.tokens.has_session():
		var pref: Dictionary = await state.profiles.fetch_own_profile()
		if bool(pref.get("ok", false)) and bool(pref.get("exists", false)):
			me = state.profiles.profile

	var section := Label.new()
	section.text = "ACCOUNT"
	MobileUi.apply_label(section, MobileUi.SIZE_SECTION, MobileUi.COLOR_TITLE)
	col.add_child(section)
	col.add_child(_settings_row("Display Name", _settings_value_label(str(me.get("display_name", "—")))))
	col.add_child(_settings_row("Username", _settings_value_label("@" + str(me.get("username", "—")))))
	col.add_child(_settings_row("Email", _settings_value_label(str(state.tokens.user_email if state.tokens.user_email != "" else "—"))))
	col.add_child(_settings_row("Friend Code", _settings_value_label(str(me.get("friend_code", "—")))))
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
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-360, -300)
	box.size = Vector2(720, 600)
	box.add_theme_constant_override("separation", 12)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	box.add_child(title)
	for line in lines:
		var lab := Label.new()
		lab.text = str(line)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 24)
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
	if state.is_online() and state.tokens.has_session():
		var resumed: Dictionary = await state.revalidate_on_resume()
		if not bool(resumed.get("ok", false)):
			_show_toast(str(resumed.get("message", "Your session has expired. Please sign in again.")))
			_show_welcome()
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
