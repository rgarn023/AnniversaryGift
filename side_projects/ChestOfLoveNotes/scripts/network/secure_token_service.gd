extends RefCounted
class_name SecureTokenService
## In-memory session only for the temporary private onboarding build.
## Never persists tokens to disk / user:// as plaintext.

var access_token: String = ""
var refresh_token: String = ""
var expires_at_unix: int = 0
var user_id: String = ""
var user_email: String = ""
var email_confirmed: bool = false
var memory_only: bool = true
var limitation_message: String = (
	"Secure persistent token storage is not yet wired. "
	+ "Sessions remain in memory for this build and clear when the app closes."
)


func set_session(access: String, refresh: String, expires_at: int = 0) -> void:
	access_token = access
	refresh_token = refresh
	expires_at_unix = expires_at


func set_user(p_user_id: String, p_email: String, p_confirmed: bool) -> void:
	user_id = p_user_id
	user_email = p_email
	email_confirmed = p_confirmed


func clear() -> void:
	access_token = ""
	refresh_token = ""
	expires_at_unix = 0
	user_id = ""
	user_email = ""
	email_confirmed = false


func has_session() -> bool:
	return not access_token.is_empty()


func is_expired(skew_sec: int = 30) -> bool:
	if expires_at_unix <= 0:
		return false
	return int(Time.get_unix_time_from_system()) >= (expires_at_unix - skew_sec)


func authorization_header() -> String:
	if access_token.is_empty():
		return ""
	return "Bearer %s" % access_token
