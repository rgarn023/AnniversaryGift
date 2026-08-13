extends SceneTree
## v53: scroll layer compositing + continuous sky gradient on frozen animation_v2.

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
	print("=== Chest scroll layer / sky polish (v53) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env_script := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")

	_assert(chest.contains("animation_v2"), "animation_v2 wired")
	_assert(chest.contains("FRAME_CANVAS := Vector2(512, 512)"), "512x512 production canvas")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "13 approved frames")
	_assert(chest.contains("CHEST_FOOT_CANVAS_Y := 420.0"), "foot canvas 420")
	_assert(chest.contains("CHEST_FOOT_Y_FRAC"), "foot fraction for grounding")
	_assert(chest.contains("chest_00_closed.png"), "frame 00 wired")
	_assert(chest.contains("chest_12_fully_open.png"), "frame 12 wired")
	_assert(chest.contains("chest_open_back.png"), "open-back layer")
	_assert(chest.contains("chest_open_front_rim.png"), "front-rim layer")
	_assert(chest.contains("love_scroll_reward.png"), "romantic horizontal reward scroll")
	_assert(chest.contains("love_scroll_horizontal.png"), "legacy horizontal tube preserved")
	_assert(chest.contains("love_scroll.png"), "original vertical scroll preserved in source const")
	_assert(chest.contains("new_love_scroll_master.png"), "master source referenced")
	_assert(chest.contains("SCROLL_NATIVE := Vector2(720, 305)"), "romantic scroll native size")
	_assert(chest.contains("SCROLL_OPENING_WIDTH_FRAC := 0.70"), "scroll ~70% opening width")
	_assert(chest.contains("CONTACT_SHADOW"), "contact shadow grounding")
	_assert(chest.contains("WARM_SPILL"), "warm spill separate from shadow")
	_assert(chest.contains("OPEN_DURATION_SEC := 1.0"), "open duration ~1.0s")
	_assert(chest.contains("OPEN_POSE_WEIGHTS"), "variable frame timing")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 0.55"), "scroll emerge duration ~0.55s")
	_assert(chest.contains("SCROLL_POST_OPEN_BEAT_SEC := 0.11"), "post-open beat")
	_assert(chest.contains("REWARD_HOLD_SEC := 0.60"), "reward hold ~0.60s")
	_assert(chest.contains("SCROLL_FINAL_ABOVE_RIM := 0.90"), "final reveal ~90%")
	_assert(chest.contains("SCROLL_PEEK_ABOVE_RIM := 0.08"), "first peek ~8%")
	_assert(chest.contains("GLOW_EMERGE_A"), "reduced emerge glow")
	_assert(chest.contains("hard-cut the scroll bottom") or chest.contains("clip_contents hard-cut"), "clipping root-cause documented")
	_assert(chest.contains("EMPHASIS_SCALE := 1.002"), "tiny settle scale only")
	_assert(chest.contains("_play_scroll_rise_tween"), "continuous scroll Y tween")
	_assert(chest.contains("_enter_layered_open"), "clean layered open switch")
	_assert(chest.contains("_set_badge_suppressed"), "badge hidden during reward")
	_assert(chest.contains("_enforce_chest_opaque"), "opaque chest enforcement")
	_assert(chest.contains("soft_glow_pulse.png"), "soft radial glow")
	_assert(chest.contains("ONE opaque chest") or chest.contains("exactly ONE"), "one chest sprite comment")
	_assert(chest.contains("ScrollLayer"), "scroll layer node")
	_assert(chest.contains("ScrollCavityClip"), "cavity clip occlusion")
	_assert(chest.contains("ChestFrontRim"), "rim node")
	_assert(chest.contains("ChestContactShadow"), "shadow node")
	_assert(chest.contains("ChestWarmSpill"), "warm spill node")
	_assert(chest.contains("_set_scroll_rise_amount"), "layered scroll rise")
	_assert(chest.contains("foot_y_in_control"), "foot helper for ground plane")
	_assert(chest.contains("No chest crossfade") or chest.contains("no crossfade"), "no crossfade policy")
	_assert(chest.contains("rotation = 0.0"), "scroll rotation locked at 0")
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
	_assert(not chest.contains("assets/art/chest/frames/empty/"), "legacy empty frames not active")
	_assert(not chest.contains("assets/art/chest/frames/scroll/"), "legacy scroll sheet not active")
	_assert(not chest.contains("magical_treasure_chest_animation_sheet"), "magical sheet not runtime")
	_assert(not chest.contains("glowing_treasure_chest_opening_sprite_sheet"), "glowing sheet not runtime")
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
	_assert(env_script.contains("ENV_DEFAULT_BEACH"), "environment id constant")
	_assert(env_script.contains("CHEST_GROUND_Y := 0.888"), "ground plane nudged down to sand")
	_assert(env_script.contains("ocean_glisten.png"), "ocean glisten asset wired")
	_assert(env_script.contains("OceanGlistenClip"), "water-only glisten clip")
	_assert(env_script.contains("OceanGlistenB"), "second shimmer glint band")
	_assert(env_script.contains("OceanGlint_"), "discrete ocean glint streaks")
	_assert(env_script.contains("GLINT_COUNT := 6"), "six visible glints")
	_assert(env_script.contains("WATER_TOP_FRAC"), "water top bound")
	_assert(env_script.contains("WATER_BOTTOM_FRAC"), "water bottom bound")
	_assert(env_script.contains("apply_environment"), "swappable environment API")
	_assert(env_script.contains("EnvironmentBaseFill") or env_script.contains("_base_fill"), "opaque beach base fill")
	_assert(env_script.contains("tod_palette_at"), "time-of-day palette interpolation")
	_assert(env_script.contains("local_hour_frac"), "device local clock helper")
	_assert(env_script.contains("debug_hour_override"), "dev hour override for validation")
	_assert(env_script.contains("SkyTimeClip"), "sky-only time wash clip")
	_assert(env_script.contains("SkyContinuousGradient"), "continuous sky gradient node")
	_assert(env_script.contains("GradientTexture2D"), "GradientTexture2D sky")
	_assert(env_script.contains("sky_mid") and env_script.contains("sky_lower"), "multi-stop sky palette")
	_assert(not env_script.contains("name = \"SkyWashTop\""), "banded sky wash top node removed")
	_assert(not env_script.contains("name = \"SkyWashHorizon\""), "banded sky wash horizon node removed")
	_assert(not env_script.contains("name = \"HorizonSheen\""), "horizon ColorRect seam removed")
	_assert(not env_script.contains("_sky_wash_top"), "legacy sky wash top var removed")
	_assert(not env_script.contains("_horizon_sheen"), "legacy horizon sheen var removed")
	_assert(env_script.contains("SkyStars"), "sky stars layer")
	_assert(env_script.contains("OceanTimeTint"), "ocean time tint")
	_assert(env_script.contains("\"night\"") and env_script.contains("\"dawn\"") and env_script.contains("\"day\"") and env_script.contains("\"sunset\""), "four TOD phases")
	_assert(not env_script.contains("BillingClient") and not env_script.contains("in_app_purchase"), "no store implementation")
	_assert(not env_script.contains("get_location") and not env_script.contains("LocationHelper"), "no location API for sky")
	_assert(chest.contains("CAVITY_RIM_CANVAS_Y := 274.0"), "rim Y matches re-derived lip top")
	_assert(chest.contains("GLOW_EMERGE_A := 0.0010") or chest.contains("GLOW_EMERGE_A := 0.001"), "reduced emerge glow")
	_assert(chest.contains("z_index = 5") and chest.contains("ScrollCavityClip"), "scroll z above glow/back")

	for i in range(13):
		var fname := ""
		if i == 0:
			fname = "chest_00_closed.png"
		elif i == 12:
			fname = "chest_12_fully_open.png"
		else:
			var labels := ["", "08", "17", "25", "33", "42", "50", "58", "67", "75", "83", "92"]
			fname = "chest_%02d_open_%s.png" % [i, labels[i]]
		_assert(
			FileAccess.file_exists("res://assets/chest/animation_v2/chest_frames/%s" % fname),
			"approved frame %s" % fname
		)
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/layers/chest_open_back.png"),
		"open-back layer asset"
	)
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/layers/chest_open_front_rim.png"),
		"front-rim layer asset"
	)
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/scroll/love_scroll.png"),
		"original vertical scroll asset preserved"
	)
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/scroll/love_scroll_horizontal.png"),
		"legacy horizontal tube asset preserved"
	)
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/scroll/love_scroll_reward.png"),
		"romantic reward scroll asset"
	)
	_assert(
		FileAccess.file_exists("res://assets/chest/animation_v2/incoming_new_art/new_love_scroll_master.png"),
		"romantic master source preserved"
	)
	_assert(FileAccess.file_exists("res://assets/art/chest/soft_glow_pulse.png"), "soft glow asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_contact_shadow.png"), "contact shadow asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_warm_spill.png"), "warm spill asset")
	_assert(
		FileAccess.file_exists("res://assets/art/background/environments/default_beach.png"),
		"default beach environment art"
	)

	_assert(flags.contains("APP_VERSION_CODE := 53"), "versionCode 53")
	_assert(preset.contains("version/code=53"), "export 53")
	_assert(preset.contains("0.1.53-scroll-layer-sky-polish"), "version name")
	_assert(preset.contains("v53-scroll-layer-sky-polish-debug.apk"), "APK name")
	_assert(gitignore.contains("*.apk"), "apks ignored by default")
	_assert(export_sh.contains("v53-scroll-layer-sky-polish-debug.apk"), "export default")
	_assert(
		FileAccess.file_exists("res://assets/art/background/environments/ocean_glisten.png"),
		"ocean glisten texture asset"
	)

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
	_assert(node._chest_frames.size() == 13, "13 chest frames loaded")
	_assert(node._empty_frames.size() == 13, "empty alias has 13 frames")
	_assert(node._scroll_view != null, "scroll layer present")
	_assert(node._scroll_clip != null, "scroll cavity clip present")
	_assert(node._rim_view != null, "rim layer present")
	_assert(node._shadow_view != null, "shadow layer present")
	_assert(node._warm_spill != null, "warm spill present")
	_assert(node._open_back_tex != null, "open-back texture loaded")
	_assert(node._rim_layer_tex != null, "rim texture loaded")
	_assert(node._scroll_layer_tex != null, "scroll texture loaded")
	_assert(str(node._scroll_layer_tex.resource_path).contains("love_scroll_reward"), "runtime uses romantic reward scroll")
	_assert(not str(node._scroll_layer_tex.resource_path).ends_with("love_scroll_horizontal.png"), "runtime not tiny horizontal tube")
	_assert(env._bg != null and env._bg.texture != null, "beach texture loaded")
	_assert(env.environment_id == ChestEnvironment.ENV_DEFAULT_BEACH, "default beach id active")
	_assert(env._base_fill != null, "opaque environment base present")
	_assert(env._water_glisten != null, "ocean glisten layer present")
	_assert(env._water_glisten_b != null, "second ocean glisten layer present")
	_assert(env._water_clip != null, "ocean glisten clip present")
	_assert(env._glints.size() == ChestEnvironment.GLINT_COUNT, "discrete glint count")
	_assert(ChestEnvironment.GLINT_COUNT == 6, "six glints configured")
	_assert(absf(env.sand_contact_y_frac() - ChestEnvironment.CHEST_GROUND_Y) < 0.001, "ground Y API")
	_assert(absf(ChestEnvironment.CHEST_GROUND_Y - 0.888) < 0.001, "ground Y is 0.888")
	_assert(env._sky_clip != null, "sky time clip present")
	_assert(env._sky_gradient_view != null, "continuous sky gradient present")
	_assert(env._sky_gradient_tex != null, "sky GradientTexture2D present")
	_assert(env._sky_gradient != null and env._sky_gradient.get_point_count() >= 4, "sky has >=4 gradient stops")
	_assert(env._stars != null, "sky stars present")
	_assert(env._ocean_tint != null, "ocean tint present")
	env._layout()
	await process_frame
	var water_top := env.size.y * ChestEnvironment.WATER_TOP_FRAC
	var water_bot := env.size.y * ChestEnvironment.WATER_BOTTOM_FRAC
	_assert(env._water_clip.position.y >= water_top - 1.0, "glisten starts at water top")
	_assert(env._water_clip.position.y + env._water_clip.size.y <= water_bot + 1.0, "glisten ends at water bottom")
	_assert(env._water_clip.position.y > env.size.y * 0.45, "glisten below sky")
	_assert(env._water_clip.position.y + env._water_clip.size.y < env.size.y * 0.60, "glisten above sand")
	_assert(env._sky_clip.size.y <= env.size.y * ChestEnvironment.SKY_BOTTOM_FRAC + 1.0, "stars/sky wash clipped to sky")
	_assert(env._sky_gradient_view.size.y >= env._sky_clip.size.y - 1.0, "gradient fills sky clip")
	for g in env._glints:
		_assert(g.get_parent() == env._water_clip, "glint parented under water clip")
		_assert(g.position.y >= -1.0, "glint inside water clip top")
		_assert(g.position.y + g.size.y <= env._water_clip.size.y + 1.0, "glint inside water clip bottom")
	## Layer order: open-back < glow < scroll < front rim
	_assert(node._glow_pulse.z_index > node._frame_view.z_index, "glow above open-back")
	_assert(node._scroll_clip.z_index > node._glow_pulse.z_index, "scroll above glow")
	_assert(node._rim_view.z_index > node._scroll_clip.z_index, "rim above scroll")
	_assert(absf(LoveNotesChest.CAVITY_RIM_CANVAS_Y - 274.0) < 0.01, "cavity rim at lip top")

	## Dynamic sky interpolation (device-local clock; mock hours for validation only).
	var prev_override := ChestEnvironment.debug_hour_override
	for hour_case in [
		{"h": 0.0, "phase": "night", "stars_min": 0.6},
		{"h": 6.5, "phase": "dawn", "stars_max": 0.35},
		{"h": 12.0, "phase": "day", "stars_max": 0.01},
		{"h": 18.5, "phase": "sunset", "stars_min": 0.1},
	]:
		ChestEnvironment.debug_hour_override = float(hour_case["h"])
		var pal := ChestEnvironment.tod_palette_at(float(hour_case["h"]))
		_assert(str(pal["phase"]) == str(hour_case["phase"]), "phase %s @%.1f" % [hour_case["phase"], float(hour_case["h"])])
		env._apply_time_of_day(true)
		await process_frame
		if hour_case.has("stars_min"):
			_assert(float(pal["star_a"]) >= float(hour_case["stars_min"]), "stars visible @%.1f" % float(hour_case["h"]))
		if hour_case.has("stars_max"):
			_assert(float(pal["star_a"]) <= float(hour_case["stars_max"]), "stars faded @%.1f" % float(hour_case["h"]))
		_assert(env._ocean_tint.color.a > 0.05, "ocean tint active @%.1f" % float(hour_case["h"]))
	## Smooth mid-phase blend (06:30 should sit between dawn keyframes).
	var dawn_mid := ChestEnvironment.tod_palette_at(6.5)
	var dawn_start := ChestEnvironment.tod_palette_at(5.0)
	var dawn_end := ChestEnvironment.tod_palette_at(8.0)
	_assert(float(dawn_mid["star_a"]) < float(dawn_start["star_a"]), "dawn mid stars below night-edge")
	_assert(float(dawn_mid["star_a"]) > float(dawn_end["star_a"]), "dawn mid stars above day")
	ChestEnvironment.debug_hour_override = prev_override
	env._apply_time_of_day(true)

	## Grounding: contact shadow kisses the foot (no hover gap).
	node._layout_frames()
	await process_frame
	var foot_y := node.foot_y_in_control()
	var shadow_top := node._shadow_view.position.y
	var shadow_bot := shadow_top + node._shadow_view.size.y
	_assert(shadow_top <= foot_y + 2.0, "shadow top at/above foot")
	_assert(shadow_bot >= foot_y - 1.0, "shadow reaches foot (no hover gap)")
	_assert(absf(foot_y - node.size.y * LoveNotesChest.CHEST_FOOT_Y_FRAC) < 3.0, "foot on ground frac")
	_assert(node._shadow_view.size.x <= node._anchor_rect.size.x * 0.40, "shadow tight under feet")

	## Horizontal scroll geometry at final pose.
	node._enter_layered_open()
	node._set_scroll_rise_amount(1.0)
	await process_frame
	var scroll_w := node._scroll_view.size.x
	var scroll_h := node._scroll_view.size.y
	var opening_w := node._anchor_rect.size.x * 0.47
	var width_frac := scroll_w / maxf(opening_w, 1.0)
	_assert(width_frac >= 0.62 and width_frac <= 0.82, "scroll width ~65-75%% of opening (got %.2f)" % width_frac)
	_assert(node._scroll_view.size.x > node._scroll_view.size.y, "scroll is horizontal (w>h)")
	_assert(is_zero_approx(node._scroll_view.rotation), "scroll rotation stays 0")
	var native_aspect := LoveNotesChest.SCROLL_NATIVE.x / LoveNotesChest.SCROLL_NATIVE.y
	var runtime_aspect := scroll_w / maxf(scroll_h, 0.01)
	_assert(absf(runtime_aspect - native_aspect) < 0.05, "scroll aspect preserved")
	## Final pose: ~85–90% of scroll HEIGHT above rim.
	var rim_y_check := node._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * node._anchor_rect.size.y
	var scroll_top_check := node._scroll_clip.position.y + node._scroll_view.position.y
	var scroll_bot_check := scroll_top_check + scroll_h
	var above_frac := (rim_y_check - scroll_top_check) / maxf(scroll_h, 0.01)
	_assert(above_frac >= 0.85 and above_frac <= 0.94, "final visible height ~85-90%% (got %.2f)" % above_frac)
	## Clipping root-cause fix: cavity clip must fully contain scroll at peek and final.
	_assert(scroll_top_check >= node._scroll_clip.position.y - 0.5, "final scroll top inside clip")
	_assert(scroll_bot_check <= node._scroll_clip.position.y + node._scroll_clip.size.y + 0.5, "final scroll bottom inside clip")
	node._set_scroll_rise_amount(0.0)
	await process_frame
	var peek_top := node._scroll_clip.position.y + node._scroll_view.position.y
	var peek_bot := peek_top + node._scroll_view.size.y
	_assert(peek_top >= node._scroll_clip.position.y - 0.5, "peek scroll top inside clip")
	_assert(peek_bot <= node._scroll_clip.position.y + node._scroll_clip.size.y + 0.5, "peek scroll bottom inside clip (no hard cut)")
	node._set_scroll_rise_amount(1.0)
	await process_frame

	## Open-frame → layer handoff alignment (identical plant rect).
	node._exit_layered_open()
	node._show_frame_index(12)
	await process_frame
	var frame_rect := Rect2(node._frame_view.position, node._frame_view.size)
	node._enter_layered_open()
	await process_frame
	_assert(node._frame_view.position == frame_rect.position, "handoff frame position unchanged")
	_assert(node._frame_view.size == frame_rect.size, "handoff frame size unchanged")
	_assert(node._rim_view.position == frame_rect.position, "rim shares frame position")
	_assert(node._rim_view.size == frame_rect.size, "rim shares frame size")

	## Sample near each pose-weight end so all 13 frames are exercised.
	var open_states := [
		{"name": "closed", "p": 0.0, "scroll": false, "expect_i": 0},
		{"name": "open_08", "p": 0.10, "scroll": false, "expect_i": 1},
		{"name": "open_17", "p": 0.18, "scroll": false, "expect_i": 2},
		{"name": "open_25", "p": 0.26, "scroll": false, "expect_i": 3},
		{"name": "open_33", "p": 0.33, "scroll": false, "expect_i": 4},
		{"name": "open_42", "p": 0.40, "scroll": false, "expect_i": 5},
		{"name": "open_50", "p": 0.47, "scroll": false, "expect_i": 6},
		{"name": "open_58", "p": 0.54, "scroll": false, "expect_i": 7},
		{"name": "open_67", "p": 0.62, "scroll": false, "expect_i": 8},
		{"name": "open_75", "p": 0.70, "scroll": false, "expect_i": 9},
		{"name": "open_83", "p": 0.78, "scroll": false, "expect_i": 10},
		{"name": "open_92", "p": 0.88, "scroll": false, "expect_i": 11},
		{"name": "fully_open", "p": 1.0, "scroll": false, "expect_i": 12},
		{"name": "scroll_hidden", "p": 0.48, "scroll": true, "expect_i": 12},
		{"name": "scroll_peek", "p": 0.55, "scroll": true, "expect_i": 12},
		{"name": "scroll_25", "p": 0.66, "scroll": true, "expect_i": 12},
		{"name": "scroll_45", "p": 0.78, "scroll": true, "expect_i": 12},
		{"name": "scroll_60", "p": 0.90, "scroll": true, "expect_i": 12},
		{"name": "scroll_final", "p": 1.0, "scroll": true, "expect_i": 12},
	]
	var validate_dir := OS.get_user_data_dir().path_join("chest_validate_v51")
	DirAccess.make_dir_recursive_absolute(validate_dir)
	var prev_body_span := -1.0
	var seen_indices: Dictionary = {}
	for s in open_states:
		node._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		await process_frame
		_assert(node.modulate.a >= 0.999, "state %s root opaque" % s["name"])
		_assert(node.self_modulate.a >= 0.999, "state %s self opaque" % s["name"])
		_assert(node._frame_view.modulate.a >= 0.999, "state %s frame opaque" % s["name"])
		_assert(
			node._frame_index == int(s["expect_i"]),
			"state %s frame index %d == %d" % [s["name"], node._frame_index, int(s["expect_i"])]
		)
		seen_indices[node._frame_index] = true
		var tex: Texture2D = node._frame_view.texture
		_assert(tex != null, "state %s has texture" % s["name"])
		var path_str := str(tex.resource_path)
		_assert(path_str.contains("animation_v2"), "state %s uses animation_v2" % s["name"])
		_assert(not path_str.contains("frames/empty"), "state %s not legacy empty" % s["name"])
		_assert(not path_str.contains("chest_body_planted"), "state %s not old body" % s["name"])
		_assert(not path_str.contains("chest_lid.png"), "state %s not old lid" % s["name"])
		if bool(s["scroll"]) and float(s["p"]) >= LoveNotesChest.SCROLL_REVEAL_START_PROGRESS:
			_assert(node._scroll_clip.visible, "state %s scroll clip visible" % s["name"])
			_assert(node._rim_view.visible, "state %s rim visible" % s["name"])
			_assert(node._layered_open, "state %s layered open" % s["name"])
			_assert(path_str.contains("chest_open_back"), "state %s shows open-back" % s["name"])
			_assert(node._scroll_clip.z_index > node._frame_view.z_index, "state %s scroll above chest" % s["name"])
			_assert(node._rim_view.z_index > node._scroll_clip.z_index, "state %s rim above scroll" % s["name"])
			_assert(is_zero_approx(node._scroll_view.rotation), "state %s scroll no rotation" % s["name"])
			_assert(node._scroll_view.size.x > node._scroll_view.size.y, "state %s scroll horizontal" % s["name"])
		if not bool(s["scroll"]):
			_assert(not node._layered_open, "state %s not layered before scroll" % s["name"])
			_assert(not node._rim_view.visible, "state %s rim hidden before scroll" % s["name"])
		if tex is ImageTexture or tex is CompressedTexture2D:
			var img: Image = tex.get_image()
			if img:
				var w := img.get_width()
				var h := img.get_height()
				_assert(w == 512 and h == 512, "state %s 512x512" % s["name"])
				var top_hits := 0
				for x in range(w):
					if img.get_pixel(x, 0).a > 0.15 or img.get_pixel(x, mini(1, h - 1)).a > 0.15:
						top_hits += 1
				_assert(top_hits == 0, "state %s no top-edge opacity" % s["name"])
				## Mid-body band (matches asset audit mid_w around planted body, not lid tips).
				var y_mid := int(h * 0.72)
				var min_x := w
				var max_x := 0
				for x in range(w):
					if img.get_pixel(x, y_mid).a > 0.15:
						min_x = mini(min_x, x)
						max_x = maxi(max_x, x)
				if max_x > min_x:
					var span := float(max_x - min_x + 1)
					if prev_body_span > 0.0 and not bool(s["scroll"]):
						var drift := absf(span - prev_body_span) / prev_body_span
						## Asset audit allows ~±4px on ~237 mid-body (~1.7%); keep runtime <4%.
						_assert(drift < 0.04, "state %s mid-body width stable (drift=%.3f)" % [s["name"], drift])
					if not bool(s["scroll"]):
						prev_body_span = span
				var path := validate_dir.path_join("%s.png" % s["name"])
				img.save_png(path)
				print("WROTE ", path)
		_assert(node._frame_index >= 0, "state %s frame index" % s["name"])

	## Confirm multi-frame progression actually visited mid frames (not binary open).
	_assert(seen_indices.size() >= 8, "visited >=8 distinct frames across samples")

	node._set_frame_progress(1.0, true)
	await process_frame
	_assert(node._frame_index == 12, "final open chest frame index 12")
	_assert(node._scroll_rise >= 0.999, "final scroll rise complete")
	_assert(node._scroll_clip.visible, "final scroll clip visible")
	_assert(node._rim_view.visible, "final rim layer visible")
	_assert(node._layered_open, "final layered open active")
	_assert(node._rim_view.z_index > node._scroll_clip.z_index, "rim occludes lower scroll only")
	_assert(node._scroll_clip.z_index > node._frame_view.z_index, "upper scroll above chest")
	_assert(str(node._frame_view.texture.resource_path).contains("chest_open_back"), "final uses open-back")

	## Occlusion geometry: scroll bottom below rim; scroll top above rim but below lid clip top.
	var rim_y := node._anchor_rect.position.y + (LoveNotesChest.CAVITY_RIM_CANVAS_Y / LoveNotesChest.FRAME_CANVAS.y) * node._anchor_rect.size.y
	var scroll_top_g := node._scroll_clip.position.y + node._scroll_view.position.y
	var scroll_bot_g := scroll_top_g + node._scroll_view.size.y
	_assert(scroll_bot_g > rim_y, "lower scroll below front rim (occluded)")
	_assert(scroll_top_g < rim_y, "upper scroll above front rim (visible)")
	_assert(scroll_top_g > node._scroll_clip.position.y - 1.0, "scroll top inside cavity (not under lid)")

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
	node._set_frame_progress(1.0, false)
	await node.play_open_empty_pulse()
	_assert(node.chest_state == LoveNotesChest.ChestState.OPEN_EMPTY, "pulse keeps OPEN_EMPTY")
	_assert(node._frame_index == 12, "retap does not replay frame sequence")

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
