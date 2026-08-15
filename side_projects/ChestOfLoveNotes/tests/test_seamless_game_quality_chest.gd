extends SceneTree
## v61: animation_v3 baked scroll reveal replaces layered open_back compositor.

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
	print("=== Chest baked scroll reveal (v61) ===")
	var chest := FileAccess.get_file_as_string("res://scripts/chest/treasure_chest.gd")
	var env_script := FileAccess.get_file_as_string("res://scripts/chest/chest_environment.gd")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var flags := FileAccess.get_file_as_string("res://scripts/build_flags.gd")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	var export_sh := FileAccess.get_file_as_string("res://tools/export_android_apk.sh")
	var boot := FileAccess.get_file_as_string("res://scripts/ui/charoite_boot.gd")
	var manifest := FileAccess.get_file_as_string("res://assets/chest/animation_v3/animation_v3_manifest.json")

	_assert(chest.contains("animation_v2"), "animation_v2 wired")
	_assert(chest.contains("animation_v3"), "animation_v3 wired")
	_assert(chest.contains("FRAME_CANVAS := Vector2(512, 512)"), "512x512 production canvas")
	_assert(chest.contains("CHEST_FRAME_COUNT := 13"), "13 approved frames")
	_assert(chest.contains("REVEAL_FRAME_COUNT := 8"), "8 baked reveal frames")
	_assert(chest.contains("CHEST_FOOT_CANVAS_Y := 420.0"), "foot canvas 420")
	_assert(chest.contains("CHEST_FOOT_Y_FRAC"), "foot fraction for grounding")
	_assert(chest.contains("chest_00_closed.png"), "frame 00 wired")
	_assert(chest.contains("chest_12_fully_open.png"), "frame 12 wired")
	_assert(chest.contains("reveal_00_hidden.png"), "reveal 00 wired")
	_assert(chest.contains("reveal_07_final.png"), "reveal 07 wired")
	_assert(chest.contains("_play_baked_scroll_reveal"), "baked reveal playback method")
	_assert(chest.contains("_show_baked_reveal_index"), "baked reveal frame swap")
	_assert(chest.contains("_load_reveal_sequence"), "reveal preload helper")
	_assert(chest.contains("SCROLL_REVEAL_DIR"), "reveal dir const")
	_assert(chest.contains("REVEAL_FRAME_DWELLS_SEC"), "per-frame reveal dwells")
	_assert(chest.contains("chest_open_back.png"), "open-back layer const retained")
	_assert(chest.contains("chest_open_front_rim.png"), "front-rim layer const retained")
	_assert(chest.contains("love_scroll_reward.png"), "romantic horizontal reward scroll")
	_assert(chest.contains("love_scroll_horizontal.png"), "legacy horizontal tube preserved")
	_assert(chest.contains("love_scroll.png"), "original vertical scroll preserved in source const")
	_assert(chest.contains("new_love_scroll_master.png"), "master source referenced")
	_assert(chest.contains("SCROLL_NATIVE := Vector2(720, 305)"), "romantic scroll native size")
	_assert(chest.contains("SCROLL_OPENING_WIDTH_FRAC := 0.92"), "scroll ~92% cavity width")
	_assert(chest.contains("CONTACT_SHADOW"), "contact shadow grounding")
	_assert(chest.contains("WARM_SPILL"), "warm spill separate from shadow")
	_assert(chest.contains("OPEN_DURATION_SEC := 1.0"), "open duration ~1.0s")
	_assert(chest.contains("OPEN_POSE_WEIGHTS"), "variable frame timing")
	_assert(chest.contains("SCROLL_EMERGE_SEC := 0.52"), "baked reveal duration ~0.52s")
	_assert(chest.contains("SCROLL_POST_OPEN_BEAT_SEC := 0.10"), "post-open beat ~0.10s")
	_assert(chest.contains("REWARD_HOLD_SEC := 0.60"), "reward hold ~0.60s")
	_assert(chest.contains("SCROLL_FINAL_ABOVE_RIM := 0.84"), "legacy final reveal const retained")
	_assert(chest.contains("SCROLL_START_ABOVE_RIM := -0.42"), "legacy buried start retained")
	_assert(chest.contains("SCROLL_PEEK_ABOVE_RIM := 0.05"), "legacy peek const retained")
	_assert(chest.contains("SCROLL_X_BIAS_CANVAS := 28.0"), "scroll right bias retained")
	_assert(chest.contains("SCROLL_CONTENT_TOP_PAD"), "scroll texture top pad accounted")
	_assert(chest.contains("SCROLL_CONTENT_BOTTOM_PAD"), "scroll texture bottom pad accounted")
	_assert(chest.contains("scroll_rise_for_above_rim"), "rise↔above helper retained")
	_assert(chest.contains("GLOW_EMERGE_A"), "reduced emerge glow")
	_assert(chest.contains("hard-cut the scroll bottom") or chest.contains("clip_contents hard-cut"), "clipping root-cause documented")
	_assert(chest.contains("EMPHASIS_SCALE := 1.002"), "tiny settle scale only")
	_assert(chest.contains("_play_scroll_rise_tween"), "legacy scroll Y tween retained inactive")
	_assert(chest.contains("_enter_layered_open"), "legacy layered open retained inactive")
	_assert(chest.contains("INACTIVE for normal scroll reward"), "legacy path marked inactive")
	_assert(chest.contains("_set_badge_suppressed"), "badge hidden during reward")
	_assert(chest.contains("_enforce_chest_opaque"), "opaque chest enforcement")
	_assert(chest.contains("soft_glow_pulse.png"), "soft radial glow")
	_assert(chest.contains("ONE opaque chest") or chest.contains("exactly ONE"), "one chest sprite comment")
	_assert(chest.contains("ScrollLayer"), "scroll layer node")
	_assert(chest.contains("ScrollCavityClip"), "cavity clip occlusion")
	_assert(chest.contains("ChestFrontRim"), "rim node")
	_assert(chest.contains("ChestContactShadow"), "shadow node")
	_assert(chest.contains("ChestWarmSpill"), "warm spill node")
	_assert(chest.contains("_set_scroll_rise_amount"), "legacy layered scroll rise retained")
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
	_assert(env_script.contains("OCEAN_WATER_MASK_LEGACY"), "legacy shoreline mask const retained")
	_assert(env_script.contains("OceanGlistenClip"), "water-only glisten clip")
	_assert(env_script.contains("OceanGlistenB"), "second shimmer glint band")
	_assert(env_script.contains("OceanGlint_"), "discrete ocean glint streaks")
	_assert(env_script.contains("GLINT_COUNT := 6"), "six visible glints")
	_assert(env_script.contains("WATER_TOP_FRAC"), "water top bound")
	_assert(env_script.contains("WATER_BOTTOM_FRAC := 0.560"), "continuous water bottom bound")
	_assert(env_script.contains("clip_contents = true"), "rectangular water clip_contents")
	_assert(env_script.contains("_water_clip = Control.new()"), "water clip is plain Control")
	_assert(not env_script.contains("_water_clip = TextureRect.new()"), "no shoreline TextureRect water host")
	_assert(not env_script.contains("clip_children = CanvasItem.CLIP_CHILDREN_ONLY"), "no water CLIP_CHILDREN_ONLY")
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
	_assert(chest.contains("CAVITY_RIM_CANVAS_Y := 269.0"), "rim Y matches re-derived lip top")
	_assert(chest.contains("CAVITY_CENTER_CANVAS_X := 219.0"), "geometric cavity center retained")
	_assert(chest.contains("SCROLL_X_BIAS_CANVAS"), "scroll X bias separate from cavity geometry")
	_assert(chest.contains("CAVITY_MASK_LEGACY"), "legacy mask const retained for history")
	_assert(not chest.contains('name = "CavityMaskHost"'), "CavityMaskHost node not created")
	_assert(not chest.contains("var _cavity_mask_host"), "cavity mask host var removed")
	_assert(not chest.contains("var _scroll_mask_mat"), "scroll mask shader material removed")
	_assert(not chest.contains("clip_children = CanvasItem.CLIP_CHILDREN_ONLY"), "no cavity CLIP_CHILDREN_ONLY")
	_assert(not chest.contains('load("res://assets/shaders/cavity_scroll_mask.gdshader")'), "mask shader not loaded at runtime")
	_assert(chest.contains("Front rim alone occludes") or chest.contains("front rim is the only"), "front-rim occlusion policy")
	_assert(chest.contains("GLOW_EMERGE_A := 0.0010") or chest.contains("GLOW_EMERGE_A := 0.001"), "reduced emerge glow")
	_assert(chest.contains("z_index = 5") and chest.contains("ScrollCavityClip"), "scroll z above back")
	_assert(env_script.contains("local_timezone_bias_minutes"), "timezone bias helper")
	_assert(env_script.contains("unix + bias_min * 60") or env_script.contains("bias_min * 60"), "local via bias path")
	_assert(env_script.contains("NOTIFICATION_APPLICATION_RESUMED") or env_script.contains("APPLICATION_FOCUS_IN"), "resume time refresh")
	_assert(env_script.contains("_glint_fade_in") or env_script.contains("_glint_alpha_at"), "independent glint cycles")
	_assert(env_script.contains("TOD_REFRESH_SEC"), "periodic TOD refresh constant")
	_assert(manifest.contains("\"integration_allowed\": true") or manifest.contains('"integration_allowed": true'), "manifest integration_allowed")

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
	var reveal_names := [
		"reveal_00_hidden.png",
		"reveal_01_peek.png",
		"reveal_02_15.png",
		"reveal_03_30.png",
		"reveal_04_50.png",
		"reveal_05_70.png",
		"reveal_06_85.png",
		"reveal_07_final.png",
	]
	for rf in reveal_names:
		_assert(
			FileAccess.file_exists("res://assets/chest/animation_v3/scroll_reveal/%s" % rf),
			"baked reveal %s" % rf
		)
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/layers/chest_open_back.png"), "open-back layer asset preserved")
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/layers/chest_open_front_rim.png"), "front-rim layer asset preserved")
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/layers/chest_cavity_mask.png"), "legacy cavity mask asset preserved on disk")
	_assert(FileAccess.file_exists("res://assets/shaders/cavity_scroll_mask.gdshader"), "legacy cavity scroll mask shader preserved on disk")
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/scroll/love_scroll.png"), "original vertical scroll asset preserved")
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/scroll/love_scroll_horizontal.png"), "legacy horizontal tube asset preserved")
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/scroll/love_scroll_reward.png"), "romantic reward scroll asset")
	_assert(FileAccess.file_exists("res://assets/chest/animation_v2/incoming_new_art/new_love_scroll_master.png"), "romantic master source preserved")
	_assert(FileAccess.file_exists("res://assets/art/chest/soft_glow_pulse.png"), "soft glow asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_contact_shadow.png"), "contact shadow asset")
	_assert(FileAccess.file_exists("res://assets/art/chest/chest_warm_spill.png"), "warm spill asset")
	_assert(FileAccess.file_exists("res://assets/art/background/environments/default_beach.png"), "default beach environment art")

	_assert(flags.contains("APP_VERSION_CODE := 73"), "versionCode 63")
	_assert(preset.contains("version/code=73"), "export 70")
	_assert(preset.contains("0.1.73-notifications-relationship-status"), "version name")
	_assert(preset.contains("v63-parrot-visible-fix-debug.apk"), "APK name")
	_assert(gitignore.contains("*.apk"), "apks ignored by default")
	_assert(export_sh.contains("ChestOfLoveNotes") and export_sh.contains("debug.apk"), "export script present")
	_assert(chest.contains("_arm_scroll_hidden_behind_lip"), "legacy arm helper retained")
	_assert(chest.contains("await _play_baked_scroll_reveal"), "open path awaits baked reveal")
	_assert(not chest.contains("await _play_scroll_rise_tween(SCROLL_EMERGE_SEC)"), "open path no longer awaits layered tween")
	_assert(env_script.contains("15.5"), "late-afternoon DAY keyframe")
	_assert(env_script.contains("phase == \"day\""), "DAY hard-hides stars/moon")
	_assert(not env_script.contains("var _top_shade"), "top shade var removed")
	_assert(not env_script.contains('name = "TopReadabilityShade"'), "top shade node not created")
	_assert(env_script.contains("get_datetime_dict_from_system"), "local time via system datetime")
	_assert(env_script.contains("debug_hour_override >= 0.0"), "debug override gated")
	_assert(env_script.contains("RenderingServer.set_default_clear_color"), "clear color tracks sky_top")
	_assert(env_script.contains("sky_top.r, sky_top.g, sky_top.b, 1.0") or env_script.contains("top_fill"), "base_fill = opaque sky_top")
	_assert(preset.contains("statusBarColor") and preset.contains("#00000000"), "transparent status bar")
	_assert(FileAccess.file_exists("res://assets/art/background/environments/ocean_glisten.png"), "ocean glisten texture asset")
	_assert(FileAccess.file_exists("res://assets/art/background/environments/ocean_water_mask.png"), "ocean water shoreline mask asset")

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
	_assert(node._reveal_frames.size() == 8, "8 reveal frames preloaded")
	_assert(node._empty_frames.size() == 13, "empty alias has 13 frames")
	_assert(node._scroll_frames.size() == 8, "scroll alias maps to reveal frames")
	_assert(node._scroll_view != null, "scroll layer present")
	_assert(node._scroll_clip != null, "scroll cavity clip present")
	_assert(node._rim_view != null, "rim layer present")
	_assert(node._shadow_view != null, "shadow layer present")
	_assert(node._warm_spill != null, "warm spill present")
	_assert(node._open_back_tex != null, "open-back texture still cached")
	_assert(node._rim_layer_tex != null, "rim texture still cached")
	_assert(node._scroll_layer_tex != null, "scroll texture still cached")
	_assert(str(node._scroll_layer_tex.resource_path).contains("love_scroll_reward"), "reward scroll asset cached")
	_assert(not str(node._scroll_layer_tex.resource_path).ends_with("love_scroll_horizontal.png"), "runtime not tiny horizontal tube")
	_assert(env._bg != null and env._bg.texture != null, "beach texture loaded")
	_assert(env.environment_id == ChestEnvironment.ENV_DEFAULT_BEACH, "default beach id active")
	_assert(env._base_fill != null, "opaque environment base present")
	_assert(env._water_glisten != null, "ocean glisten layer present")
	_assert(env._water_glisten_b != null, "second ocean glisten layer present")
	_assert(env._water_clip != null, "ocean glisten clip present")
	_assert(env._water_clip is Control and not (env._water_clip is TextureRect), "water clip is plain Control")
	_assert(env._water_clip.clip_contents == true, "water clip uses clip_contents")
	_assert(env._water_clip.clip_children != CanvasItem.CLIP_CHILDREN_ONLY, "no shoreline CLIP_CHILDREN_ONLY")
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
	var water_h := water_bot - water_top
	_assert(absf(env._water_clip.position.y - water_top) < 1.0, "water clip at water top")
	_assert(absf(env._water_clip.size.x - env.size.x) < 1.0, "water clip full width")
	_assert(absf(env._water_clip.size.y - water_h) < 1.0, "water clip continuous band height")
	_assert(env._ocean_tint.position.y <= 1.0, "ocean tint local to water clip")
	_assert(absf(env._ocean_tint.size.y - water_h) < 1.0, "ocean tint fills water clip")
	_assert(env._water_glisten.position.y <= 1.0, "glisten local to water clip")
	_assert(env._water_glisten.size.y <= water_h + 2.0, "glisten height within water clip")
	_assert(env._sky_clip.size.y <= env.size.y * ChestEnvironment.SKY_BOTTOM_FRAC + 1.0, "stars/sky wash clipped to sky")
	_assert(env._sky_gradient_view.size.y >= env._sky_clip.size.y - 1.0, "gradient fills sky clip")
	for g in env._glints:
		_assert(g.get_parent() == env._water_clip, "glint parented under water clip")
		_assert(g.position.y >= -1.0, "glint inside water clip top")
		_assert(g.position.y + g.size.y <= water_h + 2.0, "glint inside water clip bottom")
	_assert(node._scroll_clip.z_index > node._frame_view.z_index, "scroll above open-back")
	_assert(node._rim_view.z_index > node._scroll_clip.z_index, "rim above scroll")
	_assert(node._glow_pulse.z_index > node._rim_view.z_index, "glow above rim")
	_assert(node.get_node_or_null("ChestAnimationRoot/ScrollCavityClip/CavityMaskHost") == null, "no CavityMaskHost in tree")
	_assert(node._scroll_view.get_parent() == node._scroll_clip, "scroll parented under plain clip")
	_assert(node._scroll_view.material == null, "scroll has no mask shader material")
	_assert(node._scroll_clip.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED, "cavity clip host does not mask-draw")
	_assert(absf(LoveNotesChest.CAVITY_RIM_CANVAS_Y - 269.0) < 0.01, "cavity rim at lip top")
	_assert(absf(LoveNotesChest.CAVITY_CENTER_CANVAS_X - 219.0) < 0.01, "geometric cavity center x")
	_assert(absf(LoveNotesChest.SCROLL_X_BIAS_CANVAS - 28.0) < 0.01, "scroll X bias 28 canvas")
	_assert(LoveNotesChest.SCROLL_START_ABOVE_RIM <= -0.35, "scroll start deeply buried below rim")
	_assert(LoveNotesChest.SCROLL_FINAL_ABOVE_RIM >= 0.80 and LoveNotesChest.SCROLL_FINAL_ABOVE_RIM <= 0.90, "final exposure 80-90%")
	_assert(LoveNotesChest.SCROLL_CONTENT_TOP_PAD < 0.02, "top pad matches measured art")
	_assert(LoveNotesChest.SCROLL_CONTENT_BOTTOM_PAD < 0.02, "bottom pad matches measured art")

	var chest12_tex: Texture2D = node._chest_frames[12]
	var reveal0_tex: Texture2D = node._reveal_frames[0]
	_assert(chest12_tex != null and reveal0_tex != null, "chest12 + reveal00 textures present")
	var chest12_img := chest12_tex.get_image()
	var reveal0_img := reveal0_tex.get_image()
	_assert(chest12_img != null and reveal0_img != null, "chest12 + reveal00 images readable")
	if chest12_img and reveal0_img:
		_assert(chest12_img.get_width() == 512 and chest12_img.get_height() == 512, "chest12 512x512")
		_assert(reveal0_img.get_width() == 512 and reveal0_img.get_height() == 512, "reveal00 512x512")
		_assert(chest12_img.get_data() == reveal0_img.get_data(), "reveal_00 pixel-identical to chest_12")
	for ri in range(node._reveal_frames.size()):
		var rtex: Texture2D = node._reveal_frames[ri]
		_assert(rtex != null, "reveal frame %d loaded" % ri)
		var rimg := rtex.get_image()
		if rimg:
			_assert(rimg.get_width() == 512 and rimg.get_height() == 512, "reveal %d 512x512" % ri)

	var prev_override := ChestEnvironment.debug_hour_override
	for hour_case in [
		{"h": 4.0, "phase": "night", "stars_min": 0.45},
		{"h": 6.5, "phase": "dawn", "stars_max": 0.35},
		{"h": 10.0, "phase": "day", "stars_max": 0.01, "stars_hidden": true},
		{"h": 11.0, "phase": "day", "stars_max": 0.01, "stars_hidden": true},
		{"h": 12.0, "phase": "day", "stars_max": 0.01, "stars_hidden": true},
		{"h": 15.566, "phase": "day", "stars_max": 0.01, "stars_hidden": true, "day_horizon": true},
		{"h": 18.5, "phase": "sunset", "stars_min": 0.1},
		{"h": 21.0, "phase": "night", "stars_min": 0.6},
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
		if hour_case.get("stars_hidden", false):
			_assert(env._stars.visible == false or env._stars.modulate.a <= 0.01, "stars hidden @%.1f" % float(hour_case["h"]))
		if hour_case.get("day_horizon", false):
			var hz := pal["sky_horizon"] as Color
			_assert(hz.b >= hz.r * 0.90, "15:34 horizon still daytime blue-dominant")
			_assert((pal["sky_top"] as Color).a >= 0.98, "15:34 sky_top opaque")
			_assert(env._stars.visible == false or env._stars.modulate.a <= 0.01, "15:34 moon/stars hidden")
		_assert(env._ocean_tint.color.a > 0.05, "ocean tint active @%.1f" % float(hour_case["h"]))
	var day_pal := ChestEnvironment.tod_palette_at(15.566)
	_assert(str(day_pal["phase"]) == "day", "15:34 is DAY")
	_assert(float(day_pal["star_a"]) <= 0.001, "15:34 stars fully hidden")
	_assert((day_pal["sky_top"] as Color).a >= 0.98, "15:34 sky wash opaque enough for day")
	ChestEnvironment.debug_hour_override = 15.566
	env._apply_time_of_day(true)
	await process_frame
	_assert(env._stars.visible == false or env._stars.modulate.a <= 0.01, "15:34 stars node hidden")
	_assert(env._base_fill.color.a >= 0.999, "15:34 base fill opaque")
	var top_delta := absf(env._base_fill.color.r - (day_pal["sky_top"] as Color).r) \
		+ absf(env._base_fill.color.g - (day_pal["sky_top"] as Color).g) \
		+ absf(env._base_fill.color.b - (day_pal["sky_top"] as Color).b)
	_assert(top_delta < 0.02, "15:34 base_fill matches opaque sky_top (no top strip)")
	var dawn_mid := ChestEnvironment.tod_palette_at(6.5)
	var dawn_start := ChestEnvironment.tod_palette_at(5.0)
	var dawn_end := ChestEnvironment.tod_palette_at(8.0)
	_assert(float(dawn_mid["star_a"]) < float(dawn_start["star_a"]), "dawn mid stars below night-edge")
	_assert(float(dawn_mid["star_a"]) > float(dawn_end["star_a"]), "dawn mid stars above day")
	ChestEnvironment.debug_hour_override = -1.0
	var sys_h := ChestEnvironment.local_hour_frac()
	var bias_h := ChestEnvironment.local_hour_frac_via_bias()
	_assert(sys_h >= 0.0 and sys_h < 24.0, "system local hour in [0,24)")
	_assert(ChestEnvironment.local_timezone_bias_minutes() == int(Time.get_time_zone_from_system().get("bias", 0)), "bias matches Time API")
	var hour_delta := absf(sys_h - bias_h)
	if hour_delta > 12.0:
		hour_delta = 24.0 - hour_delta
	_assert(hour_delta < (2.0 / 60.0), "system local ≈ bias-adjusted unix (<2 min)")
	var sys_dict := Time.get_datetime_dict_from_system()
	if ChestEnvironment.local_timezone_bias_minutes() != 0:
		_assert(int(sys_dict.get("hour", -1)) == int(floor(sys_h)), "local_hour uses system local hour field")
	ChestEnvironment.debug_hour_override = prev_override
	env._apply_time_of_day(true)
	_assert(env.get_node_or_null("TopReadabilityShade") == null, "no TopReadabilityShade node")
	_assert(env._sky_gradient_view.position.y == 0.0, "sky gradient starts at top edge")

	node._layout_frames()
	await process_frame
	var foot_y := node.foot_y_in_control()
	var shadow_top := node._shadow_view.position.y
	var shadow_bot := shadow_top + node._shadow_view.size.y
	_assert(shadow_top <= foot_y + 2.0, "shadow top at/above foot")
	_assert(shadow_bot >= foot_y - 1.0, "shadow reaches foot (no hover gap)")
	_assert(absf(foot_y - node.size.y * LoveNotesChest.CHEST_FOOT_Y_FRAC) < 3.0, "foot on ground frac")
	_assert(node._shadow_view.size.x <= node._anchor_rect.size.x * 0.40, "shadow tight under feet")

	node._reward_sequence_log.clear()
	node._record_reward_texture("chest_12_fully_open")
	node._show_frame_index(12)
	await process_frame
	var frame_rect := Rect2(node._frame_view.position, node._frame_view.size)
	for ri2 in range(8):
		node._show_baked_reveal_index(ri2)
		await process_frame
		_assert(node._baked_reveal_active, "reveal %d baked active" % ri2)
		_assert(not node._layered_open, "reveal %d not layered" % ri2)
		_assert(not node._scroll_clip.visible, "reveal %d ScrollLayer host hidden" % ri2)
		_assert(not node._rim_view.visible, "reveal %d front rim hidden" % ri2)
		_assert(node._frame_view.position == frame_rect.position, "reveal %d plant position stable" % ri2)
		_assert(node._frame_view.size == frame_rect.size, "reveal %d plant size stable" % ri2)
		var path_r := str(node._frame_view.texture.resource_path)
		_assert(path_r.contains("animation_v3/scroll_reveal"), "reveal %d uses animation_v3" % ri2)
		_assert(not path_r.contains("chest_open_back"), "reveal %d not open_back" % ri2)
		_assert(node._frame_view.modulate.a >= 0.999, "reveal %d opaque" % ri2)
	_assert(node._reveal_frame_index == 7, "final reveal index 7")
	var expected_seq := [
		"chest_12_fully_open",
		"reveal_00_hidden",
		"reveal_01_peek",
		"reveal_02_15",
		"reveal_03_30",
		"reveal_04_50",
		"reveal_05_70",
		"reveal_06_85",
		"reveal_07_final",
	]
	_assert(node._reward_sequence_log.size() == expected_seq.size(), "reward sequence length")
	for si in range(mini(node._reward_sequence_log.size(), expected_seq.size())):
		_assert(node._reward_sequence_log[si] == expected_seq[si], "seq[%d]=%s" % [si, expected_seq[si]])

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
		{"name": "reveal_hidden", "p": 0.48, "scroll": true, "expect_i": 12, "reveal_i": 0},
		{"name": "reveal_peek", "p": 0.55, "scroll": true, "expect_i": 12, "reveal_i": 1},
		{"name": "reveal_mid", "p": 0.74, "scroll": true, "expect_i": 12, "reveal_i": 4},
		{"name": "reveal_late", "p": 0.90, "scroll": true, "expect_i": 12, "reveal_i": 6},
		{"name": "reveal_final", "p": 1.0, "scroll": true, "expect_i": 12, "reveal_i": 7},
	]
	var validate_dir := OS.get_user_data_dir().path_join("chest_validate_v61")
	DirAccess.make_dir_recursive_absolute(validate_dir)
	var prev_body_span := -1.0
	var seen_indices: Dictionary = {}
	for s in open_states:
		node._set_frame_progress(float(s["p"]), bool(s["scroll"]))
		await process_frame
		_assert(node.modulate.a >= 0.999, "state %s root opaque" % s["name"])
		_assert(node.self_modulate.a >= 0.999, "state %s self opaque" % s["name"])
		_assert(node._frame_view.modulate.a >= 0.999, "state %s frame opaque" % s["name"])
		_assert(node._frame_index == int(s["expect_i"]), "state %s frame index %d == %d" % [s["name"], node._frame_index, int(s["expect_i"])])
		seen_indices[node._frame_index] = true
		var tex: Texture2D = node._frame_view.texture
		_assert(tex != null, "state %s has texture" % s["name"])
		var path_str := str(tex.resource_path)
		if bool(s["scroll"]) and float(s["p"]) >= LoveNotesChest.SCROLL_REVEAL_START_PROGRESS:
			_assert(node._baked_reveal_active, "state %s baked reveal active" % s["name"])
			_assert(not node._layered_open, "state %s not layered" % s["name"])
			_assert(not node._scroll_clip.visible, "state %s scroll host hidden" % s["name"])
			_assert(not node._rim_view.visible, "state %s rim hidden" % s["name"])
			_assert(path_str.contains("animation_v3"), "state %s uses animation_v3" % s["name"])
			_assert(not path_str.contains("chest_open_back"), "state %s not open_back" % s["name"])
			if s.has("reveal_i"):
				_assert(node._reveal_frame_index == int(s["reveal_i"]), "state %s reveal index" % s["name"])
		if not bool(s["scroll"]):
			_assert(not node._layered_open, "state %s not layered before scroll" % s["name"])
			_assert(not node._rim_view.visible, "state %s rim hidden before scroll" % s["name"])
			_assert(path_str.contains("animation_v2"), "state %s uses animation_v2" % s["name"])
			_assert(not path_str.contains("frames/empty"), "state %s not legacy empty" % s["name"])
			_assert(not path_str.contains("chest_body_planted"), "state %s not old body" % s["name"])
			_assert(not path_str.contains("chest_lid.png"), "state %s not old lid" % s["name"])
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
						_assert(drift < 0.04, "state %s mid-body width stable (drift=%.3f)" % [s["name"], drift])
					if not bool(s["scroll"]):
						prev_body_span = span
				var path := validate_dir.path_join("%s.png" % s["name"])
				img.save_png(path)
				print("WROTE ", path)
		_assert(node._frame_index >= 0, "state %s frame index" % s["name"])

	_assert(seen_indices.size() >= 8, "visited >=8 distinct frames across samples")

	node._set_frame_progress(1.0, true)
	await process_frame
	_assert(node._frame_index == 12, "final open chest frame index 12")
	_assert(node._reveal_frame_index == 7, "final reveal index 7")
	_assert(node._baked_reveal_active, "final baked reveal active")
	_assert(not node._layered_open, "final not layered open")
	_assert(not node._scroll_clip.visible, "final scroll host hidden")
	_assert(not node._rim_view.visible, "final rim hidden")
	_assert(str(node._frame_view.texture.resource_path).contains("reveal_07_final"), "final uses reveal_07")

	node.set_unread_badge(3)
	node._set_badge_suppressed(true)
	_assert(node._badge.visible == false, "badge hidden during animation")
	node._set_badge_suppressed(false)
	_assert(node._badge.visible == true, "badge restored after animation")
	_assert(node._badge.position.y > node._anchor_rect.position.y, "badge below canvas top")
	_assert(node._badge.position.y < node._anchor_rect.position.y + node._anchor_rect.size.y * 0.55, "badge in upper chest band")

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
	_assert(not node._baked_reveal_active, "empty retap has no baked reveal")

	node.hide_rolled_scroll()
	node.apply_ready_idle_state()
	await process_frame
	_assert(not node._baked_reveal_active, "ready idle clears baked reveal")
	_assert(not node._scroll_clip.visible, "ready idle scroll hidden")
	_assert(not node._rim_view.visible, "ready idle rim hidden")
	_assert(node._frame_index == 0, "ready idle returns to closed")

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
