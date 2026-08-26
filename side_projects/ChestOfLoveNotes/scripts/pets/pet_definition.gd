extends RefCounted
class_name PetDefinition
## Immutable catalog entry for a pet species.
## Acquisition is store + delivery — default_unlocked no longer auto-owns.

const UNLOCK_FREE := "FREE"
## Reserved for Phase 3 — not used by parrot.
const UNLOCK_PAID := "PAID"

var id: String = ""
var display_name: String = ""
var unlock_type: String = UNLOCK_FREE
## Alias of unlock_type for store display (FREE / PAID).
var price_type: String = UNLOCK_FREE
var default_unlocked: bool = false
var available_in_store: bool = false
var description: String = ""
var asset_root: String = ""
var enabled: bool = true
var supports_idle: bool = true
var supports_roam: bool = true
var supports_chest_interaction: bool = true
var supports_tap_reaction: bool = true


func is_free() -> bool:
	return unlock_type == UNLOCK_FREE or price_type == UNLOCK_FREE


func is_store_available() -> bool:
	return enabled and available_in_store


func animation_dir(group: String) -> String:
	## Future: idle / move / chest_interaction / tap_reaction under asset_root.
	if asset_root.is_empty():
		return ""
	var root := asset_root
	if not root.ends_with("/"):
		root += "/"
	return root + group + "/"


static func from_dictionary(data: Dictionary) -> PetDefinition:
	var def := PetDefinition.new()
	def.id = str(data.get("id", "")).strip_edges()
	def.display_name = str(data.get("display_name", def.id))
	def.unlock_type = str(data.get("unlock_type", UNLOCK_FREE)).to_upper()
	var price_raw := str(data.get("price_type", "")).strip_edges().to_upper()
	def.price_type = price_raw if not price_raw.is_empty() else def.unlock_type
	def.default_unlocked = bool(data.get("default_unlocked", false))
	def.available_in_store = bool(data.get("available_in_store", false))
	def.description = str(data.get("description", "")).strip_edges()
	def.asset_root = str(data.get("asset_root", ""))
	def.enabled = bool(data.get("enabled", true))
	var behavior: Variant = data.get("behavior", {})
	if typeof(behavior) == TYPE_DICTIONARY:
		var b: Dictionary = behavior
		def.supports_idle = bool(b.get("supports_idle", true))
		def.supports_roam = bool(b.get("supports_roam", true))
		def.supports_chest_interaction = bool(b.get("supports_chest_interaction", true))
		def.supports_tap_reaction = bool(b.get("supports_tap_reaction", true))
	return def


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"unlock_type": unlock_type,
		"price_type": price_type,
		"default_unlocked": default_unlocked,
		"available_in_store": available_in_store,
		"description": description,
		"asset_root": asset_root,
		"enabled": enabled,
		"behavior": {
			"supports_idle": supports_idle,
			"supports_roam": supports_roam,
			"supports_chest_interaction": supports_chest_interaction,
			"supports_tap_reaction": supports_tap_reaction,
		},
	}
