shader_type canvas_item;

uniform vec4 parchment_light : source_color = vec4(0.95, 0.89, 0.72, 1.0);
uniform vec4 parchment_dark : source_color = vec4(0.82, 0.70, 0.48, 1.0);
uniform vec4 edge_color : source_color = vec4(0.45, 0.28, 0.14, 1.0);
uniform float edge_wear : hint_range(0.0, 1.0) = 0.55;
uniform float flex : hint_range(-1.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * 8.0 + flex * 3.0) * 0.004 * flex;
	float n = noise(uv * 28.0) * 0.5 + noise(uv * 64.0) * 0.25;
	vec3 base = mix(parchment_dark.rgb, parchment_light.rgb, n + uv.y * 0.15);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float wear = smoothstep(0.0, 0.08, edge);
	base = mix(edge_color.rgb, base, mix(1.0, wear, edge_wear));
	float grain = noise(uv * 120.0);
	base *= 0.96 + grain * 0.08;
	COLOR = vec4(base, COLOR.a);
}
