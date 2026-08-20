extends RefCounted
class_name AuthCallbackParser
## Safe parser for Supabase → app auth callbacks.
## Never logs access tokens, refresh tokens, authorization codes, or passwords.

const APP_SCHEME := "com.charoitegames.chestoflovenotes"
const APP_HOST := "auth-callback"
const REDIRECT_URI := "com.charoitegames.chestoflovenotes://auth-callback"

## Flow kinds returned in parse results.
const FLOW_RECOVERY := "recovery"
const FLOW_OAUTH := "oauth"
const FLOW_UNKNOWN := "unknown"
const FLOW_ERROR := "error"
const FLOW_MALFORMED := "malformed"


static func redirect_uri() -> String:
	return REDIRECT_URI


static func is_our_callback(uri: String) -> bool:
	## Require the exact registered scheme + host. A matching scheme with a
	## different host must never be treated as an auth callback.
	var lower := uri.strip_edges().to_lower()
	if lower.is_empty():
		return false
	var base := REDIRECT_URI.to_lower()
	return lower == base or lower.begins_with(base + "?") or lower.begins_with(base + "#")


static func parse(uri: String) -> Dictionary:
	## Returns a sanitized dictionary. Token values are present for session
	## exchange only — callers must not log this dictionary wholesale.
	var raw := uri.strip_edges()
	if raw.is_empty() or not is_our_callback(raw):
		return {
			"ok": false,
			"flow": FLOW_MALFORMED,
			"error": "Invalid auth callback.",
			"error_code": "invalid_callback",
		}

	var params := _extract_params(raw)
	if params.is_empty() and not raw.contains("?") and not raw.contains("#"):
		return {
			"ok": false,
			"flow": FLOW_MALFORMED,
			"error": "Auth callback is missing parameters.",
			"error_code": "invalid_callback",
		}

	var err := str(params.get("error", "")).strip_edges()
	if not err.is_empty():
		var desc := str(params.get("error_description", params.get("error_desc", ""))).strip_edges()
		var friendly := _friendly_oauth_error(err, desc)
		return {
			"ok": false,
			"flow": FLOW_ERROR,
			"error": friendly,
			"error_code": err,
			"cancelled": err == "access_denied" or desc.to_lower().contains("cancel"),
		}

	var access := str(params.get("access_token", "")).strip_edges()
	var refresh := str(params.get("refresh_token", "")).strip_edges()
	var code := str(params.get("code", "")).strip_edges()
	var type_s := str(params.get("type", "")).strip_edges().to_lower()
	var expires_in := int(str(params.get("expires_in", "3600")).strip_edges()) if str(params.get("expires_in", "")).is_valid_int() else 3600

	if type_s == "recovery" or (not access.is_empty() and type_s == "recovery"):
		if access.is_empty():
			return {
				"ok": false,
				"flow": FLOW_RECOVERY,
				"error": "This password reset link has expired. Request a new one.",
				"error_code": "recovery_expired",
				"expired": true,
			}
		return {
			"ok": true,
			"flow": FLOW_RECOVERY,
			"access_token": access,
			"refresh_token": refresh,
			"expires_in": expires_in,
			"type": type_s,
			"error": "",
		}

	if not code.is_empty():
		return {
			"ok": true,
			"flow": FLOW_OAUTH,
			"code": code,
			"error": "",
		}

	if not access.is_empty():
		## Implicit/token redirect (recovery without type, or OAuth fragment).
		var flow := FLOW_RECOVERY if type_s == "recovery" else FLOW_OAUTH
		if type_s.is_empty() and refresh.is_empty():
			flow = FLOW_UNKNOWN
		return {
			"ok": true,
			"flow": flow if flow != FLOW_UNKNOWN else FLOW_OAUTH,
			"access_token": access,
			"refresh_token": refresh,
			"expires_in": expires_in,
			"type": type_s,
			"error": "",
		}

	return {
		"ok": false,
		"flow": FLOW_MALFORMED,
		"error": "Auth callback could not be understood.",
		"error_code": "invalid_callback",
	}


static func fingerprint(uri: String) -> String:
	## Stable id for duplicate suppression — never the raw token.
	var parsed := parse(uri)
	var seed := ""
	if not str(parsed.get("code", "")).is_empty():
		seed = "code:" + str(parsed.get("code", "")).left(12)
	elif not str(parsed.get("access_token", "")).is_empty():
		seed = "tok:" + str(parsed.get("access_token", "")).left(12)
	elif not str(parsed.get("error_code", "")).is_empty():
		seed = "err:" + str(parsed.get("error_code", ""))
	else:
		seed = "raw:" + str(uri.length())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(seed.to_utf8_buffer())
	return ctx.finish().hex_encode().left(32)


static func sanitize_for_log(uri: String) -> String:
	## Safe diagnostic string — strips secrets.
	if not is_our_callback(uri):
		return "non_auth_uri"
	var parsed := parse(uri)
	return "auth_callback flow=%s ok=%s err=%s" % [
		str(parsed.get("flow", "")),
		str(parsed.get("ok", false)),
		str(parsed.get("error_code", parsed.get("error", ""))).left(64),
	]


static func _extract_params(uri: String) -> Dictionary:
	var out: Dictionary = {}
	var work := uri
	## Prefer fragment (Supabase recovery/token) then query (PKCE code).
	var hash_i := work.find("#")
	var q_i := work.find("?")
	var fragment := ""
	var query := ""
	if hash_i >= 0:
		fragment = work.substr(hash_i + 1)
		work = work.substr(0, hash_i)
	## Recompute query on residual (scheme://host?query)
	q_i = work.find("?")
	if q_i >= 0:
		query = work.substr(q_i + 1)
	_merge_query_string(out, query)
	_merge_query_string(out, fragment)
	return out


static func _merge_query_string(into: Dictionary, qs: String) -> void:
	if qs.is_empty():
		return
	for part in qs.split("&"):
		if part.is_empty():
			continue
		var eq := part.find("=")
		var key := ""
		var val := ""
		if eq < 0:
			key = part.uri_decode() if part.find("%") >= 0 else part
		else:
			key = part.substr(0, eq)
			val = part.substr(eq + 1)
			key = key.uri_decode() if key.find("%") >= 0 else key
			val = val.uri_decode() if val.find("%") >= 0 else val
		key = key.strip_edges()
		if key.is_empty():
			continue
		## First write wins for a key unless empty — fragment often more specific.
		if into.has(key) and not str(into[key]).is_empty() and val.is_empty():
			continue
		into[key] = val


static func _friendly_oauth_error(code: String, desc: String) -> String:
	var c := code.to_lower()
	var d := desc.to_lower()
	if c == "access_denied" or d.contains("cancel"):
		return "Google sign-in was cancelled."
	if c == "server_error" or d.contains("provider"):
		return "Google sign-in is not available right now. The provider may not be configured."
	if d.contains("expired"):
		return "This sign-in link has expired. Please try again."
	if not desc.is_empty():
		## Keep short; never echo tokens that might appear in odd payloads.
		return "Sign-in could not be completed."
	return "Sign-in could not be completed."


static func is_valid_email_syntax(email: String) -> bool:
	var e := email.strip_edges().to_lower()
	if e.is_empty() or e.length() > 254:
		return false
	if e.contains(" ") or e.contains("\n") or e.contains("\t"):
		return false
	var at := e.find("@")
	if at <= 0 or at != e.rfind("@"):
		return false
	var local := e.substr(0, at)
	var domain := e.substr(at + 1)
	if local.is_empty() or domain.is_empty():
		return false
	if not domain.contains("."):
		return false
	if domain.begins_with(".") or domain.ends_with(".") or domain.contains(".."):
		return false
	return true
