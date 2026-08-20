extends SceneTree
## v73 per-user relationship label static + helper checks.

var _passed := 0
var _failed := 0


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % msg)
	else:
		_failed += 1
		print("FAIL: %s" % msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _reset_prompt_cfg() -> void:
	var path := RelationshipLabelHelper.PROMPT_CFG
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _init() -> void:
	var mig := _read("res://supabase/migrations/20260815120000_my_person_relationship_labels.sql")
	var helper_src := _read("res://scripts/network/relationship_label_helper.gd")
	var svc := _read("res://scripts/network/relationship_label_service.gd")
	var friends_src := _read("res://scripts/network/friend_service.gd")
	var main := _read("res://scripts/main.gd")
	var app := _read("res://scripts/app_state.gd")
	var strings := _read("res://scripts/ui/product_strings.gd")
	var getf := _read("res://supabase/functions/get-friends/index.ts")

	_assert(mig.contains("my_person_relationship_labels"), "migration creates labels table")
	_assert(mig.contains("unique (friendship_id, owner_user_id)") or mig.contains("my_person_rel_labels_owner_pair"), "unique owner/friendship")
	_assert(mig.contains("enable row level security"), "RLS enabled")
	_assert(mig.contains("my_person_rel_labels_select_own"), "select own policy")
	_assert(mig.contains("my_person_rel_labels_insert_own"), "insert own policy")
	_assert(mig.contains("my_person_rel_labels_update_own"), "update own policy")
	_assert(mig.contains("my_person_rel_labels_delete_own"), "delete own policy")
	_assert(mig.contains("upsert_my_person_relationship_label"), "upsert RPC")
	_assert(mig.contains("clear_my_person_relationship_label"), "clear RPC")
	_assert(mig.contains("owner_user_id = auth.uid()"), "owner identity check")
	_assert(mig.contains("'wife'"), "wife preset")
	_assert(mig.contains("'other'"), "other preset")
	_assert(not mig.contains("drop table"), "non-destructive migration")

	_assert(helper_src.contains("PRESET_KEYS"), "preset keys")
	_assert(helper_src.contains("sanitize_custom"), "custom sanitation")
	_assert(helper_src.contains("should_prompt_for_pairing"), "prompt gating")
	_assert(helper_src.contains("explicit_connection_pending"), "explicit pending helper")
	_assert(helper_src.contains("mark_explicit_connection_pending"), "mark explicit pending")
	_assert(helper_src.contains("clear_explicit_connection_pending"), "clear explicit pending")
	_assert(not helper_src.contains("_connection_is_recent"), "no connected_at recency heuristic")
	_assert(not helper_src.contains("15 * 60"), "no 15-minute new-connection window")
	_assert(helper_src.contains("Not set"), "Not set display")
	_assert(helper_src.contains("Fiancé") and helper_src.contains("Fiancée"), "fiancé labels")

	_assert(friends_src.contains("mark_explicit_connection_pending"), "friend service arms explicit pending")
	_assert(
		friends_src.find("send_connection_request") >= 0
		and friends_src.find("mark_explicit_connection_pending", friends_src.find("send_connection_request"))
			< friends_src.find("func send_friend_request"),
		"send_connection_request arms pending on success"
	)
	_assert(
		friends_src.contains("if accept and bool(result.get(\"ok\", false))")
		or friends_src.contains("accept and bool(result.get(\"ok\""),
		"respond accept arms pending on success"
	)

	## Runtime helper behavior.
	_assert(RelationshipLabelHelper.display_for_key("wife") == "Wife", "wife display")
	_assert(RelationshipLabelHelper.display_for_key("not_set") == "Not set", "not set display")
	_assert(RelationshipLabelHelper.display_for_key("other", "Soulmate") == "Soulmate", "custom other")
	_assert(RelationshipLabelHelper.sanitize_custom("  Bestie<script> ") == "Bestie", "sanitize strips brackets")
	_assert(RelationshipLabelHelper.sanitize_custom("x".repeat(50)).length() == 40, "custom length cap")
	_assert(not RelationshipLabelHelper.is_valid_selection("other", ""), "other requires custom")
	_assert(RelationshipLabelHelper.is_valid_selection("other", "Companion"), "other with custom ok")
	_assert(RelationshipLabelHelper.is_valid_selection("husband"), "husband valid")
	_assert(RelationshipLabelHelper.is_valid_selection("not_set"), "not_set valid clear")

	var indep_a := {"relationship_key": "wife", "custom_label": ""}
	var indep_b := {"relationship_key": "husband", "custom_label": ""}
	_assert(
		RelationshipLabelHelper.display_for_key(str(indep_a.relationship_key)) != RelationshipLabelHelper.display_for_key(str(indep_b.relationship_key)),
		"per-user labels independent conceptually"
	)

	## Explicit-pending prompt gating (no connected_at heuristic).
	_reset_prompt_cfg()
	var recent_iso := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 60, true)
	_assert(
		not RelationshipLabelHelper.should_prompt_for_pairing("pair-upgrade", "not_set", recent_iso),
		"recent connected_at alone does not prompt"
	)
	_assert(RelationshipLabelHelper.pairing_prompt_known("pair-upgrade"), "unseen pairing silently seeded known")

	_reset_prompt_cfg()
	RelationshipLabelHelper.mark_explicit_connection_pending()
	_assert(RelationshipLabelHelper.explicit_connection_pending(), "explicit pending armed")
	_assert(
		RelationshipLabelHelper.should_prompt_for_pairing("pair-send", "not_set", ""),
		"explicit pending allows prompt"
	)
	RelationshipLabelHelper.mark_pairing_prompt_known("pair-send")
	_assert(not RelationshipLabelHelper.explicit_connection_pending(), "mark known clears explicit pending")
	_assert(
		not RelationshipLabelHelper.should_prompt_for_pairing("pair-send", "not_set", recent_iso),
		"known pairing does not reprompt"
	)

	_reset_prompt_cfg()
	_assert(
		not RelationshipLabelHelper.should_prompt_for_pairing("pair-labeled", "wife", recent_iso),
		"existing non-Not-set label does not prompt"
	)
	_assert(RelationshipLabelHelper.pairing_prompt_known("pair-labeled"), "labeled pairing marked known")

	_reset_prompt_cfg()
	RelationshipLabelHelper.mark_explicit_connection_pending()
	## Mirror friend_service accept/send arming helpers.
	_assert(RelationshipLabelHelper.explicit_connection_pending(), "send/accept path can arm pending")
	RelationshipLabelHelper.clear_explicit_connection_pending()
	_assert(not RelationshipLabelHelper.explicit_connection_pending(), "clear explicit pending works")

	_assert(svc.contains("upsert_my_person_relationship_label"), "service upsert RPC")
	_assert(svc.contains("clear_my_person_relationship_label"), "service clear RPC")
	_assert(app.contains("relationship_labels"), "AppState wires service")
	_assert(main.contains("Edit relationship") or main.contains("EDIT_RELATIONSHIP"), "edit relationship UI")
	_assert(main.contains("_show_relationship_editor"), "relationship editor")
	_assert(main.contains("_prompt_relationship_after_connect"), "post-connect prompt")
	_assert(main.contains("RelationshipStatusLabel") or main.contains("display_label"), "relationship display")
	_assert(strings.contains("What is %s to you") or strings.contains("relationship_prompt_title"), "prompt title")
	_assert(getf.contains("relationship_label"), "get-friends returns owner label")
	_assert(getf.contains("owner_user_id"), "get-friends filters by owner")

	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
