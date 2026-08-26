extends RefCounted
class_name PetCatalog
## Scalable pet catalog loaded from config JSON.
## Parrot is FREE + store-available; ownership is empty until delivery claim.

const CATALOG_PATH := "res://config/pets/catalog.json"
const PET_PARROT := "parrot"

var _by_id: Dictionary = {} ## id -> PetDefinition
var _order: Array[String] = []
var _version: int = 1


func load_catalog(path: String = CATALOG_PATH) -> bool:
	_by_id.clear()
	_order.clear()
	if not FileAccess.file_exists(path):
		_seed_builtin_parrot()
		return false
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_seed_builtin_parrot()
		return false
	var root: Dictionary = parsed
	_version = int(root.get("version", 1))
	var pets: Variant = root.get("pets", [])
	if typeof(pets) != TYPE_ARRAY:
		_seed_builtin_parrot()
		return false
	for entry in pets:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var def := PetDefinition.from_dictionary(entry)
		if def.id.is_empty() or not def.enabled:
			continue
		_by_id[def.id] = def
		_order.append(def.id)
	if _by_id.is_empty():
		_seed_builtin_parrot()
		return false
	return true


func _seed_builtin_parrot() -> void:
	## Fallback if catalog JSON is missing — keeps tests/bootstrap sane.
	var def := PetDefinition.new()
	def.id = PET_PARROT
	def.display_name = "Parrot"
	def.unlock_type = PetDefinition.UNLOCK_FREE
	def.price_type = PetDefinition.UNLOCK_FREE
	def.default_unlocked = false
	def.available_in_store = true
	def.description = "A cheerful beach companion ready to hop beside your chest."
	def.asset_root = "res://assets/pets/parrot/"
	def.enabled = true
	_by_id[def.id] = def
	_order = [def.id]
	_version = 2


func version() -> int:
	return _version


func all_ids() -> Array[String]:
	return _order.duplicate()


func all_definitions() -> Array[PetDefinition]:
	var out: Array[PetDefinition] = []
	for id in _order:
		out.append(_by_id[id])
	return out


func store_definitions() -> Array[PetDefinition]:
	var out: Array[PetDefinition] = []
	for id in _order:
		var def: PetDefinition = _by_id[id]
		if def != null and def.is_store_available():
			out.append(def)
	return out


func get_definition(pet_id: String) -> PetDefinition:
	return _by_id.get(pet_id, null)


func has_pet(pet_id: String) -> bool:
	return _by_id.has(pet_id)


func default_unlocked_ids() -> Array[String]:
	## Legacy helper — production no longer auto-owns these.
	var out: Array[String] = []
	for id in _order:
		var def: PetDefinition = _by_id[id]
		if def != null and def.default_unlocked and def.enabled:
			out.append(id)
	return out
