extends RefCounted
class_name SecureTokenService
## Session token holder.
## First-pass limitation: tokens stay in memory only (no plaintext user:// fallback).
## Android Keystore-backed persistence can be added via a native plugin later.

var access_token: String = ""
var refresh_token: String = ""
var expires_at_unix: int = 0
var memory_only: bool = true
var limitation_message: String = (
	"Secure persistent token storage is not yet wired. "
	+ "Sessions remain in memory for this build and clear when the app closes."
)


func set_session(access: String, refresh: String, expires_at: int = 0) -> void:
	access_token = access
	refresh_token = refresh
	expires_at_unix = expires_at


func clear() -> void:
	access_token = ""
	refresh_token = ""
	expires_at_unix = 0


func has_session() -> bool:
	return not access_token.is_empty()


func authorization_header() -> String:
	if access_token.is_empty():
		return ""
	return "Bearer %s" % access_token
