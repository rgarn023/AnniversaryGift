extends RefCounted
class_name RealtimeService
## Placeholder for Supabase Realtime subscriptions (chest / friend requests).

var connected: bool = false


func connect_channels(_access_token: String) -> void:
	connected = false


func disconnect_channels() -> void:
	connected = false
