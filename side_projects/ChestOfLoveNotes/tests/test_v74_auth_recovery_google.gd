extends SceneTree
## v74 password recovery + Google OAuth + Account & Security regression tests.
## Static / local validation only — does not call live Google or send real mail.

var _passed := 0
var _failed := 0


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % msg)
	else:
		_failed += 1
		print("FAIL: %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Chest of Love Notes v74 Auth Recovery / Google Tests ===")
	_test_password_recovery()
	_test_google_auth()
	_test_account_security()
	_test_no_secret_logging_surfaces()
	_test_version_pins()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _test_password_recovery() -> void:
	var main := _src("res://scripts/main.gd")
	var auth := _src("res://scripts/network/auth_service.gd")
	var parser := _src("res://scripts/network/auth_callback_parser.gd")

	_assert(main.contains("Forgot password?"), "1 forgot-password action exists")
	_assert(main.contains("_show_forgot_password"), "forgot password screen helper")

	var bad := AuthCallbackParser.is_valid_email_syntax("not-an-email")
	_assert(not bad, "2 invalid email rejected locally")
	_assert(AuthCallbackParser.is_valid_email_syntax("user@example.com"), "valid email accepted")

	_assert(auth.contains("func request_password_reset"), "3 recovery endpoint/request exists")
	_assert(auth.contains("/auth/v1/recover"), "recover path present")

	_assert(auth.contains("PASSWORD_RESET_GENERIC_MSG"), "4 generic success constant")
	_assert(
		auth.contains("If an account exists for that email, a password reset link has been sent."),
		"4 success messaging does not reveal account existence"
	)

	var recovery_uri := (
		"com.charoitegames.chestoflovenotes://auth-callback#access_token=test-access"
		+ "&refresh_token=test-refresh&type=recovery&expires_in=3600"
	)
	var parsed := AuthCallbackParser.parse(recovery_uri)
	_assert(bool(parsed.get("ok", false)), "5 reset callback parser recognizes recovery flow")
	_assert(str(parsed.get("flow", "")) == AuthCallbackParser.FLOW_RECOVERY, "5 flow=recovery")

	var malformed := AuthCallbackParser.parse("https://evil.example/callback?code=abc")
	_assert(not bool(malformed.get("ok", false)), "6 malformed callback fails safely")
	_assert(str(malformed.get("flow", "")) == AuthCallbackParser.FLOW_MALFORMED, "6 malformed flow")

	var state := AppState.new()
	state.bootstrap()
	## Force configured-looking tokens without network for local validation.
	state.tokens.set_session("access-placeholder", "refresh-placeholder", 9999999999)
	var mismatch: Dictionary = await state.auth.update_password("password-one", "password-two")
	_assert(not bool(mismatch.get("ok", false)), "7 password mismatch rejected")
	_assert(str(mismatch.get("error", "")).to_lower().contains("match"), "7 mismatch copy")

	var short_pw: Dictionary = await state.auth.update_password("short", "short")
	_assert(not bool(short_pw.get("ok", false)), "8 password length enforced")
	_assert(str(short_pw.get("error", "")).to_lower().contains("8"), "8 min length mentioned")

	_assert(auth.contains("func update_password"), "9 update-password request exists")
	_assert(auth.contains('PUT') or auth.contains("\"PUT\"") or auth.contains("/auth/v1/user"), "9 user update path")

	_assert(not auth.contains("print(password"), "10 passwords not printed in auth service")
	_assert(not auth.contains("print(new_password"), "10 new password not printed")
	_assert(parser.contains("Never logs") or parser.contains("never log"), "10 parser documents no token logs")
	_assert(parser.contains("sanitize_for_log"), "10 sanitize_for_log present")


func _test_google_auth() -> void:
	var main := _src("res://scripts/main.gd")
	var auth := _src("res://scripts/network/auth_service.gd")
	var parser := _src("res://scripts/network/auth_callback_parser.gd")
	var deep := _src("res://scripts/network/auth_deep_link_helper.gd")
	var notify_kt := _src("res://android/plugins/chest_secure_storage/ChestNotifyPlugin.kt")
	var install := _src("res://android/plugins/chest_secure_storage/install_into_android_build.sh")

	_assert(main.contains("Continue with Google"), "11 Continue with Google exists")
	_assert(auth.contains("begin_google_sign_in"), "12 Google provider request is configured")
	_assert(auth.contains("provider=google"), "12 provider=google")

	_assert(auth.contains("com.charoitegames.chestoflovenotes://auth-callback"), "13 redirect URI configured")
	_assert(parser.contains("com.charoitegames.chestoflovenotes://auth-callback"), "13 parser redirect URI")
	_assert(AuthCallbackParser.redirect_uri() == AuthService.AUTH_REDIRECT_URI, "13 redirect URI consistent")

	_assert(auth.contains("handle_auth_callback_uri"), "14 OAuth callback handler exists")
	_assert(deep.contains("consume_pending_auth_callback"), "14 deep link helper consume")
	_assert(notify_kt.contains("consume_pending_auth_callback"), "14 android consume auth callback")
	_assert(install.contains("auth-callback"), "14 intent filter auth-callback")

	_assert(auth.contains("_callback_processing"), "15 single-flight callback processing")
	_assert(auth.contains("_last_callback_fp"), "15 duplicate fingerprint gate")
	_assert(auth.contains("duplicate"), "15 duplicate handling")

	_assert(auth.contains("tokens.set_session"), "16 tokens flow into SecureTokenService")
	_assert(auth.contains("await refresh_user()"), "17 refresh_user is called")
	_assert(main.contains("await _after_verified_sign_in()"), "18 normal post-login initialization reused")

	var cancelled := AuthCallbackParser.parse(
		"com.charoitegames.chestoflovenotes://auth-callback?error=access_denied&error_description=cancel"
	)
	_assert(not bool(cancelled.get("ok", false)), "19 cancelled OAuth not ok")
	_assert(bool(cancelled.get("cancelled", false)), "19 cancelled OAuth handled safely")

	_assert(not auth.contains("print(access"), "20 raw OAuth tokens not logged")
	_assert(not auth.contains("print(refresh"), "20 refresh tokens not logged")
	_assert(not notify_kt.contains("Log.i(TAG, uri"), "20 android does not log auth uri")
	_assert(notify_kt.contains("Never logs the URI") or notify_kt.contains("may contain"), "20 android warns against logging")


func _test_account_security() -> void:
	var main := _src("res://scripts/main.gd")
	var auth := _src("res://scripts/network/auth_service.gd")

	_assert(main.contains("ACCOUNT & SECURITY"), "21 account-security section exists")
	_assert(main.contains("Sign-in methods"), "21 sign-in methods label")
	_assert(main.contains("state.tokens.user_email"), "22 current email shown")
	_assert(auth.contains("linked_providers"), "23 providers from identities")
	_assert(auth.contains("_update_linked_providers"), "23 identity metadata parsing")
	_assert(main.contains("_show_change_password"), "24 change-password flow exists")
	_assert(main.contains("Sign Out"), "25 sign-out remains functional")
	## Delete-account edge function remains; no accidental removal of backend contract.
	_assert(
		FileAccess.file_exists("res://supabase/functions/delete-account/index.ts"),
		"26 delete-account backend remains intact"
	)


func _test_no_secret_logging_surfaces() -> void:
	var auth := _src("res://scripts/network/auth_service.gd")
	_assert(not auth.contains("service_role"), "no service role in auth service")
	_assert(not auth.contains("client_secret"), "no google client secret in auth service")
	var docs := _src("res://docs/V74_AUTH_SETUP.md")
	_assert(docs.contains("GOOGLE LOGIN REQUIRES DASHBOARD CONFIGURATION") or docs.contains("REQUIRES DASHBOARD"), "docs note dashboard config")
	_assert(docs.contains("https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback"), "docs Google→Supabase callback")
	_assert(docs.contains("com.charoitegames.chestoflovenotes://auth-callback"), "docs Supabase→app callback")


func _test_version_pins() -> void:
	_assert(BuildFlags.APP_VERSION_CODE == 74, "versionCode 74")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.74-auth-recovery-google-signin", "versionName v74")
	var gate := FileAccess.get_file_as_string("res://android/signing/LAST_RELEASED_VERSION_CODE").strip_edges()
	_assert(gate == "72", "LAST_RELEASED_VERSION_CODE remains 72")
