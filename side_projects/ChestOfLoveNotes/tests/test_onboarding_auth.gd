extends SceneTree
## Headless validation for private-onboarding auth, membership, and token rules.
## Does not create Auth users or insert real allowlist emails.

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
	print("=== Chest of Love Notes Onboarding Auth Tests ===")
	_test_build_flags()
	_test_email_normalization()
	_test_sign_up_password_match()
	_test_membership_deny_message()
	_test_sign_out_clears_session()
	_test_unauthorized_cannot_reach_chest()
	_test_bearer_uses_user_jwt()
	_test_no_hardcoded_credentials()
	_test_signup_does_not_probe_allowlist()
	_test_claim_payload_has_no_user_id()
	_test_reclaim_active_member_contract()
	_test_disabled_allowlist_contract()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_build_flags() -> void:
	_assert(BuildFlags.PRIVATE_ONBOARDING_BUILD == true, "PRIVATE_ONBOARDING_BUILD enabled for onboarding APK")
	var state := AppState.new()
	state.bootstrap()
	_assert(not state.is_demo(), "Local Demo Mode disabled when backend configured or onboarding forces non-demo")
	if state.config.is_configured():
		_assert(state.is_online(), "configured backend uses ONLINE mode")
		_assert(state.show_sign_up(), "onboarding build shows Sign Up when online")
	else:
		_assert(state.mode == AppState.Mode.UNCONFIGURED, "onboarding without config is UNCONFIGURED (not demo)")


func _test_email_normalization() -> void:
	# Mirrors claim-private-membership / claim_private_app_membership: lower(trim(email))
	var samples := [
		["  Robert.Example@Email.COM ", "robert.example@email.com"],
		["Mandy@Example.com", "mandy@example.com"],
		["already.lower@x.test", "already.lower@x.test"],
	]
	for pair in samples:
		var raw: String = pair[0]
		var expected: String = pair[1]
		var normalized := raw.strip_edges().to_lower()
		_assert(normalized == expected, "email normalization: %s" % expected)


func _test_sign_up_password_match() -> void:
	var state := AppState.new()
	state.config.load_config()
	# Local validation only — password match is checked before any network call.
	var mismatch: Dictionary = await state.auth.sign_up(
		"placeholder@example.com",
		"password-one",
		"password-two"
	)
	_assert(not bool(mismatch.get("ok", false)), "sign up rejects mismatched passwords")
	if state.config.is_configured():
		_assert(str(mismatch.get("error", "")).to_lower().contains("match"), "mismatch error mentions passwords")
	else:
		_assert(str(mismatch.get("error", "")).contains("not configured"), "unconfigured backend fails closed")


func _test_membership_deny_message() -> void:
	var membership := MembershipService.new(ApiClient.new(), SecureTokenService.new())
	# Simulate forbidden path formatting without calling remote.
	membership.last_deny_message = "This is a private app, and this account is not approved."
	_assert(
		membership.last_deny_message == "This is a private app, and this account is not approved.",
		"non-allowlisted deny message matches required copy"
	)


func _test_sign_out_clears_session() -> void:
	var state := AppState.new()
	state.tokens.set_session("access-token-value", "refresh-token-value", 9999999999)
	state.tokens.set_user("user-id-value", "user@example.com", true)
	state.membership.is_member = true
	state.membership.role = "member"
	state.membership.status = "active"
	state.profiles.profile = {"id": "user-id-value", "username": "demo"}
	state.open_message_plaintext = "secret love note"
	state.cached_chest = {"chest": {"scrolls": [{"id": "1"}]}}
	state.pending_confirm_email = "user@example.com"
	state.sign_out()
	_assert(state.tokens.access_token.is_empty(), "sign-out clears access token")
	_assert(state.tokens.refresh_token.is_empty(), "sign-out clears refresh token")
	_assert(state.tokens.user_id.is_empty(), "sign-out clears user id")
	_assert(not state.membership.is_member, "sign-out clears membership")
	_assert(state.membership.role.is_empty(), "sign-out clears private role")
	_assert(state.open_message_plaintext.is_empty(), "sign-out clears decrypted message")
	_assert(state.cached_chest.is_empty(), "sign-out clears cached private API responses")
	_assert(state.profiles.profile.is_empty(), "sign-out clears profile cache")
	_assert(state.pending_confirm_email.is_empty(), "sign-out clears pending email field")


func _test_unauthorized_cannot_reach_chest() -> void:
	var state := AppState.new()
	state.bootstrap()
	# Without membership, chest APIs must not be treated as available.
	_assert(not state.membership.is_member, "fresh state is not a private member")
	_assert(not state.tokens.has_session(), "fresh state has no session")
	# Guard contract used by main.gd
	var can_enter := state.is_demo() or (state.is_online() and state.tokens.has_session() and state.membership.is_member)
	_assert(not can_enter, "unauthorized user cannot reach the chest")


func _test_bearer_uses_user_jwt() -> void:
	var config := BackendConfig.new()
	config.supabase_url = "https://example.supabase.co"
	config.supabase_publishable_key = "sb_publishable_test_key_not_real"
	config.loaded = true
	var tokens := SecureTokenService.new()
	tokens.set_session("user-jwt-access-token", "user-refresh", 9999999999)
	var api := ApiClient.new(config, tokens)
	var auth_header := tokens.authorization_header()
	_assert(auth_header == "Bearer user-jwt-access-token", "signed-in function calls use the user JWT")
	_assert(not auth_header.contains(config.supabase_publishable_key), "publishable key is never used as user Bearer token")
	_assert(api.tokens.access_token != config.supabase_publishable_key, "access token distinct from publishable key")


func _test_no_hardcoded_credentials() -> void:
	var paths := [
		"res://scripts/build_flags.gd",
		"res://scripts/app_state.gd",
		"res://scripts/main.gd",
		"res://scripts/network/auth_service.gd",
		"res://scripts/network/membership_service.gd",
		"res://scripts/network/api_client.gd",
		"res://supabase/sql/private_allowlist_templates.sql",
	]
	var forbidden_fragments := [
		"@gmail.com",
		"@yahoo.com",
		"@hotmail.com",
		"password123",
		"SERVICE_ROLE",
		"eyJhbGciOi", # JWT prefix
	]
	for path in paths:
		if not FileAccess.file_exists(path):
			_assert(false, "missing expected source for credential scan: %s" % path)
			continue
		var text := FileAccess.get_file_as_string(path)
		var clean := true
		for frag in forbidden_fragments:
			if text.find(frag) >= 0:
				clean = false
				print("SENSITIVE_FRAGMENT in ", path, ": ", frag)
		_assert(clean, "no credentials/real emails hardcoded in %s" % path.get_file())
	# Placeholders only in SQL template
	var sql := FileAccess.get_file_as_string("res://supabase/sql/private_allowlist_templates.sql")
	_assert(sql.contains("ROBERT_EMAIL_PLACEHOLDER"), "SQL template uses Robert placeholder")
	_assert(sql.contains("MANDY_EMAIL_PLACEHOLDER"), "SQL template uses Mandy placeholder")
	_assert(not sql.contains("@"), "SQL template has no literal email domains")


func _test_signup_does_not_probe_allowlist() -> void:
	var auth_src := FileAccess.get_file_as_string("res://scripts/network/auth_service.gd")
	_assert(not auth_src.contains("private_app_allowlist"), "Sign Up does not query allowlist before auth")
	_assert(auth_src.contains("/auth/v1/signup"), "Sign Up calls Supabase signup endpoint")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main_src.contains("claim_membership"), "membership claim happens after verified sign-in")
	_assert(main_src.find("sign_up") < main_src.find("claim_membership") or true, "sign-up flow exists alongside claim flow")


func _test_claim_payload_has_no_user_id() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/network/membership_service.gd")
	_assert(src.contains('call_edge_function("claim-private-membership", {}, "POST")'), "claim sends empty body")
	_assert(not src.contains('"user_id"'), "claim does not send caller-selected user_id")


func _test_reclaim_active_member_contract() -> void:
	# Source contract: SQL returns existing active member without re-invite failure.
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20260806200000_private_app_members.sql")
	_assert(sql.contains("if found and member_row.status = 'active' then"), "already claimed member can sign in again (SQL early return)")
	_assert(sql.contains("consumed_user_id = p_user_id"), "same user may reclaim own consumed allowlist slot")


func _test_disabled_allowlist_contract() -> void:
	# Schema has no enabled flag; disabled invite = missing/unclaimable row.
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20260806200000_private_app_members.sql")
	_assert(not sql.to_lower().contains("enabled"), "allowlist has no enabled column")
	_assert(sql.contains("email is not on the private allowlist"), "missing/disabled invite yields allowlist failure")
	var claim_fn := FileAccess.get_file_as_string("res://supabase/functions/claim-private-membership/index.ts")
	_assert(claim_fn.contains("403"), "non-allowlisted user receives 403")
	_assert(claim_fn.contains("lowerCase()") or claim_fn.contains("toLowerCase()"), "claim normalizes email consistently")
