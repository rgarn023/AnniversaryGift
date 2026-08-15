extends RefCounted
class_name RelationshipLabelHelper
## Personal "What is this person to you?" labels — private per owner/user.

const KEY_NOT_SET := "not_set"
const KEY_OTHER := "other"
const CUSTOM_MAX_LEN := 40
const PROMPT_CFG := "user://coln_relationship_prompt.cfg"

## Display order for the select UI (Not set first, Other last).
const PRESET_KEYS: Array[String] = [
	"not_set",
	"wife",
	"husband",
	"spouse",
	"partner",
	"boyfriend",
	"girlfriend",
	"fiance",
	"fiancee",
	"significant_other",
	"best_friend",
	"friend",
	"family",
	"other",
]


static func display_for_key(key: String, custom_label: String = "") -> String:
	var k := normalize_key(key)
	match k:
		KEY_NOT_SET, "":
			return "Not set"
		"wife":
			return "Wife"
		"husband":
			return "Husband"
		"spouse":
			return "Spouse"
		"partner":
			return "Partner"
		"boyfriend":
			return "Boyfriend"
		"girlfriend":
			return "Girlfriend"
		"fiance":
			return "Fiancé"
		"fiancee":
			return "Fiancée"
		"significant_other":
			return "Significant Other"
		"best_friend":
			return "Best Friend"
		"friend":
			return "Friend"
		"family":
			return "Family"
		KEY_OTHER:
			var c := sanitize_custom(custom_label)
			return c if not c.is_empty() else "Other"
		_:
			return "Not set"


static func normalize_key(raw: String) -> String:
	var k := raw.strip_edges().to_lower()
	if k == "fiancé" or k == "fiancé":
		return "fiance"
	if k == "fiancée" or k == "fiancée":
		return "fiancee"
	if k.is_empty():
		return KEY_NOT_SET
	return k


static func sanitize_custom(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	## Strip control characters and angle brackets (basic XSS/injection hygiene).
	var out := ""
	for i in s.length():
		var ch := s.unicode_at(i)
		if ch < 32:
			continue
		if ch == 60 or ch == 62: ## < >
			continue
		out += String.chr(ch)
	out = out.strip_edges()
	if out.length() > CUSTOM_MAX_LEN:
		out = out.substr(0, CUSTOM_MAX_LEN)
	return out


static func is_valid_selection(key: String, custom_label: String = "") -> bool:
	var k := normalize_key(key)
	if k == KEY_NOT_SET:
		return true
	if k == KEY_OTHER:
		var c := sanitize_custom(custom_label)
		return not c.is_empty() and c.length() <= CUSTOM_MAX_LEN
	return PRESET_KEYS.has(k)


static func option_labels() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k in PRESET_KEYS:
		out.append(display_for_key(k))
	return out


static func key_at_index(idx: int) -> String:
	if idx < 0 or idx >= PRESET_KEYS.size():
		return KEY_NOT_SET
	return PRESET_KEYS[idx]


static func index_for_key(key: String) -> int:
	var k := normalize_key(key)
	for i in PRESET_KEYS.size():
		if PRESET_KEYS[i] == k:
			return i
	return 0


static func from_person_payload(person: Dictionary) -> Dictionary:
	## Prefer nested relationship_label object from get-friends; fall back to flat fields.
	var nested: Variant = person.get("relationship_label", null)
	if typeof(nested) == TYPE_DICTIONARY:
		var d: Dictionary = nested
		var key := normalize_key(str(d.get("relationship_key", d.get("key", KEY_NOT_SET))))
		var custom := sanitize_custom(str(d.get("custom_label", d.get("custom", ""))))
		return {
			"relationship_key": key,
			"custom_label": custom,
			"display_label": display_for_key(key, custom),
		}
	var key2 := normalize_key(str(person.get("relationship_key", KEY_NOT_SET)))
	var custom2 := sanitize_custom(str(person.get("relationship_custom_label", person.get("custom_label", ""))))
	return {
		"relationship_key": key2,
		"custom_label": custom2,
		"display_label": display_for_key(key2, custom2),
	}


static func _prompt_cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PROMPT_CFG)
	return c


static func prompt_seeded() -> bool:
	return bool(_prompt_cfg().get_value("prompt", "seeded", false))


static func mark_prompt_seeded() -> void:
	var c := _prompt_cfg()
	c.set_value("prompt", "seeded", true)
	c.save(PROMPT_CFG)


static func pairing_prompt_known(pairing_id: String) -> bool:
	if pairing_id.is_empty():
		return true
	return bool(_prompt_cfg().get_value("known", pairing_id, false))


static func mark_pairing_prompt_known(pairing_id: String) -> void:
	if pairing_id.is_empty():
		return
	var c := _prompt_cfg()
	c.set_value("known", pairing_id, true)
	c.set_value("prompt", "seeded", true)
	c.save(PROMPT_CFG)


## Returns true when a new-connection relationship prompt should appear.
## Existing / long-lived connections are seeded once without prompting.
static func should_prompt_for_pairing(
	pairing_id: String,
	current_key: String,
	connected_at_iso: String = ""
) -> bool:
	if pairing_id.is_empty():
		return false
	if normalize_key(current_key) != KEY_NOT_SET:
		mark_pairing_prompt_known(pairing_id)
		return false
	if pairing_prompt_known(pairing_id):
		return false
	if not prompt_seeded():
		mark_prompt_seeded()
		## Upgrade / first load with an already-established pair: no popup.
		## Brand-new accept within the last ~15 minutes may still prompt (sender path).
		if _connection_is_recent(connected_at_iso):
			return true
		mark_pairing_prompt_known(pairing_id)
		return false
	return true


static func _connection_is_recent(connected_at_iso: String) -> bool:
	var raw := connected_at_iso.strip_edges()
	if raw.is_empty():
		return false
	var unix := int(Time.get_unix_time_from_datetime_string(raw))
	if unix <= 0:
		return false
	var now_u := int(Time.get_unix_time_from_system())
	return (now_u - unix) <= 15 * 60
