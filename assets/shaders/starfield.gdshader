shader_type canvas_item;

uniform vec4 color_top : source_color = vec4(0.03, 0.02, 0.10, 1.0);
uniform vec4 color_mid : source_color = vec4(0.08, 0.04, 0.18, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.12, 0.05, 0.16, 1.0);
uniform float time_scale : hint_range(0.0, 2.0) = 0.08;
uniform float star_density : hint_range(0.0, 1.0) = 0.55;
uniform vec2 parallax_offset = vec2(0.0, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float soft_star(vec2 uv, float threshold) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float n = hash(cell);
	if (n < threshold) {
		return 0.0;
	}
	// Random offset inside cell for less grid look.
	vec2 jitter = vec2(hash(cell + 1.7), hash(cell + 9.3)) - 0.5;
	f -= jitter * 0.55;
	float d = length(f);
	float size = mix(0.015, 0.045, hash(cell + 3.1));
	float core = smoothstep(size, 0.0, d);
	return core * core;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;
	vec3 col = mix(color_top.rgb, color_mid.rgb, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, color_bottom.rgb, smoothstep(0.45, 1.0, uv.y));

	// Soft rose/gold nebula — smooth, not blocky.
	float neb = sin((uv.x + parallax_offset.x * 0.1) * 3.0 + t) * 0.5 + 0.5;
	neb *= exp(-pow((uv.y - 0.42) * 3.2, 2.0));
	col += vec3(0.22, 0.08, 0.16) * neb * 0.18;
	col += vec3(0.18, 0.12, 0.05) * (1.0 - abs(uv.x - 0.5) * 1.5) * 0.04;

	vec2 p1 = uv * vec2(70.0, 140.0) + parallax_offset * 0.35;
	vec2 p2 = uv * vec2(120.0, 220.0) - parallax_offset * 0.55;
	float s1 = soft_star(p1, 1.0 - star_density * 0.22);
	float s2 = soft_star(p2 + 17.0, 1.0 - star_density * 0.12);
	float twinkle = 0.75 + 0.25 * sin(t * 2.4 + hash(floor(p1)) * 20.0);
	col += vec3(1.0, 0.96, 0.88) * s1 * 0.65 * twinkle;
	col += vec3(0.95, 0.88, 1.0) * s2 * 0.35;

	COLOR = vec4(col, 1.0);
}
