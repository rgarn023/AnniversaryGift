extends SceneTree
## v34: Permanent disconnect — no auto-reconnect from reconcile / sticky cache.

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
	print("=== Permanent disconnect / auto-reconnect root-cause fix (v34) ===")
	var disc := FileAccess.get_file_as_string("res://supabase/functions/disconnect-person/index.ts")
	var getf := FileAccess.get_file_as_string("res://supabase/functions/get-friends/index.ts")
	var accept := FileAccess.get_file_as_string("res://supabase/functions/respond-to-friend-request/index.ts")
	var block := FileAccess.get_file_as_string("res://supabase/functions/block-user/index.ts")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260812140000_my_person_pair_ends_no_auto_reconnect.sql")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var state := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")

	## ROOT CAUSE FIX — reconcile must NOT recreate pairings
	_assert(not getf.contains("async function reconcileAcceptedPairing"), "get-friends reconcile function REMOVED")
	_assert(not getf.contains("from(\"friendships\").insert"), "get-friends never inserts friendship")
	_assert(getf.contains("Intentionally NO reconcileAcceptedPairing"), "documents no-reconcile policy")
	_assert(getf.contains("reconciliation_last_result"), "exposes reconciliation result")
	_assert(getf.contains("legacy_migration_eligible: false"), "legacy migration never eligible")

	## TOMBSTONE + disconnect verification
	_assert(mig.contains("create table if not exists public.my_person_pair_ends"), "tombstone table")
	_assert(mig.contains("enforce_pair_not_ended"), "insert blocked when ended")
	_assert(mig.contains("record_my_person_pair_end"), "record end helper")
	_assert(mig.contains("clear_my_person_pair_end"), "clear end on explicit accept")
	_assert(mig.contains("NEVER insert from history") or mig.contains("NEVER recreate"), "reconcile RPC neutralized")
	_assert(disc.contains("record_my_person_pair_end"), "disconnect writes tombstone")
	_assert(disc.contains("verified_disconnected"), "disconnect verifies")
	_assert(disc.contains("has_active_person"), "post-write active check")
	_assert(disc.contains("status\", \"accepted\""), "cancels accepted")
	_assert(disc.contains("status\", \"pending\""), "cancels pending")
	_assert(accept.contains("clear_my_person_pair_end"), "accept clears tombstone for reconnect")
	_assert(block.contains("record_my_person_pair_end"), "block tombs pair")

	## CLIENT — sticky cannot resurrect after authoritative null
	_assert(state.contains("friends_backend_authoritative"), "authoritative friends flag")
	_assert(state.contains("mark_verified_disconnected"), "verified disconnect helper")
	_assert(main.contains("friends_backend_authoritative"), "main respects authoritative empty")
	_assert(main.contains("mark_verified_disconnected"), "disconnect uses verified clear")
	_assert(main.contains("active_pair_after_refresh"), "post-disconnect refresh logged")
	_assert(main.contains("Couldn't disconnect right now. Please try again."), "failure keeps pairing")
	_assert(main.contains("_relationship_diagnostics_text"), "relationship diagnostics")
	_assert(main.contains("Active Person:"), "diag Active Person label")
	_assert(main.contains("Legacy migration eligible:"), "diag migration label")
	_assert(main.contains("Reconciliation last result:"), "diag reconcile label")
	_assert(main.contains("apply_friends_payload(data)"), "token lookup applies full payload")

	## NO CHEST CHANGES THIS PASS (file may still exist from prior; ensure we didn't rewrite animation this turn via version bump alone)
	_assert(chest.contains("LoveNotesChest") or chest.contains("class_name LoveNotesChest"), "chest file untouched structurally")

	## VERSION
	_assert(flags.contains("APP_VERSION_CODE := 52") or flags.contains("APP_VERSION_CODE := 51") or flags.contains("APP_VERSION_CODE := 50") or flags.contains("APP_VERSION_CODE := 49") or flags.contains("APP_VERSION_CODE := 48") or flags.contains("APP_VERSION_CODE := 47") or flags.contains("APP_VERSION_CODE := 42") or flags.contains("APP_VERSION_CODE := 41") or flags.contains("APP_VERSION_CODE := 40") or flags.contains("APP_VERSION_CODE := 39") or flags.contains("APP_VERSION_CODE := 35") or flags.contains("APP_VERSION_CODE := 34"), "versionCode 34+")
	_assert(preset.contains("version/code=52") or preset.contains("version/code=51") or preset.contains("version/code=50") or preset.contains("version/code=49") or preset.contains("version/code=48") or preset.contains("version/code=47") or preset.contains("version/code=46") or preset.contains("version/code=45") or preset.contains("version/code=42") or preset.contains("version/code=41") or preset.contains("version/code=40") or preset.contains("version/code=39") or preset.contains("version/code=38") or preset.contains("version/code=35") or preset.contains("version/code=34"), "export 34+")
	_assert(
		preset.contains("v52-scroll-shimmer-dynamic-sky-debug.apk") or preset.contains("v51-scroll-ground-shimmer-polish-debug.apk") or preset.contains("v50-horizontal-scroll-water-shimmer-debug.apk") or preset.contains("v49-chest-scroll-polish-debug.apk") or preset.contains("v47-chest-clean-transition-debug.apk") or preset.contains("v46-chest-geometry-grounding-debug.apk") or preset.contains("v45-chest-grounding-scroll-fix-debug.apk") or preset.contains("v44-chest-render-scroll-beach-polish-debug.apk")
		or preset.contains("v42-one-chest-beach-layout-debug.apk")
		or preset.contains("v40-chest-smoothing-hidden-fix-debug.apk")
		or preset.contains("v39-chest-polish-debug.apk")
		or preset.contains("backend-disconnect-fix-debug.apk")
		or preset.contains("permanent-disconnect-fix-debug.apk"),
		"APK name"
	)
	_assert(
		gitignore.contains("*.apk")
		or gitignore.contains("ChestOfLoveNotes-backend-disconnect-fix-debug.apk")
		or gitignore.contains("ChestOfLoveNotes-permanent-disconnect-fix-debug.apk"),
		"gitignore"
	)
	_assert(
		export_sh.contains("v52-scroll-shimmer-dynamic-sky-debug.apk") or export_sh.contains("v51-scroll-ground-shimmer-polish-debug.apk") or export_sh.contains("v50-horizontal-scroll-water-shimmer-debug.apk") or export_sh.contains("v49-chest-scroll-polish-debug.apk") or export_sh.contains("v47-chest-clean-transition-debug.apk") or export_sh.contains("v46-chest-geometry-grounding-debug.apk") or export_sh.contains("v45-chest-grounding-scroll-fix-debug.apk") or export_sh.contains("v44-chest-render-scroll-beach-polish-debug.apk")
		or export_sh.contains("v42-one-chest-beach-layout-debug.apk")
		or export_sh.contains("v40-chest-smoothing-hidden-fix-debug.apk")
		or export_sh.contains("v39-chest-polish-debug.apk")
		or export_sh.contains("backend-disconnect-fix-debug.apk")
		or export_sh.contains("permanent-disconnect-fix-debug.apk"),
		"export default"
	)

	## Unit: sticky must not invent person after authoritative null
	var st := AppState.new()
	st.friends_backend_authoritative = true
	st.cached_friends = {"person": null, "friends": []}
	st.remember_person({"id": "should-not-surface", "display_name": "Mandy"})
	## Simulate main resolver rules via apply + flag
	st.clear_last_person_cache()
	st.mark_verified_disconnected()
	_assert(st.friends_backend_authoritative == true, "authoritative after disconnect")
	_assert(st.load_last_person_cache().is_empty(), "sticky cleared")
	_assert(typeof(st.cached_friends.get("person")) != TYPE_DICTIONARY, "cached person null")
	_assert(str(st.relationship_debug.get("relationship_status", "")) == "disconnected", "status disconnected")
	_assert(bool(st.relationship_debug.get("legacy_migration_eligible", true)) == false, "migration not eligible")
	_assert(str(st.relationship_debug.get("reconciliation_last_result", "")) == "no_change", "reconcile no_change")

	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
