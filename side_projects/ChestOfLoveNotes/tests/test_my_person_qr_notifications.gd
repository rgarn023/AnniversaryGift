extends SceneTree
## My Person / QR / identity / notifications regression checks.

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
	print("=== My Person / QR / Notifications (v24) ===")
	var strings := FileAccess.get_file_as_string("res://scripts/ui/product_strings.gd")
	var identity := FileAccess.get_file_as_string("res://scripts/network/identity_helper.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	var qr := FileAccess.get_file_as_string("res://scripts/network/qr_helper.gd")
	var reqn := FileAccess.get_file_as_string("res://scripts/network/requirement_notifier.gd")
	var viewer := FileAccess.get_file_as_string("res://scripts/scroll/scroll_viewer.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var send_ts := FileAccess.get_file_as_string("res://supabase/functions/send-scroll/index.ts")
	var open_ts := FileAccess.get_file_as_string("res://supabase/functions/open-scroll/index.ts")
	var getf := FileAccess.get_file_as_string("res://supabase/functions/get-friends/index.ts")
	var send_req := FileAccess.get_file_as_string("res://supabase/functions/send-friend-request/index.ts")
	var mig1 := FileAccess.get_file_as_string("res://supabase/migrations/20260810180000_my_person_one_pairing.sql")
	var mig2 := FileAccess.get_file_as_string("res://supabase/migrations/20260810180100_device_push_tokens.sql")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var qr_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestQrPlugin.kt")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")

	_assert(strings.contains("MY_PERSON"), "ProductStrings MY_PERSON")
	_assert(strings.contains("Scan Person Code"), "scan string")
	_assert(identity.contains("looks_like_uuid"), "uuid detector")
	_assert(identity.contains("format_from"), "format_from helper")
	_assert(identity.contains("Unknown sender"), "unknown sender")
	_assert(main.contains("ProductStrings.MY_PERSON"), "nav My Person")
	_assert(main.contains("_on_scan_person_code"), "scan entry")
	_assert(main.contains("_show_my_connection_code"), "show my code")
	_assert(main.contains("IdentityHelper.format_from"), "opened scroll uses identity helper")
	_assert(not main.contains('meta.get("sender_id", "Friend")'), "no UUID fallback in From line")
	_assert(compose.contains("setup_with_person"), "compose person setup")
	_assert(compose.contains("go_to_my_person_requested"), "go to My Person signal")
	_assert(compose.contains("ProductStrings.COMPOSE_NEED_PERSON"), "compose needs person")
	_assert(friends.contains("resolve_connection_token"), "resolve token API")
	_assert(friends.contains("disconnect_person"), "disconnect API")
	_assert(qr.contains("chestoflovenotes://connect/"), "deep link prefix")
	_assert(qr.contains("extract_token"), "token extract")
	_assert(reqn.contains("_claim"), "dedupe claim")
	_assert(viewer.contains("Close"), "close button")
	_assert(viewer.contains("_balance_short_note_layout"), "short note layout")
	_assert(send_ts.contains("get_active_person_id"), "send-scroll person check")
	_assert(send_ts.contains("sendPushToUser"), "send-scroll push")
	_assert(open_ts.contains("sender_display_name"), "open-scroll sender profile")
	_assert(getf.contains("public_connection_token"), "get-friends returns token for me")
	_assert(send_req.contains("connection_token"), "send request accepts token")
	_assert(send_req.contains("already_has_person"), "one-person enforcement")
	_assert(mig1.contains("public_connection_token"), "token migration")
	_assert(mig1.contains("enforce_one_active_person"), "one person trigger")
	_assert(mig2.contains("device_push_tokens"), "push tokens migration")
	_assert(install.contains("ChestQr"), "install wires QR plugin")
	_assert(install.contains("zxing:core"), "zxing dependency")
	_assert(install.contains("CAMERA"), "camera permission install")
	_assert(qr_kt.contains("encode_qr_png_base64"), "QR encode")
	_assert(qr_kt.contains("start_qr_scan"), "QR scan")
	_assert(flags.contains("APP_VERSION_CODE := 30"), "versionCode 26")
	_assert(preset.contains("version/code=30"), "export 24")
	_assert(preset.contains("backend-location-qr-splash-fix-debug.apk"), "APK name")
	_assert(preset.contains("permissions/camera=true"), "camera export permission")
	_assert(gitignore.contains("ChestOfLoveNotes-backend-location-qr-splash-fix-debug.apk"), "APK gitignore allow")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
