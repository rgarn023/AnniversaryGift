extends SceneTree
## Headless checks for BackendConfig load/export readiness.

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
	print("=== BackendConfig load tests ===")
	var cfg := BackendConfig.new()
	var ok := cfg.load_config()
	if BuildFlags.PRIVATE_ONBOARDING_BUILD:
		_assert(ok, "private onboarding build loads backend_config.json")
		_assert(cfg.is_configured(), "is_configured true after successful load")
		_assert(not cfg.supabase_url.is_empty(), "supabase_url non-empty")
		_assert(not cfg.supabase_publishable_key.is_empty(), "publishable key non-empty")
		_assert(not cfg.supabase_url.contains("YOUR_SUPABASE"), "url is not placeholder")
		_assert(not cfg.supabase_publishable_key.contains("YOUR_SUPABASE"), "key is not placeholder")
		var state := AppState.new()
		state.bootstrap()
		_assert(state.is_online(), "bootstrap enters ONLINE when config present")
		_assert(not state.is_demo(), "demo stays disabled for private online")
	else:
		_assert(true, "skipped private-onboarding assertions")

	# Example file must remain a placeholder template (never treated as live config).
	if FileAccess.file_exists(BackendConfig.EXAMPLE_PATH):
		var example := FileAccess.open(BackendConfig.EXAMPLE_PATH, FileAccess.READ)
		_assert(example != null, "example config readable")
		if example != null:
			var text := example.get_as_text()
			example.close()
			_assert(text.contains("YOUR_SUPABASE"), "example retains placeholders")
			_assert(cfg.supabase_url.is_empty() or not text.contains(cfg.supabase_url), "live url not stored in example")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
