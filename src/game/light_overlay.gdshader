shader_type canvas_item;
// Multiplies everything drawn below by (ambient + light map). The light map is a
// low-res banded render of additive light sprites (see world_view.gd).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D light_tex : filter_nearest;
uniform vec4 ambient : source_color = vec4(0.42, 0.44, 0.62, 1.0);
uniform float gain = 1.25;
uniform vec4 danger_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float vignette = 0.0;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base = texture(screen_tex, SCREEN_UV);
	vec3 l = texture(light_tex, UV).rgb;
	vec3 lit = base.rgb * (ambient.rgb * danger_tint.rgb + l * gain);
	// soft shoulder so stacked lights do not clip to flat white
	lit = lit / (1.0 + max(lit - 1.0, 0.0));
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.35, 0.75, length(d * vec2(1.0, 1.35)));
	lit *= 1.0 - v * vignette;
	lit = mix(lit, flash_color.rgb, flash);
	COLOR = vec4(lit, 1.0);
}
