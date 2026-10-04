shader_type canvas_item;
// Tutorial dim with up to 6 rectangular holes (screen pixels: x, y, w, h).

uniform vec4 holes[6];
uniform int hole_count = 0;
uniform float dim = 0.62;
uniform vec2 screen_size = vec2(640.0, 360.0);

void fragment() {
	vec2 p = UV * screen_size;
	float a = dim;
	for (int i = 0; i < 6; i++) {
		if (i >= hole_count) {
			break;
		}
		vec4 h = holes[i];
		if (p.x >= h.x && p.y >= h.y && p.x < h.x + h.z && p.y < h.y + h.w) {
			a = 0.0;
		}
	}
	COLOR = vec4(0.02, 0.02, 0.05, a);
}
