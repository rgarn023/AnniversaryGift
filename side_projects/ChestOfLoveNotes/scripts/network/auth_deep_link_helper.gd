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
	## Android plugin singletons can expose @UsedByGodot methods even when
	## Object.has_method() does not report them reliably. Presence of the v74
	## plugin singleton is the capability check; this APK ships both sides together.
	return _plugin() != null


static func peek_pending_auth_callback() -> String:
	var p = _plugin()
	if p == null:
		return ""
	return str(p.call("peek_pending_auth_callback"))


static func consume_pending_auth_callback() -> String:
	## Compatibility name used by main.gd. Intentionally non-destructive now:
	## AuthService clears the callback only after terminal success/failure so a
	## process/network interruption cannot lose a still-usable PKCE callback.
	var p = _plugin()
	if p == null:
		return ""
	return str(p.call("consume_pending_auth_callback"))


static func clear_pending_auth_callback() -> bool:
	var p = _plugin()
	if p == null:
		return true
	return bool(p.call("clear_pending_auth_callback"))


static func open_external_auth_url(url: String) -> Dictionary:
	## Prefer Android's native ACTION_VIEW intent. OS.shell_open() can report OK
	## on some Godot Android builds without actually foregrounding a browser.
	var u := url.strip_edges()
	if u.is_empty():
		return {"ok": false, "error": "Missing sign-in URL."}
	if not (u.begins_with("https://") or u.begins_with("http://")):
		return {"ok": false, "error": "Invalid sign-in URL."}
	if OS.get_name() == "Android":
		var p = _plugin()
		if p == null:
			return {"ok": false, "error": "Android browser launcher is unavailable. Restart the app and try again."}
		var opened := bool(p.call("open_external_auth_url", u))
		if not opened:
			return {"ok": false, "error": "Could not open a browser for Google sign-in."}
		return {"ok": true, "error": ""}
	var err := OS.shell_open(u)
	if err != OK:
		return {"ok": false, "error": "Could not open the browser for Google sign-in."}
	return {"ok": true, "error": ""}
