extends SceneTree
## v30: Backend config packaging + bridges + splash pipeline + Mandy/Compose.

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
	print("=== Backend + location + QR + splash fix (v30) ===")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var qr := FileAccess.get_file_as_string("res://scripts/network/qr_helper.gd")
	var perm := FileAccess.get_file_as_string("res://scripts/network/permissions_helper.gd")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var cfg := FileAccess.get_file_as_string("res://scripts/network/backend_config.gd")
	var prepare := FileAccess.get_file_as_string("res://tools/prepare_backend_config.py")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var splash_py := FileAccess.get_file_as_string("res://tools/prepare_charoite_splash_from_gif.py")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")
	var project := FileAccess.get_file_as_string("res://project.godot")

	## BACKEND — exact string sources + packaging
	_assert(main.contains("Backend is not configured."), "main contains Backend is not configured")
	_assert(cfg.contains("RES_PATH"), "BackendConfig RES_PATH")
	_assert(cfg.contains("is_configured"), "BackendConfig is_configured")
	_assert(prepare.contains("SUPABASE_ANON_KEY") or prepare.contains("SUPABASE_PUBLISHABLE_KEY"), "prepare uses public key env")
	_assert(prepare.contains("SUPABASE_SERVICE_ROLE_KEY"), "prepare forbids service role match")
	_assert(export_sh.contains("prepare_backend_config.py"), "export runs prepare")
	_assert(export_sh.contains("verify_backend_config_for_export.py"), "export runs verify")
	_assert(export_sh.contains("backend_config.json"), "export checks packed config")
	_assert(preset.contains("config/backend_config.json"), "export include_filter packs config")
	_assert(prepare.contains("FORBIDDEN_ENV"), "prepare refuses privileged secrets")
	_assert(not prepare.contains('"supabase_service_role'), "prepare json has no service role field")

	## COMPOSE Mandy
	_assert(compose.contains("Send to Myself (Test)"), "debug self-send separate")
	_assert(compose.contains("never overlays or replaces"), "self-send below Person")
	_assert(main.contains("Always rebind Compose to the active Person"), "compose rebind")
	_assert(main.contains("sticky identity for Compose"), "sticky person")

	## LOCATION native (no Supabase required for coords)
	_assert(loc.contains("LOCATION BRIDGE MISSING"), "bridge missing log")
	_assert(loc.contains("_await_plugin_ready"), "await plugin")
	_assert(compose.contains("Coordinates succeed immediately"), "coords before geocode")
	_assert(not loc.contains("Backend is not configured"), "location helper no backend string")

	## CAMERA / QR
	_assert(qr.contains("os_granted or plugin_granted"), "live camera OR")
	_assert(perm.contains("os_ok or plugin_ok"), "permissions camera OR")
	_assert(main.contains("Camera scanner couldn't start."), "scanner init vs permission")
	_assert(main.contains("Do NOT re-verify at a different size"), "QR single-size encode")
	_assert(main.contains("QR generation unavailable"), "QR fail fallback")
	_assert(main.contains("ProductStrings.CONNECTION_CODE"), "Connection Code visible")

	## DIAGNOSTICS backend fields
	_assert(main.contains("Backend configured:"), "diag backend configured")
	_assert(main.contains("Supabase client:"), "diag supabase client")
	_assert(main.contains("Authenticated session:"), "diag session")
	_assert(main.contains("Connection-token service:"), "diag token service")
	_assert(perm.contains("backend_configured"), "snapshot backend field")

	## SPLASH — approved GIF pipeline (no redraw)
	_assert(boot.contains("154659_cursor_under4mb.gif"), "boot references approved GIF")
	_assert(boot.contains("splash_frames"), "boot plays frame sequence")
	_assert(boot.contains("reduced_motion"), "reduced motion still")
	_assert(boot.contains("Color(0.0, 0.0, 0.0"), "black background")
	_assert(boot.contains("Intentionally NO Label"), "splash has no extra labels/starfield chrome")
	_assert(splash_py.contains("154659_cursor_under4mb.gif"), "converter source GIF")
	_assert(splash_py.contains("source_redrawn\": False") or splash_py.contains('"source_redrawn": False'), "converter no redraw")
	_assert(project.contains("boot_splash/bg_color=Color(0, 0, 0, 1)"), "native splash black")

	## MAP untouched
	_assert(map.contains("PINCH_DAMPING"), "map pinch unchanged")
	_assert(map.contains("_gesture_layer"), "map gesture unchanged")

	## VERSION
	_assert(flags.contains("APP_VERSION_CODE := 30"), "versionCode 30")
	_assert(preset.contains("version/code=30"), "export 30")
	_assert(preset.contains("backend-location-qr-splash-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-backend-location-qr-splash-fix-debug.apk"), "gitignore allow")
	_assert(BuildFlags.APP_VERSION_CODE >= 30, "BuildFlags >= 30")

	## Pairing frozen
	_assert(not main.contains("reconcile_my_person_pairing"), "no pairing reconcile")

	## QrHelper unit
	var token := "aabbccddeeff00112233445566778899"
	var link := QrHelper.deep_link_for_token(token)
	_assert(QrHelper.extract_token(link) == token, "extract token")
	_assert(not QrHelper.payload_contains_raw_uuid(link), "not UUID")

	var ok := LocationHelper._parse_fix_raw("ok|33.45|-112.07|35.0|800|fused", true, 180000)
	_assert(bool(ok.get("ok", false)), "valid coords accepted")

	## BackendConfig unit: empty = not configured
	var bc := BackendConfig.new()
	_assert(not bc.is_configured(), "fresh BackendConfig not configured")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
