extends RefCounted
class_name PetManager
## Owns pet catalog + local ownership/active-pet persistence + CHEST spawn.
## Ownership starts empty. Parrot is granted only after a completed pet delivery claim.
## Existing owned Parrot from earlier builds is preserved (migration-safe).

const PERSIST_PATH := "user://coln_pets.cfg"
const SECTION_OWNED := "owned"
const SECTION_ACTIVE := "active"
const SECTION_SETTINGS := "settings"
const SECTION_POSITION := "position"
const SECTION_META := "meta"
const KEY_IDS := "ids"
const KEY_ID := "id"
const KEY_ENABLED := "pet_enabled"
const KEY_SCHEMA := "ownership_schema"
## Schema 2: stop auto-granting default_unlocked pets on every load.
const OWNERSHIP_SCHEMA_V2 := 2
## Normalized last-safe world position (fraction of usable viewport).
const KEY_PARROT_X_NORM := "parrot_position_x_norm"
const KEY_PARROT_Y_NORM := "parrot_position_y_norm"

## Backward-compatible alias — prefer PetRuntimeConfig.PET_RUNTIME_ENABLED.
const CHEST_SPAWN_ENABLED := PetRuntimeConfig.PET_RUNTIME_ENABLED

var catalog: PetCatalog = PetCatalog.new()
var owned_pet_ids: Array[String] = []
var active_pet_id: String = ""
## When false, no PetActor on CHEST. Ownership + active_pet_id are preserved.
var pet_enabled: bool = false
var _actor: Node = null
var _runtime_root: Node = null
## pet_id -> Vector2(x_norm, y_norm). Survives Off / CHEST leave / app restart.
var _position_norm_by_pet: Dictionary = {}
## Counts ConfigFile position writes (tests assert not every frame).
var position_persist_write_count: int = 0
var ownership_schema: int = OWNERSHIP_SCHEMA_V2


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
	## MIGRATION SAFETY: never re-grant catalog defaults on every startup.
	## Preserve parrot (or any pet) already present in owned list from earlier builds.
	## Do NOT call catalog.default_unlocked_ids() to append ownership.
	ownership_schema = int(cfg.get_value(SECTION_META, KEY_SCHEMA, 1))
	active_pet_id = str(cfg.get_value(SECTION_ACTIVE, KEY_ID, "")).strip_edges()
	if active_pet_id.is_empty() or not is_owned(active_pet_id) or not catalog.has_pet(active_pet_id):
		active_pet_id = _default_active_id()
	## Migration: v63 and earlier had no pet_enabled key. Missing ≠ Off when owned.
	pet_enabled = _migrate_pet_enabled(cfg)
	_load_positions(cfg)
	ownership_schema = OWNERSHIP_SCHEMA_V2
	save()


func _load_positions(cfg: ConfigFile) -> void:
	_position_norm_by_pet.clear()
	## Canonical parrot keys (also accepts future per-pet "%s_x_norm" style).
	if cfg.has_section_key(SECTION_POSITION, KEY_PARROT_X_NORM) \
		and cfg.has_section_key(SECTION_POSITION, KEY_PARROT_Y_NORM):
		_position_norm_by_pet[PetCatalog.PET_PARROT] = Vector2(
			float(cfg.get_value(SECTION_POSITION, KEY_PARROT_X_NORM)),
			float(cfg.get_value(SECTION_POSITION, KEY_PARROT_Y_NORM))
		)
	## Settings-section fallback for older drafts of this feature.
	elif cfg.has_section_key(SECTION_SETTINGS, KEY_PARROT_X_NORM) \
		and cfg.has_section_key(SECTION_SETTINGS, KEY_PARROT_Y_NORM):
		_position_norm_by_pet[PetCatalog.PET_PARROT] = Vector2(
			float(cfg.get_value(SECTION_SETTINGS, KEY_PARROT_X_NORM)),
			float(cfg.get_value(SECTION_SETTINGS, KEY_PARROT_Y_NORM))
		)


func _migrate_pet_enabled(cfg: ConfigFile) -> bool:
	## Explicit stored false → Off. Explicit true → On.
	## Missing key: On only when an owned active pet already exists (legacy v63).
	if cfg.has_section_key(SECTION_SETTINGS, KEY_ENABLED):
		return bool(cfg.get_value(SECTION_SETTINGS, KEY_ENABLED))
	if active_pet_id == PetCatalog.PET_PARROT and is_owned(PetCatalog.PET_PARROT):
		return true
	if not active_pet_id.is_empty() and is_owned(active_pet_id) and catalog.has_pet(active_pet_id):
		return true
	## Clean / unowned: Off — no PetActor until claim + Profile enable.
	return false


func _seed_defaults() -> void:
	## Fresh install: empty ownership. Store → send → claim grants pets.
	owned_pet_ids.clear()
	active_pet_id = ""
	pet_enabled = false
	ownership_schema = OWNERSHIP_SCHEMA_V2


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
	cfg.set_value(SECTION_SETTINGS, KEY_ENABLED, pet_enabled)
	cfg.set_value(SECTION_META, KEY_SCHEMA, ownership_schema)
	_write_positions_into(cfg)
	cfg.save(PERSIST_PATH)


func _write_positions_into(cfg: ConfigFile) -> void:
	## Persist normalized positions without clearing other pets' keys.
	for pet_id in _position_norm_by_pet.keys():
		var n: Vector2 = _position_norm_by_pet[pet_id]
		if str(pet_id) == PetCatalog.PET_PARROT:
			cfg.set_value(SECTION_POSITION, KEY_PARROT_X_NORM, n.x)
			cfg.set_value(SECTION_POSITION, KEY_PARROT_Y_NORM, n.y)
		else:
			cfg.set_value(SECTION_POSITION, "%s_x_norm" % str(pet_id), n.x)
			cfg.set_value(SECTION_POSITION, "%s_y_norm" % str(pet_id), n.y)


func _save_positions_only() -> void:
	## Disk write for position commits — not called every frame.
	var cfg := ConfigFile.new()
	cfg.load(PERSIST_PATH)
	_write_positions_into(cfg)
	cfg.save(PERSIST_PATH)
	position_persist_write_count += 1


func has_saved_position(pet_id: String = "") -> bool:
	var id := pet_id.strip_edges()
	if id.is_empty():
		id = active_pet_id if not active_pet_id.is_empty() else PetCatalog.PET_PARROT
	return _position_norm_by_pet.has(id)


func get_saved_position_norm(pet_id: String = "") -> Vector2:
	var id := pet_id.strip_edges()
	if id.is_empty():
		id = active_pet_id if not active_pet_id.is_empty() else PetCatalog.PET_PARROT
	if not _position_norm_by_pet.has(id):
		return Vector2(-1.0, -1.0)
	return _position_norm_by_pet[id]


func set_saved_position_norm(pet_id: String, norm: Vector2, write_disk: bool = true) -> void:
	## Off must NOT clear this. Invalid norms are ignored.
	var id := pet_id.strip_edges()
	if id.is_empty():
		return
	if norm.x < 0.0 or norm.y < 0.0 or norm.x > 1.5 or norm.y > 1.5:
		return
	var prev: Variant = _position_norm_by_pet.get(id, null)
	if typeof(prev) == TYPE_VECTOR2:
		var p: Vector2 = prev
		## Skip no-op writes (same cell within ~0.1%).
		if absf(p.x - norm.x) < 0.001 and absf(p.y - norm.y) < 0.001:
			return
	_position_norm_by_pet[id] = norm
	if write_disk:
		_save_positions_only()


func world_to_norm(world: Vector2, viewport_size: Vector2) -> Vector2:
	var w := maxf(viewport_size.x, 1.0)
	var h := maxf(viewport_size.y, 1.0)
	return Vector2(world.x / w, world.y / h)


func norm_to_world(norm: Vector2, viewport_size: Vector2) -> Vector2:
	return Vector2(norm.x * viewport_size.x, norm.y * viewport_size.y)


func persist_active_actor_position() -> void:
	## Capture last safe actor position before despawn / CHEST leave / Off.
	if _actor == null or not is_instance_valid(_actor):
		return
	if not (_actor is Node2D):
		return
	var id := active_pet_id
	if id.is_empty():
		id = str(_actor.get("pet_id")) if _actor.get("pet_id") != null else PetCatalog.PET_PARROT
	if id.is_empty():
		id = PetCatalog.PET_PARROT
	var world: Vector2 = (_actor as Node2D).position
	var vp := Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
	var sa: Variant = _actor.get("safe_area")
	if sa != null and sa.get("viewport_size") != null:
		var v: Vector2 = sa.viewport_size
		if v.x > 1.0 and v.y > 1.0:
			vp = v
	## Prefer actor-reported safe point when available.
	if _actor.has_method("get_persistable_world_position"):
		world = _actor.call("get_persistable_world_position")
	set_saved_position_norm(id, world_to_norm(world, vp), true)


func resolve_spawn_world_position(vp_size: Vector2, chest_local_rect: Rect2, rng: RandomNumberGenerator = null) -> Vector2:
	## Restore normalized position into current viewport, then validate safe area.
	var area := PetSafeArea.new()
	area.configure(vp_size, chest_local_rect)
	var id := active_pet_id if not active_pet_id.is_empty() else PetCatalog.PET_PARROT
	if not has_saved_position(id):
		return area.default_spawn_position(rng)
	var world := norm_to_world(get_saved_position_norm(id), vp_size)
	return area.ensure_safe_position(world, rng)


func is_owned(pet_id: String) -> bool:
	return owned_pet_ids.has(pet_id)


func has_any_owned() -> bool:
	return not owned_pet_ids.is_empty()


func grant_pet(pet_id: String) -> bool:
	## Legacy grant — keeps enabled state unchanged.
	return grant_pet_from_claim(pet_id, false)


func grant_pet_from_claim(pet_id: String, disable_until_profile: bool = true) -> bool:
	## Idempotent ownership grant after a completed delivery claim.
	if not catalog.has_pet(pet_id):
		return false
	var already := is_owned(pet_id)
	_add_owned(pet_id)
	if active_pet_id.is_empty() or not is_owned(active_pet_id):
		active_pet_id = pet_id
	## First claim: available under Profile, but Off until user enables.
	if disable_until_profile and not already:
		pet_enabled = false
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


func set_pet_enabled(enabled: bool) -> void:
	## Turning off must NOT clear ownership or active_pet_id.
	pet_enabled = enabled
	save()


func select_profile_pet(choice: String) -> bool:
	## Profile single-choice: "off" or an owned pet id (currently "parrot").
	var c := choice.strip_edges().to_lower()
	if c.is_empty() or c == "off":
		## Save current safe position BEFORE despawn; never clear ownership/position.
		persist_active_actor_position()
		pet_enabled = false
		## Preserve active_pet so re-enable restores selection.
		if active_pet_id.is_empty() or not is_owned(active_pet_id) or not catalog.has_pet(active_pet_id):
			active_pet_id = _default_active_id()
		despawn_active_pet()
		save()
		return true
	if not is_owned(c):
		return false
	if not catalog.has_pet(c):
		return false
	active_pet_id = c
	pet_enabled = true
	save()
	return true


func get_profile_pet_selection() -> String:
	## UI selection key: "off" or active owned pet id.
	if not has_any_owned():
		return "off"
	if not pet_enabled:
		return "off"
	if active_pet_id.is_empty() or not is_owned(active_pet_id) or not catalog.has_pet(active_pet_id):
		## Invalid while enabled — fall back for UI without crashing.
		var fallback := _default_active_id()
		if fallback.is_empty():
			return "off"
		return fallback
	return active_pet_id


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
	if not pet_enabled:
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
	## HARD RULE: no PetActor unless owned + enabled (unless force for tests).
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
	var restore := resolve_spawn_world_position(vp_size, chest_local_rect, null)
	## Wire persist callback BEFORE configure so initial/restored idle commit is saved.
	if _actor.has_method("set_position_persist_callback"):
		_actor.call("set_position_persist_callback", Callable(self, "_on_actor_safe_position"))
	if _actor.has_method("configure_runtime"):
		_actor.call("configure_runtime", vp_size, chest_local_rect, seed, restore)


func _on_actor_safe_position(world: Vector2) -> void:
	## Called from PetActor on ROAM arrive / IDLE-after-move / pre-hide — not every frame.
	if _actor == null or not is_instance_valid(_actor):
		return
	var id := active_pet_id
	if id.is_empty():
		id = PetCatalog.PET_PARROT
	var vp := Vector2(PetRuntimeConfig.DESIGN_WIDTH, PetRuntimeConfig.DESIGN_HEIGHT)
	var sa: Variant = _actor.get("safe_area")
	if sa != null and sa.get("viewport_size") != null:
		var v: Vector2 = sa.viewport_size
		if v.x > 1.0 and v.y > 1.0:
			vp = v
	set_saved_position_norm(id, world_to_norm(world, vp), true)


func despawn_active_pet() -> void:
	persist_active_actor_position()
	if _actor != null and is_instance_valid(_actor):
		var p := _actor.get_parent()
		if p != null:
			p.remove_child(_actor)
		_actor.free()
	_actor = null


func notify_chest_screen_cleared() -> void:
	## Parent tree is being freed — persist last safe pos, then drop refs.
	persist_active_actor_position()
	_actor = null
	_runtime_root = null


func pause_for_chest_reward() -> void:
	persist_active_actor_position()
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


func clear_ownership_for_tests() -> void:
	## DEV / test helper — never called from production UI.
	owned_pet_ids.clear()
	active_pet_id = ""
	pet_enabled = false
	despawn_active_pet()
	save()


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
