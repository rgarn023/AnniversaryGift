class_name PdfHelper
extends RefCounted

## Copies the bundled PDF to user storage and talks to the Android plugin.

const BUNDLED_PDF := "res://assets/documents/anniversary_gift.pdf"
const USER_PDF := "user://anniversary_gift.pdf"
const PAGE_DIR := "res://assets/documents/pdf_pages/"

signal operation_finished(success: bool, message: String)


func ensure_user_pdf() -> String:
	if FileAccess.file_exists(USER_PDF):
		return USER_PDF
	if not FileAccess.file_exists(BUNDLED_PDF):
		push_warning("PdfHelper: bundled PDF missing")
		return ""
	var src := FileAccess.open(BUNDLED_PDF, FileAccess.READ)
	if src == null:
		return ""
	var bytes: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(USER_PDF, FileAccess.WRITE)
	if dst == null:
		return ""
	dst.store_buffer(bytes)
	dst.close()
	return USER_PDF


func get_absolute_user_pdf_path() -> String:
	var user_path: String = ensure_user_pdf()
	if user_path.is_empty():
		return ""
	return ProjectSettings.globalize_path(user_path)


func list_page_previews() -> PackedStringArray:
	var pages: PackedStringArray = []
	var dir := DirAccess.open(PAGE_DIR)
	if dir == null:
		return pages
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			pages.append(PAGE_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	pages.sort()
	return pages


func open_original_pdf() -> Dictionary:
	var abs_path: String = get_absolute_user_pdf_path()
	if abs_path.is_empty():
		return {"ok": false, "message": "The gift PDF could not be prepared."}
	if not OS.has_feature("android"):
		return {
			"ok": false,
			"message": "Opening the original PDF requires Android. The in-app page preview remains available."
		}
	if not Engine.has_singleton("AnniversaryPdf"):
		return {
			"ok": false,
			"message": "The Android PDF helper is unavailable. You can still view the page previews here."
		}
	var plugin: Object = Engine.get_singleton("AnniversaryPdf")
	var result: Variant = plugin.call("openPdf", abs_path)
	return _normalize_plugin_result(result, "open")


func share_original_pdf() -> Dictionary:
	var abs_path: String = get_absolute_user_pdf_path()
	if abs_path.is_empty():
		return {"ok": false, "message": "The gift PDF could not be prepared."}
	if not OS.has_feature("android"):
		return {
			"ok": false,
			"message": "Sharing the original PDF requires Android. The in-app page preview remains available."
		}
	if not Engine.has_singleton("AnniversaryPdf"):
		return {
			"ok": false,
			"message": "The Android PDF helper is unavailable. You can still view the page previews here."
		}
	var plugin: Object = Engine.get_singleton("AnniversaryPdf")
	var result: Variant = plugin.call("sharePdf", abs_path)
	return _normalize_plugin_result(result, "share")


func _normalize_plugin_result(result: Variant, action: String) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		var d: Dictionary = result
		return {
			"ok": bool(d.get("ok", false)),
			"message": str(d.get("message", "")),
		}
	var text := str(result)
	if text.begins_with("OK") or text.to_lower().begins_with("ok"):
		return {"ok": true, "message": text}
	if text.is_empty():
		return {"ok": true, "message": "PDF %s requested." % action}
	return {"ok": false, "message": text}
