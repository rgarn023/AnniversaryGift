extends SceneTree
## v33: Game-quality hybrid chest + durable My Person disconnect (no auto-reconnect).

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
	print("=== Game-quality chest + disconnect fix (v33) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var disc := FileAccess.get_file_as_string("res://supabase/functions/disconnect-person/index.ts")
	var getf := FileAccess.get_file_as_string("res://supabase/functions/get-friends/index.ts")
	var block := FileAccess.get_file_as_string("res://supabase/functions/block-user/index.ts")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260812120000_disconnect_prevents_rehydrate.sql")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var compose := FileAccess.get_file_as_string("res://scripts/scroll/compose_scroll_screen.gd")
	var strings := FileAccess.get_file_as_string("res://scripts/ui/product_strings.gd")

	## SPLASH unchanged timing
	_assert(boot.contains("MIN_VISIBLE_SEC := 2.0"), "splash min 2.0s kept")
	_assert(boot.contains("mark_app_ready"), "splash app-ready gate kept")
	_assert(main.contains("mark_app_ready"), "main still marks boot ready")

	## CHEST hybrid game-feel
	_assert(chest.contains("Architecture C") or chest.contains("Hybrid"), "hybrid architecture")
	_assert(chest.contains("chest_interior.png"), "interior layer")
	_assert(chest.contains("_ease_open_curve"), "custom open easing")
	_assert(chest.contains("OPEN_WAITING_FOR_SCROLL"), "waiting-for-scroll state")
	_assert(chest.contains("sfx_latch_release"), "latch sound hook")
	_assert(chest.contains("sfx_magical_swell"), "magical swell hook")
	_assert(chest.contains("_motes"), "restrained motes")
	_assert(chest.contains("_rim_light"), "rim light spill")
	_assert(chest.contains("EMPHASIS_SCALE"), "tiny open emphasis")
	_assert(chest.contains("clip_contents = true"), "scroll occlusion clip")
	_assert(not chest.contains("scale.y"), "no scale.y squash")
	_assert(not chest.contains("_cinematic_zoom"), "no cinematic zoom reopen")
	_assert(chest.contains("OPEN_DURATION_SEC := 0.88"), "open duration tuned")
	for fname in [
		"chest_closed.png", "chest_open_10.png", "chest_open_25.png",
		"chest_ajar.png", "chest_half.png", "chest_open.png", "chest_interior.png",
	]:
		_assert(FileAccess.file_exists("res://assets/art/chest/%s" % fname), "asset %s" % fname)

	## DISCONNECT durable — root cause fix
	_assert(disc.contains('status: "cancelled"'), "disconnect cancels requests")
	_assert(disc.contains('.eq("status", "accepted")'), "cancels accepted requests")
	_assert(disc.contains("pending"), "cancels pending requests")
	_assert(disc.contains("Durable disconnect tombstone") or disc.contains("auto-reconnect"), "documents root cause")
	_assert(getf.contains('String(fr.status) !== "accepted"'), "reconcile refuses non-accepted")
	_assert(getf.contains("never resurrect") or getf.contains("deliberate disconnect"), "reconcile docs disconnect")
	_assert(mig.contains("status = 'cancelled'"), "migration tombs orphaned accepted")
	_assert(mig.contains("reconcile_my_person_pairing"), "migration updates reconcile RPC")
	_assert(block.contains('.eq("status", "accepted")'), "block also cancels accepted")
	_assert(main.contains("Disconnected from %s"), "named disconnect toast")
	_assert(main.contains("Couldn't disconnect right now. Please try again."), "failure keeps pairing")
	_assert(main.contains("clear_last_person_cache"), "clears local person cache")
	_assert(strings.contains("Existing scroll history will remain"), "confirm preserves history")
	_assert(compose.contains("COMPOSE_NEED_PERSON"), "compose needs person gate")

	## VERSION / APK
	_assert(flags.contains("APP_VERSION_CODE := 33"), "versionCode 33")
	_assert(preset.contains("version/code=33"), "export 33")
	_assert(preset.contains("game-quality-chest-disconnect-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("ChestOfLoveNotes-game-quality-chest-disconnect-fix-debug.apk"), "gitignore allow")
	_assert(export_sh.contains("game-quality-chest-disconnect-fix-debug.apk"), "export default")
	_assert(BuildFlags.APP_VERSION_CODE >= 33, "BuildFlags >= 33")

	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
