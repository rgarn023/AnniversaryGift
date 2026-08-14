extends SceneTree


func _init() -> void:
	var paths := [
		"res://android/build/.build_version",
		"res://android/.build_version",
		"user://../android/build/.build_version",
	]
	for p in paths:
		print(p, " exists=", FileAccess.file_exists(p))
		if FileAccess.file_exists(p):
			print(" content=[", FileAccess.get_file_as_string(p).strip_edges(), "]")
	# Also try absolute via globalize
	print("globalized=", ProjectSettings.globalize_path("res://android/build/.build_version"))
	quit()
