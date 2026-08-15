shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform float pulse_speed : hint_range(0.0, 4.0) = 1.2;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float reduced_motion : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float pulse = mix(0.85 + 0.15 * sin(TIME * pulse_speed), 1.0, reduced_motion);
	float alpha = smoothstep(1.0, 0.15, dist) * glow_color.a * intensity * pulse;
	COLOR = vec4(glow_color.rgb, alpha);
}
