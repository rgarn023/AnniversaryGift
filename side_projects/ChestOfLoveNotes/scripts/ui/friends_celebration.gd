extends Control
class_name FriendsCelebration
## Subtle petal celebration for friend-accept — charming, not overwhelming.
## Particles stay behind readable content and never cover bottom navigation.

const PETAL_COUNT_NORMAL := 10
const PETAL_COUNT_REDUCED := 0
const DURATION_SEC := 1.15


func play(reduced_motion: bool = false) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 2
	if reduced_motion:
		queue_free()
		return
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.amount = PETAL_COUNT_NORMAL
	particles.lifetime = DURATION_SEC
	particles.one_shot = true
	particles.explosiveness = 0.35
	particles.local_coords = true
	particles.direction = Vector2(0, 1)
	particles.spread = 55.0
	particles.initial_velocity_min = 18.0
	particles.initial_velocity_max = 46.0
	particles.gravity = Vector2(0, 36)
	particles.scale_amount_min = 0.18
	particles.scale_amount_max = 0.36
	particles.color = Color(1.0, 0.72, 0.82, 0.55)
	## Keep burst in the upper half, behind list content / above nav.
	particles.position = Vector2(size.x * 0.5 if size.x > 1.0 else 195.0, 72.0)
	add_child(particles)
	await get_tree().process_frame
	particles.position = Vector2(size.x * 0.5, mini(90.0, size.y * 0.12))
	particles.restart()
	particles.emitting = true
	await get_tree().create_timer(DURATION_SEC + 0.05).timeout
	queue_free()
