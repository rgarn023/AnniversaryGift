extends SceneTree
## Preview rebuild, flexible radius, attachments polish.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _run() -> void:
	print("=== Preview / Radius / Attachments ===")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	var helper := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var attach := FileAccess.get_file_as_string("res://scripts/network/attachment_helper.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var send := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260808040000_scroll_attachments_and_radius.sql")

	_assert(not compose.contains("Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.72)"), "no full-screen 0.72 purple tint")
	_assert(compose.contains("HSlider"), "radius slider present")
	_assert(compose.contains("_location_radius_edit"), "numeric radius field")
	_assert(helper.contains("MIN_RADIUS_M := 1"), "1 m minimum")
	_assert(helper.contains("MAX_RADIUS_M := 10000"), "10 km maximum")
	_assert(compose.contains("Very small radii may be difficult"), "small-radius warning")
	_assert(send.contains("radius < 1 || radius > 10000"), "send-scroll radius 1–10000")
	_assert(map.contains("Loading map"), "map loading state")
	_assert(map.contains("_confirm_btn.disabled"), "confirm disabled until ready")
	_assert(viewer.contains("_zoom_pan_root") or viewer.contains("_parchment_root"), "unified scroll composite")
	_assert(viewer.contains("✕ Close") or viewer.contains("Close"), "preview close")
	_assert(viewer.contains("NOTIFICATION_WM_GO_BACK_REQUEST"), "preview android back")
	_assert(compose.contains("Attachments removed from active product UI"), "attachments UI removed")
	_assert(attach.contains("MAX_ATTACHMENTS := 5"), "max 5 photos")
	_assert(attach.contains("MAX_LONG_EDGE := 1800"), "compression long edge")
	_assert(mig.contains("scroll_attachments"), "migration table")
	_assert(mig.contains("scroll-attachments"), "storage bucket")
	_assert(mig.contains("between 1 and 10000"), "radius constraint migration")
	_assert(compose.contains("_make_optional_header"), "collapsible cards")
	_assert(compose.contains("Recipient:"), "ready check rows")
	_assert(FileAccess.file_exists("res://supabase/functions/prepare-attachment-uploads/index.ts"), "prepare uploads fn")
	_assert(FileAccess.file_exists("res://supabase/functions/get-scroll-attachments/index.ts"), "get attachments fn")
	_assert(BuildFlags.APP_VERSION_CODE >= 22, "versionCode 22+")
	_assert(AttachmentHelper.clamp_radius(1) == 1, "clamp allows 1m")
	_assert(AttachmentHelper.clamp_radius(10000) == 10000, "clamp allows 10km")
	_assert(AttachmentHelper.clamp_radius(0) == 1, "clamp raises 0")
	_assert(AttachmentHelper.clamp_radius(500000) == 10000, "clamp caps huge")
	var p1 := AttachmentHelper.parse_radius_text("500")
	_assert(bool(p1.ok) and int(p1.value) == 500, "parse 500")
	var p2 := AttachmentHelper.parse_radius_text("-5")
	_assert(not bool(p2.ok), "reject negative")
	var p3 := AttachmentHelper.parse_radius_text("abc")
	_assert(not bool(p3.ok), "reject letters")
	var p4 := AttachmentHelper.parse_radius_text("0")
	_assert(not bool(p4.ok), "reject zero")
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
