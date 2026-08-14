extends RefCounted
class_name PetManager
## Owns pet catalog + local ownership/active-pet persistence.
## Phase 1A: data foundation only — does NOT spawn into the CHEST scene.
##
## Long-term: spawn/despawn active pet, collection, gifting, billing (later phases).

const PERSIST_PATH := "user://coln_pets.cfg"
const SECTION_OWNED := "owned"
const SECTION_ACTIVE := "active"
const KEY_IDS := "ids"
const KEY_ID := "id"

## Phase 1A / 1B gate: production CHEST must not auto-mount pets until Phase 1B.
const CHEST_SPAWN_ENABLED := false

var catalog: PetCatalog = PetCatalog.new()
var owned_pet_ids: Array[String] = []
var active_pet_id: String = ""
var _actor: Node = null


func bootstrap() -> void:
	catalog.load_catalog()
	_load_or_seed_persistence()


func _load_or_seed_persistence() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PERSIST_PATH)
	if err != OK:
		_seed_defaults()
		save()
		return
	owned_pet_ids.clear()
	var ids_var: Variant = cfg.get_value(SECTION_OWNED, KEY_IDS, PackedStringArray())
	if typeof(ids_var) == TYPE_PACKED_STRING_ARRAY:
		for id in ids_var:
			_add_owned(str(id))
	elif typeof(ids_var) == TYPE_ARRAY:
		for id in ids_var:
			_add_owned(str(id))
	elif typeof(ids_var) == TYPE_STRING:
		for id in str(ids_var).split(",", false):
			_add_owned(id.strip_edges())
	## Ensure catalog default-unlocked pets (parrot) are always owned.
	for id in catalog.default_unlocked_ids():
		_add_owned(id)
	active_pet_id = str(cfg.get_value(SECTION_ACTIVE, KEY_ID, "")).strip_edges()
	if active_pet_id.is_empty() or not is_owned(active_pet_id):
		active_pet_id = _default_active_id()
	save()


func _seed_defaults() -> void:
	owned_pet_ids.clear()
	for id in catalog.default_unlocked_ids():
		_add_owned(id)
	active_pet_id = _default_active_id()


func _default_active_id() -> String:
	if is_owned(PetCatalog.PET_PARROT):
		return PetCatalog.PET_PARROT
	if not owned_pet_ids.is_empty():
		return owned_pet_ids[0]
	return ""


func _add_owned(pet_id: String) -> void:
	var id := pet_id.strip_edges()
	if id.is_empty():
		return
	if not catalog.has_pet(id):
		return
	if owned_pet_ids.has(id):
		return
	owned_pet_ids.append(id)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PERSIST_PATH) ## merge-safe; OK if missing
	var packed := PackedStringArray()
	for id in owned_pet_ids:
		packed.append(id)
	cfg.set_value(SECTION_OWNED, KEY_IDS, packed)
	cfg.set_value(SECTION_ACTIVE, KEY_ID, active_pet_id)
	cfg.save(PERSIST_PATH)


func is_owned(pet_id: String) -> bool:
	return owned_pet_ids.has(pet_id)


func grant_pet(pet_id: String) -> bool:
	## Future unlocks / gifts. Free parrot is already seeded.
	if not catalog.has_pet(pet_id):
		return false
	_add_owned(pet_id)
	if active_pet_id.is_empty():
		active_pet_id = pet_id
	save()
	return true


func set_active_pet(pet_id: String) -> bool:
	if pet_id.is_empty():
		active_pet_id = ""
		save()
		return true
	if not is_owned(pet_id):
		return false
	active_pet_id = pet_id
	save()
	return true


func get_active_definition() -> PetDefinition:
	if active_pet_id.is_empty():
		return null
	return catalog.get_definition(active_pet_id)


func should_spawn_on_chest() -> bool:
	## Hard off in Phase 1A — production CHEST stays visually identical.
	return CHEST_SPAWN_ENABLED and not active_pet_id.is_empty() and is_owned(active_pet_id)


func spawn_active_pet(parent: Node) -> Node:
	## Phase 1B entry point. Phase 1A returns null unless explicitly forced in tests.
	if parent == null:
		return null
	if not should_spawn_on_chest():
		return null
	despawn_active_pet()
	var scene := load("res://scenes/pets/PetActor.tscn") as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	parent.add_child(node)
	if node.has_method("setup_from_definition"):
		node.call("setup_from_definition", get_active_definition())
	_actor = node
	return node


func despawn_active_pet() -> void:
	if _actor != null and is_instance_valid(_actor):
		_actor.queue_free()
	_actor = null


func get_spawned_actor() -> Node:
	return _actor
