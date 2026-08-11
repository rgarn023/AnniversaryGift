extends RefCounted
class_name QrHelper
## Show-My-Code encoding + Scan Person Code camera bridge.

const PLUGIN_NAME := "ChestQr"
const DEEP_LINK_PREFIX := "chestoflovenotes://connect/"

signal qr_scanned(text: String)
signal qr_scan_cancelled
signal qr_scan_error(code: String)

var _wired: bool = false


static func deep_link_for_token(token: String) -> String:
	return DEEP_LINK_PREFIX + token.strip_edges().to_lower()


static func extract_token(raw: String) -> String:
	var t := raw.strip_edges()
	var lower := t.to_lower()
	if lower.begins_with(DEEP_LINK_PREFIX):
		return t.substr(DEEP_LINK_PREFIX.length()).strip_edges().to_lower()
	var idx := lower.find("/connect/")
	if idx >= 0:
		return t.substr(idx + "/connect/".length()).strip_edges().to_lower()
	## Bare token (hex)
	if t.length() >= 16 and t.find(" ") < 0 and not t.begins_with("http"):
		return t.to_lower()
	return ""


static func is_coln_connect_payload(raw: String) -> bool:
	var tok := extract_token(raw)
	if tok.is_empty() or tok.length() < 16:
		return false
	## Must be our deep link or bare token — never open arbitrary URLs.
	var lower := raw.strip_edges().to_lower()
	if lower.begins_with("http://") or lower.begins_with("https://"):
		return lower.find("chestoflovenotes") >= 0 or lower.find("/connect/") >= 0
	return true


static func _plugin():
	if Engine.has_singleton(PLUGIN_NAME):
		return Engine.get_singleton(PLUGIN_NAME)
	return null


static func available() -> bool:
	var p = _plugin()
	if p == null:
		return false
	if p.has_method("qr_plugin_available"):
		return bool(p.qr_plugin_available())
	return true


static func has_camera_permission() -> bool:
	if OS.get_name() != "Android":
		return false
	var p = _plugin()
	if p != null and p.has_method("has_camera_permission"):
		return bool(p.has_camera_permission())
	return OS.get_granted_permissions().has("android.permission.CAMERA")


static func request_camera_permission() -> void:
	if OS.get_name() == "Android" and OS.has_method("request_permission"):
		OS.request_permission("android.permission.CAMERA")
	var p = _plugin()
	if p != null and p.has_method("request_camera_permission"):
		p.request_camera_permission()


static func open_app_settings() -> void:
	var p = _plugin()
	if p != null and p.has_method("open_app_settings"):
		p.open_app_settings()


static func encode_png_base64(payload: String, size_px: int = 512) -> String:
	## Encode via Android ZXing; returns "" if missing plugin or verify-decode fails.
	var p = _plugin()
	if p != null and p.has_method("encode_qr_png_base64"):
		return str(p.encode_qr_png_base64(payload, size_px))
	return ""


static func verify_roundtrip(payload: String, size_px: int = 512) -> bool:
	var p = _plugin()
	if p != null and p.has_method("verify_qr_roundtrip"):
		var raw := str(p.verify_qr_roundtrip(payload, size_px))
		return raw.begins_with("ok|")
	## Fallback: encode then require non-empty PNG (encode already verify-decodes on Android).
	return not encode_png_base64(payload, size_px).is_empty()


static func payload_contains_raw_uuid(payload: String) -> bool:
	## Guard: QR must never encode a raw UUID.
	var lower := payload.to_lower()
	var uuid_re := RegEx.new()
	uuid_re.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
	return uuid_re.search(lower) != null


static func texture_from_base64_png(b64: String) -> Texture2D:
	if b64.is_empty():
		return null
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		return null
	return ImageTexture.create_from_image(img)


func ensure_signals() -> void:
	if _wired:
		return
	var p = _plugin()
	if p == null:
		return
	if p.has_signal("qr_scanned") and not p.is_connected("qr_scanned", Callable(self, "_on_scanned")):
		p.connect("qr_scanned", Callable(self, "_on_scanned"))
	if p.has_signal("qr_scan_cancelled") and not p.is_connected("qr_scan_cancelled", Callable(self, "_on_cancelled")):
		p.connect("qr_scan_cancelled", Callable(self, "_on_cancelled"))
	if p.has_signal("qr_scan_error") and not p.is_connected("qr_scan_error", Callable(self, "_on_error")):
		p.connect("qr_scan_error", Callable(self, "_on_error"))
	_wired = true


func start_scan() -> bool:
	ensure_signals()
	var p = _plugin()
	if p == null or not p.has_method("start_qr_scan"):
		qr_scan_error.emit("unavailable")
		return false
	return bool(p.start_qr_scan())


func _on_scanned(text: String) -> void:
	qr_scanned.emit(str(text))


func _on_cancelled() -> void:
	qr_scan_cancelled.emit()


func _on_error(code: String) -> void:
	qr_scan_error.emit(str(code))
