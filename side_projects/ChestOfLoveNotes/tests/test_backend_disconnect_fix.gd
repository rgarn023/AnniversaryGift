extends SceneTree
## v35: Backend disconnect must succeed (atomic RPC) — no optimistic UI clear.

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
	print("=== Backend disconnect failure fix (v35) ===")
	var disc := FileAccess.get_file_as_string("res://supabase/functions/disconnect-person/index.ts")
	var mig := FileAccess.get_file_as_string("res://supabase/migrations/20260812150000_disconnect_my_person_rpc.sql")
	var friends := FileAccess.get_file_as_string("res://scripts/network/friend_service.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var state := FileAccess.get_file_as_string("res://scripts/app_state.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var rls := FileAccess.get_file_as_string("res://supabase/migrations/20260806000002_rls_policies.sql")

	## ROOT CAUSE — atomic RPC + no hard-fail after delete on missing tombstone
	_assert(mig.contains("create or replace function public.disconnect_my_person()"), "disconnect_my_person RPC")
	_assert(mig.contains("auth.uid()"), "RPC uses auth.uid()")
	_assert(mig.contains("f.user_one_id = uid or f.user_two_id = uid"), "either participant")
	_assert(mig.contains("record_my_person_pair_end"), "tombstone in transaction")
	_assert(mig.contains("status in ('accepted', 'pending')"), "cancels accepted+pending")
	_assert(mig.contains("delete from public.friendships"), "deletes friendships")
	_assert(mig.contains("has_active_person"), "verifies after write")
	_assert(mig.contains("grant execute on function public.disconnect_my_person() to authenticated"), "authenticated execute")
	_assert(mig.contains("rows_affected"), "returns rows_affected")
	_assert(not mig.contains("service_role_key"), "no service key in SQL")

	_assert(disc.contains("disconnect_my_person"), "edge prefers RPC")
	_assert(disc.contains("createUserClient"), "edge uses user JWT for RPC")
	_assert(disc.contains("rpcMissing"), "detects missing RPC")
	_assert(disc.contains("tombstone unavailable; continuing"), "tombstone missing does not abort after plan")
	_assert(disc.contains("count: \"exact\""), "checks delete row count")
	_assert(disc.contains("disconnect_rows_affected=0") or disc.contains("delCount < 1"), "zero rows = failure")

	## CLIENT — RPC first, verified only, diagnostics
	_assert(friends.contains("rest_rpc(\"disconnect_my_person\""), "client calls RPC first")
	_assert(friends.contains("call_edge_function(\"disconnect-person\""), "edge fallback")
	_assert(friends.contains("disconnect_failure_category"), "failure categories")
	_assert(main.contains("verified_disconnected"), "requires verified")
	_assert(main.contains("Couldn't disconnect right now. Please try again."), "keeps Mandy on failure")
	_assert(main.contains("disconnect_failure_category"), "logs failure category")
	_assert(main.contains("disconnect_http_status"), "logs HTTP status")
	_assert(main.contains("active_pair_found="), "logs active_pair_found")
	_assert(main.contains("Last disconnect failure category:"), "diag failure category")
	_assert(main.contains("Disconnect mechanism:"), "diag mechanism")
	_assert(main.contains("Post-disconnect active pair:"), "diag post state")
	_assert(state.contains("record_disconnect_failure"), "records failure state")
	_assert(state.contains("record_disconnect_attempt_started"), "records started")
	_assert(state.contains("last_disconnect_failure_category"), "debug key")

	## RLS — friendships still have no client delete; RPC is the path
	_assert(rls.contains("No insert/update/delete policies for authenticated clients") \
		or rls.contains("friendships_select_participants"), "friendships RLS inspected")

	## NO CHEST / version / APK
	_assert(chest.contains("class_name LoveNotesChest") or chest.contains("LoveNotesChest"), "chest untouched")
	_assert(flags.contains("APP_VERSION_CODE := 48") or flags.contains("APP_VERSION_CODE := 48") or flags.contains("APP_VERSION_CODE := 47") or flags.contains("APP_VERSION_CODE := 42") or flags.contains("APP_VERSION_CODE := 41") or flags.contains("APP_VERSION_CODE := 40") or flags.contains("APP_VERSION_CODE := 39") or flags.contains("APP_VERSION_CODE := 35"), "versionCode 35+")
	_assert(preset.contains("version/code=48") or preset.contains("version/code=47") or preset.contains("version/code=46") or preset.contains("version/code=45") or preset.contains("version/code=42") or preset.contains("version/code=41") or preset.contains("version/code=40") or preset.contains("version/code=39") or preset.contains("version/code=38") or preset.contains("version/code=35"), "export 35+")
	_assert(
		preset.contains("v48-approved-smooth-chest-debug.apk") or preset.contains("v47-chest-clean-transition-debug.apk") or preset.contains("v46-chest-geometry-grounding-debug.apk") or preset.contains("v45-chest-grounding-scroll-fix-debug.apk") or preset.contains("v44-chest-render-scroll-beach-polish-debug.apk")
		or preset.contains("v42-one-chest-beach-layout-debug.apk")
		or preset.contains("v40-chest-smoothing-hidden-fix-debug.apk")
		or preset.contains("v39-chest-polish-debug.apk")
		or preset.contains("backend-disconnect-fix-debug.apk"),
		"APK name"
	)
	_assert(gitignore.contains("*.apk") or gitignore.contains("ChestOfLoveNotes-backend-disconnect-fix-debug.apk"), "gitignore allow")
	_assert(
		export_sh.contains("v48-approved-smooth-chest-debug.apk") or export_sh.contains("v47-chest-clean-transition-debug.apk") or export_sh.contains("v46-chest-geometry-grounding-debug.apk") or export_sh.contains("v45-chest-grounding-scroll-fix-debug.apk") or export_sh.contains("v44-chest-render-scroll-beach-polish-debug.apk")
		or export_sh.contains("v42-one-chest-beach-layout-debug.apk")
		or export_sh.contains("v40-chest-smoothing-hidden-fix-debug.apk")
		or export_sh.contains("v39-chest-polish-debug.apk")
		or export_sh.contains("backend-disconnect-fix-debug.apk"),
		"export default"
	)

	## Unit: failure recording does not clear Person
	var AppStateScript: Script = load("res://scripts/app_state.gd") as Script
	var st: Object = AppStateScript.new()
	st.cached_friends = {
		"person": {"id": "person-a", "display_name": "Mandy"},
		"friends": [{"id": "person-a", "display_name": "Mandy"}],
	}
	st.friends_backend_authoritative = true
	st.record_disconnect_attempt_started("RPC")
	_assert(str(st.relationship_debug.get("last_disconnect_request", "")) == "Started", "started")
	st.record_disconnect_failure("RPC Missing", "Edge Function", true)
	_assert(str(st.relationship_debug.get("last_disconnect_request", "")) == "Failed", "failed")
	_assert(str(st.relationship_debug.get("last_disconnect_failure_category", "")) == "RPC Missing", "category")
	_assert(typeof(st.cached_friends.get("person")) == TYPE_DICTIONARY, "person kept on failure")
	_assert(str((st.cached_friends.get("person") as Dictionary).get("display_name", "")) == "Mandy", "Mandy kept")
	st.mark_verified_disconnected()
	_assert(st.cached_friends.get("person") == null, "cleared only after verified")
	_assert(str(st.relationship_debug.get("last_disconnect_request", "")) == "Success", "success state")

	## FriendService category helper
	var ApiClientScript: Script = load("res://scripts/network/api_client.gd") as Script
	var FriendServiceScript: Script = load("res://scripts/network/friend_service.gd") as Script
	var fs: Object = FriendServiceScript.new(ApiClientScript.new())
	_assert(fs.disconnect_failure_category({"status": 404, "error": "x", "data": {}}, true) != "", "category helper runs")
	_assert(fs.disconnect_failure_category({"status": 0, "error": "", "data": {}}, false) == "Network", "network category")
	_assert(fs.disconnect_failure_category({"status": 401, "error": "", "data": {}}, false) == "Unauthorized", "unauthorized category")
	_assert(fs.disconnect_failure_category({"status": 500, "error": "boom", "data": {}}, false) == "Function Error", "function error category")

	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
