extends Node
class_name AppState
## Global app mode and services for Chest of Love Notes.

enum Mode { UNCONFIGURED, LOCAL_DEMO, ONLINE }

var mode: Mode = Mode.UNCONFIGURED
var config: BackendConfig = BackendConfig.new()
var tokens: SecureTokenService = SecureTokenService.new()
var api: ApiClient
var scrolls: ScrollService
var demo: DemoSession = DemoSession.new()
var reduced_motion: bool = false
## Ephemeral plaintext held only while a scroll viewer is open (online/demo).
var open_message_plaintext: String = ""


func _init() -> void:
	api = ApiClient.new(config, tokens)
	scrolls = ScrollService.new(api)


func clear_open_message() -> void:
	open_message_plaintext = ""


func bootstrap() -> void:
	var is_release := OS.has_feature("release") or not OS.is_debug_build()
	if config.load_config():
		mode = Mode.ONLINE
		demo.disable()
		return
	if is_release:
		mode = Mode.UNCONFIGURED
		demo.disable()
		return
	# Debug builds without backend use LOCAL DEMO MODE.
	mode = Mode.LOCAL_DEMO
	demo.enable()


func is_demo() -> bool:
	return mode == Mode.LOCAL_DEMO


func is_online() -> bool:
	return mode == Mode.ONLINE


func sign_out() -> void:
	tokens.clear()
	clear_open_message()
	demo.clear_sensitive()
