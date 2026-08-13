shader_type canvas_item;
// Alpha-mask the romantic scroll to the open-chest cavity only.
// mask_tex is the 512x512 cavity mask in chest-canvas space.
// scroll_canvas_rect = (left, top, width, height) of this node in canvas px.

uniform sampler2D mask_tex : source_color, filter_linear, repeat_disable;
uniform vec4 scroll_canvas_rect = vec4(0.0, 0.0, 512.0, 512.0);
uniform float canvas_size = 512.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	// Map this fragment into chest-canvas UVs for the cavity mask.
	vec2 canvas_px = scroll_canvas_rect.xy + UV * scroll_canvas_rect.zw;
	vec2 mask_uv = canvas_px / max(canvas_size, 1.0);
	float m = 0.0;
	if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
		m = texture(mask_tex, mask_uv).r;
	}
	col.a *= m;
	COLOR = col;
}
