extends RefCounted
class_name MediaPickerHelper
## Android Photo Picker wrapper with desktop FileDialog fallback.

signal images_picked(paths: PackedStringArray)
signal cancelled

const PLUGIN_NAME := "ChestMedia"


static func plugin_available() -> bool:
	if Engine.has_singleton(PLUGIN_NAME):
		return true
	return false


func pick_images(max_count: int = 1, host: Node = null) -> void:
	var limit := clampi(max_count, 1, AttachmentHelper.MAX_ATTACHMENTS)
	if Engine.has_singleton(PLUGIN_NAME):
		var plugin = Engine.get_singleton(PLUGIN_NAME)
		if not plugin.images_picked.is_connected(_on_plugin_picked):
			plugin.images_picked.connect(_on_plugin_picked)
		if not plugin.images_pick_cancelled.is_connected(_on_plugin_cancelled):
			plugin.images_pick_cancelled.connect(_on_plugin_cancelled)
		var ok := bool(plugin.pick_images(limit))
		if ok:
			return
	## Desktop / fallback: native image-filtered dialog (not a full filesystem dump when possible).
	if host == null:
		cancelled.emit()
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES if limit > 1 else FileDialog.FILE_MODE_OPEN_FILE
	dlg.use_native_dialog = true
	dlg.title = "Add Photo"
	dlg.add_filter("*.jpg,*.jpeg,*.png,*.webp;Images")
	dlg.filters = PackedStringArray(["*.jpg, *.jpeg, *.png, *.webp ; Images"])
	host.add_child(dlg)
	dlg.files_selected.connect(func(paths: PackedStringArray) -> void:
		images_picked.emit(paths)
		dlg.queue_free()
	)
	dlg.file_selected.connect(func(path: String) -> void:
		images_picked.emit(PackedStringArray([path]))
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void:
		cancelled.emit()
		dlg.queue_free()
	)
	dlg.popup_centered_ratio(0.9)


func _on_plugin_picked(joined: String) -> void:
	var parts := joined.split("\n", false)
	var out: PackedStringArray = PackedStringArray()
	for p in parts:
		var s := str(p).strip_edges()
		if not s.is_empty():
			out.append(s)
	if out.is_empty():
		cancelled.emit()
	else:
		images_picked.emit(out)


func _on_plugin_cancelled() -> void:
	cancelled.emit()
