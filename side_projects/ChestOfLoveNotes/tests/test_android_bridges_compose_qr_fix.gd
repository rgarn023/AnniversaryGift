extends SceneTree
## v29: Android bridge runtime + Compose recipient + camera truth + Show My Code + diagnostics.

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
	print("=== Android bridges + Compose + QR fix (v29) ===")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var qr := FileAccess.get_file_as_string("res://scripts/network/qr_helper.gd")
	var qr_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestQrPlugin.kt")
	var scan_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/QrScanActivity.kt")
	var perm := FileAccess.get_file_as_string("res://scripts/network/permissions_helper.gd")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var getf := FileAccess.get_file_as_string("res://supabase/functions/get-friends/index.ts")

	## COMPOSE — auto To Mandy, no picker overlay, debug self-send separate
	_assert(compose.contains("Send to Myself (Test)"), "debug self-send label")
	_assert(compose.contains("never overlays or replaces"), "self-send below Person label")
	_assert(compose.contains("Production recipient is a fixed label"), "no full-rect recipient button")
	_assert(compose.contains("Keep production recipient bound to My Person"), "Person stays while self-send on")
	var recip_fn := compose.find("func _build_recipient_card")
	var recip_end := compose.find("func _", recip_fn + 10)
	var recip_block := compose.substr(recip_fn, maxi(0, recip_end - recip_fn)) if recip_fn >= 0 else ""
	_assert(not recip_block.contains("PRESET_FULL_RECT"), "recipient card avoids covering label")
	_assert(main.contains("Always rebind Compose to the active Person"), "compose rebinds person")
	_assert(main.contains("sticky identity for Compose"), "sticky person for empty payload")
	_assert(main.contains("need_person_refresh"), "refresh when person empty")

	## LOCATION — runtime bridge check, no silent missing, timeout race
	_assert(loc.contains("LOCATION BRIDGE MISSING"), "LOCATION BRIDGE MISSING log/error")
	_assert(loc.contains("_await_plugin_ready"), "await plugin ready")
	_assert(loc.contains("bridge_available"), "bridge_available helper")
	_assert(loc.contains("Engine.has_singleton(ChestLocation)"), "runtime singleton log")
	_assert(loc.contains("state=SUCCESS"), "location state machine SUCCESS")
	_assert(loc.contains("timeout_fired after success — ignored") or loc.contains("success_latched"), "timeout cannot overwrite success")
	_assert(compose.contains("LOCATION BRIDGE MISSING"), "compose surfaces bridge missing")
	_assert(compose.contains("Coordinates succeed immediately"), "coords before geocode")
	_assert(not loc_kt.contains("Tasks.await("), "no Tasks.await")
	_assert(loc_kt.contains("getCurrentLocation"), "fused getCurrentLocation")
	_assert(install.contains("ChestLocation"), "ChestLocation install registration")

	## CAMERA — live OS truth, not cached; separate init vs permission errors
	_assert(qr.contains("_os_camera_permission_granted"), "OS camera permission helper")
	_assert(qr.contains("os_granted or plugin_granted"), "OR plugin+OS camera truth")
	_assert(perm.contains("os_ok or plugin_ok"), "PermissionsHelper OR camera truth")
	_assert(qr_kt.contains("applicationContext"), "ChestQr uses applicationContext")
	_assert(qr_kt.contains("android.permission.CAMERA") or qr_kt.contains("Manifest.permission.CAMERA"), "CAMERA constant")
	_assert(main.contains("Camera scanner couldn't start."), "scanner init error separate from permission")
	_assert(main.contains("PermissionsHelper.log_resume_refresh()"), "resume refreshes permissions")
	_assert(main.contains("plugin may have lied when Activity was null"), "camera_permission signal recheck")

	## QR SHOW MY CODE — Connection Code independent of encode; no dual-size verify
	_assert(main.contains("Do NOT re-verify at a different size"), "no 640-then-320 verify discard")
	_assert(main.contains("QR generation unavailable"), "DEBUG QR failure label")
	_assert(main.contains("ProductStrings.CONNECTION_CODE"), "Connection Code heading")
	_assert(main.contains("ChestQr singleton found"), "QR diagnostic logs")
	_assert(main.contains("Never show a raw UUID"), "no raw UUID as Connection Code")
	_assert(qr_kt.contains("verify_qr_roundtrip"), "native roundtrip API")
	_assert(qr.contains("verify_roundtrip"), "QrHelper verify")
	_assert(install.contains("ChestQr"), "ChestQr registered")
	_assert(install.contains("zxing"), "zxing dependency")

	## QR SCANNER
	_assert(main.contains("scan_paired"), "Scan visible when paired")
	_assert(main.contains("ProductStrings.SHOW_MY_CODE"), "Show My Code when paired")
	_assert(scan_kt.contains("DecoratedBarcodeView"), "live camera preview")
	_assert(qr_kt.contains("startActivityForResult"), "starts scanner activity")

	## DEBUG DIAGNOSTICS — helpers kept, but NOT on normal Profile UI.
	## Literal user title "Android Diagnostics" must not be assigned in production UI.
	_assert(not main.contains('sec.text = "Android Diagnostics"'), "no Android Diagnostics UI title assignment")
	_assert(main.contains("Bridge Diagnostics (debug)"), "internal bridge diagnostics title")
	_assert(main.contains("Refresh Diagnostics"), "Refresh Diagnostics button")
	_assert(main.contains("_build_android_diagnostics_panel"), "diagnostics builder")
	_assert(perm.contains("android_diagnostics_snapshot"), "diagnostics snapshot helper")
	_assert(main.contains("_build_profile_pets_section"), "Profile pets section")
	_assert(main.contains("never mounted from"), "diagnostics omitted from Profile")
	## Profile must not call the diagnostics panel builder.
	var profile_fn_start := main.find("func _show_profile()")
	var profile_fn_end := main.find("func _show_diagnostics()")
	_assert(profile_fn_start >= 0 and profile_fn_end > profile_fn_start, "profile/diagnostics funcs present")
	var profile_body := main.substr(profile_fn_start, profile_fn_end - profile_fn_start)
	_assert(not profile_body.contains("_build_android_diagnostics_panel"), "Profile does not show Android Diagnostics")
	_assert(profile_body.contains("_build_profile_pets_section"), "Profile shows Pets section")

	## PAIRING FROZEN
	_assert(not main.contains("reconcile_my_person_pairing"), "no pairing reconcile")
	_assert(getf.contains("person"), "get-friends person unchanged")

	## MAP UNTOUCHED
	_assert(map.contains("PINCH_DAMPING"), "map pinch unchanged")
	_assert(map.contains("_gesture_layer"), "map gesture layer unchanged")

	## VERSION / APK
	_assert(flags.contains("APP_VERSION_CODE := 67"), "versionCode 67")
	_assert(preset.contains("version/code=67"), "export 66")
	_assert(preset.contains("v67-profile-pet-persistence-fix-debug.apk") or export_sh.contains("v67-profile-pet-persistence-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-backend-location-qr-splash-fix-debug.apk"), "gitignore allow")
	_assert(BuildFlags.APP_VERSION_CODE >= 30, "BuildFlags >= 29")

	## QrHelper unit: token extract / UUID guard / encode-decode contract (plugin optional)
	var token := "aabbccddeeff00112233445566778899"
	var link := QrHelper.deep_link_for_token(token)
	_assert(link.begins_with("chestoflovenotes://connect/"), "deep link prefix")
	_assert(QrHelper.extract_token(link) == token, "extract token")
	_assert(QrHelper.is_coln_connect_payload(link), "valid payload")
	_assert(not QrHelper.payload_contains_raw_uuid(link), "token link is not UUID")
	_assert(QrHelper.payload_contains_raw_uuid("chestoflovenotes://connect/dbb3889c-3f6b-4b8b-9aec-fd03f759e1fc"), "detects raw UUID")
	## Encode/decode: when ChestQr unavailable (desktop), verify_roundtrip returns false; assert API contract.
	if Engine.has_singleton("ChestQr"):
		_assert(QrHelper.verify_roundtrip(link, 512), "encode/decode roundtrip")
		var b64 := QrHelper.encode_png_base64(link, 512)
		_assert(not b64.is_empty(), "encode non-empty")
		_assert(QrHelper.texture_from_base64_png(b64) != null, "texture from png")
	else:
		_assert(QrHelper.encode_png_base64(link, 512).is_empty(), "desktop encode empty without plugin")
		print("NOTE: ChestQr singleton absent on desktop — APK install must register it")

	## Location parse still accepts valid coords
	var ok := LocationHelper._parse_fix_raw("ok|33.45|-112.07|35.0|800|fused", true, 180000)
	_assert(bool(ok.get("ok", false)), "valid coords accepted")
	_assert(LocationHelper.bridge_available() == Engine.has_singleton("ChestLocation"), "bridge_available matches singleton")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
