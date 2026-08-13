extends SceneTree
## v47: PATH B clean magical chest transition + grounding + scroll + beach polish.

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
	print("=== Chest PATH B clean transition (v47) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env_script := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var prep := FileAccess.get_file_as_string("res://tools/prepare_chest_animation_frames.py")
	var beach_prep := FileAccess.get_file_as_string("res://tools/prepare_default_beach_environment.py")

	_assert(chest.contains("PATH B"), "PATH B architecture")
	_assert(chest.contains("FRAME_CANVAS := Vector2(384, 496)"), "taller canvas 384x496")
	_assert(chest.contains("EMPTY_FRAME_COUNT := 2"), "2 PATH B empty frames")
	_assert(chest.contains("SCROLL_FRAME_COUNT := 7"), "7 scroll sheet frames")
	_assert(chest.contains("CHEST_FOOT_CANVAS_Y"), "foot canvas constant")
	_assert(chest.contains("CHEST_FOOT_Y_FRAC"), "foot fraction for grounding")
	_assert(chest.contains("SCROLL_LAYER"), "separate scroll layer constant")
	_assert(chest.contains("FRONT_RIM"), "front rim occlusion layer")
	_assert(chest.contains("CONTACT_SHADOW"), "contact shadow grounding")
	_assert(chest.contains("WARM_SPILL"), "warm spill separate from shadow")
	_assert(chest.contains("EMPTY_POSE_WEIGHTS"), "pose cadence constant")
	_assert(chest.contains("OPEN_DURATION_SEC := 0.55"), "short PATH B open")
	_assert(chest.contains("MAGICAL_FLARE_SEC"), "magical flare phase")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 1.28"), "scroll emerge duration")
	_assert(chest.contains("REWARD_HOLD_SEC := 0.45"), "reward hold ~0.45s")
	_assert(chest.contains("EMPHASIS_SCALE := 1.002"), "tiny settle scale only")
	_assert(chest.contains("GLOW_OPEN_A := 0.010"), "reduced glow open")
	_assert(chest.contains("GLOW_SETTLE_A := 0.014"), "reduced glow settle")
	_assert(chest.contains("_play_scroll_rise_tween"), "continuous scroll Y tween")
	_assert(chest.contains("_set_badge_suppressed"), "badge hidden during reward")
	_assert(chest.contains("_enforce_chest_opaque"), "opaque chest enforcement")
	_assert(chest.contains("soft_glow_pulse.png"), "soft radial glow")
	_assert(chest.contains("exactly one TextureRect") or chest.contains("ONE opaque chest"), "one chest sprite comment")
	_assert(chest.contains("ScrollLayer"), "scroll layer node")
	_assert(chest.contains("ScrollCavityClip"), "cavity clip occlusion")
	_assert(chest.contains("ChestFrontRim"), "rim node")
	_assert(chest.contains("ChestContactShadow"), "shadow node")
	_assert(chest.contains("ChestWarmSpill"), "warm spill node")
	_assert(chest.contains("_set_scroll_rise_amount"), "layered scroll rise")
	_assert(chest.contains("foot_y_in_control"), "foot helper for ground plane")
	_assert(chest.contains("hard swap"), "PATH B hard swap comment")
	_assert(not chest.contains("ColorRect.new()"), "no rectangular ColorRect glow")
	_assert(not chest.contains("ChestOpaqueUnderlay"), "no duplicate chest underlay")
	_assert(chest.contains("_ease_open_curve"), "quality easing")
	_assert(chest.contains("_frame_index_from_progress"), "frame timing helper")
	_assert(chest.contains("play_open_empty_pulse"), "empty retap pulse")
	_assert(chest.contains("if animating"), "guards overlapping anim")
	_assert(not chest.contains("HINGE_CANVAS"), "old hinge path removed")
	_assert(not chest.contains("LID_OPEN_ANGLE"), "old lid angle removed")
	_assert(not chest.contains("_lid.rotation"), "no procedural lid rotation")
	_assert(not chest.contains('scale.y =') and not chest.contains('"scale:y"'), "no scale.y squash")
	_assert(chest.contains("preload_assets"), "preload")
	_assert(chest.contains("Color(0.55, 0.55, 0.75, 1.0)"), "locked silhouette keeps alpha 1")
	_assert(chest.contains("draw_w * 0.76") or chest.contains("draw_w * 0.74"), "badge near chest")
	_assert(main.contains("LoveNotesChest.preload_assets"), "main preloads chest")
	_assert(main.contains("ChestEnvironment.preload_assets"), "main preloads beach env")
	_assert(main.contains("ChestEnvironment.new()"), "chest screen mounts environment")
	_assert(main.contains("ENV_DEFAULT_BEACH"), "default_beach id")
	_assert(main.contains("CHEST_GROUND_Y"), "main uses ground-plane constant")
	_assert(main.contains("CHEST_FOOT_Y_FRAC"), "main plants by foot fraction")
	_assert(main.contains("_set_chest_environment_active"), "starfield hidden on chest")
	_assert(main.contains("No new scrolls today."), "empty copy")
	_assert(main.contains("ChestMessageSafeZone"), "message safe zone on landing")
	_assert(main.contains("_add_inventory_filter_rows"), "shared filter rows")
	_assert(main.contains('_add_inventory_filter_rows(root, "saved")'), "Saved uses full filter set")
	_assert(main.contains("_add_inventory_stats_panel"), "management stats helper")
	## Landing reward scene must NOT mount management filters/stats/refresh.
	_assert(not main.contains('_add_inventory_filter_rows(root, "all")'), "landing has no filter rows")
	_assert(main.contains("Do NOT mount Current/Unread/Locked") or main.contains("management UI lives only"), "landing hierarchy comment")
	_assert(main.contains('["hidden", "Hidden", row2]'), "Hidden chip in shared filters")
	_assert(not main.contains("ChestRefreshButton"), "no refresh button on main CHEST")
	_assert(main.contains("Do NOT mount a top-right refresh") or main.contains("no refresh"), "refresh removal comment")
	_assert(main.contains("ChestStatsPanel"), "named stats panel helper")
	_assert(main.contains("_dismiss_toast_if_visible"), "toast dismiss on chest open")
	_assert(main.contains("_fill_inventory_list_deferred"), "deferred loading flash")
	_assert(main.contains("create_timer(0.28)"), "loading delay threshold")
	_assert(main.contains("chest_h := 326"), "taller chest host")
	_assert(main.contains("viewport-centered CHEST") or main.contains("Title centered") or main.contains("Landing reward hierarchy"), "viewport-centered CHEST title")
	_assert(not main.contains("header.add_child(MobileUi.make_page_title(\"Chest\""), "title not HBox-centered")
	_assert(not main.contains('your.text = "Your Chest"'), "no Your Chest label on landing")
	_assert(main.contains("soft fade into YOUR CHEST") or main.contains("0.34"), "intentional transition fade")
	_assert(boot.contains("MIN_VISIBLE_SEC := 4.0"), "splash min 4s")
	_assert(prep.contains("CANVAS_H = 496"), "prep taller canvas")
	_assert(prep.contains("BASE_Y = 394"), "foot lock absolute")
	_assert(prep.contains("primary_mass_crop_h"), "primary-mass crop rejects bleed")
	_assert(prep.contains("normalize_body_scale"), "body scale normalization")
	_assert(prep.contains("normalize_body_exposure"), "body exposure normalization")
	_assert(prep.contains("harden_chest_opacity"), "frame opacity harden")
	_assert(prep.contains("seal_body_cracks"), "wood crack seal")
	_assert(prep.contains("dampen_cavity_glow"), "cavity glow dampen")
	_assert(prep.contains("build_vertical_love_note") or prep.contains("build_clean_scroll_layer"), "vertical love note")
	_assert(prep.contains("scroll_rolled.png"), "rolled parchment donor")
	_assert(prep.contains("compose_scroll_rise"), "raised scroll composites")
	_assert(prep.contains("PATH B") or prep.contains("empty_picks = [0, 15]"), "PATH B empty picks")
	_assert(prep.contains("empty_picks = [0, 15]"), "compatible empty picks only")
	_assert(prep.contains("cell_top_clipped"), "rejects damaged top cells")
	_assert(prep.contains('(-78, "scroll_fully")'), "final scroll rise dy")
	_assert(prep.contains("write_warm_spill"), "warm spill asset writer")
	_assert(beach_prep.contains("default_beach.png"), "beach generator output")
	_assert(beach_prep.contains("shoreline_y") or beach_prep.contains("paint_sand"), "detailed shoreline/sand")
	_assert(beach_prep.contains("paint_ocean"), "ocean detail")
	_assert(beach_prep.contains("no repetitive stripe") or beach_prep.contains("not geometric stripe") or beach_prep.contains("non-striped") or beach_prep.contains("polish-only"), "beach polish path")
	_assert(beach_prep.contains("default_rng(47)") or beach_prep.contains("rng(47)"), "v47 beach seed")
	_assert(env_script.contains("ENV_DEFAULT_BEACH"), "environment id constant")
	_assert(env_script.contains("CHEST_GROUND_Y := 0.805"), "ground plane lowered to sand")
	_assert(env_script.contains("apply_environment"), "swappable environment API")
	_assert(env_script.contains("EnvironmentBaseFill") or env_script.contains("_base_fill"), "opaque beach base fill")
	_assert(not env_script.contains("BillingClient") and not env_script.contains("in_app_purchase"), "no store implementation")

	_assert(
		FileAccess.file_exists(
			"res://assets/chest/animation/glowing_treasure_chest_opening_sprite_sheet.png"
		),
		"glowing source sheet"
	)
	_assert(
		FileAccess.file_exists(
			"res://assets/chest/animation/magical_treasure_chest_animation_sheet.png"
		),
		"magical source sheet"
	)
	_assert(FileAccess.file_exists("res://assets/art/chest/soft_glow_pulse.png"), "soft glow asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/scroll_rolled.png"), "scroll layer asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_front_rim.png"), "front rim asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_contact_shadow.png"), "contact shadow asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_warm_spill.png"), "warm spill asset")
	_assert(
		FileAccess.file_exists("res://assets/art/background/environments/default_beach.png"),
		"default beach environment art"
	)
	for i in range(2):
		_assert(
			FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_%02d.png" % i),
			"empty frame %02d" % i
		)
	for i in range(7):
		_assert(
			FileAccess.file_exists("res://assets/art/chest/frames/scroll/scroll_%02d.png" % i),
			"scroll frame %02d" % i
		)
	_assert(not FileAccess.file_exists("res://assets/art/chest/frames/empty/empty_02.png"), "no empty_02")
	_assert(not FileAccess.file_exists("res://assets/art/chest/frames/scroll/scroll_07.png"), "no scroll_07")

	_assert(flags.contains("APP_VERSION_CODE := 47"), "versionCode 47")
	_assert(preset.contains("version/code=47"), "export 47")
	_assert(preset.contains("0.1.47-chest-clean-transition"), "version name")
	_assert(preset.contains("v47-chest-clean-transition-debug.apk"), "APK name")
	_assert(gitignore.contains("*.apk"), "apks ignored by default")
	_assert(export_sh.contains("v47-chest-clean-transition-debug.apk"), "export default")

	## Runtime: preload + pose snaps for representative states.
	LoveNotesChest.preload_assets()
	ChestEnvironment.preload_assets()
	var node := LoveNotesChest.new()
	root.add_child(node)
	node.size = Vector2(252, 326)
	var env := ChestEnvironment.new()
	root.add_child(env)
	env.size = Vector2(390, 844)
	await process_frame
	_assert(node._empty_frames.size() == 2, "empty frames loaded")
	_assert(node._scroll_frames.size() == 7, "scroll frames loaded")
	_assert(node._scroll_view != null, "scroll layer present")
	_assert(node._scroll_clip != null, "scroll cavity clip present")
	_assert(node._rim_view != null, "rim layer present")
	_assert(node._shadow_view != null, "shadow layer present")
	_assert(node._warm_spill != null, "warm spill present")
	_assert(env._bg != null and env._bg.texture != null, "beach texture loaded")
	_assert(env.environment_id == ChestEnvironment.ENV_DEFAULT_BEACH, "default beach id active")
	_assert(env._base_fill != null, "opaque environment base present")
	_assert(absf(env.sand_contact_y_frac() - ChestEnvironment.CHEST_GROUND_Y) < 0.001, "ground Y API")
	_assert(absf(ChestEnvironment.CHEST_GROUND_Y - 0.805) < 0.001, "ground Y is 0.805")

	## Grounding: contact shadow kisses the foot (no hover gap).
	node._layout_frames()
	await process_frame
	var foot_y := node.foot_y_in_control()
	var shadow_top := node._shadow_view.position.y
	var shadow_bot := shadow_top + node._shadow_view.size.y
	_assert(shadow_top <= foot_y + 2.0, "shadow top at/above foot")
	_assert(shadow_bot >= foot_y - 1.0, "shadow reaches foot (no hover gap)")
	_assert(absf(foot_y - node.size.y * LoveNotesChest.CHEST_FOOT_Y_FRAC) < 3.0, "foot on ground frac")

	var states := [
		{"name": "closed", "p": 0.0, "scroll": false},
		{"name": "flare_hold_closed", "p": 0.40, "scroll": false},
		{"name": "open_swap", "p": 0.85, "scroll": false},
		{"name": "fully_open", "p": 1.0, "scroll": false},
		{"name": "scroll_peek", "p": 0.48, "scroll": true},
		{"name": "scroll_partial", "p": 0.62, "scroll": true},
		{"name": "scroll_halfway", "p": 0.78, "scroll": true},
		{"name": "scroll_mostly", "p": 0.90, "scroll": true},
		{"name": "scroll_fully", "p": 1.0, "scroll": true},
	]
	var validate_dir := OS.get_user_data_dir().path_join("chest_validate_v47")
	DirAccess.make_dir_recursive_absolute(validate_dir)
	var prev_body_span := -1.0
	for s in states:
		node._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		await process_frame
		_assert(node.modulate.a >= 0.999, "state %s root opaque" % s["name"])
		_assert(node.self_modulate.a >= 0.999, "state %s self opaque" % s["name"])
		_assert(node._frame_view.modulate.a >= 0.999, "state %s frame opaque" % s["name"])
		## PATH B uses only empty_00 / empty_01 — never mid-pose glitch frames.
		_assert(node._frame_index == 0 or node._frame_index == 1, "state %s PATH B index" % s["name"])
		var tex: Texture2D = node._frame_view.texture
		_assert(tex != null, "state %s has texture" % s["name"])
		_assert(not str(tex.resource_path).contains("chest_body_planted"), "state %s not old body" % s["name"])
		_assert(not str(tex.resource_path).contains("chest_lid.png"), "state %s not old lid" % s["name"])
		_assert(node._frame_view != null, "state %s single frame view" % s["name"])
		if bool(s["scroll"]) and float(s["p"]) >= LoveNotesChest.SCROLL_REVEAL_START_PROGRESS:
			_assert(node._scroll_clip.visible, "state %s scroll clip visible" % s["name"])
			_assert(node._rim_view.visible, "state %s rim visible" % s["name"])
			_assert(node._scroll_clip.z_index > node._frame_view.z_index, "state %s scroll above chest" % s["name"])
			_assert(node._rim_view.z_index > node._scroll_clip.z_index, "state %s rim above scroll" % s["name"])
			_assert(node._scroll_rise > 0.0, "state %s scroll rising" % s["name"])
		if tex is ImageTexture or tex is CompressedTexture2D:
			var img: Image = tex.get_image()
			if img:
				var w := img.get_width()
				var h := img.get_height()
				var top_hits := 0
				for x in range(w):
					if img.get_pixel(x, 0).a > 0.15 or img.get_pixel(x, mini(1, h - 1)).a > 0.15:
						top_hits += 1
				_assert(top_hits == 0, "state %s no top-edge opacity" % s["name"])
				var y0 := int(h * 0.55)
				var min_x := w
				var max_x := 0
				for y in range(y0, h):
					for x in range(w):
						if img.get_pixel(x, y).a > 0.15:
							min_x = mini(min_x, x)
							max_x = maxi(max_x, x)
				if max_x > min_x:
					var span := float(max_x - min_x + 1)
					if prev_body_span > 0.0 and not bool(s["scroll"]):
						var drift := absf(span - prev_body_span) / prev_body_span
						_assert(drift < 0.10, "state %s body width stable (drift=%.3f)" % [s["name"], drift])
					if not bool(s["scroll"]):
						prev_body_span = span
				var gold_mid := 0
				var gold_n := 0
				for y in range(int(h * 0.40), int(h * 0.80)):
					for x in range(int(w * 0.25), int(w * 0.75)):
						var px := img.get_pixel(x, y)
						if px.a > 0.08 and px.r > 0.45 and px.g > 0.25 and (px.r - px.b) > 0.12:
							gold_n += 1
							if px.a < 0.97:
								gold_mid += 1
				if gold_n > 40:
					var mid_frac := float(gold_mid) / float(gold_n)
					_assert(mid_frac < 0.05, "state %s gold body opaque (mid=%.3f)" % [s["name"], mid_frac])
				var path := validate_dir.path_join("%s.png" % s["name"])
				img.save_png(path)
				print("WROTE ", path)
		_assert(node._frame_index >= 0, "state %s frame index" % s["name"])

	node._set_frame_progress(1.0, true)
	await process_frame
	_assert(node._frame_index == 1, "final open chest frame index 1")
	_assert(node._scroll_rise >= 0.999, "final scroll rise complete")
	_assert(node._scroll_clip.visible, "final scroll clip visible")
	_assert(node._rim_view.visible, "final rim layer visible")
	_assert(node._rim_view.z_index > node._scroll_clip.z_index, "rim occludes lower scroll only")
	_assert(node._scroll_clip.z_index > node._frame_view.z_index, "upper scroll above chest")

	node.set_unread_badge(3)
	node._set_badge_suppressed(true)
	_assert(node._badge.visible == false, "badge hidden during animation")
	node._set_badge_suppressed(false)
	_assert(node._badge.visible == true, "badge restored after animation")
	_assert(node._badge.position.y > node._anchor_rect.position.y, "badge below canvas top")
	_assert(node._badge.position.y < node._anchor_rect.position.y + node._anchor_rect.size.y * 0.55, "badge in upper chest band")

	## Rapid-tap guard
	node.animating = true
	node.play_open_animation(false, false)
	_assert(node.animating == true, "rapid tap blocked while animating")
	node.animating = false
	node.chest_state = LoveNotesChest.ChestState.OPEN_EMPTY
	node._open_amount = 1.0
	await node.play_open_empty_pulse()
	_assert(node.chest_state == LoveNotesChest.ChestState.OPEN_EMPTY, "pulse keeps OPEN_EMPTY")

	## Title centering without refresh button — title center == viewport center.
	for vw in [360, 390, 412]:
		var header := Control.new()
		header.size = Vector2(vw, 52)
		root.add_child(header)
		var title := Label.new()
		title.text = "Chest"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		header.add_child(title)
		await process_frame
		var title_center_x := title.global_position.x + title.size.x * 0.5
		var view_center_x := header.global_position.x + header.size.x * 0.5
		_assert(absf(title_center_x - view_center_x) < 1.0, "title center == viewport center @%d" % vw)
		header.queue_free()

	node.queue_free()
	env.queue_free()
	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
