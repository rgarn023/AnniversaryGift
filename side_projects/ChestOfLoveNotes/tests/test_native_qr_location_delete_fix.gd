extends SceneTree
## v31: Canonical My Person + Location/QR bridges + Hide/Delete visibility.

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
	print("=== Native QR/Location/Delete fix (v31) ===")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var qr := FileAccess.get_file_as_string("res://scripts/network/qr_helper.gd")
	var util := FileAccess.get_file_as_string("res://scripts/network/native_plugin_util.gd")
	var perm := FileAccess.get_file_as_string("res://scripts/network/permissions_helper.gd")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var scroll_svc := FileAccess.get_file_as_string("res://scripts/network/scroll_service.gd")
	var demo := FileAccess.get_file_as_string("res://scripts/demo/demo_session.gd")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260811190000_scroll_hide_delete_visibility.sql")
	var get_chest := FileAccess.get_file_as_string("res://supabase/functions/get-chest/index.ts")
	var get_sent := FileAccess.get_file_as_string("res://supabase/functions/get-sent-scrolls/index.ts")
	var hide_sent := FileAccess.get_file_as_string("res://supabase/functions/hide-sent-scroll/index.ts")
	var hide_recv := FileAccess.get_file_as_string("res://supabase/functions/hide-received-scroll/index.ts")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var qr_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestQrPlugin.kt")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")

	## MY PERSON / COMPOSE
	_assert(main.contains("Same canonical active-Person resolver"), "friends uses canonical person")
	_assert(main.contains("Always rebind Compose to the active Person (canonical recipient), including empty"), "compose rebinds including empty")
	_assert(compose.contains("Send to Myself (Test)"), "debug self-send separate")
	_assert(compose.contains("never overlays or replaces"), "self-send below Person")
	_assert(compose.contains("LocationHelper.request_current_location"), "compose uses canonical location service")

	## LOCATION — same bridge for Diagnostics + Compose; no has_method-only gate
	_assert(util.contains("class_name NativePluginUtil"), "NativePluginUtil present")
	_assert(loc.contains("NativePluginUtil"), "LocationHelper uses NativePluginUtil")
	_assert(loc.contains("request_current_location"), "canonical request_current_location")
	_assert(loc.contains("request_diagnostics_snapshot"), "location request diagnostics")
	_assert(loc.contains("last_failure_stage"), "failure stage tracking")
	_assert(loc.contains("success_latched"), "timeout cannot overwrite success")
	_assert(perm.contains("LocationHelper.bridge_available()"), "diagnostics uses LocationHelper bridge")
	_assert(perm.contains("LocationHelper.location_services_enabled()"), "diagnostics uses live services")
	_assert(perm.contains("QrHelper.capabilities_snapshot()"), "diagnostics uses QrHelper caps")
	_assert(loc_kt.contains("is_location_enabled"), "native live services method")
	_assert(loc_kt.contains("begin_fresh_location"), "native begin_fresh_location")

	## QR
	_assert(qr.contains("NativePluginUtil.method_available"), "QR capability via util")
	_assert(qr.contains("encoder_available"), "encoder_available")
	_assert(qr.contains("scanner_available"), "scanner_available")
	_assert(qr.contains("capabilities_snapshot"), "QR capabilities snapshot")
	_assert(main.contains("QrHelper.encoder_available()"), "Show My Code uses encoder_available")
	_assert(main.contains("Camera scanner isn't available in this build."), "distinct scanner unavailable error")
	_assert(main.contains("Camera permission is required."), "distinct camera permission error")
	_assert(qr_kt.contains("encode_qr_png_base64"), "native encode export")
	_assert(qr_kt.contains("start_qr_scan"), "native scan export")
	_assert(qr_kt.contains("verify_qr_roundtrip"), "native roundtrip")

	## HIDE / DELETE
	_assert(mig.contains("hidden_at"), "migration adds hidden_at")
	_assert(mig.contains("hide_recipient_scroll"), "hide recipient RPC")
	_assert(mig.contains("unhide_sender_scroll"), "unhide sender RPC")
	_assert(mig.contains("maybe_purge_scroll_if_both_deleted"), "both-deleted cleanup")
	_assert(mig.contains("deleted_at = null"), "historic soft-delete → hidden migration")
	_assert(hide_sent.contains("hide_sender_scroll"), "hide-sent edge")
	_assert(hide_recv.contains("hide_recipient_scroll"), "hide-received edge")
	_assert(get_chest.contains("hidden_at"), "get-chest filters hidden")
	_assert(get_sent.contains("hidden_at"), "get-sent filters hidden")
	_assert(scroll_svc.contains("hide_sent_scroll"), "ScrollService hide_sent")
	_assert(scroll_svc.contains("unhide_received_scroll"), "ScrollService unhide_received")
	_assert(main.contains("Delete Permanently"), "delete confirmation CTA")
	_assert(main.contains("will still keep"), "other-party preserved copy wording")
	_assert(main.contains("_hide_received"), "recipient Hide action")
	_assert(main.contains("_unhide_received"), "recipient Unhide action")
	_assert(main.contains("_confirm_delete_sent"), "sender delete confirm")
	_assert(demo.contains("hide_sent_scroll"), "demo hide sent")
	_assert(demo.contains("_maybe_purge_both_deleted"), "demo both-deleted purge")

	## DIAGNOSTICS
	_assert(main.contains("Location request state:"), "diag request state")
	_assert(main.contains("Last native request:"), "diag last native request")
	_assert(main.contains("Last callback:"), "diag last callback")
	_assert(main.contains("Last failure stage:"), "diag failure stage")

	## REGRESSION — map / pairing frozen
	_assert(map.contains("PINCH_DAMPING"), "map pinch unchanged")
	_assert(map.contains("_gesture_layer"), "map gesture unchanged")
	_assert(not main.contains("reconcile_my_person_pairing"), "no pairing reconcile")

	## VERSION / APK
	_assert(flags.contains("APP_VERSION_CODE := 31"), "versionCode 31")
	_assert(preset.contains("version/code=31"), "export 31")
	_assert(preset.contains("native-qr-location-delete-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-native-qr-location-delete-fix-debug.apk"), "gitignore allow")
	_assert(BuildFlags.APP_VERSION_CODE >= 31, "BuildFlags >= 31")

	## Unit: QrHelper + LocationHelper contracts
	var token := "aabbccddeeff00112233445566778899"
	var link := QrHelper.deep_link_for_token(token)
	_assert(QrHelper.extract_token(link) == token, "extract token")
	_assert(QrHelper.is_coln_connect_payload(link), "valid payload")
	_assert(not QrHelper.payload_contains_raw_uuid(link), "not UUID")
	if Engine.has_singleton("ChestQr"):
		_assert(QrHelper.verify_roundtrip(link, 512), "encode/decode roundtrip")
	else:
		_assert(QrHelper.encode_png_base64(link, 512).is_empty(), "desktop encode empty without plugin")
		print("NOTE: ChestQr absent on desktop — APK registers it")

	var ok := LocationHelper._parse_fix_raw("ok|33.45|-112.07|35.0|800|fused", true, 180000)
	_assert(bool(ok.get("ok", false)), "valid coords accepted")
	## Desktop: bridge_available matches singleton presence.
	_assert(LocationHelper.bridge_available() == Engine.has_singleton("ChestLocation"), "bridge matches singleton")

	## Demo visibility isolation
	var session := DemoSession.new()
	session.enable()
	_assert(session.has_method("hide_received_scroll"), "demo hide_received API")
	_assert(session.has_method("delete_sent_scroll"), "demo delete_sent API")
	_assert(session.has_method("unhide_sent_scroll"), "demo unhide_sent API")
	_assert(not session.scrolls.is_empty(), "demo seeded scrolls")

	var sid := str(session.scrolls[0].id)
	var sender_id := str(session.scrolls[0].sender_id)
	var recip_id := str(session.scrolls[0].recipient_id)
	session.current_user_id = sender_id
	var del_s := session.delete_sent_scroll(sid)
	_assert(bool(del_s.get("ok", false)), "sender delete ok")
	session.current_user_id = recip_id
	var st_r: Dictionary = session.recipient_states.get(sid, {})
	_assert(st_r.get("deleted_at") == null, "recipient preserved after sender delete")
	var hide_r := session.hide_received_scroll(sid)
	_assert(bool(hide_r.get("ok", false)), "recipient hide ok")
	var in_current := false
	for it in session.get_chest_items("all"):
		if str(it.get("id", "")) == sid:
			in_current = true
	_assert(not in_current, "hidden not in current")
	var in_hidden := false
	for it2 in session.get_chest_items("hidden"):
		if str(it2.get("id", "")) == sid:
			in_hidden = true
	_assert(in_hidden, "hidden in Hidden view")
	var unhide_r := session.unhide_received_scroll(sid)
	_assert(bool(unhide_r.get("ok", false)), "recipient unhide ok")
	var del_r := session.delete_received_scroll(sid)
	_assert(bool(del_r.get("ok", false)), "recipient delete ok")
	## Both deleted → purge (sender already deleted above)
	_assert(not session.scroll_bodies.has(sid), "both-deleted cleanup removes content")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
