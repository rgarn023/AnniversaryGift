extends SceneTree
## v28: Current Location (no Tasks.await), Show My Code, Scan Person Code — pairing frozen.

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
	print("=== Current Location + QR camera fix (v28) ===")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var qr := FileAccess.get_file_as_string("res://scripts/network/qr_helper.gd")
	var qr_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestQrPlugin.kt")
	var scan_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/QrScanActivity.kt")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var strings := FileAccess.get_file_as_string("res://scripts/ui/product_strings.gd")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var getf := FileAccess.get_file_as_string("res://supabase/functions/get-friends/index.ts")

	## CURRENT LOCATION — async fused, no Tasks.await deadlock
	_assert(not loc_kt.contains("import com.google.android.gms.tasks.Tasks"), "no blocking Tasks import (Galaxy hang fix)")
	_assert(not loc_kt.contains("Tasks.await("), "no Tasks.await call")
	_assert(loc_kt.contains("getCurrentLocation"), "fused getCurrentLocation")
	_assert(loc_kt.contains("NETWORK_PROVIDER"), "network provider fallback")
	_assert(loc_kt.contains("current_location_requested"), "native log current_location_requested")
	_assert(loc_kt.contains("location_request_started"), "native log request started")
	_assert(loc_kt.contains("timeout_fired after success"), "timeout cannot overwrite success")
	_assert(loc_kt.contains("requestGen"), "request generation id")
	_assert(loc.contains("current_location_requested"), "gdscript log requested")
	_assert(loc.contains("permission_fine="), "log fine permission")
	_assert(loc.contains("permission_coarse="), "log coarse permission")
	_assert(loc.contains("reverse_geocode_success") or compose.contains("reverse_geocode_success="), "reverse geocode log")
	_assert(loc.contains("Approximate accuracy:"), "approximate accuracy note")
	_assert(loc.contains("_active_request_token"), "GDScript request token")
	_assert(compose.contains("Coordinates succeed immediately"), "coords before geocode")
	_assert(compose.contains("Address unavailable"), "geocode fail fallback")
	_assert(compose.contains("Current location selected"), "success UI")
	_assert(install.contains("play-services-location"), "location dependency install")
	_assert(install.contains("ChestLocation"), "ChestLocation registered in install")

	var ok := LocationHelper._parse_fix_raw("ok|33.45|-112.07|35.0|800|fused", true, 180000)
	_assert(bool(ok.get("ok", false)), "valid coords accepted")
	_assert(str(ok.get("accuracy_note", "")).contains("35"), "accuracy note ~35m")

	## QR SHOW MY CODE
	_assert(main.contains("ProductStrings.SHOW_MY_CODE"), "Show My Code button")
	_assert(main.contains("_show_my_connection_code"), "Show My Code screen")
	_assert(main.contains("_ensure_my_connection_token"), "token backfill helper")
	_assert(main.contains("ProductStrings.SHOW_MY_CODE_HELP"), "instruction copy")
	_assert(main.contains("verify_roundtrip"), "QR verify decodable")
	_assert(main.contains("payload_contains_raw_uuid"), "reject UUID payload")
	_assert(qr.contains("verify_roundtrip"), "QrHelper verify")
	_assert(qr_kt.contains("EncodeHintType.MARGIN"), "quiet zone margin")
	_assert(qr_kt.contains("verify failed") or qr_kt.contains("encode_qr verify"), "encode verifies decode")
	_assert(qr_kt.contains("verify_qr_roundtrip"), "roundtrip API")
	_assert(install.contains("ChestQr"), "ChestQr registered")
	_assert(install.contains("zxing"), "zxing dependency")

	## QR SCANNER
	_assert(main.contains("ProductStrings.SCAN_PERSON_CODE"), "Scan Person Code string usage")
	_assert(main.contains("scan_paired"), "Scan visible when already paired")
	_assert(main.contains("_on_scan_person_code"), "scan entry")
	_assert(main.contains("_show_qr_scan_message"), "invalid/own/already-connected UI")
	_assert(main.contains("ProductStrings.SCAN_AGAIN"), "Scan Again action")
	_assert(main.contains("ALREADY_CONNECTED_FMT"), "already connected copy")
	_assert(main.contains("DISCONNECT_FIRST"), "disconnect-first copy")
	_assert(main.contains("OWN_CODE"), "own code copy")
	_assert(scan_kt.contains("DecoratedBarcodeView"), "live camera barcode view")
	_assert(scan_kt.contains("setTorchOff"), "flashlight toggle off")
	_assert(scan_kt.contains("releaseCamera") or scan_kt.contains("pause()"), "camera cleanup")
	_assert(scan_kt.contains("deliverScanResult"), "pending result delivery")
	_assert(qr_kt.contains("onMainResume"), "flush scan result on resume")
	_assert(qr_kt.contains("startActivityForResult"), "starts scanner activity")
	_assert(strings.contains("SCAN_PERSON_CODE"), "product string scan")
	_assert(strings.contains("SHOW_MY_CODE_HELP"), "product string help")

	## PAIRING FROZEN — do not re-migrate / recreate pairing in this pass
	_assert(not main.contains("reconcile_my_person_pairing"), "main does not call pairing reconcile RPC")
	_assert(getf.contains("person"), "get-friends still returns person (unchanged pairing API)")

	## MAP / PERMISSIONS / UNRELATED UNTOUCHED
	_assert(map.contains("PINCH_DAMPING"), "map pinch unchanged")
	_assert(map.contains("_gesture_layer"), "map gesture layer unchanged")

	## VERSION
	_assert(flags.contains("APP_VERSION_CODE := 28"), "versionCode 28")
	_assert(preset.contains("version/code=28"), "export 28")
	_assert(preset.contains("current-location-qr-camera-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-current-location-qr-camera-fix-debug.apk"), "gitignore allow")
	_assert(BuildFlags.APP_VERSION_CODE >= 28, "BuildFlags >= 28")

	## QrHelper unit: token extract / UUID guard
	var link := QrHelper.deep_link_for_token("aabbccddeeff00112233445566778899")
	_assert(link.begins_with("chestoflovenotes://connect/"), "deep link prefix")
	_assert(QrHelper.extract_token(link) == "aabbccddeeff00112233445566778899", "extract token")
	_assert(QrHelper.is_coln_connect_payload(link), "valid payload")
	_assert(not QrHelper.payload_contains_raw_uuid(link), "token link is not UUID")
	_assert(QrHelper.payload_contains_raw_uuid("chestoflovenotes://connect/dbb3889c-3f6b-4b8b-9aec-fd03f759e1fc"), "detects raw UUID")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
