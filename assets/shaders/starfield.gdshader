shader_type canvas_item;

uniform vec4 color_top : source_color = vec4(0.05, 0.03, 0.14, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.12, 0.05, 0.22, 1.0);
uniform float time_scale : hint_range(0.0, 2.0) = 0.15;
uniform float star_density : hint_range(0.0, 1.0) = 0.65;
uniform float parallax : hint_range(0.0, 1.0) = 0.25;
uniform vec2 parallax_offset = vec2(0.0, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float star(vec2 uv, float threshold) {
	float n = hash(uv);
	float b = smoothstep(threshold, threshold + 0.015, n);
	return b * b;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;
	vec3 col = mix(color_top.rgb, color_bottom.rgb, uv.y);

	vec2 p1 = uv * vec2(48.0, 96.0) + parallax_offset * parallax * 0.6;
	vec2 p2 = uv * vec2(90.0, 160.0) - parallax_offset * parallax;
	vec2 cell1 = floor(p1);
	vec2 cell2 = floor(p2);
	float s1 = star(cell1, 1.0 - star_density * 0.35);
	float s2 = star(cell2 + 19.0, 1.0 - star_density * 0.2);
	float twinkle = 0.65 + 0.35 * sin(t * 3.0 + hash(cell1) * 20.0);
	col += vec3(1.0, 0.95, 0.85) * s1 * 0.55 * twinkle;
	col += vec3(1.0, 0.85, 0.95) * s2 * 0.35;

	// Soft rose/gold nebula wash.
	float neb = smoothstep(0.2, 0.9, hash(floor(uv * 6.0)));
	col += vec3(0.35, 0.12, 0.28) * neb * 0.08;
	col += vec3(0.35, 0.25, 0.1) * (1.0 - abs(uv.x - 0.5) * 1.4) * 0.05;

	COLOR = vec4(col, 1.0);
}
