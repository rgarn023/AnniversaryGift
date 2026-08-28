extends RefCounted
class_name AuthService
## Live Supabase email/password + Google OAuth auth with single-flight refresh + secure persist.
## Never logs passwords or tokens. Never stores the account password.

const AUTH_REDIRECT_URI := "com.charoitegames.chestoflovenotes://auth-callback"
const PASSWORD_RESET_GENERIC_MSG := (
	"If an account exists for that email, a password reset link has been sent."
)
const MIN_PASSWORD_LEN := 8
const OAUTH_STATE_VERSION := 1
const OAUTH_STATE_TTL_SEC := 10 * 60

var api: ApiClient
var config: BackendConfig
var tokens: SecureTokenService
var _resend_cooldown_until: int = 0
var _is_refreshing: bool = false
var _last_refresh_result: Dictionary = {"ok": false, "error": "Session refresh failed.", "invalid_session": false}

## OAuth callback state. The PKCE verifier/mode are mirrored into encrypted
## Android Keystore-backed transient storage so browser OAuth survives process death.
var _oauth_code_verifier: String = ""
var _oauth_mode: String = "" ## "signin" | "link" | ""
var _oauth_started_at_unix: int = 0
var _callback_processing: bool = false
var _last_callback_fp: String = ""
var recovery_session_active: bool = false
## Provider ids from last successful /auth/v1/user payload (e.g. email, google).
var linked_providers: PackedStringArray = PackedStringArray()


func _init(p_api: ApiClient, p_config: BackendConfig, p_tokens: SecureTokenService) -> void:
	api = p_api
	config = p_config
	tokens = p_tokens


func redirect_uri() -> String:
	return AUTH_REDIRECT_URI


func is_valid_email_syntax(email: String) -> bool:
	return AuthCallbackParser.is_valid_email_syntax(email)


func sign_up(email: String, password: String, confirm_password: String) -> Dictionary:
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured.", "needs_confirmation": false}
	var e := email.strip_edges().to_lower()
	if e.is_empty() or not e.contains("@"):
		return {"ok": false, "error": "Enter a valid email address.", "needs_confirmation": false}
	if password.length() < MIN_PASSWORD_LEN:
		return {"ok": false, "error": "Password must be at least %d characters." % MIN_PASSWORD_LEN, "needs_confirmation": false}
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


func request_password_reset(email: String) -> Dictionary:
	## Always returns the same generic success copy when the request is accepted
	## or when the account may or may not exist — no account enumeration.
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured.", "generic_success": false}
	var e := email.strip_edges().to_lower()
	if not is_valid_email_syntax(e):
		return {"ok": false, "error": "Enter a valid email address.", "generic_success": false}
	## Supabase GoTrue treats redirect_to as a query option for /recover.
	var url := "%s/auth/v1/recover?redirect_to=%s" % [
		config.supabase_url.rstrip("/"),
		AUTH_REDIRECT_URI.uri_encode(),
	]
	var result: Dictionary = await api.request(url, "POST", {"email": e}, false)
	## GoTrue commonly returns 200 even when the email is unknown.
	## On transport/config failure, surface a real error; otherwise generic success.
	if not bool(result.get("ok", false)):
		var status := int(result.get("status", 0))
		if status == 429:
			return {"ok": false, "error": "Please wait a moment before requesting another reset email.", "generic_success": false}
		if status == 0:
			return {"ok": false, "error": "No internet connection. Check your network and try again.", "generic_success": false}
		## Do not reveal whether the address is registered.
		return {"ok": true, "error": "", "message": PASSWORD_RESET_GENERIC_MSG, "generic_success": true}
	return {"ok": true, "error": "", "message": PASSWORD_RESET_GENERIC_MSG, "generic_success": true}


func update_password(new_password: String, confirm_password: String) -> Dictionary:
	## Local validation first (no network) — never logs password values.
	if new_password.length() < MIN_PASSWORD_LEN:
		return {"ok": false, "error": "Password must be at least %d characters." % MIN_PASSWORD_LEN}
	if new_password != confirm_password:
		return {"ok": false, "error": "Passwords do not match."}
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	if not tokens.has_session():
		return {"ok": false, "error": "Not signed in.", "expired": true}
	var url := "%s/auth/v1/user" % config.supabase_url.rstrip("/")
	var result: Dictionary = await api.request(url, "PUT", {"password": new_password}, true, "", false)
	if not bool(result.get("ok", false)):
		var status := int(result.get("status", 0))
		var expired := status == 401 or status == 403
		var err := str(result.get("error", "Could not update password."))
		if expired:
			err = "This password reset session has expired. Request a new reset email."
		return {"ok": false, "error": err, "expired": expired, "status": status}
	recovery_session_active = false
	var user_result := await refresh_user()
	if not bool(user_result.get("ok", false)):
		return {"ok": false, "error": str(user_result.get("error", "Password updated, but user refresh failed."))}
	tokens.persist_if_needed()
	return {"ok": true, "error": "", "user_id": tokens.user_id}


func begin_google_sign_in() -> Dictionary:
	## Builds a PKCE authorize URL. Caller opens the system browser.
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	_oauth_code_verifier = _generate_code_verifier()
	_oauth_mode = "signin"
	_oauth_started_at_unix = int(Time.get_unix_time_from_system())
	if not _persist_oauth_state():
		cancel_oauth()
		return {"ok": false, "error": "Secure Google sign-in storage is unavailable. Restart the app and try again."}
	var challenge := _code_challenge_s256(_oauth_code_verifier)
	var redirect_enc := AUTH_REDIRECT_URI.uri_encode()
	var url := (
		"%s/auth/v1/authorize?provider=google&redirect_to=%s&code_challenge=%s&code_challenge_method=s256"
		% [config.supabase_url.rstrip("/"), redirect_enc, challenge.uri_encode()]
	)
	return {
		"ok": true,
		"url": url,
		"redirect_uri": AUTH_REDIRECT_URI,
		"provider": "google",
		"error": "",
	}


func begin_link_google() -> Dictionary:
	## Explicit identity link for an already signed-in email/password user.
	## Uses Supabase's supported identities/authorize endpoint only; never falls
	## back to ordinary sign-in because that could switch to another user UUID.
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	if not tokens.has_session():
		return {"ok": false, "error": "Not signed in."}
	if has_google_provider():
		return {"ok": false, "error": "Google is already linked to this account.", "already_linked": true}
	_oauth_code_verifier = _generate_code_verifier()
	_oauth_mode = "link"
	_oauth_started_at_unix = int(Time.get_unix_time_from_system())
	if not _persist_oauth_state():
		cancel_oauth()
		return {"ok": false, "error": "Secure Google linking storage is unavailable. Restart the app and try again."}
	var challenge := _code_challenge_s256(_oauth_code_verifier)
	var redirect_enc := AUTH_REDIRECT_URI.uri_encode()
	var url := (
		"%s/auth/v1/user/identities/authorize?provider=google&redirect_to=%s&code_challenge=%s&code_challenge_method=s256&skip_http_redirect=true"
		% [config.supabase_url.rstrip("/"), redirect_enc, challenge.uri_encode()]
	)
	## Supabase's official linkIdentity clients use the signed-in user's bearer
	## for this endpoint. Allow one refresh/retry if that bearer expired between
	## opening Account & Security and tapping Link Google Account.
	var result: Dictionary = await api.request(url, "GET", {}, true, "", true)
	if not bool(result.get("ok", false)):
		var status := int(result.get("status", 0))
		var safe_error := str(result.get("error", "")).strip_edges()
		cancel_oauth()
		if status == 0:
			return {"ok": false, "error": "No internet connection. Check your network and try again."}
		if status == 401 or status == 403:
			return {
				"ok": false,
				"error": "Your sign-in session expired. Sign in again, then retry Link Google Account.",
				"status": status,
			}
		var lowered := safe_error.to_lower()
		if lowered.contains("manual") and lowered.contains("link"):
			return {
				"ok": false,
				"error": "Google account linking is unavailable. Enable manual identity linking in Supabase Auth settings and try again.",
				"setup_required": true,
				"status": status,
			}
		if safe_error.is_empty():
			safe_error = "Request failed (%d)." % status
		return {
			"ok": false,
			"error": "Could not start Google account linking: %s" % safe_error,
			"status": status,
		}
	var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	var link_url := str(data.get("url", "")).strip_edges()
	if link_url.is_empty():
		link_url = str(data.get("provider_url", "")).strip_edges()
	if link_url.is_empty():
		cancel_oauth()
		return {
			"ok": false,
			"error": "Supabase did not return a Google linking URL. Verify the Google provider is enabled and try again.",
			"setup_required": true,
		}
	return {"ok": true, "url": link_url, "redirect_uri": AUTH_REDIRECT_URI, "mode": "link", "error": ""}


func cancel_oauth() -> void:
	_oauth_code_verifier = ""
	_oauth_mode = ""
	_oauth_started_at_unix = 0
	AndroidSecureStore.delete_oauth_state()


func handle_auth_callback_uri(uri: String) -> Dictionary:
	## Single-flight callback consumer. Terminal callbacks are explicitly cleared;
	## transient network failures remain pending for another resume/retry.
	if _callback_processing:
		return {"ok": false, "error": "Sign-in is already being processed.", "duplicate": true}
	var fp := AuthCallbackParser.fingerprint(uri)
	if not fp.is_empty() and fp == _last_callback_fp:
		AuthDeepLinkHelper.clear_pending_auth_callback()
		return {"ok": false, "error": "This sign-in link was already used.", "duplicate": true, "dead": true}

	_callback_processing = true
	var parsed: Dictionary = AuthCallbackParser.parse(uri)
	if not bool(parsed.get("ok", false)):
		_last_callback_fp = fp
		AuthDeepLinkHelper.clear_pending_auth_callback()
		cancel_oauth()
		_callback_processing = false
		if bool(parsed.get("cancelled", false)):
			return {
				"ok": false,
				"cancelled": true,
				"error": str(parsed.get("error", "Google sign-in was cancelled.")),
				"flow": str(parsed.get("flow", "")),
			}
		return {
			"ok": false,
			"error": str(parsed.get("error", "Invalid auth callback.")),
			"expired": bool(parsed.get("expired", false)),
			"flow": str(parsed.get("flow", "")),
			"error_code": str(parsed.get("error_code", "")),
		}

	var flow := str(parsed.get("flow", ""))
	var out: Dictionary = {"ok": false, "error": "Session exchange failed."}
	if flow == AuthCallbackParser.FLOW_RECOVERY or (
		not str(parsed.get("access_token", "")).is_empty()
		and str(parsed.get("type", "")).to_lower() == "recovery"
	):
		out = await _apply_token_session(parsed, true)
		if bool(out.get("ok", false)):
			out["flow"] = AuthCallbackParser.FLOW_RECOVERY
			out["needs_password_reset"] = true
	elif not str(parsed.get("code", "")).is_empty():
		out = await _exchange_pkce_code(str(parsed.get("code", "")))
		if bool(out.get("ok", false)):
			out["flow"] = AuthCallbackParser.FLOW_OAUTH
			out["mode"] = _oauth_mode if not _oauth_mode.is_empty() else "signin"
	elif not str(parsed.get("access_token", "")).is_empty():
		out = await _apply_token_session(parsed, false)
		if bool(out.get("ok", false)):
			out["flow"] = AuthCallbackParser.FLOW_OAUTH
			out["mode"] = _oauth_mode if not _oauth_mode.is_empty() else "signin"
	else:
		out = {"ok": false, "error": "Auth callback could not be understood.", "flow": flow}

	var terminal := not bool(out.get("retryable", false))
	if terminal:
		_last_callback_fp = fp
		AuthDeepLinkHelper.clear_pending_auth_callback()
		cancel_oauth()
	_callback_processing = false
	return out


func _exchange_pkce_code(code: String) -> Dictionary:
	if not config.is_configured():
		return {"ok": false, "error": "Backend is not configured."}
	if code.is_empty():
		return {"ok": false, "error": "Missing authorization code."}
	if _oauth_code_verifier.is_empty() and not _restore_oauth_state():
		return {"ok": false, "error": "Sign-in session expired. Please try Google sign-in again.", "expired": true}
	var url := "%s/auth/v1/token?grant_type=pkce" % config.supabase_url.rstrip("/")
	var body := {
		"auth_code": code,
		"code_verifier": _oauth_code_verifier,
	}
	var result: Dictionary = await api.request(url, "POST", body, false)
	if not bool(result.get("ok", false)):
		var status := int(result.get("status", 0))
		var retryable := status == 0 or status == 429 or status >= 500
		var err := str(result.get("error", "Could not complete Google sign-in."))
		if status == 0:
			err = "No internet connection. Check your network and try again."
		return {"ok": false, "error": err, "status": status, "retryable": retryable}
	var data: Dictionary = result.data if typeof(result.get("data")) == TYPE_DICTIONARY else {}
	return await _apply_token_session({
		"access_token": str(data.get("access_token", "")),
		"refresh_token": str(data.get("refresh_token", "")),
		"expires_in": int(data.get("expires_in", 3600)),
	}, false)


func _apply_token_session(payload: Dictionary, as_recovery: bool) -> Dictionary:
	var access := str(payload.get("access_token", "")).strip_edges()
	var refresh := str(payload.get("refresh_token", "")).strip_edges()
	if access.is_empty():
		return {"ok": false, "error": "Auth callback did not include a session.", "expired": true}
	var expires_in := int(payload.get("expires_in", 3600))
	if expires_in <= 0:
		expires_in = 3600
	tokens.set_session(
		access,
		refresh,
		int(Time.get_unix_time_from_system()) + expires_in
	)
	recovery_session_active = as_recovery
	var user_result := await refresh_user()
	if not bool(user_result.get("ok", false)):
		if as_recovery:
			## Recovery may still allow password update with the access token.
			return {
				"ok": true,
				"error": "",
				"needs_password_reset": true,
				"user_soft_fail": true,
			}
		tokens.clear(true)
		return {"ok": false, "error": str(user_result.get("error", "Could not load user."))}
	if not as_recovery and not tokens.email_confirmed:
		## Google accounts are typically pre-verified; still enforce flag.
		## Do not clear if provider list includes google with confirmed email.
		if not has_google_provider():
			tokens.clear(true)
			recovery_session_active = false
			return {
				"ok": false,
				"error": "Please confirm your email before signing in.",
				"needs_confirmation": true,
			}
	if not as_recovery:
		tokens.persist_if_needed()
	return {
		"ok": true,
		"error": "",
		"user_id": tokens.user_id,
		"needs_password_reset": as_recovery,
	}


func _persist_oauth_state() -> bool:
	if _oauth_code_verifier.is_empty() or (_oauth_mode != "signin" and _oauth_mode != "link"):
		return false
	var payload := JSON.stringify({
		"version": OAUTH_STATE_VERSION,
		"code_verifier": _oauth_code_verifier,
		"mode": _oauth_mode,
		"created_at": _oauth_started_at_unix,
	})
	if AndroidSecureStore.is_available():
		return AndroidSecureStore.store_oauth_state_json(payload)
	## Desktop/headless development has no Android Keystore. Memory-only is fine
	## there; Android release must persist before opening the browser.
	return OS.get_name() != "Android"


func _restore_oauth_state() -> bool:
	if not _oauth_code_verifier.is_empty():
		return true
	if not AndroidSecureStore.is_available() or not AndroidSecureStore.has_oauth_state():
		return false
	var raw := AndroidSecureStore.load_oauth_state_json()
	if raw.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		AndroidSecureStore.delete_oauth_state()
		return false
	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	var verifier := str(data.get("code_verifier", ""))
	var mode := str(data.get("mode", ""))
	var created := int(data.get("created_at", 0))
	var now := int(Time.get_unix_time_from_system())
	if (
		version != OAUTH_STATE_VERSION
		or verifier.length() < 43
		or verifier.length() > 128
		or (mode != "signin" and mode != "link")
		or created <= 0
		or now < created - 60
		or now - created > OAUTH_STATE_TTL_SEC
	):
		AndroidSecureStore.delete_oauth_state()
		return false
	_oauth_code_verifier = verifier
	_oauth_mode = mode
	_oauth_started_at_unix = created
	return true


func has_google_provider() -> bool:
	for p in linked_providers:
		if str(p).to_lower() == "google":
			return true
	return false


func has_email_password_provider() -> bool:
	for p in linked_providers:
		var pl := str(p).to_lower()
		if pl == "email" or pl == "password":
			return true
	## Email/password users often only show "email" identity; if we have a
	## local email and no oauth-only signal, treat email as available.
	if linked_providers.is_empty() and not tokens.user_email.is_empty():
		return true
	return false


func get_sign_in_providers() -> PackedStringArray:
	return linked_providers.duplicate()


func refresh_session() -> Dictionary:
	## Single-flight refresh with refresh-token rotation persistence.
	if tokens.refresh_token.is_empty():
		return {"ok": false, "error": "No refresh token in memory.", "invalid_session": true}
	if _is_refreshing:
		while _is_refreshing:
			await Engine.get_main_loop().process_frame
		## Return the leader's actual outcome — do not mark soft failures as invalid.
		if tokens.has_session() and not tokens.is_expired():
			return {"ok": true, "invalid_session": false}
		return _last_refresh_result.duplicate(true)

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
			out = {"ok": true, "invalid_session": false}
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

	_last_refresh_result = out.duplicate(true)
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
	_update_linked_providers(data)
	return {"ok": true, "user_id": uid, "email": email, "email_confirmed": confirmed}


func _update_linked_providers(user_payload: Dictionary) -> void:
	var found: PackedStringArray = PackedStringArray()
	var identities: Variant = user_payload.get("identities", [])
	if typeof(identities) == TYPE_ARRAY:
		for item in identities:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var prov := str(item.get("provider", "")).strip_edges().to_lower()
			if prov.is_empty():
				continue
			if not found.has(prov):
				found.append(prov)
	var app_meta: Variant = user_payload.get("app_metadata", {})
	if typeof(app_meta) == TYPE_DICTIONARY:
		var providers: Variant = app_meta.get("providers", [])
		if typeof(providers) == TYPE_ARRAY:
			for p in providers:
				var pl := str(p).strip_edges().to_lower()
				if not pl.is_empty() and not found.has(pl):
					found.append(pl)
		var provider := str(app_meta.get("provider", "")).strip_edges().to_lower()
		if not provider.is_empty() and not found.has(provider):
			found.append(provider)
	linked_providers = found


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
	AuthDeepLinkHelper.clear_pending_auth_callback()
	cancel_oauth()
	recovery_session_active = false
	linked_providers = PackedStringArray()
	_last_callback_fp = ""
	tokens.clear(true)


func _generate_code_verifier() -> String:
	## Authentication material must use a CSPRNG, not gameplay PRNG/randi().
	var crypto := Crypto.new()
	var random_bytes := crypto.generate_random_bytes(32)
	return Marshalls.raw_to_base64(random_bytes).replace("+", "-").replace("/", "_").rstrip("=")


func _code_challenge_s256(verifier: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_utf8_buffer())
	var digest := ctx.finish()
	return Marshalls.raw_to_base64(digest).replace("+", "-").replace("/", "_").rstrip("=")
