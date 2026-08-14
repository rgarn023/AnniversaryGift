extends SceneTree
## v66 — Production Profile path + v63 pet_enabled migration + diagnostics absence.


var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _run() -> void:
	print("=== v66 Profile pet production path ===")
	_test_version()
	_test_profile_source_path()
	_test_pets_section_runtime()
	_test_ui_callbacks_and_persistence()
	_test_actor_counts()
	_test_v63_pet_enabled_migration()
	_test_diagnostics_search()
	_test_regressions()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_version() -> void:
	_assert(BuildFlags.APP_VERSION_CODE == 70, "versionCode 70")
	_assert(BuildFlags.APP_VERSION_NAME == "0.1.70-pet-store-gifting", "versionName 70")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert(preset.contains("version/code=70"), "export versionCode 70")
	_assert(preset.contains("0.1.70-pet-store-gifting"), "export versionName 70")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_assert(proj.contains("0.1.70-pet-store-gifting"), "project.godot version")


func _test_profile_source_path() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(main.contains('["profile", "◎", "Profile", _show_profile]'), "bottom nav → _show_profile")
	_assert(main.contains("func _show_profile()"), "_show_profile exists")
	_assert(main.contains("_build_profile_pets_section"), "pets builder")
	_assert(main.contains('sec.text = "Pets"'), "Pets title")
	_assert(main.contains("ProfilePetChoiceOff"), "Off control name")
	_assert(main.contains("ProfilePetChoiceParrot"), "Parrot control name")
	_assert(main.contains("ProfilePetsSection"), "Pets section name")
	_assert(main.contains("select_profile_pet"), "select API")
	_assert(not main.contains("AndroidProfile"), "no AndroidProfile alternate")
	_assert(not main.contains("_show_profile_android"), "no android profile fn")
	_assert(not main.contains("_show_profile_mobile"), "no mobile profile fn")
	var p0 := main.find("func _show_profile()")
	var p1 := main.find("func _show_diagnostics()")
	_assert(p0 >= 0 and p1 > p0, "profile function bounds")
	var body := main.substr(p0, p1 - p0)
	_assert(body.contains("_build_profile_pets_section"), "pets mounted in _show_profile")
	_assert(not body.contains("_build_android_diagnostics_panel"), "diagnostics not mounted in _show_profile")
	_assert(not body.contains("col.add_child(_build_android_diagnostics_panel())"), "no diagnostics add_child")
	## Helper remains for internal debug tooling only — must NOT render user title.
	_assert(main.contains("_build_android_diagnostics_panel"), "diagnostics helper kept internal")
	_assert(not main.contains('sec.text = "Android Diagnostics"'), "no production UI title Android Diagnostics")
	_assert(main.contains("Bridge Diagnostics (debug)"), "internal bridge diagnostics title")
	_assert(main.contains("never mounted from `_show_profile`") or main.contains("never mounted from"), "internal-only note")
	_assert(main.contains("set_pressed_no_signal"), "Profile pet buttons init without signal")
	_assert(main.contains("_migrate_pet_enabled") or FileAccess.get_file_as_string("res://scripts/pets/pet_manager.gd").contains("_migrate_pet_enabled"), "pet_enabled migration helper")


func _test_pets_section_runtime() -> void:
	## Build the real pets section via Main helpers without full splash.
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var main_script := load("res://scripts/main.gd") as Script
	var main: Node = main_script.new()
	root.add_child(main)
	main.state = AppState.new()
	main.state.bootstrap()
	main.state.mode = AppState.Mode.LOCAL_DEMO
	main.state.demo.enable()
	main.state.pets.bootstrap()
	main.state.pets.grant_pet_from_claim("parrot", false)
	main.state.pets.select_profile_pet("parrot")
	## Minimal chrome so builders that touch toast/screen do not crash.
	main._screen_host = Control.new()
	main.add_child(main._screen_host)
	var section: VBoxContainer = main._build_profile_pets_section()
	main._screen_host.add_child(section)
	_assert(section.name == "ProfilePetsSection", "section node name")
	var title := section.get_node_or_null("ProfilePetsTitle") as Label
	_assert(title != null and title.text == "Pets", "Pets title runtime")
	var off_btn := section.get_node_or_null("ProfilePetChoiceOff") as Button
	var parrot_btn := section.get_node_or_null("ProfilePetChoiceParrot") as Button
	_assert(off_btn != null, "Off button runtime")
	_assert(parrot_btn != null, "Parrot button runtime")
	_assert(off_btn != null and off_btn.text.contains("Off"), "Off label")
	_assert(parrot_btn != null and parrot_btn.text.contains("Parrot"), "Parrot label")
	_assert(parrot_btn != null and parrot_btn.text.contains("●"), "Parrot selected mark")
	_assert(off_btn != null and off_btn.text.contains("○"), "Off unselected mark")
	_assert(not _tree_has_text(section, "Android Diagnostics"), "no diagnostics in pets section")
	main.queue_free()


func _test_ui_callbacks_and_persistence() -> void:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var main_script := load("res://scripts/main.gd") as Script
	var main: Node = main_script.new()
	root.add_child(main)
	main.state = AppState.new()
	main.state.bootstrap()
	main.state.pets.bootstrap()
	main.state.pets.grant_pet_from_claim("parrot", false)
	main.state.pets.select_profile_pet("parrot")
	main._screen_host = Control.new()
	main.add_child(main._screen_host)
	var section: VBoxContainer = main._build_profile_pets_section()
	main._screen_host.add_child(section)
	var off_btn := section.get_node_or_null("ProfilePetChoiceOff") as Button
	var parrot_btn := section.get_node_or_null("ProfilePetChoiceParrot") as Button
	_assert(off_btn != null and parrot_btn != null, "controls for callback test")
	## Parrot → Off via UI control
	off_btn.button_pressed = true
	_assert(main.state.pets.pet_enabled == false, "UI Off → pet_enabled false")
	_assert(main.state.pets.active_pet_id == "parrot", "ownership/active preserved")
	_assert(main.state.pets.is_owned("parrot"), "owned preserved")
	_assert(main.state.pets.get_profile_pet_selection() == "off", "selection off")
	_assert(off_btn.text.contains("●"), "Off visual selected after callback")
	_assert(parrot_btn.text.contains("○"), "Parrot visual unselected after callback")
	## Persist reload
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.pet_enabled == false, "Off persists")
	_assert(mgr2.get_profile_pet_selection() == "off", "UI Off after reload")
	## Off → Parrot via UI
	parrot_btn.button_pressed = true
	_assert(main.state.pets.pet_enabled == true, "UI Parrot → enabled")
	_assert(main.state.pets.active_pet_id == "parrot", "active parrot")
	_assert(main.state.pets.get_profile_pet_selection() == "parrot", "selection parrot")
	_assert(parrot_btn.text.contains("●"), "Parrot visual selected")
	_assert(off_btn.text.contains("○"), "Off visual unselected")
	var mgr3 := PetManager.new()
	mgr3.bootstrap()
	_assert(mgr3.pet_enabled == true and mgr3.get_profile_pet_selection() == "parrot", "Parrot persists")
	main.queue_free()


func _test_actor_counts() -> void:
	var wipe := ConfigFile.new()
	wipe.save(PetManager.PERSIST_PATH)
	var env := Node2D.new()
	root.add_child(env)
	var mgr := PetManager.new()
	mgr.bootstrap()
	mgr.grant_pet_from_claim("parrot", false)
	var rt := mgr.ensure_pet_runtime_root(env)
	mgr.select_profile_pet("off")
	_assert(mgr.spawn_active_pet(rt) == null, "spawn null Off")
	_assert(mgr.count_actors_under(env) == 0, "PetActor Off = 0")
	mgr.select_profile_pet("parrot")
	_assert(mgr.spawn_active_pet(rt) != null, "spawn Parrot")
	_assert(mgr.count_actors_under(env) == 1, "PetActor Parrot = 1")
	mgr.despawn_active_pet()
	env.queue_free()


func _test_v63_pet_enabled_migration() -> void:
	## Simulate pre-toggle save: owned+active parrot, NO pet_enabled key.
	var cfg := ConfigFile.new()
	cfg.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg.set_value("active", "id", "parrot")
	## Intentionally omit settings/pet_enabled
	cfg.save(PetManager.PERSIST_PATH)
	var mgr := PetManager.new()
	mgr.bootstrap()
	_assert(mgr.is_owned("parrot"), "migrated owned parrot")
	_assert(mgr.active_pet_id == "parrot", "migrated active parrot")
	_assert(mgr.pet_enabled == true, "missing pet_enabled → true (v63 upgrade)")
	_assert(mgr.get_profile_pet_selection() == "parrot", "UI selection Parrot after migrate")
	_assert(mgr.should_spawn_on_chest(), "should spawn after migrate")
	## Explicit false must remain Off.
	var cfg2 := ConfigFile.new()
	cfg2.set_value("owned", "ids", PackedStringArray(["parrot"]))
	cfg2.set_value("active", "id", "parrot")
	cfg2.set_value("settings", "pet_enabled", false)
	cfg2.save(PetManager.PERSIST_PATH)
	var mgr2 := PetManager.new()
	mgr2.bootstrap()
	_assert(mgr2.pet_enabled == false, "explicit false preserved")
	_assert(mgr2.get_profile_pet_selection() == "off", "explicit false → Off")
	_assert(mgr2.active_pet_id == "parrot", "active preserved while Off")
	_assert(mgr2.is_owned("parrot"), "owned preserved while Off")


func _test_diagnostics_search() -> void:
	var hits: Array[String] = []
	_scan_for_android_diagnostics("res://", hits)
	## Allowed: comments in helpers, tests/tools/docs only.
	## Production UI must never assign sec.text = "Android Diagnostics".
	for path in hits:
		var allowed := (
			path.ends_with("scripts/main.gd")
			or path.ends_with("scripts/scroll/compose_scroll_screen.gd")
			or path.ends_with("scripts/network/location_helper.gd")
			or path.contains("/tests/")
			or path.contains("/tools/")
			or path.contains("/docs/")
		)
		_assert(allowed, "Android Diagnostics ref allowed: " + path)
		if path.ends_with("scripts/main.gd"):
			var src := FileAccess.get_file_as_string(path)
			var p0 := src.find("func _show_profile()")
			var p1 := src.find("func _show_diagnostics()")
			var body := src.substr(p0, p1 - p0)
			_assert(not body.contains('sec.text = "Android Diagnostics"'), "Profile body has no Android Diagnostics title")
			_assert(not body.contains("_build_android_diagnostics_panel"), "Profile body does not call diagnostics builder")
			_assert(not src.contains('sec.text = "Android Diagnostics"'), "main.gd never assigns Android Diagnostics title")
			_assert(body.contains("_build_profile_pets_section"), "Profile mounts pets")


func _scan_for_android_diagnostics(dir_path: String, hits: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var p := dir_path.path_join(name)
		if d.current_is_dir():
			if name in ["android", "build", ".godot", "assets"]:
				name = d.get_next()
				continue
			_scan_for_android_diagnostics(p, hits)
		elif name.ends_with(".gd") or name.ends_with(".tscn") or name.ends_with(".md"):
			var txt := FileAccess.get_file_as_string(p)
			if txt.contains("Android Diagnostics"):
				hits.append(p)
		name = d.get_next()


func _test_regressions() -> void:
	_assert(FileAccess.file_exists("res://scripts/pets/pet_actor.gd"), "pet actor")
	_assert(FileAccess.file_exists("res://scripts/pets/pet_manager.gd"), "pet manager")
	_assert(FileAccess.file_exists("res://scenes/pets/PetActor.tscn"), "pet scene")
	var actor := FileAccess.get_file_as_string("res://scripts/pets/pet_actor.gd")
	_assert(actor.contains("pause_for_reward") or actor.contains("resume_after_reward"), "reward hide hooks")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(not main.contains("Pet Shop"), "no pet shop")
	_assert(main.contains("_show_pet_store") or main.contains("Pet Store"), "Pet Store present")
	_assert(PetRuntimeConfig.PET_RUNTIME_ENABLED, "pet runtime enabled")


func _tree_has_text(n: Node, needle: String) -> bool:
	if n is Label and str((n as Label).text).contains(needle):
		return true
	if n is Button and str((n as Button).text).contains(needle):
		return true
	for c in n.get_children():
		if _tree_has_text(c, needle):
			return true
	return false
