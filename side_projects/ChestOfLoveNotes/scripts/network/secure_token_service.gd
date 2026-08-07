extends RefCounted
class_name SecureTokenService
## In-memory Supabase session with optional Android Keystore persistence.
## Never saves access/refresh tokens as plaintext under user://.
## Never stores the account password or Magic Passwords.

const SESSION_VERSION := 1
const EXPIRY_SKEW_SEC := 90

var access_token: String = ""
var refresh_token: String = ""
var expires_at_unix: int = 0
var user_id: String = ""
var user_email: String = ""
var email_confirmed: bool = false
var keep_me_signed_in: bool = true
var memory_only: bool = true
var limitation_message: String = ""
var last_persist_error: String = ""
var session_restored: bool = false
var session_refresh_performed: bool = false


func _init() -> void:
	keep_me_signed_in = AndroidSecureStore.get_keep_me_signed_in()
	_refresh_limitation_message()


func _refresh_limitation_message() -> void:
	if AndroidSecureStore.is_available() and keep_me_signed_in:
		memory_only = false
		limitation_message = "Session is protected by Android Keystore-backed storage."
	elif keep_me_signed_in and not AndroidSecureStore.is_available():
		memory_only = true
		limitation_message = (
			"Secure sign-in storage is unavailable. "
			+ "You’ll need to sign in again after closing the app."
		)
	else:
		memory_only = true
		limitation_message = "Keep Me Signed In is off. Session clears when the app closes."


func set_keep_me_signed_in(enabled: bool) -> void:
	keep_me_signed_in = enabled
	AndroidSecureStore.set_keep_me_signed_in(enabled)
	_refresh_limitation_message()
	if enabled:
		persist_if_needed()
	else:
		AndroidSecureStore.delete_session()


func set_session(access: String, refresh: String, expires_at: int = 0) -> void:
	access_token = access
	refresh_token = refresh
	expires_at_unix = expires_at
	persist_if_needed()


func set_user(p_user_id: String, p_email: String, p_confirmed: bool) -> void:
	user_id = p_user_id
	user_email = p_email
	email_confirmed = p_confirmed
	persist_if_needed()


func clear(delete_persistent: bool = true) -> void:
	access_token = ""
	refresh_token = ""
	expires_at_unix = 0
	user_id = ""
	user_email = ""
	email_confirmed = false
	session_restored = false
	session_refresh_performed = false
	if delete_persistent:
		AndroidSecureStore.delete_session()


func has_session() -> bool:
	return not access_token.is_empty()


func is_expired(skew_sec: int = EXPIRY_SKEW_SEC) -> bool:
	if expires_at_unix <= 0:
		return false
	return int(Time.get_unix_time_from_system()) >= (expires_at_unix - skew_sec)


func authorization_header() -> String:
	if access_token.is_empty():
		return ""
	return "Bearer %s" % access_token


func to_session_dict() -> Dictionary:
	## Minimal secure payload — never includes account password or Magic Password.
	return {
		"version": SESSION_VERSION,
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at": expires_at_unix,
		"user_id": user_id,
	}


func persist_if_needed() -> bool:
	last_persist_error = ""
	if not keep_me_signed_in:
		return false
	if not AndroidSecureStore.is_available():
		last_persist_error = "secure_store_unavailable"
		_refresh_limitation_message()
		return false
	if access_token.is_empty() or refresh_token.is_empty():
		return false
	var payload := JSON.stringify(to_session_dict())
	# Defense: never write the JSON payload under user://.
	var ok := AndroidSecureStore.store_session_json(payload)
	if not ok:
		last_persist_error = "secure_store_failed"
	_refresh_limitation_message()
	return ok


func restore_from_secure_storage() -> bool:
	clear(false)
	session_restored = false
	if not keep_me_signed_in:
		return false
	if not AndroidSecureStore.is_available() or not AndroidSecureStore.has_session():
		return false
	var raw := AndroidSecureStore.load_session_json()
	if raw.is_empty():
		AndroidSecureStore.delete_session()
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		AndroidSecureStore.delete_session()
		return false
	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version != SESSION_VERSION and version != 0:
		# Unknown future/corrupt version — reject safely.
		AndroidSecureStore.delete_session()
		return false
	access_token = str(data.get("access_token", ""))
	refresh_token = str(data.get("refresh_token", ""))
	expires_at_unix = int(data.get("expires_at", data.get("expires_at_unix", 0)))
	user_id = str(data.get("user_id", ""))
	# Email/confirmation are refreshed from Supabase after restore; optional legacy fields ignored.
	if access_token.is_empty() or refresh_token.is_empty():
		clear(true)
		return false
	session_restored = true
	_refresh_limitation_message()
	return true
