extends RefCounted
class_name AuthDeepLinkHelper
## Bridge to Android pending auth-callback URIs (custom scheme).
## Never logs raw callback URIs (may contain tokens/codes).

const PLUGIN_NAME := "ChestNotify"


static func _plugin():
	if Engine.has_singleton(PLUGIN_NAME):
		return Engine.get_singleton(PLUGIN_NAME)
	return null


static func available() -> bool:
	var p = _plugin()
	return p != null and p.has_method("consume_pending_auth_callback")


static func peek_pending_auth_callback() -> String:
	var p = _plugin()
	if p != null and p.has_method("peek_pending_auth_callback"):
		return str(p.peek_pending_auth_callback())
	return ""


static func consume_pending_auth_callback() -> String:
	var p = _plugin()
	if p != null and p.has_method("consume_pending_auth_callback"):
		return str(p.consume_pending_auth_callback())
	return ""


static func open_external_auth_url(url: String) -> Dictionary:
	## Opens the system browser / Custom Tab target via OS.shell_open.
	var u := url.strip_edges()
	if u.is_empty():
		return {"ok": false, "error": "Missing sign-in URL."}
	if not (u.begins_with("https://") or u.begins_with("http://")):
		return {"ok": false, "error": "Invalid sign-in URL."}
	var err := OS.shell_open(u)
	if err != OK:
		return {"ok": false, "error": "Could not open the browser for Google sign-in."}
	return {"ok": true, "error": ""}
