extends SceneTree

## Entry point wrapper so tests can be launched with --script.


func _init() -> void:
	var script_path := "res://tests/test_anniversary_logic.gd"
	var script: GDScript = load(script_path)
	if script == null:
		push_error("Unable to load test script")
		quit(1)
		return
	var runner = script.new()
	# test script extends SceneTree; when loaded via .new() as RefCounted-like it won't run.
	# Prefer direct --script on the test file. This wrapper exits if misused.
	push_error("Run with: godot --headless --path . --script res://tests/test_anniversary_logic.gd")
	quit(1)
