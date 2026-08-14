extends RefCounted
class_name PetAnimationLoader
## Loads pet animation frames from a JSON manifest.
## Phase 1B-2A: missing artwork is NOT fatal — artwork_ready stays false.

const PARROT_MANIFEST_PATH := "res://assets/pets/parrot/parrot_animation_manifest.json"

## State → animation name (matches PetActor visual states).
const STATE_TO_ANIM := {
	"idle": "idle",
	"move": "move",
	"chest_interaction": "chest_interaction",
	"tap_reaction": "tap_reaction",
	"roam": "move",
}

var manifest_path: String = PARROT_MANIFEST_PATH
var pet_id: String = ""
var artwork_ready: bool = false
var visuals_enabled_flag: bool = false
var load_status: String = "uninitialized"
var load_detail: String = ""
var manifest: Dictionary = {}
var animations: Dictionary = {} ## name -> anim dict from manifest
var sprite_frames: SpriteFrames = null
var frame_canvas: Vector2i = Vector2i(128, 128)
var ground_anchor: Vector2 = Vector2(64, 116)
var default_facing: String = "right"
var recommended_runtime_scale: float = 0.72
var missing_files: Array[String] = []
var present_files: Array[String] = []


func reset() -> void:
	artwork_ready = false
	visuals_enabled_flag = false
	load_status = "uninitialized"
	load_detail = ""
	manifest.clear()
	animations.clear()
	sprite_frames = null
	missing_files.clear()
	present_files.clear()
	pet_id = ""


func load_parrot_manifest() -> bool:
	return load_manifest(PARROT_MANIFEST_PATH)


func load_manifest(path: String) -> bool:
	reset()
	manifest_path = path
	if not FileAccess.file_exists(path):
		load_status = "manifest_missing"
		load_detail = "Manifest not found: %s" % path
		artwork_ready = false
		return false
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		load_status = "manifest_invalid"
		load_detail = "Manifest JSON is not an object"
		artwork_ready = false
		return false
	manifest = parsed
	pet_id = str(manifest.get("pet_id", "")).strip_edges()
	visuals_enabled_flag = bool(manifest.get("visuals_enabled", false))
	frame_canvas = Vector2i(
		int(manifest.get("frame_canvas_width", 128)),
		int(manifest.get("frame_canvas_height", 128))
	)
	ground_anchor = Vector2(
		float(manifest.get("ground_anchor_x", 64)),
		float(manifest.get("ground_anchor_y", 116))
	)
	default_facing = str(manifest.get("default_facing", "right")).to_lower()
	recommended_runtime_scale = float(manifest.get("recommended_runtime_scale", 0.72))
	var anims_var: Variant = manifest.get("animations", [])
	if typeof(anims_var) == TYPE_ARRAY:
		for item in anims_var:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var anim: Dictionary = item
			var name := str(anim.get("name", "")).strip_edges()
			if name.is_empty():
				continue
			animations[name] = anim
	## Probe files — never fatal if missing.
	_probe_animation_files()
	if missing_files.is_empty() and not animations.is_empty() and present_files.size() > 0:
		artwork_ready = true
		load_status = "artwork_ready"
		load_detail = "All expected frames present (%d files)" % present_files.size()
		_build_sprite_frames_if_ready()
	else:
		artwork_ready = false
		load_status = "awaiting_artwork"
		if missing_files.is_empty() and present_files.is_empty():
			load_detail = "AWAITING_ARTWORK — no frames found (expected)"
		else:
			load_detail = "AWAITING_ARTWORK — missing %d frame(s); present %d" % [
				missing_files.size(), present_files.size()
			]
		## Do not attach empty/broken SpriteFrames.
		sprite_frames = null
	return true


func _probe_animation_files() -> void:
	missing_files.clear()
	present_files.clear()
	var root := str(manifest.get("asset_root", "res://assets/pets/parrot/"))
	if not root.ends_with("/"):
		root += "/"
	for name in animations.keys():
		var anim: Dictionary = animations[name]
		var folder := str(anim.get("folder", name)).strip_edges()
		var count := int(anim.get("expected_frame_count", 0))
		var pattern := str(anim.get("filename_pattern", ""))
		for i in range(count):
			var fname := _format_frame_name(pattern, i, name, folder)
			var path := root + folder + "/" + fname
			if FileAccess.file_exists(path):
				present_files.append(path)
			else:
				missing_files.append(path)


func _format_frame_name(pattern: String, index: int, anim_name: String, folder: String) -> String:
	## Supports parrot_*_{index:02d}.png style patterns.
	if pattern.is_empty():
		match anim_name:
			"idle":
				return "parrot_idle_%02d.png" % index
			"move":
				return "parrot_move_%02d.png" % index
			"chest_interaction":
				return "parrot_chest_%02d.png" % index
			"tap_reaction":
				return "parrot_tap_%02d.png" % index
			_:
				return "parrot_%s_%02d.png" % [folder, index]
	if pattern.contains("{index:02d}"):
		return pattern.replace("{index:02d}", "%02d" % index)
	if pattern.contains("{index}"):
		return pattern.replace("{index}", str(index))
	## Fallback: treat as printf-style with one int.
	if pattern.contains("%"):
		return pattern % index
	return pattern


func _build_sprite_frames_if_ready() -> void:
	## Only called when every expected file exists. Still gated by PET_VISUALS_ENABLED at play time.
	var frames := SpriteFrames.new()
	var root := str(manifest.get("asset_root", "res://assets/pets/parrot/"))
	if not root.ends_with("/"):
		root += "/"
	for name in animations.keys():
		var anim: Dictionary = animations[name]
		var folder := str(anim.get("folder", name)).strip_edges()
		var count := int(anim.get("expected_frame_count", 0))
		var pattern := str(anim.get("filename_pattern", ""))
		var fps := float(anim.get("fps", 8.0))
		var loop := bool(anim.get("loop", true))
		if frames.has_animation(name):
			frames.remove_animation(name)
		frames.add_animation(name)
		frames.set_animation_speed(name, fps)
		frames.set_animation_loop(name, loop)
		for i in range(count):
			var fname := _format_frame_name(pattern, i, name, folder)
			var path := root + folder + "/" + fname
			var tex := load(path) as Texture2D
			if tex == null:
				## Should not happen after probe; abort building broken frames.
				sprite_frames = null
				artwork_ready = false
				load_status = "awaiting_artwork"
				load_detail = "Failed to load texture: %s" % path
				return
			frames.add_frame(name, tex)
	sprite_frames = frames


func animation_name_for_visual_state(visual_state: String) -> String:
	var key := visual_state.strip_edges().to_lower()
	if STATE_TO_ANIM.has(key):
		return str(STATE_TO_ANIM[key])
	if animations.has(key):
		return key
	return "idle"


func get_animation_def(anim_name: String) -> Dictionary:
	if animations.has(anim_name):
		return animations[anim_name]
	return {}


func should_attempt_playback() -> bool:
	## Playback only when art exists AND global visuals flag is on.
	return artwork_ready and PetRuntimeConfig.PET_VISUALS_ENABLED and sprite_frames != null


func to_debug_dict() -> Dictionary:
	return {
		"manifest_path": manifest_path,
		"pet_id": pet_id,
		"artwork_ready": artwork_ready,
		"visuals_enabled_flag": visuals_enabled_flag,
		"load_status": load_status,
		"load_detail": load_detail,
		"frame_canvas": frame_canvas,
		"ground_anchor": ground_anchor,
		"default_facing": default_facing,
		"recommended_runtime_scale": recommended_runtime_scale,
		"animation_count": animations.size(),
		"missing_file_count": missing_files.size(),
		"present_file_count": present_files.size(),
		"has_sprite_frames": sprite_frames != null,
		"pet_visuals_enabled_runtime": PetRuntimeConfig.PET_VISUALS_ENABLED,
	}
