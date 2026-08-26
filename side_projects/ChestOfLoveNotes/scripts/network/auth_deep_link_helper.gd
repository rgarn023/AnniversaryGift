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
	var value: Variant = p.call("peek_pending_auth_callback")
	return "" if value == null else str(value)


static func consume_pending_auth_callback() -> String:
	## Compatibility name used by main.gd. Intentionally non-destructive now:
	## AuthService clears the callback only after terminal success/failure so a
	## process/network interruption cannot lose a still-usable PKCE callback.
	var p = _plugin()
	if p == null:
		return ""
	var value: Variant = p.call("consume_pending_auth_callback")
	return "" if value == null else str(value)


static func clear_pending_auth_callback() -> bool:
	var p = _plugin()
	if p == null:
		return true
	var value: Variant = p.call("clear_pending_auth_callback")
	return value != null and bool(value)


static func open_external_auth_url(url: String) -> Dictionary:
	## Godot 4.7 includes AndroidRuntime + JavaClassWrapper specifically for
	## direct access to Android APIs. Prefer that path over a custom JNI method.
	var u := url.strip_edges()
	if u.is_empty():
		return {"ok": false, "error": "Missing Google sign-in URL."}
	if not (u.begins_with("https://") or u.begins_with("http://")):
		return {"ok": false, "error": "Invalid Google sign-in URL."}

	if OS.get_name() == "Android":
		var android_runtime = Engine.get_singleton("AndroidRuntime")
		if android_runtime == null:
			return {"ok": false, "error": "Android runtime is unavailable. Restart the app and try again."}
		var activity = android_runtime.getActivity()
		if activity == null:
			return {"ok": false, "error": "Android activity is unavailable. Restart the app and try again."}
		var Intent = JavaClassWrapper.wrap("android.content.Intent")
		var Uri = JavaClassWrapper.wrap("android.net.Uri")
		if Intent == null or Uri == null:
			return {"ok": false, "error": "Android browser support could not be initialized."}
		var intent = Intent.Intent()
		intent.setAction(Intent.ACTION_VIEW)
		intent.setData(Uri.parse(u))
		intent.addCategory(Intent.CATEGORY_BROWSABLE)
		activity.startActivity(intent)
		return {"ok": true, "error": ""}

	var err := OS.shell_open(u)
	if err != OK:
		return {"ok": false, "error": "Could not open the browser for Google sign-in."}
	return {"ok": true, "error": ""}
