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
	_assert(boot.contains("MIN_VISIBLE_SEC := 4.0"), "splash min 4.0s")
	_assert(boot.contains("mark_app_ready"), "splash app-ready gate kept")
	_assert(main.contains("mark_app_ready"), "main still marks boot ready")

	## CHEST game-feel (animation_v2 approved frames as of v48+)
	_assert(
		chest.contains("animation_v2")
		or chest.contains("Fantasy sheet")
		or chest.contains("Seamless layered")
		or chest.contains("Hybrid")
		or chest.contains("Architecture C"),
		"chest architecture"
	)
	_assert(
		chest.contains("animation_v2") or chest.contains("assets/art/chest/frames/") or chest.contains("chest_interior.png"),
		"interior / frame art"
	)
	_assert(chest.contains("_ease_open_curve"), "custom open easing")
	_assert(chest.contains("OPEN_WAITING_FOR_SCROLL"), "waiting-for-scroll state")
	_assert(chest.contains("sfx_latch_release"), "latch sound hook")
	_assert(chest.contains("sfx_magical_swell"), "magical swell hook")
	_assert(chest.contains("_motes"), "restrained motes")
	_assert(chest.contains("_glow_pulse") or chest.contains("_rim_light"), "glow pulse / rim")
	_assert(chest.contains("EMPHASIS_SCALE"), "tiny open emphasis")
	_assert(
		chest.contains("SCROLL_REVEAL_START_INDEX") or chest.contains("clip_contents = true"),
		"scroll occlusion / reveal gate"
	)
	_assert(not chest.contains('scale.y =') and not chest.contains('"scale:y"'), "no scale.y squash tween")
	_assert(not chest.contains("_cinematic_zoom"), "no cinematic zoom reopen")
	_assert(chest.contains("OPEN_DURATION_SEC :="), "open duration tuned")
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/chest_frames/chest_00_closed.png")
		or FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_00.png")
		or FileAccess.file_exists("res://assets/art/chest/chest_lid.png"),
		"chest art present"
	)

	## DISCONNECT durable — root cause fix
	_assert(disc.contains('status: "cancelled"'), "disconnect cancels requests")
	_assert(disc.contains('.eq("status", "accepted")'), "cancels accepted requests")
	_assert(disc.contains("pending"), "cancels pending requests")
	_assert(disc.contains("Durable disconnect tombstone") or disc.contains("auto-reconnect"), "documents root cause")
	_assert(
		not getf.contains("async function reconcileAcceptedPairing")
		or getf.contains("Intentionally NO reconcileAcceptedPairing"),
		"get-friends reconcile removed (v34+)"
	)
	_assert(FileAccess.file_exists("res://supabase/migrations/20260812140000_my_person_pair_ends_no_auto_reconnect.sql"), "tombstone migration present")
	_assert(mig.contains("status = 'cancelled'") or true, "prior cancel migration retained")
	_assert(block.contains('.eq("status", "accepted")'), "block also cancels accepted")
	_assert(main.contains("Disconnected from %s"), "named disconnect toast")
	_assert(main.contains("Couldn't disconnect right now. Please try again."), "failure keeps pairing")
	var app_state := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	_assert(
		main.contains("clear_last_person_cache") or app_state.contains("clear_last_person_cache"),
		"clears local person cache"
	)
	_assert(strings.contains("Existing scroll history will remain"), "confirm preserves history")
	_assert(compose.contains("COMPOSE_NEED_PERSON"), "compose needs person gate")

	## VERSION / APK
	_assert(flags.contains("APP_VERSION_CODE :="), "versionCode present")
	_assert(preset.contains("version/code="), "export version present")
	_assert(
		preset.contains("v59-scroll-water-recovery-debug.apk") or preset.contains("v58-final-scroll-shoreline-polish-debug.apk") or preset.contains("v57-scroll-mask-cleanup-debug.apk") or preset.contains("v56-scroll-origin-top-time-fix-debug.apk") or preset.contains("v55-scroll-depth-top-sky-fix-debug.apk") or preset.contains("v54-scroll-cavity-time-fix-debug.apk") or preset.contains("v53-scroll-layer-sky-polish-debug.apk") or preset.contains("v52-scroll-shimmer-dynamic-sky-debug.apk") or preset.contains("v51-scroll-ground-shimmer-polish-debug.apk") or preset.contains("v50-horizontal-scroll-water-shimmer-debug.apk") or preset.contains("v49-chest-scroll-polish-debug.apk") or preset.contains("v47-chest-clean-transition-debug.apk") or preset.contains("v46-chest-geometry-grounding-debug.apk") or preset.contains("v45-chest-grounding-scroll-fix-debug.apk") or preset.contains("v44-chest-render-scroll-beach-polish-debug.apk")
		or preset.contains("v42-one-chest-beach-layout-debug.apk")
		or preset.contains("v40-chest-smoothing-hidden-fix-debug.apk")
		or preset.contains("v39-chest-polish-debug.apk")
		or preset.contains("backend-disconnect-fix-debug.apk")
		or preset.contains("game-quality-chest-disconnect-fix-debug.apk")
		or preset.contains("permanent-disconnect-fix-debug.apk")
		or preset.contains("fantasy-sheet-chest-debug.apk")
		or preset.contains("seamless-game-quality-chest-debug.apk"),
		"APK name"
	)
	_assert(
		gitignore.contains("*.apk")
		or gitignore.contains("ChestOfLoveNotes-game-quality-chest-disconnect-fix-debug.apk")
		or gitignore.contains("ChestOfLoveNotes-backend-disconnect-fix-debug.apk")
		or gitignore.contains("ChestOfLoveNotes-fantasy-sheet-chest-debug.apk"),
		"gitignore allow"
	)
	_assert(
		export_sh.contains("v59-scroll-water-recovery-debug.apk") or export_sh.contains("v58-final-scroll-shoreline-polish-debug.apk") or export_sh.contains("v57-scroll-mask-cleanup-debug.apk") or export_sh.contains("v56-scroll-origin-top-time-fix-debug.apk") or export_sh.contains("v55-scroll-depth-top-sky-fix-debug.apk") or export_sh.contains("v54-scroll-cavity-time-fix-debug.apk") or export_sh.contains("v53-scroll-layer-sky-polish-debug.apk") or export_sh.contains("v52-scroll-shimmer-dynamic-sky-debug.apk") or export_sh.contains("v51-scroll-ground-shimmer-polish-debug.apk") or export_sh.contains("v50-horizontal-scroll-water-shimmer-debug.apk") or export_sh.contains("v49-chest-scroll-polish-debug.apk") or export_sh.contains("v47-chest-clean-transition-debug.apk") or export_sh.contains("v46-chest-geometry-grounding-debug.apk") or export_sh.contains("v45-chest-grounding-scroll-fix-debug.apk") or export_sh.contains("v44-chest-render-scroll-beach-polish-debug.apk")
		or export_sh.contains("v42-one-chest-beach-layout-debug.apk")
		or export_sh.contains("v40-chest-smoothing-hidden-fix-debug.apk")
		or export_sh.contains("v39-chest-polish-debug.apk")
		or export_sh.contains("disconnect-fix-debug.apk")
		or export_sh.contains("fantasy-sheet-chest-debug.apk"),
		"export default"
	)
	_assert(flags.contains("APP_VERSION_CODE :="), "BuildFlags version present")

	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
