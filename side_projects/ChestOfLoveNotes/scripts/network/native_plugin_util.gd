extends RefCounted
class_name NativePluginUtil
## Shared helpers for Godot Android JNI plugins (@UsedByGodot).
## Object.has_method() is unreliable for these singletons on device even when
## methods are registered and callable — never use it as the sole availability gate.


static func get_singleton(plugin_name: String) -> Object:
	if not Engine.has_singleton(plugin_name):
		return null
	return Engine.get_singleton(plugin_name)


static func is_present(plugin_name: String) -> bool:
	return get_singleton(plugin_name) != null


## True when the singleton is present. On Android that means the plugin AAR/class
## registered; known methods are assumed available without trusting has_method().
static func bridge_available(plugin_name: String) -> bool:
	return is_present(plugin_name)


static func method_available(plugin_name: String, method: String) -> bool:
	var p := get_singleton(plugin_name)
	if p == null:
		return false
	if p.has_method(method):
		return true
	## Android @UsedByGodot: has_method often lies; singleton presence is enough.
	return OS.get_name() == "Android"


static func call_method(plugin_name: String, method: String, args: Array = []) -> Variant:
	var p := get_singleton(plugin_name)
	if p == null:
		return null
	if p.has_method(method) or OS.get_name() == "Android":
		return p.callv(method, args)
	return null
