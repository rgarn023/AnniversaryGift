extends Control
class_name LoveNotesChest
## animation_v2 approved 13-frame chest opening + animation_v3 baked scroll reveal
## (v61). Empty + unread share the same smooth multi-frame open (#00→#12).
## No chest crossfade / alpha fade / ghost duplicate — exactly ONE visible chest
## (or baked chest+scroll) frame at any instant.
## v61 NORMAL SCROLL REWARD: after chest_12, play discrete baked reveal_00…07
## frames (animation_v3). The open_back + ScrollLayer + front_rim runtime
## compositor is NO LONGER used for the normal unread reward path.
## Legacy layered helpers remain on disk / in-code for history / empty tooling
## but must stay inactive during baked reveal.
## Empty chest: approved open only → glow → "No new scrolls today."
## Chest plant/frames/size remain frozen.

signal tapped
signal open_finished
signal skip_requested
signal scroll_emerged(global_pos: Vector2)
## Future audio hooks (no assets required this pass).
signal sfx_open_start
signal sfx_latch_release
signal sfx_fully_open
signal sfx_magical_swell
signal sfx_scroll_emerge

## Explicit state machine — prevent overlapping opens / duplicate scrolls.
enum ChestState {
	LOCKED_SILHOUETTE,
	AVAILABLE, ## CLOSED
	OPENING,
	OPEN_EMPTY,
	OPEN_WAITING_FOR_SCROLL,
	OPEN_SCROLL_EMERGING,
	OPENED, ## compat alias for empty-open
	READY,
	CLOSING,
	TRANSITIONING,
}

## Approved production package — never fall back to legacy frames/sheets.
const ANIM_V2 := "res://assets/chest/animation_v2/"
const ANIM_V3 := "res://assets/chest/animation_v3/"
const CHEST_FRAMES_DIR := ANIM_V2 + "chest_frames/"
const SCROLL_REVEAL_DIR := ANIM_V3 + "scroll_reveal/"
## Legacy layered assets — retained on disk / preloaded for history, but NOT
## drawn during the normal animation_v3 baked scroll reward path.
const OPEN_BACK := ANIM_V2 + "layers/chest_open_back.png"
const FRONT_RIM := ANIM_V2 + "layers/chest_open_front_rim.png"
## Legacy cavity mask asset kept on disk for tooling history only — NOT loaded
## at runtime (v57). Drawing that gray TextureRect caused the visible cavity
## rectangle on device even with CLIP_CHILDREN_ONLY.
const CAVITY_MASK_LEGACY := ANIM_V2 + "layers/chest_cavity_mask.png"
## Horizontal romantic reward scroll — source for baked reveal composites only
## in the normal reward path (standalone ScrollLayer stays hidden).
const SCROLL_LAYER := ANIM_V2 + "scroll/love_scroll_reward.png"
## Prior tiny horizontal tube (132×56) — kept for reference, not used at runtime.
const SCROLL_LAYER_LEGACY_HORIZONTAL := ANIM_V2 + "scroll/love_scroll_horizontal.png"
## Original vertical tube source preserved (not used at runtime in v51+).
const SCROLL_LAYER_VERTICAL_SOURCE := ANIM_V2 + "scroll/love_scroll.png"
## Incoming romantic master used to package SCROLL_LAYER (not loaded at runtime).
const SCROLL_LAYER_MASTER_SOURCE := ANIM_V2 + "incoming_new_art/new_love_scroll_master.png"
const SOFT_GLOW := "res://assets/art/chest/soft_glow_pulse.png"
const CONTACT_SHADOW := "res://assets/art/chest/chest_contact_shadow.png"
const WARM_SPILL := "res://assets/art/chest/chest_warm_spill.png"
## animation_v2 / v3 production canvas (base anchor 256,420).
const FRAME_CANVAS := Vector2(512, 512)
## Absolute plant row in authored frames (matches animation_manifest base_anchor.y).
const CHEST_FOOT_CANVAS_Y := 420.0
## Foot as fraction of FRAME_CANVAS height — scene grounding uses this.
const CHEST_FOOT_Y_FRAC := CHEST_FOOT_CANVAS_Y / 512.0
## Full approved opening sequence #00–#12.
const CHEST_FRAME_COUNT := 13
## Baked scroll-reveal frames (animation_v3) — exact order, no skips / reverse.
const REVEAL_FRAME_COUNT := 8
## Compat aliases (tests / older callers).
const EMPTY_FRAME_COUNT := CHEST_FRAME_COUNT
const SCROLL_FRAME_COUNT := REVEAL_FRAME_COUNT
## Smooth premium open — restrained start, accelerate mid, ease into fully open.
const OPEN_DURATION_SEC := 1.0
const OPEN_DURATION_RM := 0.42
const ANTICIPATION_SEC := 0.06
const SETTLE_SEC := 0.10
const MAGICAL_SWELL_SEC := 0.10
## Brief intentional beat after chest_12 before baked reveal begins (0.08–0.12).
const SCROLL_POST_OPEN_BEAT_SEC := 0.10
## Legacy layered emerge duration — retained for documentation / inactive path.
## Production normal reward uses REVEAL_FRAME_DWELLS_SEC instead.
const SCROLL_EMERGE_SEC := 0.52
## Per-frame dwell for reveal_00…reveal_06 before advancing (seconds).
## reveal_07 uses REWARD_HOLD_SEC as the final settle hold.
## Sum of dwells ≈ 0.52s (within the 0.50–0.60 target).
const REVEAL_FRAME_DWELLS_SEC := [
	0.06, ## reveal_00_hidden
	0.07, ## reveal_01_peek
	0.07, ## reveal_02_15
	0.08, ## reveal_03_30
	0.08, ## reveal_04_50
	0.08, ## reveal_05_70
	0.08, ## reveal_06_85
]
## Intentional hold on reveal_07_final before note handoff (0.55–0.65).
const REWARD_HOLD_SEC := 0.60
## Tiny settle pulse only — must not read as the chest growing while opening.
const EMPHASIS_SCALE := 1.002
## Progress split when sampling combined unread progress (validation path).
## After this progress, samples map onto baked reveal frames (not layered open).
const SCROLL_REVEAL_START_PROGRESS := 0.48
## Compat index marker (legacy).
const SCROLL_REVEAL_START_INDEX := 0
## Native romantic horizontal scroll art size (love_scroll_reward.png = 720×305).
const SCROLL_NATIVE := Vector2(720, 305)
## Measured transparent pad in love_scroll_reward.png (opaque rows ≈1..303).
## Legacy layered rise math only — inactive during baked reveal.
const SCROLL_CONTENT_TOP_PAD := 0.004
const SCROLL_CONTENT_BOTTOM_PAD := 0.007
## Legacy layered scroll width fraction — inactive during baked reveal.
const SCROLL_OPENING_WIDTH_FRAC := 0.92
## Canvas-space cavity / rim geometry — top of front lip (y≈269). Matches
## animation_v3 lip burial lock used when baking reveal frames.
const CAVITY_RIM_CANVAS_Y := 269.0
## Geometric center of the 3/4-view cavity opening (not the canvas midpoint).
const CAVITY_CENTER_CANVAS_X := 219.0
## Legacy layered scroll X bias — inactive during baked reveal.
const SCROLL_X_BIAS_CANVAS := 28.0
const CAVITY_INNER_LEFT_X := 137.0
const CAVITY_INNER_RIGHT_X := 301.0
## Legacy layered final/start rise params — inactive during baked reveal.
const SCROLL_FINAL_ABOVE_RIM := 0.84
const SCROLL_START_ABOVE_RIM := -0.42
const SCROLL_PEEK_ABOVE_RIM := 0.05
## Soft glow peaks — restrained warm accent; never washes out parchment/wood.
## Glow/particles may sit ABOVE the baked reveal texture only.
const GLOW_OPEN_A := 0.012
const GLOW_SETTLE_A := 0.016
const GLOW_RETAP_A := 0.028
const GLOW_REWARD_HOLD_A := 0.0030
const GLOW_MID_A := 0.013
const GLOW_EMERGE_A := 0.0010
## Per-frame dwell weights — restrained start, smooth mid accel, soft finish.
## Sum-normalized against OPEN_DURATION_SEC; no pauses between frames.
const OPEN_POSE_WEIGHTS := [
	1.20, ## 00 closed
	0.95, ## 01 8%
	0.90, ## 02 17%
	0.85, ## 03 25%
	0.82, ## 04 33%
	0.80, ## 05 42%
	0.80, ## 06 50%
	0.85, ## 07 58%
	0.90, ## 08 67%
	0.95, ## 09 75%
	1.00, ## 10 83%
	1.10, ## 11 92%
	1.20, ## 12 fully open
]
## Exact approved filenames in order.
## Smooth playback sequence (v79). Contains all 13 approved poses BYTE-IDENTICAL
## at every third slot, plus 2 motion-compensated in-betweens per gap, so the
## open runs at 37 fps instead of 13 fps without re-authoring the approved art.
## CHEST_FRAME_COUNT below still describes the approved pose count — that set is
## unchanged and is what the frozen-art guards assert.
const CHEST_SMOOTH_FRAMES_DIR := ANIM_V2 + "chest_frames_smooth/"
const CHEST_SMOOTH_FRAME_COUNT := 37
const CHEST_SMOOTH_FRAME_FILES := [
	"s00_00_closed.png",
	"s01_tween.png",
	"s02_tween.png",
	"s03_01_open_08.png",
	"s04_tween.png",
	"s05_tween.png",
	"s06_02_open_17.png",
	"s07_tween.png",
	"s08_tween.png",
	"s09_03_open_25.png",
	"s10_tween.png",
	"s11_tween.png",
	"s12_04_open_33.png",
	"s13_tween.png",
	"s14_tween.png",
	"s15_05_open_42.png",
	"s16_tween.png",
	"s17_tween.png",
	"s18_06_open_50.png",
	"s19_tween.png",
	"s20_tween.png",
	"s21_07_open_58.png",
	"s22_tween.png",
	"s23_tween.png",
	"s24_08_open_67.png",
	"s25_tween.png",
	"s26_tween.png",
	"s27_09_open_75.png",
	"s28_tween.png",
	"s29_tween.png",
	"s30_10_open_83.png",
	"s31_tween.png",
	"s32_tween.png",
	"s33_11_open_92.png",
	"s34_tween.png",
	"s35_tween.png",
	"s36_12_fully_open.png",
]

const CHEST_FRAME_FILES := [
	"chest_00_closed.png",
	"chest_01_open_08.png",
	"chest_02_open_17.png",
	"chest_03_open_25.png",
	"chest_04_open_33.png",
	"chest_05_open_42.png",
	"chest_06_open_50.png",
	"chest_07_open_58.png",
	"chest_08_open_67.png",
	"chest_09_open_75.png",
	"chest_10_open_83.png",
	"chest_11_open_92.png",
	"chest_12_fully_open.png",
]
## Exact approved animation_v3 baked scroll-reveal filenames in order.
const REVEAL_FRAME_FILES := [
	"reveal_00_hidden.png",
	"reveal_01_peek.png",
	"reveal_02_15.png",
	"reveal_03_30.png",
	"reveal_04_50.png",
	"reveal_05_70.png",
	"reveal_06_85.png",
	"reveal_07_final.png",
]

@export var reduced_motion: bool = false

var chest_state: ChestState = ChestState.AVAILABLE
var animating: bool = false
var _idle_time: float = 0.0
var _skip: bool = false
var _input_locked: bool = false
var _label: Label
var _root_visual: Control
var _shadow_view: TextureRect
var _warm_spill: TextureRect
var _frame_view: TextureRect
var _scroll_clip: Control
var _scroll_view: TextureRect
var _rim_view: TextureRect
var _glow_pulse: TextureRect
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _motes: CPUParticles2D
var _button: Button
var _ready_visuals: bool = false
var _badge: Label
var _unread_count: int = 0
var _badge_suppressed: bool = false
var _open_amount: float = 0.0
var _scroll_rise: float = 0.0
var _show_scroll_on_finish: bool = false
var _layered_open: bool = false
## True while ChestFrame is showing an animation_v3 baked reveal texture.
var _baked_reveal_active: bool = false
var _anchor_rect: Rect2 = Rect2()
var _anticipation_y: float = 0.0
var _emphasis_scale: float = 1.0
var _particles_armed: bool = false
var _chest_frames: Array[Texture2D] = []
var _empty_frames: Array[Texture2D] = [] ## alias of _chest_frames
var _scroll_frames: Array[Texture2D] = [] ## alias of _reveal_frames (compat)
var _reveal_frames: Array[Texture2D] = []
var _active_frames: Array[Texture2D] = []
var _frame_index: int = 0
var _reveal_frame_index: int = -1
var _scroll_emerged_emitted: bool = false
var _scroll_layer_tex: Texture2D = null
var _rim_layer_tex: Texture2D = null
var _open_back_tex: Texture2D = null
var _shadow_tex: Texture2D = null
var _fit_scale: float = 1.0
## Programmatic reward texture-order log for tests (chest_12 → reveal_00…07).
var _reward_sequence_log: Array[String] = []

## Process-wide preload so the first tap never decompresses textures.
static var _tex_cache: Dictionary = {}
static var _chest_cache: Array = []
static var _empty_cache: Array = [] ## alias
static var _scroll_cache: Array = []
static var _reveal_cache: Array = []
static var _preloaded: bool = false
static var _sprite_frames_empty: SpriteFrames = null
static var _sprite_frames_scroll: SpriteFrames = null
static var _open_weight_ends: PackedFloat32Array = PackedFloat32Array()
static var _using_smooth_frames: bool = false


static func preload_assets() -> void:
	if _preloaded:
		return
	_chest_cache = _load_chest_sequence()
	_empty_cache = _chest_cache
	_reveal_cache = _load_reveal_sequence()
	_scroll_cache = _reveal_cache
	_load_cached(SOFT_GLOW)
	_load_cached(SCROLL_LAYER)
	_load_cached(SCROLL_LAYER_LEGACY_HORIZONTAL)
	_load_cached(SCROLL_LAYER_VERTICAL_SOURCE)
	_load_cached(FRONT_RIM)
	_load_cached(OPEN_BACK)
	_load_cached(CONTACT_SHADOW)
	_load_cached(WARM_SPILL)
	_open_weight_ends = _build_open_weight_ends()
	## fps == frame count keeps the sequence exactly 1.0 s whichever set loaded
	## (13 frames @ 13 fps, 37 @ 37 fps) — playback gets finer, not slower.
	_sprite_frames_empty = _build_sprite_frames(
		"empty_open", _chest_cache, maxf(1.0, float(_chest_cache.size()))
	)
	_sprite_frames_scroll = _build_sprite_frames("baked_reveal", _reveal_cache, 16.0)
	_preloaded = true


static func _load_chest_sequence() -> Array:
	## Play the smooth sequence; fall back to the approved 13 if it is absent.
	var out: Array = []
	for fname in CHEST_SMOOTH_FRAME_FILES:
		var tex: Texture2D = _load_cached(CHEST_SMOOTH_FRAMES_DIR + String(fname))
		if tex == null:
			out.clear()
			break
		out.append(tex)
	if not out.is_empty():
		_using_smooth_frames = true
		return out
	_using_smooth_frames = false
	for fname in CHEST_FRAME_FILES:
		out.append(_load_cached(CHEST_FRAMES_DIR + String(fname)))
	return out


static func _load_reveal_sequence() -> Array:
	var out: Array = []
	for fname in REVEAL_FRAME_FILES:
		out.append(_load_cached(SCROLL_REVEAL_DIR + String(fname)))
	return out


static func _playback_pose_weights() -> Array:
	## One weight per PLAYBACK slot. The smooth sequence renders each approved
	## pose as 3 slots (pose + 2 in-betweens), so each pose's approved display
	## weight is split evenly across its slots. Total is unchanged, so the
	## approved timing envelope — slow start, fast middle, eased finish — is
	## preserved exactly; only the sampling gets finer.
	if not _using_smooth_frames:
		return OPEN_POSE_WEIGHTS
	var sub := 3
	var out: Array = []
	for i in range(OPEN_POSE_WEIGHTS.size()):
		if i == OPEN_POSE_WEIGHTS.size() - 1:
			out.append(float(OPEN_POSE_WEIGHTS[i]))   ## final pose has no tweens after it
		else:
			var part := float(OPEN_POSE_WEIGHTS[i]) / float(sub)
			for _j in range(sub):
				out.append(part)
	return out


static func _build_open_weight_ends() -> PackedFloat32Array:
	var weights := _playback_pose_weights()
	var ends := PackedFloat32Array()
	ends.resize(weights.size())
	var total := 0.0
	for w in weights:
		total += float(w)
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i]) / total
		ends[i] = acc
	if ends.size() > 0:
		ends[ends.size() - 1] = 1.0
	return ends


static func _build_sprite_frames(anim_name: String, textures: Array, fps: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, false)
	for tex in textures:
		if tex != null:
			sf.add_frame(anim_name, tex as Texture2D)
	return sf


static func _load_cached(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(220, 260)
	## Physical chest never fades — only glow/particles/shadow may be translucent.
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	visible = true
	preload_assets()
	_chest_frames.clear()
	_empty_frames.clear()
	_scroll_frames.clear()
	_reveal_frames.clear()
	for t in _chest_cache:
		_chest_frames.append(t as Texture2D)
	_empty_frames = _chest_frames
	for t in _reveal_cache:
		_reveal_frames.append(t as Texture2D)
	_scroll_frames = _reveal_frames
	_scroll_layer_tex = _load_cached(SCROLL_LAYER)
	_rim_layer_tex = _load_cached(FRONT_RIM)
	_open_back_tex = _load_cached(OPEN_BACK)
	_shadow_tex = _load_cached(CONTACT_SHADOW)
	_build_visuals()
	_ready_visuals = true
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = "Open your chest"
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	set_process(not reduced_motion)
	resized.connect(_layout_frames)
	_layout_frames()
	_set_frame_progress(0.0, false)
	_enforce_chest_opaque()


func _build_visuals() -> void:
	_root_visual = Control.new()
	_root_visual.name = "ChestAnimationRoot"
	_root_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_visual.clip_contents = false
	add_child(_root_visual)

	## Soft contact shadow under the planted foot — grounds the chest on sand.
	_shadow_view = TextureRect.new()
	_shadow_view.name = "ChestContactShadow"
	_shadow_view.texture = _shadow_tex
	_shadow_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow_view.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shadow_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Tight / restrained — neutral dark contact kissing the feet (no bright halo).
	_shadow_view.modulate = Color(0.12, 0.10, 0.09, 0.90)
	_shadow_view.z_index = 1
	_root_visual.add_child(_shadow_view)

	## Tiny warm magical spill on sand — separate from the dark contact shadow.
	_warm_spill = TextureRect.new()
	_warm_spill.name = "ChestWarmSpill"
	_warm_spill.texture = _load_cached(WARM_SPILL)
	_warm_spill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_warm_spill.stretch_mode = TextureRect.STRETCH_SCALE
	_warm_spill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_warm_spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warm_spill.modulate = Color(1, 1, 1, 0.0)
	_warm_spill.z_index = 2
	_root_visual.add_child(_warm_spill)

	## Exactly ONE opaque chest sprite — no duplicate underlay / crossfade layers.
	## Normal scroll reward swaps this through animation_v3 baked reveal frames
	## (chest+scroll already composited). Legacy open-back swap is inactive.
	_frame_view = TextureRect.new()
	_frame_view.name = "ChestFrame"
	_frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## No mipmaps at draw time — keep wood/gold edges crisp while opening.
	_frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_view.modulate = Color(1, 1, 1, 1)
	_frame_view.self_modulate = Color(1, 1, 1, 1)
	_frame_view.z_index = 3
	_root_visual.add_child(_frame_view)

	## Order: chest sprite → (legacy scroll/rim inactive for reward) → glow → particles.
	## ScrollCavityClip / ScrollLayer / ChestFrontRim remain in the tree for
	## history and empty/legacy helpers, but stay HIDDEN during baked reveal.
	## Front rim alone occludes only in the inactive layered compositor path.
	## clip_contents hard-cut the scroll bottom was a historical root-cause —
	## baked frames eliminate that path for normal rewards.
	_scroll_clip = Control.new()
	_scroll_clip.name = "ScrollCavityClip"
	_scroll_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_clip.clip_contents = false
	_scroll_clip.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	_scroll_clip.modulate = Color(1, 1, 1, 1)
	_scroll_clip.self_modulate = Color(1, 1, 1, 1)
	_scroll_clip.z_index = 5
	_scroll_clip.visible = false
	_root_visual.add_child(_scroll_clip)

	## Legacy standalone ScrollLayer — NOT drawn during animation_v3 baked reveal.
	## Orientation is baked into love_scroll_reward.png (no runtime rotation).
	_scroll_view = TextureRect.new()
	_scroll_view.name = "ScrollLayer"
	_scroll_view.texture = _scroll_layer_tex
	_scroll_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scroll_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_scroll_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_scroll_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Preserve authored parchment / ribbon / heart colors — no pale wash tint.
	_scroll_view.modulate = Color(1, 1, 1, 1)
	_scroll_view.material = null
	_scroll_view.rotation = 0.0
	_scroll_view.visible = true
	_scroll_clip.add_child(_scroll_view)

	## Legacy front-rim occlusion — NOT drawn during animation_v3 baked reveal.
	_rim_view = TextureRect.new()
	_rim_view.name = "ChestFrontRim"
	_rim_view.texture = _rim_layer_tex
	_rim_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rim_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rim_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rim_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim_view.modulate = Color(1, 1, 1, 1)
	_rim_view.z_index = 6
	_rim_view.visible = false
	_root_visual.add_child(_rim_view)

	## Soft radial pulse — restrained; sits ABOVE the baked reveal texture only.
	## Smaller/softer so it never washouts parchment contrast.
	_glow_pulse = TextureRect.new()
	_glow_pulse.name = "GlowPulse"
	_glow_pulse.texture = _load_cached(SOFT_GLOW)
	_glow_pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow_pulse.stretch_mode = TextureRect.STRETCH_SCALE
	_glow_pulse.modulate = Color(1.0, 0.82, 0.48, 0.0)
	_glow_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_pulse.z_index = 7
	_root_visual.add_child(_glow_pulse)

	_dust = _make_particles(Color(0.90, 0.78, 0.48, 0.28), 3, Vector2(0, -1), 12.0, 0.65)
	_dust.z_index = 8
	_root_visual.add_child(_dust)
	_sparks = _make_particles(Color(1.0, 0.84, 0.48, 0.34), 2, Vector2(0, -1), 18.0, 0.50)
	_sparks.z_index = 8
	_root_visual.add_child(_sparks)
	_motes = _make_particles(Color(1.0, 0.86, 0.55, 0.24), 4, Vector2(0, -1), 9.0, 1.0)
	_motes.one_shot = false
	_motes.explosiveness = 0.0
	_motes.z_index = 8
	_root_visual.add_child(_motes)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 15)
	_badge.add_theme_color_override("font_color", Color(0.12, 0.06, 0.1))
	_badge.visible = false
	_badge.z_index = 20
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_label.add_theme_font_size_override("font_size", 17)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 12
	add_child(_label)

	_active_frames = _chest_frames
	_show_frame_index(0)


func _make_particles(
	color: Color,
	amount: int,
	dir: Vector2,
	speed: float,
	lifetime: float = 0.55
) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.15
	p.local_coords = true
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = speed * 0.10
	p.initial_velocity_max = speed * 0.42
	p.gravity = Vector2(0, 14)
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.52
	p.color = color
	return p


func foot_y_in_control() -> float:
	## Visible base / plant Y inside this control after layout.
	if _anchor_rect.size.y <= 1.0:
		return size.y * CHEST_FOOT_Y_FRAC
	return _anchor_rect.position.y + _anchor_rect.size.y * CHEST_FOOT_Y_FRAC


func _layout_frames() -> void:
	if not _ready_visuals:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(220, 260)
	_root_visual.pivot_offset = area * 0.5
	## Fit the production canvas; keep headroom so scroll tops are not clipped.
	var fit: float = minf(area.x / FRAME_CANVAS.x, area.y / FRAME_CANVAS.y)
	_fit_scale = fit
	var draw_w: float = FRAME_CANVAS.x * fit
	var draw_h: float = FRAME_CANVAS.y * fit
	## Plant the authored foot on a fixed ground line inside this control.
	## CHEST_FOOT_Y_FRAC is the sand contact within the chest host; scene code
	## aligns that host line to ChestEnvironment.sand_contact_y_frac().
	var left: float = (area.x - draw_w) * 0.5
	var foot_y: float = area.y * CHEST_FOOT_Y_FRAC
	var top: float = foot_y - draw_h * CHEST_FOOT_Y_FRAC
	_anchor_rect = Rect2(left, top, draw_w, draw_h)
	_place_rect(_frame_view, _anchor_rect)
	_place_scroll_and_rim()
	## Contact shadow: tight under the foot, kissing the base (no hover gap).
	if _shadow_view:
		var sh_w := draw_w * 0.26
		var sh_h := draw_h * 0.011
		## Top of shadow overlaps the foot row — grounded weight on sand.
		var sh_y := foot_y - sh_h * 1.15
		_place_rect(_shadow_view, Rect2(
			_anchor_rect.position.x + (draw_w - sh_w) * 0.5,
			sh_y,
			sh_w,
			sh_h
		))
	## Warm spill sits slightly below/around the foot — never replaces the shadow.
	## Keep alpha low so it cannot read as a bright floating halo under the base.
	if _warm_spill:
		var sp_w := draw_w * 0.24
		var sp_h := draw_h * 0.014
		var sp_y := foot_y - sp_h * 0.01
		_place_rect(_warm_spill, Rect2(
			_anchor_rect.position.x + (draw_w - sp_w) * 0.5,
			sp_y,
			sp_w,
			sp_h
		))
	## Soft radial pulse in the cavity — restrained accent ABOVE the chest sprite.
	## Smaller/softer so it never blowouts parchment contrast on baked reveal.
	_place_rect(_glow_pulse, Rect2(
		_anchor_rect.position.x + draw_w * 0.38,
		_anchor_rect.position.y + draw_h * 0.48,
		draw_w * 0.24,
		draw_h * 0.09
	))
	var cavity_center := Vector2(area.x * 0.5, _anchor_rect.position.y + draw_h * 0.48)
	_dust.position = cavity_center
	_sparks.position = cavity_center
	_motes.position = cavity_center
	_apply_root_transform()
	if _badge:
		## Near the closed chest — slightly above/right, not on lid, not horizon.
		_badge.position = Vector2(
			_anchor_rect.position.x + draw_w * 0.76,
			_anchor_rect.position.y + draw_h * 0.30
		)
		_badge.size = Vector2(40, 40)


func _place_scroll_and_rim() -> void:
	if _anchor_rect.size == Vector2.ZERO:
		return
	var draw_w := _anchor_rect.size.x
	var draw_h := _anchor_rect.size.y
	## Preserve native texture aspect — size by opening width, never stretch.
	var native := SCROLL_NATIVE
	if _scroll_layer_tex != null:
		var tex_size := _scroll_layer_tex.get_size()
		if tex_size.x > 1.0 and tex_size.y > 1.0:
			native = tex_size
	## Fit scroll to the real cavity width (3/4 opening), not a canvas-centered guess.
	var cavity_w_frac := (CAVITY_INNER_RIGHT_X - CAVITY_INNER_LEFT_X) / FRAME_CANVAS.x
	var opening_w := draw_w * cavity_w_frac
	var sw := opening_w * SCROLL_OPENING_WIDTH_FRAC
	var aspect := native.x / maxf(native.y, 1.0)
	var sh := sw / maxf(aspect, 0.01)
	var rim_y := _anchor_rect.position.y + (CAVITY_RIM_CANVAS_Y / FRAME_CANVAS.y) * draw_h
	## Y-only rise from fully buried → final ~88% content exposed.
	## rise=0 → START (hidden); early rise ≈ PEEK (~5%); rise=1 → FINAL.
	## Same X for hidden / first-visible / tween / final — vertical rise only.
	## CONTENT height excludes transparent pad so first art pixels clear the lip.
	var above := lerpf(SCROLL_START_ABOVE_RIM, SCROLL_FINAL_ABOVE_RIM, _scroll_rise)
	var content_frac := 1.0 - SCROLL_CONTENT_TOP_PAD - SCROLL_CONTENT_BOTTOM_PAD
	var content_h := sh * content_frac
	var content_top := rim_y - content_h * above
	var scroll_top := content_top - sh * SCROLL_CONTENT_TOP_PAD
	## Cavity center + right bias — applied on the whole path, not final-only.
	var cavity_cx := _anchor_rect.position.x + (
		(CAVITY_CENTER_CANVAS_X + SCROLL_X_BIAS_CANVAS) / FRAME_CANVAS.x
	) * draw_w
	var scroll_left := cavity_cx - sw * 0.5
	## ScrollCavityClip is a non-drawing host (no StyleBox / ColorRect / texture).
	## Prior rectangular clip_contents hard-cut the scroll bottom during emerge;
	## prior CavityMaskHost drew gray cavity pixels — both remain removed.
	## Front rim alone occludes the lower scroll (no hard cut, no mask fill).
	if _scroll_clip:
		_place_rect(_scroll_clip, _anchor_rect)
	if _scroll_view and _scroll_clip:
		var local_x := scroll_left - _anchor_rect.position.x
		var local_y := scroll_top - _anchor_rect.position.y
		_place_rect(_scroll_view, Rect2(local_x, local_y, sw, sh))
		_scroll_view.rotation = 0.0
		_scroll_view.scale = Vector2.ONE
		_scroll_view.modulate = Color(1, 1, 1, 1)
		_scroll_view.material = null
	if _rim_view:
		## Draw order: open-back → scroll → front rim → glow → UI.
		_place_rect(_rim_view, _anchor_rect)


func _place_rect(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.position = rect.position
	node.size = rect.size


func _apply_root_transform() -> void:
	if _root_visual == null:
		return
	var z := _emphasis_scale
	_root_visual.scale = Vector2(z, z)
	_root_visual.rotation = 0.0
	_root_visual.position = Vector2(
		(1.0 - z) * size.x * 0.5,
		_anticipation_y + (1.0 - z) * size.y * 0.5
	)


func set_unread_badge(count: int) -> void:
	_unread_count = count
	_refresh_badge_visibility()


func _refresh_badge_visibility() -> void:
	if _badge == null:
		return
	if _badge_suppressed or _unread_count <= 0:
		_badge.visible = false
		if _unread_count <= 0:
			_badge.text = ""
		return
	_badge.visible = true
	_badge.text = str(mini(_unread_count, 99))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.98, 0.78, 0.42, 1.0)
	bg.set_corner_radius_all(20)
	_badge.add_theme_stylebox_override("normal", bg)


func _set_badge_suppressed(suppressed: bool) -> void:
	_badge_suppressed = suppressed
	_refresh_badge_visibility()


func _enforce_chest_opaque() -> void:
	## Never fade the physical chest sprite / root — glow may still use alpha.
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	if _root_visual:
		_root_visual.modulate = Color(1, 1, 1, 1)
		_root_visual.self_modulate = Color(1, 1, 1, 1)
	if _frame_view:
		## Preserve idle RGB shimmer channel but keep alpha locked at 1.
		var c := _frame_view.modulate
		_frame_view.modulate = Color(c.r, c.g, c.b, 1.0)
		_frame_view.self_modulate = Color(1, 1, 1, 1)
	if _scroll_view:
		## Keep authored ribbon/heart colors; lock alpha (never translucent wash).
		_scroll_view.modulate = Color(1, 1, 1, 1)
		_scroll_view.self_modulate = Color(1, 1, 1, 1)
	if _rim_view:
		_rim_view.modulate = Color(1, 1, 1, 1)
		_rim_view.self_modulate = Color(1, 1, 1, 1)


func configure(state: ChestState, show_final_label: bool = false) -> void:
	chest_state = state
	animating = false
	_skip = false
	_input_locked = false
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_scroll_emerged_emitted = false
	_set_badge_suppressed(false)
	_stop_motes()
	_reset_pose()
	match state:
		ChestState.LOCKED_SILHOUETTE:
			## Dim RGB only — never reduce alpha (chest must stay opaque).
			self_modulate = Color(0.55, 0.55, 0.75, 1.0)
			_label.visible = false
			_set_frame_progress(0.0, false)
			set_process(false)
		ChestState.AVAILABLE, ChestState.READY:
			self_modulate = Color.WHITE
			_label.visible = show_final_label
			_label.text = "Your Chest"
			_set_frame_progress(0.0, false)
			set_process(not reduced_motion)
		ChestState.OPENED, ChestState.OPEN_EMPTY:
			self_modulate = Color.WHITE
			_set_frame_progress(1.0, false)
			_label.visible = false
			set_process(false)
		_:
			set_process(false)
	_enforce_chest_opaque()


func _ease_open_curve(t: float) -> float:
	## Slightly restrained start → smooth mid acceleration → soft ease-out.
	t = clampf(t, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var early := t * t * t
	return lerpf(early, s, 0.58)


func _select_sequence(_emerge_scroll: bool) -> void:
	## Runtime always displays animation_v2 chest frames on the chest sprite
	## during the open. Normal scroll reward then swaps to animation_v3 baked
	## reveal frames via _play_baked_scroll_reveal / _show_baked_reveal_index.
	_active_frames = _chest_frames


func _show_frame_index(index: int) -> void:
	if _active_frames.is_empty():
		return
	_frame_index = clampi(index, 0, _active_frames.size() - 1)
	var tex: Texture2D = _active_frames[_frame_index]
	if _frame_view and tex and not _layered_open and not _baked_reveal_active:
		_frame_view.texture = tex
		## One opaque chest sprite only — never a second chest overlay.
		_enforce_chest_opaque()


func _ensure_legacy_layers_hidden() -> void:
	## Normal baked reward path: never draw standalone scroll / rim / cavity.
	_layered_open = false
	_set_scroll_layers_visible(false)
	if _scroll_view:
		_scroll_view.visible = false
	if _scroll_clip:
		_scroll_clip.visible = false
	if _rim_view:
		_rim_view.visible = false


func _show_baked_reveal_index(index: int) -> void:
	## Discrete opaque swap onto ONE baked reveal frame — no crossfade / morph.
	if _reveal_frames.is_empty():
		return
	_ensure_legacy_layers_hidden()
	_baked_reveal_active = true
	_reveal_frame_index = clampi(index, 0, _reveal_frames.size() - 1)
	_frame_index = _chest_frames.size() - 1
	_scroll_rise = float(_reveal_frame_index) / float(maxi(_reveal_frames.size() - 1, 1))
	var tex: Texture2D = _reveal_frames[_reveal_frame_index]
	if _frame_view and tex:
		_frame_view.texture = tex
		_frame_view.modulate = Color(1, 1, 1, 1)
	_enforce_chest_opaque()
	_record_reward_texture(String(REVEAL_FRAME_FILES[_reveal_frame_index]).get_basename())


func _record_reward_texture(label: String) -> void:
	if _reward_sequence_log.is_empty() or _reward_sequence_log[_reward_sequence_log.size() - 1] != label:
		_reward_sequence_log.append(label)


func _clear_baked_reveal() -> void:
	_baked_reveal_active = false
	_reveal_frame_index = -1


func _enter_layered_open() -> void:
	## LEGACY / INACTIVE for normal scroll reward (v61+).
	## Kept for history and optional tooling; production uses baked reveal.
	_baked_reveal_active = false
	_layered_open = true
	if _frame_view and _open_back_tex:
		_frame_view.texture = _open_back_tex
		_frame_view.modulate = Color(1, 1, 1, 1)
	_set_scroll_layers_visible(true)
	_enforce_chest_opaque()


func _exit_layered_open() -> void:
	_layered_open = false
	_set_scroll_layers_visible(false)
	if _baked_reveal_active:
		return
	if _active_frames.size() > 0 and _frame_view:
		_frame_view.texture = _active_frames[clampi(_frame_index, 0, _active_frames.size() - 1)]
		_frame_view.modulate = Color(1, 1, 1, 1)
	_enforce_chest_opaque()


func _arm_scroll_hidden_behind_lip() -> void:
	## LEGACY / INACTIVE for normal scroll reward (v61+).
	## Production path calls _play_baked_scroll_reveal instead.
	_enter_layered_open()
	_scroll_rise = 0.0
	_place_scroll_and_rim()
	if _scroll_clip:
		_scroll_clip.visible = true
	if _scroll_view:
		_scroll_view.visible = true
		_scroll_view.modulate = Color(1, 1, 1, 1)
	if _rim_view:
		_rim_view.visible = true
	if _frame_view:
		_frame_view.modulate = Color(1, 1, 1, 1)
	_enforce_chest_opaque()


func _weighted_frame_index(eased: float) -> int:
	## Map eased progress onto all 13 approved frames via pose-weight ends.
	## No blending — discrete opaque frame swaps only.
	var max_i := _active_frames.size() - 1
	if max_i <= 0:
		return 0
	eased = clampf(eased, 0.0, 1.0)
	if eased >= 0.999:
		return max_i
	var ends := _open_weight_ends
	if ends.is_empty():
		ends = _build_open_weight_ends()
	for i in range(mini(ends.size(), max_i + 1)):
		if eased <= ends[i] + 1e-6:
			return i
	return max_i


func _frame_index_from_progress(amount: float, emerge_scroll: bool) -> int:
	## Chest pose only during open. Combined unread samples hold on #12 while
	## the reveal index is driven separately onto baked frames.
	var max_i := _active_frames.size() - 1
	if max_i <= 0:
		return 0
	if emerge_scroll:
		if amount < SCROLL_REVEAL_START_PROGRESS:
			var t_open := amount / SCROLL_REVEAL_START_PROGRESS
			return _weighted_frame_index(t_open)
		return max_i
	return _weighted_frame_index(amount)


func _reveal_index_from_progress(amount: float) -> int:
	## Map combined unread progress remainder onto reveal_00…07.
	var t := 0.0
	if amount >= SCROLL_REVEAL_START_PROGRESS:
		t = (amount - SCROLL_REVEAL_START_PROGRESS) / (1.0 - SCROLL_REVEAL_START_PROGRESS)
	t = clampf(t, 0.0, 1.0)
	var max_i := maxi(_reveal_frames.size() - 1, 0)
	if max_i <= 0:
		return 0
	if t >= 0.999:
		return max_i
	return clampi(int(floor(t * float(max_i + 1))), 0, max_i)


func _set_scroll_layers_visible(vis: bool) -> void:
	if _scroll_clip:
		_scroll_clip.visible = vis
	if _rim_view:
		_rim_view.visible = vis


static func scroll_rise_for_above_rim(above: float) -> float:
	## Legacy helper for inactive layered path / older validation tools.
	var span := SCROLL_FINAL_ABOVE_RIM - SCROLL_START_ABOVE_RIM
	if absf(span) < 0.0001:
		return 0.0
	return clampf((above - SCROLL_START_ABOVE_RIM) / span, 0.0, 1.0)


static func scroll_above_rim_at_rise(rise: float) -> float:
	return lerpf(SCROLL_START_ABOVE_RIM, SCROLL_FINAL_ABOVE_RIM, clampf(rise, 0.0, 1.0))


func _set_scroll_rise_amount(amount: float) -> void:
	## LEGACY layered rise — inactive for normal baked reward playback.
	_scroll_rise = clampf(amount, 0.0, 1.0)
	if not _layered_open:
		_enter_layered_open()
	_place_scroll_and_rim()
	_set_scroll_layers_visible(true)
	if _scroll_view:
		_scroll_view.visible = true
		_scroll_view.modulate = Color(1, 1, 1, 1)
	var above_now := scroll_above_rim_at_rise(_scroll_rise)
	if above_now > 0.01 and not _scroll_emerged_emitted:
		_scroll_emerged_emitted = true
		chest_state = ChestState.OPEN_SCROLL_EMERGING
		sfx_scroll_emerge.emit()
		scroll_emerged.emit(get_scroll_global_center())


func _set_frame_progress(raw_amount: float, emerge_scroll: bool) -> void:
	var linear := clampf(raw_amount, 0.0, 1.0)
	_open_amount = linear
	_select_sequence(emerge_scroll)
	if _active_frames.is_empty():
		return
	## Soft visual ease for glow only — frame index uses weighted linear progress.
	var glow_ease := _ease_open_curve(linear)
	var idx := _frame_index_from_progress(linear, emerge_scroll)

	if emerge_scroll and linear >= SCROLL_REVEAL_START_PROGRESS:
		## Combined unread validation path: baked reveal frames, never open_back.
		_frame_index = _active_frames.size() - 1
		if _layered_open:
			_exit_layered_open()
		_show_baked_reveal_index(_reveal_index_from_progress(linear))
	else:
		if _layered_open:
			_exit_layered_open()
		if _baked_reveal_active:
			_clear_baked_reveal()
		_show_frame_index(idx)
		_ensure_legacy_layers_hidden()
		_scroll_rise = 0.0
		_place_scroll_and_rim()

	## Progressive warm glow while the lid opens / reveal plays.
	if _glow_pulse and not _layered_open:
		if _baked_reveal_active:
			_glow_pulse.modulate.a = GLOW_EMERGE_A
		else:
			_glow_pulse.modulate.a = lerpf(0.0, GLOW_MID_A, glow_ease)
	if _warm_spill and not _layered_open and not _baked_reveal_active:
		## Keep spill softer than the contact shadow so feet stay grounded.
		_warm_spill.modulate.a = lerpf(0.0, 0.06, glow_ease)

	## Particles arm near mid-open — restrained, secondary to the chest.
	if not reduced_motion and linear >= 0.45 and not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()


func _apply_open_amount(raw_amount: float) -> void:
	## Compat path used by close tween — empty sequence, no scroll.
	_set_frame_progress(raw_amount, _show_scroll_on_finish)


func _reset_pose() -> void:
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_frame_index = 0
	_scroll_rise = 0.0
	_layered_open = false
	_clear_baked_reveal()
	_reward_sequence_log.clear()
	if _root_visual:
		_root_visual.scale = Vector2.ONE
		_root_visual.position = Vector2.ZERO
		_root_visual.rotation = 0.0
		_root_visual.modulate = Color.WHITE
	if _glow_pulse:
		_glow_pulse.modulate.a = 0.0
	if _warm_spill:
		_warm_spill.modulate.a = 0.0
	_ensure_legacy_layers_hidden()
	_layout_frames()
	_select_sequence(false)
	_show_frame_index(0)


func _process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
		return
	if animating or reduced_motion or not _ready_visuals:
		return
	if chest_state != ChestState.AVAILABLE and chest_state != ChestState.READY:
		return
	_idle_time += delta
	## Subtle idle shimmer via modulate — no lid squash.
	if _frame_view:
		var shimmer := 0.02 * sin(_idle_time * 1.35)
		_frame_view.modulate = Color(1.0 + shimmer, 1.0 + shimmer * 0.6, 1.0, 1.0)


func set_active_processing(enabled: bool) -> void:
	set_process(enabled)


func _on_pressed() -> void:
	if _input_locked or animating:
		_skip = true
		skip_requested.emit()
		return
	if chest_state == ChestState.OPENING \
			or chest_state == ChestState.OPEN_WAITING_FOR_SCROLL \
			or chest_state == ChestState.OPEN_SCROLL_EMERGING \
			or chest_state == ChestState.TRANSITIONING \
			or chest_state == ChestState.CLOSING:
		return
	tapped.emit()


func play_press_feedback() -> void:
	## Tiny planted response — not a button bounce / squash.
	HapticHelper.light_tap()
	if reduced_motion:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_anticipation_y = v
		_apply_root_transform()
	, 0.0, 2.5, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float) -> void:
		_anticipation_y = v
		_apply_root_transform()
	, 2.5, 0.0, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func play_empty_feedback() -> void:
	await play_open_empty_pulse()


func play_open_empty_pulse() -> void:
	## Retap on open empty: glow/motes only — stay open, no reopen / no 13-frame replay.
	if animating:
		return
	if chest_state != ChestState.OPENED and chest_state != ChestState.OPEN_EMPTY:
		if _open_amount < 0.95:
			return
	animating = true
	_input_locked = true
	HapticHelper.light_tap()
	## Hold last approved open frame — never arm layered scroll on empty retap.
	_select_sequence(false)
	_clear_baked_reveal()
	_ensure_legacy_layers_hidden()
	_show_frame_index(_chest_frames.size() - 1)
	var pulse := create_tween()
	if _glow_pulse:
		pulse.tween_property(_glow_pulse, "modulate:a", GLOW_RETAP_A, 0.14).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_glow_pulse, "modulate:a", GLOW_SETTLE_A * 0.5, 0.30).set_trans(Tween.TRANS_SINE)
	if _frame_view:
		var shimmer := create_tween()
		## Brightness shimmer only — alpha stays 1.0 (no translucent chest).
		shimmer.tween_property(_frame_view, "modulate", Color(1.06, 1.03, 0.96, 1.0), 0.12)
		shimmer.tween_property(_frame_view, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.26)
	if not reduced_motion:
		_emit_burst()
	if pulse.is_valid():
		await pulse.finished
	else:
		await get_tree().create_timer(0.28).timeout
	animating = false
	_input_locked = false


func play_open_animation(short: bool = false, emerge_scroll: bool = false) -> void:
	if animating \
			or chest_state == ChestState.OPENING \
			or chest_state == ChestState.OPEN_WAITING_FOR_SCROLL \
			or chest_state == ChestState.OPEN_SCROLL_EMERGING \
			or chest_state == ChestState.TRANSITIONING \
			or chest_state == ChestState.CLOSING:
		return
	if (chest_state == ChestState.OPENED or chest_state == ChestState.OPEN_EMPTY) and not emerge_scroll:
		await play_open_empty_pulse()
		return
	animating = true
	_input_locked = true
	_skip = false
	_particles_armed = false
	_scroll_emerged_emitted = false
	_reward_sequence_log.clear()
	_clear_baked_reveal()
	_ensure_legacy_layers_hidden()
	_set_badge_suppressed(true)
	set_process(false)
	_show_scroll_on_finish = emerge_scroll
	_select_sequence(emerge_scroll)
	chest_state = ChestState.OPENING
	sfx_open_start.emit()
	play_press_feedback()
	if reduced_motion or short:
		await _open_short()
	else:
		await _open_full()
	_apply_finished_state()
	if emerge_scroll:
		chest_state = ChestState.TRANSITIONING
	else:
		chest_state = ChestState.OPEN_EMPTY
		_set_badge_suppressed(false)
	animating = false
	_input_locked = false
	sfx_fully_open.emit()
	open_finished.emit()


func play_close_animation() -> void:
	if animating or chest_state == ChestState.OPENING or chest_state == ChestState.OPEN_SCROLL_EMERGING:
		return
	animating = true
	_input_locked = true
	chest_state = ChestState.CLOSING
	_stop_motes()
	hide_rolled_scroll()
	_show_scroll_on_finish = false
	var dur := 0.28 if reduced_motion else 0.55
	var tw := create_tween()
	tw.tween_method(_apply_open_amount, _open_amount, 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_set_frame_progress(0.0, false)
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	_set_badge_suppressed(false)
	chest_state = ChestState.READY
	animating = false
	_input_locked = false


func play_final_reopen_animation() -> void:
	await play_open_animation(true, false)


func set_interaction_enabled(enabled: bool) -> void:
	_input_locked = not enabled
	if _button != null and is_instance_valid(_button):
		_button.disabled = not enabled
		_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)


func finish_opening_safely() -> void:
	if not animating:
		return
	_skip = true
	_apply_finished_state()
	animating = false
	_input_locked = false
	chest_state = ChestState.OPEN_EMPTY if not _show_scroll_on_finish else ChestState.TRANSITIONING
	if not _show_scroll_on_finish:
		_set_badge_suppressed(false)
	open_finished.emit()


func apply_ready_idle_state() -> void:
	animating = false
	_skip = false
	_idle_time = 0.0
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_particles_armed = false
	_scroll_emerged_emitted = false
	_stop_motes()
	if _dust != null:
		_dust.emitting = false
	if _sparks != null:
		_sparks.emitting = false
	hide_rolled_scroll()
	_reset_pose()
	configure(ChestState.READY, true)
	set_interaction_enabled(true)
	modulate = Color(1, 1, 1, 1)
	visible = true


func _open_short() -> void:
	## Reduced-motion: quick opaque walk of key frames — never a translucent blend.
	_layout_frames()
	_clear_baked_reveal()
	_ensure_legacy_layers_hidden()
	_show_frame_index(0)
	_open_amount = 0.0
	var steps := [0, 3, 6, 9, 12]
	var step_dur := OPEN_DURATION_RM / float(maxi(steps.size() - 1, 1))
	for i in range(steps.size()):
		if _skip:
			break
		_show_frame_index(int(steps[i]))
		_open_amount = float(i) / float(maxi(steps.size() - 1, 1))
		if _glow_pulse:
			_glow_pulse.modulate.a = lerpf(0.0, GLOW_OPEN_A, _open_amount)
		await get_tree().create_timer(step_dur).timeout
	_show_frame_index(_chest_frames.size() - 1)
	_open_amount = 1.0
	_enforce_chest_opaque()
	if _show_scroll_on_finish and not _skip:
		_record_reward_texture("chest_12_fully_open")
		await get_tree().create_timer(SCROLL_POST_OPEN_BEAT_SEC * 0.7).timeout
		await _play_baked_scroll_reveal(0.70)
		await get_tree().create_timer(REWARD_HOLD_SEC * 0.6).timeout
	else:
		await get_tree().create_timer(0.06).timeout


func _play_scroll_rise_tween(duration: float) -> void:
	## LEGACY layered Y-tween — inactive for normal scroll reward (v61+).
	## Production uses _play_baked_scroll_reveal. Retained for tooling history.
	chest_state = ChestState.OPEN_SCROLL_EMERGING
	_arm_scroll_hidden_behind_lip()
	if _glow_pulse:
		var glow_in := create_tween()
		glow_in.tween_property(_glow_pulse, "modulate:a", GLOW_EMERGE_A, duration * 0.14).set_trans(Tween.TRANS_SINE)
	if _warm_spill:
		var spill_in := create_tween()
		spill_in.tween_property(_warm_spill, "modulate:a", 0.018, duration * 0.14).set_trans(Tween.TRANS_SINE)
	var rise := create_tween()
	rise.tween_method(_set_scroll_rise_amount, 0.00, 1.00, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await rise.finished
	_set_scroll_rise_amount(1.0)
	if _frame_view:
		_frame_view.modulate = Color(1, 1, 1, 1)
	if _glow_pulse:
		var glow_hold := create_tween()
		glow_hold.tween_property(_glow_pulse, "modulate:a", GLOW_REWARD_HOLD_A, 0.12).set_trans(Tween.TRANS_SINE)
	if not _scroll_emerged_emitted:
		_scroll_emerged_emitted = true
		sfx_scroll_emerge.emit()
		scroll_emerged.emit(get_scroll_global_center())


func _play_baked_scroll_reveal(time_scale: float = 1.0) -> void:
	## Normal scroll reward: discrete animation_v3 reveal_00…07 swaps.
	## Exactly ONE baked frame visible at any instant — no crossfade / ghosting.
	## Standalone ScrollLayer / open_back / front_rim stay hidden.
	chest_state = ChestState.OPEN_SCROLL_EMERGING
	_ensure_legacy_layers_hidden()
	if _glow_pulse:
		_glow_pulse.modulate.a = GLOW_EMERGE_A
	if _warm_spill:
		_warm_spill.modulate.a = 0.018
	var scale := clampf(time_scale, 0.35, 1.0)
	var count := _reveal_frames.size()
	if count <= 0:
		return
	for i in range(count):
		if _skip:
			_show_baked_reveal_index(count - 1)
			break
		_show_baked_reveal_index(i)
		## Advance after dwell on reveal_00…06; reveal_07 settles into hold.
		if i < count - 1:
			var dwell := 0.06
			if i < REVEAL_FRAME_DWELLS_SEC.size():
				dwell = float(REVEAL_FRAME_DWELLS_SEC[i])
			await get_tree().create_timer(dwell * scale).timeout
	if _glow_pulse:
		var glow_hold := create_tween()
		glow_hold.tween_property(_glow_pulse, "modulate:a", GLOW_REWARD_HOLD_A, 0.12).set_trans(Tween.TRANS_SINE)
	if not _scroll_emerged_emitted:
		_scroll_emerged_emitted = true
		sfx_scroll_emerge.emit()
		scroll_emerged.emit(get_scroll_global_center())


func _open_full() -> void:
	## Smooth 13-frame animation_v2 open — opaque discrete swaps, no crossfade.
	_layout_frames()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	_exit_layered_open()
	_clear_baked_reveal()
	_ensure_legacy_layers_hidden()
	_show_frame_index(0)
	_open_amount = 0.0
	_enforce_chest_opaque()
	await get_tree().create_timer(ANTICIPATION_SEC).timeout
	if _skip:
		_apply_finished_state()
		return

	sfx_latch_release.emit()
	HapticHelper.lock_release()

	## Drive progress 0→1; weighted frames provide restrained→accel→decel feel.
	var open_tw := create_tween()
	open_tw.tween_method(func(v: float) -> void:
		_set_frame_progress(v, false)
		_enforce_chest_opaque()
	, 0.0, 1.0, OPEN_DURATION_SEC).set_trans(Tween.TRANS_LINEAR)
	await open_tw.finished
	if _skip:
		_apply_finished_state()
		return

	_show_frame_index(_chest_frames.size() - 1)
	_open_amount = 1.0
	_enforce_chest_opaque()
	_record_reward_texture("chest_12_fully_open")
	sfx_magical_swell.emit()
	if not _particles_armed:
		_particles_armed = true
		_emit_burst()
		_start_motes()
	else:
		_emit_burst()

	## Settle glow at fully open — magical but not washed-out.
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_method(func(v: float) -> void:
		_emphasis_scale = v
		_apply_root_transform()
	, EMPHASIS_SCALE, 1.0, SETTLE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _glow_pulse:
		settle.tween_property(_glow_pulse, "modulate:a", GLOW_SETTLE_A, SETTLE_SEC).set_trans(Tween.TRANS_SINE)
	if _warm_spill:
		settle.tween_property(_warm_spill, "modulate:a", 0.07, SETTLE_SEC).set_trans(Tween.TRANS_SINE)
	await settle.finished
	if _skip:
		_apply_finished_state()
		return

	## Full-open beat, then animation_v3 baked reveal (no layered reconstruction).
	if _show_scroll_on_finish:
		if _glow_pulse:
			_glow_pulse.modulate.a = GLOW_EMERGE_A
		await get_tree().create_timer(SCROLL_POST_OPEN_BEAT_SEC).timeout
		if _skip:
			_apply_finished_state()
			return
		await _play_baked_scroll_reveal(1.0)
		if _skip:
			_apply_finished_state()
			return

	var swell := create_tween()
	swell.set_parallel(true)
	if _glow_pulse:
		swell.tween_property(
			_glow_pulse,
			"modulate:a",
			GLOW_REWARD_HOLD_A if _show_scroll_on_finish else GLOW_SETTLE_A * 0.55,
			MAGICAL_SWELL_SEC
		)
	if _warm_spill and not _show_scroll_on_finish:
		swell.tween_property(_warm_spill, "modulate:a", 0.04, MAGICAL_SWELL_SEC)
	await swell.finished
	_emphasis_scale = 1.0
	_apply_root_transform()

	if _show_scroll_on_finish and not _skip:
		chest_state = ChestState.OPEN_WAITING_FOR_SCROLL
		## Intentional hold on reveal_07 so the completed scroll reads before transition.
		await get_tree().create_timer(REWARD_HOLD_SEC).timeout
	else:
		await get_tree().create_timer(0.06).timeout
		## Empty remains open with restrained glow — motes stay soft.
	_anticipation_y = 0.0
	_apply_root_transform()


func get_scroll_global_center() -> Vector2:
	## Approximate scroll center from the baked frame cavity / host plant.
	if _baked_reveal_active and _anchor_rect.size != Vector2.ZERO:
		return global_position + _anchor_rect.position + Vector2(
			_anchor_rect.size.x * 0.48,
			_anchor_rect.size.y * 0.48
		)
	if _scroll_view and _scroll_view.is_visible_in_tree() and _scroll_clip and _scroll_clip.visible:
		return _scroll_view.global_position + Vector2(
			_scroll_view.size.x * 0.5,
			_scroll_view.size.y * 0.45
		)
	if _scroll_clip and _scroll_clip.visible:
		return _scroll_clip.global_position + Vector2(
			_scroll_clip.size.x * 0.5,
			_scroll_clip.size.y * 0.55
		)
	if _anchor_rect.size != Vector2.ZERO:
		return global_position + _anchor_rect.position + Vector2(
			_anchor_rect.size.x * 0.5,
			_anchor_rect.size.y * 0.38
		)
	return global_position + size * 0.5


func hide_rolled_scroll() -> void:
	_scroll_rise = 0.0
	_clear_baked_reveal()
	if _layered_open:
		_exit_layered_open()
	_ensure_legacy_layers_hidden()
	_place_scroll_and_rim()


func _apply_finished_state() -> void:
	_select_sequence(false)
	_frame_index = _chest_frames.size() - 1
	_open_amount = 1.0
	if _show_scroll_on_finish:
		## End on reveal_07_final — never reconstruct open_back + rim + ScrollLayer.
		_ensure_legacy_layers_hidden()
		if _reveal_frames.size() > 0:
			_show_baked_reveal_index(_reveal_frames.size() - 1)
		elif _frame_view and _chest_frames.size() > 0:
			_clear_baked_reveal()
			_frame_view.texture = _chest_frames[_chest_frames.size() - 1]
			_frame_view.modulate = Color(1, 1, 1, 1)
	else:
		_layered_open = false
		_clear_baked_reveal()
		_ensure_legacy_layers_hidden()
		if _frame_view and _chest_frames.size() > 0:
			_frame_view.texture = _chest_frames[_chest_frames.size() - 1]
			_frame_view.modulate = Color(1, 1, 1, 1)
		_place_scroll_and_rim()
	_anticipation_y = 0.0
	_emphasis_scale = 1.0
	_apply_root_transform()
	if _glow_pulse:
		_glow_pulse.modulate.a = GLOW_REWARD_HOLD_A if _show_scroll_on_finish else GLOW_SETTLE_A * 0.45
	if _warm_spill:
		_warm_spill.modulate.a = 0.022 if _show_scroll_on_finish else 0.030
	_enforce_chest_opaque()


func _emit_burst() -> void:
	if reduced_motion:
		return
	if _dust:
		_dust.restart()
		_dust.emitting = true
	if _sparks:
		_sparks.restart()
		_sparks.emitting = true


func _start_motes() -> void:
	if reduced_motion or _motes == null:
		return
	_motes.emitting = true


func _stop_motes() -> void:
	if _motes != null:
		_motes.emitting = false


func request_skip() -> void:
	_skip = true


func frame_count() -> int:
	return maxi(_chest_frames.size(), 1)
