extends SceneTree
## Regression: Current Location success semantics + My Person pairing repair.

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
	print("=== Current Location + My Person repair (v27) ===")
	var loc := FileAccess.get_file_as_string("res://scripts/network/location_helper.gd")
	var loc_kt := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/ChestLocationPlugin.kt")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var getf := FileAccess.get_file_as_string("res://supabase/functions/get-friends/index.ts")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260811170000_reconcile_accepted_person_pairings.sql")
	var state := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var install := FileAccess.get_file_as_string("res://android/plugins/chest_secure_storage/install_into_android_build.sh")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var map := FileAccess.get_file_as_string("res://scripts/ui/map_location_picker.gd")

	## CURRENT LOCATION — fused pipeline + success semantics
	_assert(loc_kt.contains("FusedLocationProviderClient"), "uses fused location client")
	_assert(loc_kt.contains("getCurrentLocation"), "uses getCurrentLocation")
	_assert(loc_kt.contains("PRIORITY_BALANCED_POWER_ACCURACY"), "balanced fused current location")
	_assert(loc_kt.contains("PRIORITY_HIGH_ACCURACY"), "high accuracy updates")
	_assert(loc_kt.contains("fixAccepted"), "accepted-fix flag")
	_assert(loc_kt.contains("timeout fired after success — ignored"), "timeout cannot overwrite success")
	_assert(loc_kt.contains("FRESH_TIMEOUT_MS = 45_000L"), "practical 45s timeout")
	_assert(loc_kt.contains("Tasks.await(client.lastLocation"), "awaits fused lastLocation")
	_assert(loc.contains("MAX_ACCEPTABLE_ACCURACY_M := 500.0"), "sensible accuracy threshold 500m")
	_assert(loc.contains("MAX_FIX_AGE_MS := 120000"), "120s fix age for selection")
	_assert(loc.contains("keeping settled success"), "GDScript timeout race guard")
	_assert(loc.contains("trying last-known fallback"), "timeout tries last-known")
	_assert(loc.contains("accuracy_note"), "optional accuracy note")
	_assert(compose.contains("Address unavailable"), "reverse-geocode failure fallback copy")
	_assert(compose.contains("Coordinates succeed immediately"), "coords before reverse geocode")
	_assert(compose.contains("never fail or clear the lock target if reverse geocode fails"), "geocode fail ≠ location fail")
	_assert(compose.contains("preserved_radius"), "radius preserved on current location")
	_assert(compose.contains("Current location selected"), "success status copy")
	_assert(install.contains("play-services-location"), "Play Services location packaged via install")

	## Runtime parse: coords + accuracy
	var ok_geo := LocationHelper._parse_fix_raw("ok|33.45|-112.07|30.0|1200|fused", true, 120000)
	_assert(bool(ok_geo.get("ok", false)), "valid coords + reverse-geocode-irrelevant parse ok")
	_assert(str(ok_geo.get("accuracy_note", "")).contains("30"), "accuracy note ~30m")
	var mediocre := LocationHelper._parse_fix_raw("ok|33.45|-112.07|180.0|2000|fused", true, 120000)
	_assert(bool(mediocre.get("ok", false)), "mediocre accuracy accepted under 500m")
	var too_bad := LocationHelper._parse_fix_raw("ok|33.45|-112.07|900.0|2000|fused", true, 120000)
	_assert(not bool(too_bad.get("ok", false)), "extreme accuracy still rejected")
	var stale := LocationHelper._parse_fix_raw("ok|33.45|-112.07|20.0|999999|fused", true, 120000)
	_assert(not bool(stale.get("ok", false)), "very stale rejected")

	## MY PERSON — migrate + profile delay + compose
	_assert(getf.contains("reconcileAcceptedPairing"), "get-friends reconciles accepted requests")
	_assert(getf.contains("profile_pending"), "pairing survives profile lookup delay")
	_assert(getf.contains("My Person"), "fallback display name when profile missing")
	_assert(not getf.contains("public_connection_token") or getf.contains("meProfile"), "person select does not require their token")
	_assert(mig.contains("reconcile_my_person_pairing"), "SQL reconcile RPC")
	_assert(mig.contains("status = 'accepted'"), "migrates accepted relationships")
	_assert(mig.contains("on conflict do nothing"), "no duplicate pairings")
	_assert(state.contains("remember_person"), "sticky person identity cache")
	_assert(state.contains("apply_friends_payload"), "friends payload merge")
	_assert(state.contains("clear_last_person_cache"), "clears on disconnect/sign-out")
	_assert(main.contains("apply_friends_payload"), "main uses friends payload helper")
	_assert(main.contains("profile_pending"), "main hydrates pending profile")
	_assert(compose.contains("Test with myself"), "debug self-send separate label")
	_assert(compose.contains("Production recipient is always the active Person"), "compose forces Person")
	_assert(compose.contains("is_self_test"), "self-test flag remains")
	_assert(compose.contains("ProductStrings.to_label(person_name)"), "To <Person> from my_person")

	## MAP UNTOUCHED (gesture/pinch constants still present; this pass must not regress)
	_assert(map.contains("PINCH_DAMPING"), "map pinch unchanged")
	_assert(map.contains("_gesture_layer"), "map gesture layer unchanged")

	## VERSION / APK
	_assert(flags.contains("APP_VERSION_CODE := 27"), "versionCode 27")
	_assert(preset.contains("version/code=27"), "export versionCode 27")
	_assert(preset.contains("current-location-person-repair-debug.apk"), "export APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-current-location-person-repair-debug.apk"), "APK gitignore allow")
	_assert(BuildFlags.APP_VERSION_CODE >= 27, "BuildFlags >= 27")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
