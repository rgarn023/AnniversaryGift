extends RefCounted
class_name IdentityHelper
## Central identity resolver — never surface raw UUIDs in UI.

const UNKNOWN_SENDER := "Unknown sender"
const UNKNOWN_PERSON := "Unknown"


static func looks_like_uuid(value: String) -> bool:
	var s := value.strip_edges().to_lower()
	if s.length() != 36:
		return false
	# 8-4-4-4-12 hex
	var re := RegEx.new()
	if re.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") != OK:
		return false
	return re.search(s) != null


static func display_name_from_profile(profile: Dictionary, fallback: String = UNKNOWN_PERSON) -> String:
	var name := str(profile.get("display_name", "")).strip_edges()
	if not name.is_empty() and not looks_like_uuid(name):
		return name
	var user := str(profile.get("username", "")).strip_edges()
	if not user.is_empty() and not looks_like_uuid(user):
		return user
	return fallback


static func username_from_profile(profile: Dictionary) -> String:
	var user := str(profile.get("username", "")).strip_edges()
	if user.is_empty() or looks_like_uuid(user):
		return ""
	return user


static func format_person(profile: Dictionary, fallback: String = UNKNOWN_PERSON) -> String:
	var name := display_name_from_profile(profile, fallback)
	var user := username_from_profile(profile)
	if user.is_empty():
		return name
	return "%s · @%s" % [name, user]


static func format_from(profile: Dictionary = {}, display_name: String = "", username: String = "", raw_id: String = "") -> String:
	## Priority: nested profile → explicit display/username → never raw UUID.
	if not profile.is_empty():
		var label := format_person(profile, "")
		if not label.is_empty() and label != UNKNOWN_PERSON:
			return "From %s" % label
	var name := display_name.strip_edges()
	var user := username.strip_edges()
	if looks_like_uuid(name):
		name = ""
	if looks_like_uuid(user):
		user = ""
	if not name.is_empty() and not user.is_empty():
		return "From %s · @%s" % [name, user]
	if not name.is_empty():
		return "From %s" % name
	if not user.is_empty():
		return "From @%s" % user
	# Intentionally ignore raw_id — never show UUID.
	return "From %s" % UNKNOWN_SENDER


static func safe_label(value: String, fallback: String = UNKNOWN_PERSON) -> String:
	var s := value.strip_edges()
	if s.is_empty() or looks_like_uuid(s):
		return fallback
	return s
