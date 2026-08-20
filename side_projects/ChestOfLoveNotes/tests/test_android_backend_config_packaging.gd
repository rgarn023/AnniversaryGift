extends SceneTree
## v71: Android export must stage+pack backend_config via the wrapper hard gate.

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
	print("=== Android backend-config packaging gate (v71) ===")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var prepare := FileAccess.get_file_as_string("res://tools/prepare_backend_config.py")
	var verify := FileAccess.get_file_as_string("res://tools/verify_backend_config_for_export.py")
	var apk_gate := FileAccess.get_file_as_string("res://tools/verify_apk_packed_backend_config.py")
	var runtime_gate := FileAccess.get_file_as_string("res://tools/validate_exported_backend_runtime.py")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var cfg := FileAccess.get_file_as_string("res://scripts/network/backend_config.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var parrot := FileAccess.get_file_as_string("res://scripts/pets/pet_animation_loader.gd")
	var readme := FileAccess.get_file_as_string("res://README.md")

	_assert(export_sh.contains("Do NOT call `godot --export-debug` directly"), "wrapper forbids raw godot export")
	_assert(export_sh.contains("prepare_backend_config.py"), "wrapper prepares config")
	_assert(export_sh.contains("verify_backend_config_for_export.py"), "wrapper verifies staged config")
	_assert(export_sh.contains("verify_apk_packed_backend_config.py"), "wrapper hard-gates packed APK")
	_assert(export_sh.contains("validate_exported_backend_runtime.py"), "wrapper validates exported runtime load")
	_assert(export_sh.contains("packed size matches staged source") or export_sh.contains("packed config size"), "wrapper checks size parity")
	_assert(apk_gate.contains("assets/config/backend_config.json"), "apk gate looks for packed path")
	_assert(apk_gate.contains("Backend is not configured"), "apk gate explains failure mode")
	_assert(runtime_gate.contains("YOUR_SUPABASE"), "runtime gate rejects placeholders")
	_assert(prepare.contains("SUPABASE_URL"), "prepare uses SUPABASE_URL")
	_assert(verify.contains("config/backend_config.json"), "verify checks staged path")
	_assert(preset.contains("config/backend_config.json"), "export include_filter packs config")
	_assert(cfg.contains("res://config/backend_config.json"), "runtime RES_PATH matches pack path")
	_assert(gitignore.contains("config/backend_config.json"), "live config stays gitignored")
	_assert(flags.contains("0.1.74-auth-recovery-google-signin"), "version name bumped")
	_assert(flags.contains("APP_VERSION_CODE := 74"), "version code bumped")
	_assert(readme.contains("tools/export_android_apk.sh"), "README mandates wrapper")
	_assert(readme.contains("Do not call `godot --export-debug` directly"), "README forbids raw export")
	## Do not regress parrot Android resource fix.
	_assert(parrot.contains("ResourceLoader.exists"), "parrot loader keeps ResourceLoader.exists")
	_assert(parrot.contains("FileAccess.file_exists(res://…png) is FALSE"), "parrot comment documents Android PNG probe pitfall")

	if BuildFlags.PRIVATE_ONBOARDING_BUILD:
		var backend := BackendConfig.new()
		var ok := backend.load_config()
		_assert(ok, "source project BackendConfig.load_config succeeds when staged")
		_assert(backend.is_configured(), "source project is_configured after load")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
