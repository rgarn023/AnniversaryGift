extends RefCounted
class_name AuthService
## Live Supabase email/password auth. Never logs passwords or tokens.

var api: ApiClient
var config: BackendConfig
var tokens: SecureTokenService
var _resend_cooldown_until: int = 0


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
	# Supabase may return a user with empty identities when email confirmation is required,
	# or a session when confirmation is disabled.
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
		tokens.clear()
		return {"ok": false, "error": str(user_result.get("error", "Could not load user."))}
	if not tokens.email_confirmed:
		tokens.clear()
		return {
			"ok": false,
			"error": "Please confirm your email before signing in.",
			"needs_confirmation": true,
		}
	return {"ok": true, "error": "", "user_id": tokens.user_id}


func refresh_session() -> Dictionary:
	if tokens.refresh_token.is_empty():
		return {"ok": false, "error": "No refresh token in memory."}
	var url := "%s/auth/v1/token?grant_type=refresh_token" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(
		url,
		"POST",
		{"refresh_token": tokens.refresh_token},
		false
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "Session refresh failed."))}
	var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	var access := str(data.get("access_token", ""))
	if access.is_empty():
		return {"ok": false, "error": "Refresh did not return an access token."}
	tokens.set_session(
		access,
		str(data.get("refresh_token", tokens.refresh_token)),
		int(Time.get_unix_time_from_system()) + int(data.get("expires_in", 3600))
	)
	await refresh_user()
	return {"ok": true}


func ensure_fresh_access() -> Dictionary:
	if not tokens.has_session():
		return {"ok": false, "error": "Not signed in."}
	if tokens.is_expired():
		return await refresh_session()
	return {"ok": true}


func refresh_user() -> Dictionary:
	if not tokens.has_session():
		return {"ok": false, "error": "Not signed in."}
	var url := "%s/auth/v1/user" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(url, "GET", {}, true)
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


func sign_out() -> void:
	tokens.clear()
