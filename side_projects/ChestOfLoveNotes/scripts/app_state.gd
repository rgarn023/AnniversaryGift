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


func _init() -> void:
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
	# Private onboarding APK must use the real backend — never fall back to demo.
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
	# Clears sensitive state synchronously; remote logout continues in background.
	auth.sign_out()
	membership.clear()
	profiles.clear()
	clear_open_message()
	clear_revealed_passwords()
	clear_private_caches()
	pending_confirm_email = ""
	session_restore_message = ""
	demo.clear_sensitive()


func restore_session_if_possible() -> Dictionary:
	## Startup restore: secure storage → refresh if needed → membership → profile.
	session_restore_message = ""
	if not is_online():
		return {"ok": false, "reason": "not_online"}
	if not tokens.restore_from_secure_storage():
		return {"ok": false, "reason": "no_session"}
	var fresh: Dictionary = await auth.ensure_fresh_access()
	if not bool(fresh.get("ok", false)):
		tokens.clear(true)
		session_restore_message = "Your session has expired. Please sign in again."
		return {"ok": false, "reason": "refresh_failed", "message": session_restore_message}
	var user_result: Dictionary = await auth.refresh_user()
	if not bool(user_result.get("ok", false)) or not tokens.email_confirmed:
		tokens.clear(true)
		session_restore_message = "Your session has expired. Please sign in again."
		return {"ok": false, "reason": "user_invalid", "message": session_restore_message}
	var claim: Dictionary = await membership.claim_membership()
	if not bool(claim.get("ok", false)) or not membership.is_member:
		sign_out()
		session_restore_message = "This is a private app, and this account is not approved."
		return {"ok": false, "reason": "membership_denied", "message": session_restore_message}
	var profile_result: Dictionary = await profiles.fetch_own_profile()
	if not bool(profile_result.get("ok", false)):
		sign_out()
		session_restore_message = "Your session has expired. Please sign in again."
		return {"ok": false, "reason": "profile_failed", "message": session_restore_message}
	tokens.persist_if_needed()
	return {
		"ok": true,
		"profile_exists": bool(profile_result.get("exists", false)),
	}


func backend_host() -> String:
	if not config.is_configured():
		return ""
	var u := config.supabase_url
	# Host only — never include keys.
	if u.begins_with("https://"):
		u = u.substr(8)
	elif u.begins_with("http://"):
		u = u.substr(7)
	var slash := u.find("/")
	if slash >= 0:
		u = u.substr(0, slash)
	return u


func diagnostics_snapshot() -> Dictionary:
	return {
		"backend_configured": config.is_configured(),
		"backend_host": backend_host(),
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
	}
