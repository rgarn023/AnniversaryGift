extends Node
class_name AppState
## Global app mode and services for Chest of Love Notes.

enum Mode { UNCONFIGURED, LOCAL_DEMO, ONLINE }

var mode: Mode = Mode.UNCONFIGURED
var config: BackendConfig = BackendConfig.new()
var tokens: SecureTokenService = SecureTokenService.new()
var api: ApiClient
var auth: AuthService
var membership: MembershipService
var profiles: ProfileService
var scrolls: ScrollService
var friends: FriendService
var demo: DemoSession = DemoSession.new()
var reduced_motion: bool = false
## Ephemeral plaintext held only while a scroll viewer is open.
var open_message_plaintext: String = ""
var pending_confirm_email: String = ""
var cached_chest: Dictionary = {}
var cached_saved: Dictionary = {}
var cached_sent: Dictionary = {}
var cached_friends: Dictionary = {}

## Ephemeral revealed Magic Passwords keyed by scroll_id (never persisted).
var revealed_magic_passwords: Dictionary = {}
var session_restore_message: String = ""
var last_persist_warning: String = ""
var debug_session_trace: Dictionary = {}


func _init() -> void:
	MobileUi.ensure_loaded()
	reduced_motion = MobileUi.reduced_motion()
	api = ApiClient.new(config, tokens)
	auth = AuthService.new(api, config, tokens)
	api.auth = auth
	membership = MembershipService.new(api, tokens)
	profiles = ProfileService.new(api, tokens)
	scrolls = ScrollService.new(api)
	friends = FriendService.new(api)


func bootstrap() -> void:
	var is_release := OS.has_feature("release") or not OS.is_debug_build()
	if config.load_config():
		mode = Mode.ONLINE
		demo.disable()
		return
	if BuildFlags.PRIVATE_ONBOARDING_BUILD:
		mode = Mode.UNCONFIGURED
		demo.disable()
		return
	if is_release:
		mode = Mode.UNCONFIGURED
		demo.disable()
		return
	mode = Mode.LOCAL_DEMO
	demo.enable()


func is_demo() -> bool:
	return mode == Mode.LOCAL_DEMO


func is_online() -> bool:
	return mode == Mode.ONLINE


func is_private_onboarding_build() -> bool:
	return BuildFlags.PRIVATE_ONBOARDING_BUILD


func show_sign_up() -> bool:
	return is_online() and BuildFlags.PRIVATE_ONBOARDING_BUILD


func clear_open_message() -> void:
	open_message_plaintext = ""


func clear_revealed_passwords() -> void:
	revealed_magic_passwords.clear()


func clear_private_caches() -> void:
	cached_chest.clear()
	cached_saved.clear()
	cached_sent.clear()
	cached_friends.clear()


func sign_out() -> void:
	auth.sign_out()
	membership.clear()
	profiles.clear()
	clear_open_message()
	clear_revealed_passwords()
	clear_private_caches()
	pending_confirm_email = ""
	session_restore_message = ""
	last_persist_warning = ""
	demo.clear_sensitive()


func sign_out_full() -> void:
	await auth.logout_remote()
	sign_out()


func maybe_warn_persist_failure() -> String:
	last_persist_warning = ""
	if tokens.keep_me_signed_in and tokens.last_persist_error != "":
		last_persist_warning = (
			"Secure sign-in storage is unavailable. "
			+ "You’ll need to sign in again after closing the app."
		)
		return last_persist_warning
	return ""


func persist_session_verified() -> Dictionary:
	## Call after successful sign-in + membership. Hard-checks Keystore write.
	var ok := tokens.persist_if_needed()
	var has := AndroidSecureStore.has_session()
	debug_session_trace = _plugin_trace()
	debug_session_trace["persist_ok"] = ok
	debug_session_trace["has_session_after_persist"] = has
	if tokens.keep_me_signed_in and (not ok or not has):
		return {
			"ok": false,
			"error": tokens.last_persist_error if tokens.last_persist_error != "" else "persist_failed",
			"warning": maybe_warn_persist_failure(),
		}
	return {"ok": true, "persisted": ok and has}


func _plugin_trace() -> Dictionary:
	var on_android := OS.get_name() == "Android"
	return {
		"plugin_found": on_android and Engine.has_singleton(AndroidSecureStore.PLUGIN_NAME),
		"secure_available": AndroidSecureStore.is_available(),
		"secure_has_session": AndroidSecureStore.has_session(),
		"keep_me_signed_in": tokens.keep_me_signed_in,
		"os": OS.get_name(),
	}


func restore_session_if_possible() -> Dictionary:
	## Startup restore. Soft network failures do NOT delete Keystore ciphertext.
	session_restore_message = ""
	tokens.session_refresh_performed = false
	debug_session_trace = _plugin_trace()
	if not is_online():
		return {"ok": false, "reason": "not_online"}
	if not tokens.restore_from_secure_storage():
		for k in tokens.debug_restore_trace.keys():
			debug_session_trace[k] = tokens.debug_restore_trace[k]
		return {"ok": false, "reason": "no_session"}
	debug_session_trace["decrypt_ok"] = tokens.last_decrypt_ok
	debug_session_trace["session_restored"] = true

	var needed_refresh := tokens.is_expired() or tokens.access_token.is_empty()
	var fresh: Dictionary = await auth.ensure_fresh_access()
	debug_session_trace["refresh_attempted"] = needed_refresh or tokens.session_refresh_performed
	debug_session_trace["refresh_succeeded"] = bool(fresh.get("ok", false))
	if not bool(fresh.get("ok", false)):
		var invalid := bool(fresh.get("invalid_session", false))
		if invalid:
			tokens.clear(true) # definitive auth failure
			session_restore_message = "Your session has expired. Please sign in again."
			return {"ok": false, "reason": "refresh_invalid", "message": session_restore_message}
		# Soft/network failure — keep Keystore for next launch.
		tokens.clear(false)
		session_restore_message = "Could not reach the server. Please try again."
		return {"ok": false, "reason": "refresh_soft_fail", "message": session_restore_message}

	var user_result: Dictionary = await auth.refresh_user()
	debug_session_trace["user_ok"] = bool(user_result.get("ok", false))
	if not bool(user_result.get("ok", false)):
		var status := int(api.last_http_status)
		if status == 401 or status == 403:
			tokens.clear(true)
			session_restore_message = "Your session has expired. Please sign in again."
			return {"ok": false, "reason": "user_invalid", "message": session_restore_message}
		tokens.clear(false)
		session_restore_message = "Could not verify your account. Please try again."
		return {"ok": false, "reason": "user_soft_fail", "message": session_restore_message}
	if not tokens.email_confirmed:
		tokens.clear(true)
		session_restore_message = "Please confirm your email, then sign in."
		return {"ok": false, "reason": "email_unconfirmed", "message": session_restore_message}

	var claim: Dictionary = await membership.claim_membership()
	debug_session_trace["membership_revalidated"] = bool(claim.get("ok", false)) and membership.is_member
	if not bool(claim.get("ok", false)) or not membership.is_member:
		# Membership denial is definitive for this account.
		sign_out()
		session_restore_message = "This is a private app, and this account is not approved."
		return {"ok": false, "reason": "membership_denied", "message": session_restore_message}

	var profile_result: Dictionary = await profiles.fetch_own_profile()
	debug_session_trace["profile_loaded"] = bool(profile_result.get("ok", false))
	if not bool(profile_result.get("ok", false)):
		var status2 := int(api.last_http_status)
		if status2 == 401 or status2 == 403:
			sign_out()
			session_restore_message = "Your session has expired. Please sign in again."
			return {"ok": false, "reason": "profile_invalid", "message": session_restore_message}
		tokens.clear(false)
		session_restore_message = "Could not load your profile. Please try again."
		return {"ok": false, "reason": "profile_soft_fail", "message": session_restore_message}

	# Persist rotated tokens after successful restore.
	tokens.persist_if_needed()
	return {
		"ok": true,
		"profile_exists": bool(profile_result.get("exists", false)),
		"session_restored": tokens.session_restored,
		"session_refresh_performed": tokens.session_refresh_performed,
	}


func revalidate_on_resume() -> Dictionary:
	if not is_online() or not tokens.has_session():
		return {"ok": false, "reason": "not_signed_in"}
	var fresh: Dictionary = await auth.ensure_fresh_access()
	if not bool(fresh.get("ok", false)):
		if bool(fresh.get("invalid_session", false)):
			sign_out()
			session_restore_message = "Your session has expired. Please sign in again."
			return {"ok": false, "reason": "refresh_failed", "message": session_restore_message}
		return {"ok": false, "reason": "refresh_soft_fail", "message": "Could not refresh session."}
	var claim: Dictionary = await membership.claim_membership()
	if not bool(claim.get("ok", false)) or not membership.is_member:
		sign_out()
		session_restore_message = "Your session has expired. Please sign in again."
		return {"ok": false, "reason": "membership_denied", "message": session_restore_message}
	tokens.persist_if_needed()
	return {"ok": true}


func backend_host() -> String:
	if not config.is_configured():
		return ""
	var u := config.supabase_url
	if u.begins_with("https://"):
		u = u.substr(8)
	elif u.begins_with("http://"):
		u = u.substr(7)
	var slash := u.find("/")
	if slash >= 0:
		u = u.substr(0, slash)
	return u


func diagnostics_snapshot() -> Dictionary:
	var trace: Dictionary = debug_session_trace.duplicate()
	return {
		"backend_configured": config.is_configured(),
		"backend_host": backend_host(),
		"secure_plugin_found": bool(trace.get("plugin_found", Engine.has_singleton(AndroidSecureStore.PLUGIN_NAME) if OS.get_name() == "Android" else false)),
		"secure_storage_available": AndroidSecureStore.is_available(),
		"saved_session_exists": AndroidSecureStore.has_session(),
		"session_decrypt_ok": bool(trace.get("decrypt_ok", tokens.last_decrypt_ok)),
		"session_restored": tokens.session_restored,
		"session_refresh_performed": tokens.session_refresh_performed,
		"refresh_attempted": bool(trace.get("refresh_attempted", tokens.session_refresh_performed)),
		"refresh_succeeded": bool(trace.get("refresh_succeeded", false)),
		"membership_revalidated": bool(trace.get("membership_revalidated", membership.is_member)),
		"profile_loaded": bool(trace.get("profile_loaded", not profiles.profile.is_empty())),
		"keep_me_signed_in": tokens.keep_me_signed_in,
		"memory_only": tokens.memory_only,
		"last_persist_error": tokens.last_persist_error,
		"signed_in": tokens.has_session(),
		"email_confirmed": tokens.email_confirmed,
		"membership_approved": membership.is_member,
		"private_role": membership.role,
		"profile_exists": not profiles.profile.is_empty(),
		"last_function": api.last_function_name,
		"last_http_status": api.last_http_status,
		"last_safe_error": api.last_safe_error,
		"private_onboarding_build": BuildFlags.PRIVATE_ONBOARDING_BUILD,
		"demo_disabled": not is_demo(),
		"text_size": MobileUi.text_size_label(),
		"reduced_motion": MobileUi.reduced_motion(),
		"storage_version": AndroidSecureStore.storage_version(),
	}
