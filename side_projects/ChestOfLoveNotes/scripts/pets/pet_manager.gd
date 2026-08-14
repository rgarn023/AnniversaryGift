extends RefCounted
class_name PetManager
## Owns pet catalog + local ownership/active-pet persistence + CHEST spawn.
## Phase 1B-1: invisible runtime spawn when PET_RUNTIME_ENABLED.
## Visuals gated by PetRuntimeConfig.PET_VISUALS_ENABLED (false).

const PERSIST_PATH := "user://coln_pets.cfg"
const SECTION_OWNED := "owned"
const SECTION_ACTIVE := "active"
const KEY_IDS := "ids"
const KEY_ID := "id"

## Backward-compatible alias — prefer PetRuntimeConfig.PET_RUNTIME_ENABLED.
const CHEST_SPAWN_ENABLED := PetRuntimeConfig.PET_RUNTIME_ENABLED

var catalog: PetCatalog = PetCatalog.new()
var owned_pet_ids: Array[String] = []
var active_pet_id: String = ""
var _actor: Node = null
var _runtime_root: Node = null


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
	if active_pet_id.is_empty() or not is_owned(active_pet_id) or not catalog.has_pet(active_pet_id):
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
	if not catalog.has_pet(pet_id):
		return false
	active_pet_id = pet_id
	save()
	return true


func get_active_definition() -> PetDefinition:
	if active_pet_id.is_empty():
		return null
	var def := catalog.get_definition(active_pet_id)
	if def == null:
		## Invalid persisted ID — fall back safely.
		active_pet_id = _default_active_id()
		save()
		if active_pet_id.is_empty():
			return null
		return catalog.get_definition(active_pet_id)
	return def


func should_spawn_on_chest() -> bool:
	if not PetRuntimeConfig.PET_RUNTIME_ENABLED:
		return false
	if active_pet_id.is_empty():
		return false
	if not is_owned(active_pet_id):
		return false
	if not catalog.has_pet(active_pet_id):
		return false
	return true


func ensure_pet_runtime_root(chest_environment: Node) -> Node:
	## CHEST environment → PetRuntimeRoot → PetActor
	if chest_environment == null or not is_instance_valid(chest_environment):
		return null
	var existing := chest_environment.get_node_or_null("PetRuntimeRoot")
	if existing != null:
		_runtime_root = existing
		return existing
	var root := Node2D.new()
	root.name = "PetRuntimeRoot"
	chest_environment.add_child(root)
	_runtime_root = root
	return root


func spawn_active_pet(parent: Node, force: bool = false) -> Node:
	## Spawns at most one actor. Despawns any prior instance first.
	if parent == null:
		return null
	if not force and not should_spawn_on_chest():
		return null
	if active_pet_id.is_empty() and not force:
		return null
	despawn_active_pet()
	## Also remove any orphan PetActor under parent (duplicate protection).
	_purge_orphan_actors(parent)
	var scene := load("res://scenes/pets/PetActor.tscn") as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	parent.add_child(node)
	if node.has_method("setup_from_definition"):
		node.call("setup_from_definition", get_active_definition())
	_actor = node
	return node


func configure_spawned_actor(vp_size: Vector2, chest_local_rect: Rect2, seed: int = -1) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _actor.has_method("configure_runtime"):
		_actor.call("configure_runtime", vp_size, chest_local_rect, seed)


func despawn_active_pet() -> void:
	if _actor != null and is_instance_valid(_actor):
		var p := _actor.get_parent()
		if p != null:
			p.remove_child(_actor)
		_actor.free()
	_actor = null


func notify_chest_screen_cleared() -> void:
	## Parent tree is being freed — drop refs without double-free races.
	_actor = null
	_runtime_root = null


func pause_for_chest_reward() -> void:
	if _actor != null and is_instance_valid(_actor) and _actor.has_method("pause_for_reward"):
		_actor.call("pause_for_reward")


func resume_after_chest_reward() -> void:
	if _actor != null and is_instance_valid(_actor) and _actor.has_method("resume_after_reward"):
		_actor.call("resume_after_reward")


func get_spawned_actor() -> Node:
	if _actor != null and is_instance_valid(_actor):
		return _actor
	_actor = null
	return null


func count_actors_under(parent: Node) -> int:
	if parent == null:
		return 0
	var n := 0
	for c in parent.get_children():
		if c is PetActor or (c.get_script() != null and str(c.get_script().resource_path).ends_with("pet_actor.gd")):
			n += 1
		n += count_actors_under(c)
	return n


func _purge_orphan_actors(parent: Node) -> void:
	if parent == null:
		return
	var doomed: Array[Node] = []
	for c in parent.get_children():
		if c is PetActor:
			doomed.append(c)
	for c in doomed:
		if c == _actor:
			continue
		parent.remove_child(c)
		c.free()
