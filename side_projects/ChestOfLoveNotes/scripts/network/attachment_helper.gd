extends RefCounted
class_name AttachmentHelper
## First-phase image attachment helpers: pick, compress, draft I/O.
## Never stores full-resolution phone images in draft or upload payloads.

const MAX_ATTACHMENTS := 5
const MAX_LONG_EDGE := 1800
const JPEG_QUALITY := 0.82
const DRAFT_DIR := "user://attachment_drafts"
const SMALL_RADIUS_WARN_M := 50

const ALLOWED_EXT := ["jpg", "jpeg", "png", "webp"]


static func ensure_draft_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DRAFT_DIR)


static func clear_draft_dir() -> void:
	ensure_draft_dir()
	var dir := DirAccess.open(DRAFT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()


static func is_supported_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in ALLOWED_EXT


static func mime_for_path(path: String) -> String:
	match path.get_extension().to_lower():
		"png":
			return "image/png"
		"webp":
			return "image/webp"
		_:
			return "image/jpeg"


static func load_image(path: String) -> Image:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		return null
	return img


static func compress_to_draft(source_path: String, draft_id: String = "") -> Dictionary:
	## Returns {ok, path, mime, width, height, byte_size, error}
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "error": "Could not open that photo."}
	if not is_supported_path(source_path):
		return {"ok": false, "error": "Use a JPEG, PNG, or WebP photo."}
	var img := load_image(source_path)
	if img == null or img.is_empty():
		return {"ok": false, "error": "That photo could not be read."}
	var w := img.get_width()
	var h := img.get_height()
	var long_edge := maxi(w, h)
	if long_edge > MAX_LONG_EDGE:
		var scale := float(MAX_LONG_EDGE) / float(long_edge)
		img.resize(maxi(1, int(round(w * scale))), maxi(1, int(round(h * scale))), Image.INTERPOLATE_LANCZOS)
		w = img.get_width()
		h = img.get_height()
	ensure_draft_dir()
	var id := draft_id if not draft_id.is_empty() else str(Time.get_unix_time_from_system()) + "_" + str(randi() % 100000)
	var out_path := "%s/%s.jpg" % [DRAFT_DIR, id]
	## Always store draft as JPEG for predictable upload size/orientation.
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var err := img.save_jpg(out_path, JPEG_QUALITY)
	if err != OK:
		return {"ok": false, "error": "Could not prepare that photo."}
	var bytes := FileAccess.get_file_as_bytes(out_path)
	return {
		"ok": true,
		"path": out_path,
		"mime": "image/jpeg",
		"width": w,
		"height": h,
		"byte_size": bytes.size(),
		"id": id,
	}


static func make_thumbnail_texture(path: String, max_edge: int = 256) -> Texture2D:
	var img := load_image(path)
	if img == null or img.is_empty():
		return null
	var w := img.get_width()
	var h := img.get_height()
	var long_edge := maxi(w, h)
	if long_edge > max_edge:
		var scale := float(max_edge) / float(long_edge)
		img.resize(maxi(1, int(round(w * scale))), maxi(1, int(round(h * scale))), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


static func clamp_radius(meters: int) -> int:
	return clampi(meters, LocationHelper.MIN_RADIUS_M, LocationHelper.MAX_RADIUS_M)


static func parse_radius_text(text: String) -> Dictionary:
	## {ok, value, error}. Accepts integers only.
	var t := text.strip_edges()
	if t.is_empty():
		return {"ok": false, "error": "Enter a radius in meters."}
	if not t.is_valid_int():
		## Reject decimals / letters cleanly.
		if t.is_valid_float():
			return {"ok": false, "error": "Use a whole number of meters."}
		return {"ok": false, "error": "Enter a whole number of meters."}
	var n := int(t)
	if n <= 0:
		return {"ok": false, "error": "Radius must be at least 1 meter."}
	if n > LocationHelper.MAX_RADIUS_M:
		return {"ok": false, "error": "Radius can be at most %s." % LocationHelper.format_radius(LocationHelper.MAX_RADIUS_M)}
	return {"ok": true, "value": n}
