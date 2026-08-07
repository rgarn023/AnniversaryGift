extends RefCounted
class_name AuthService
## Live Supabase email/password auth with single-flight refresh + secure persist.
## Never logs passwords or tokens. Never stores the account password.

var api: ApiClient
var config: BackendConfig
var tokens: SecureTokenService
var _resend_cooldown_until: int = 0
var _is_refreshing: bool = false


func _init(p_api: ApiClient, p_config: BackendConfig, p_tokens: SecureTokenService) -> void:
	api = p_api
	config = p_config
	tokens = p_tokens


func sign_up(email: String, password: String, confirm_password: String) -> Dictionary:
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured.", "needs_confirmation": false}
	var e := email.strip_edges().to_lower()
	if e.is_empty() or not e.contains("@"):
		return {"ok": false, "error": "Enter a valid email address.", "needs_confirmation": false}
	if password.length() < 8:
		return {"ok": false, "error": "Password must be at least 8 characters.", "needs_confirmation": false}
	if password != confirm_password:
		return {"ok": false, "error": "Passwords do not match.", "needs_confirmation": false}
	var url := "%s/auth/v1/signup" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(url, "POST", {"email": e, "password": password}, false)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"error": str(result.get("error", "Sign up failed.")),
			"needs_confirmation": false,
			"status": int(result.get("status", 0)),
		}
	var data: Variant = result.get("data", {})
	var has_session := false
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		has_session = not str(d.get("access_token", "")).is_empty()
		if has_session:
			tokens.set_session(
				str(d.get("access_token", "")),
				str(d.get("refresh_token", "")),
				int(Time.get_unix_time_from_system()) + int(d.get("expires_in", 3600))
			)
			await refresh_user()
	return {
		"ok": true,
		"needs_confirmation": not has_session,
		"error": "",
		"status": int(result.get("status", 200)),
	}


func sign_in(email: String, password: String) -> Dictionary:
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	var e := email.strip_edges().to_lower()
	if e.is_empty() or password.is_empty():
		return {"ok": false, "error": "Email and password are required."}
	var url := "%s/auth/v1/token?grant_type=password" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(url, "POST", {"email": e, "password": password}, false)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"error": str(result.get("error", "Sign in failed.")),
			"status": int(result.get("status", 0)),
		}
	var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	var access := str(data.get("access_token", ""))
	if access.is_empty():
		return {"ok": false, "error": "Sign in did not return a session."}
	tokens.set_session(
		access,
		str(data.get("refresh_token", "")),
		int(Time.get_unix_time_from_system()) + int(data.get("expires_in", 3600))
	)
	var user_result := await refresh_user()
	if not bool(user_result.get("ok", false)):
		tokens.clear(true)
		return {"ok": false, "error": str(user_result.get("error", "Could not load user."))}
	if not tokens.email_confirmed:
		tokens.clear(true)
		return {
			"ok": false,
			"error": "Please confirm your email before signing in.",
			"needs_confirmation": true,
		}
	# Persistence is verified after membership in the UI layer.
	return {"ok": true, "error": "", "user_id": tokens.user_id}


func refresh_session() -> Dictionary:
	## Single-flight refresh with refresh-token rotation persistence.
	if tokens.refresh_token.is_empty():
		return {"ok": false, "error": "No refresh token in memory.", "invalid_session": true}
	if _is_refreshing:
		while _is_refreshing:
			await Engine.get_main_loop().process_frame
		if tokens.has_session() and not tokens.is_expired():
			return {"ok": true}
		return {"ok": false, "error": "Session refresh failed.", "invalid_session": true}

	_is_refreshing = true
	var url := "%s/auth/v1/token?grant_type=refresh_token" % config.supabase_url.rstrip("/")
	var used_refresh := tokens.refresh_token
	var result: Dictionary = await api.request(
		url,
		"POST",
		{"refresh_token": used_refresh},
		false,
		"",
		false
	)
	var out: Dictionary = {"ok": false, "error": "Session refresh failed.", "invalid_session": false}
	if bool(result.get("ok", false)):
		var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
		var access := str(data.get("access_token", ""))
		var new_refresh := str(data.get("refresh_token", ""))
		if access.is_empty():
			out = {"ok": false, "error": "Refresh did not return an access token.", "invalid_session": true}
		else:
			# Always replace with newly returned refresh token when present (rotation).
			if new_refresh.is_empty():
				new_refresh = used_refresh
			tokens.set_session(
				access,
				new_refresh,
				int(Time.get_unix_time_from_system()) + int(data.get("expires_in", 3600))
			)
			await refresh_user()
			tokens.persist_if_needed()
			out = {"ok": true}
	else:
		var status := int(result.get("status", 0))
		var invalid := status == 400 or status == 401 or status == 403
		out = {
			"ok": false,
			"error": str(result.get("error", "Session refresh failed.")),
			"invalid_session": invalid,
		}
		if invalid:
			tokens.clear(true)

	_is_refreshing = false
	return out


func ensure_fresh_access() -> Dictionary:
	if not tokens.has_session() and tokens.refresh_token.is_empty():
		return {"ok": false, "error": "Not signed in.", "invalid_session": true}
	if tokens.is_expired(SecureTokenService.EXPIRY_SKEW_SEC) or tokens.access_token.is_empty():
		var refreshed := await refresh_session()
		if bool(refreshed.get("ok", false)):
			tokens.session_refresh_performed = true
		return refreshed
	return {"ok": true}


func refresh_user() -> Dictionary:
	if not tokens.has_session():
		return {"ok": false, "error": "Not signed in."}
	var url := "%s/auth/v1/user" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(url, "GET", {}, true, "", false)
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "Could not load user."))}
	var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	var uid := str(data.get("id", ""))
	var email := str(data.get("email", "")).strip_edges().to_lower()
	var confirmed := false
	if data.get("email_confirmed_at") != null and str(data.get("email_confirmed_at", "")) != "":
		confirmed = true
	elif data.get("confirmed_at") != null and str(data.get("confirmed_at", "")) != "":
		confirmed = true
	if uid.is_empty():
		return {"ok": false, "error": "User payload missing id."}
	tokens.set_user(uid, email, confirmed)
	return {"ok": true, "user_id": uid, "email": email, "email_confirmed": confirmed}


func resend_confirmation(email: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	if now < _resend_cooldown_until:
		var wait := _resend_cooldown_until - now
		return {"ok": false, "error": "Please wait %d seconds before resending." % wait}
	var e := email.strip_edges().to_lower()
	if e.is_empty():
		return {"ok": false, "error": "Email is required."}
	var url := "%s/auth/v1/resend" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(
		url,
		"POST",
		{"type": "signup", "email": e},
		false
	)
	_resend_cooldown_until = now + 60
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "Could not resend confirmation."))}
	return {"ok": true, "error": ""}


func logout_remote() -> void:
	## Best-effort Supabase logout. Never blocks local sign-out correctness.
	if not config.is_configured() or tokens.access_token.is_empty():
		return
	var url := "%s/auth/v1/logout" % config.supabase_url.rstrip("/")
	await api.request(url, "POST", {}, true, "", false)


func sign_out() -> void:
	## Clears in-memory tokens and Android Keystore-backed session storage.
	## Account password is never stored and therefore never wiped from disk here.
	tokens.clear(true)
