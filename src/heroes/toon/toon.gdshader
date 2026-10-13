shader_type spatial;
// Flat toon colour with a slight 2-tone step. Unshaded (no scene lights), deterministic on every client
// and renderer (GL Compatibility friendly). Light direction is fixed in view space.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float shade_strength : hint_range(0.0, 0.5) = 0.12;   // darkening of the shadow tone
uniform float step_at : hint_range(-1.0, 1.0) = -0.05;          // N.L threshold of the tone step
uniform vec3 light_dir_view = vec3(0.45, 0.65, 0.6);
uniform vec4 tint : source_color = vec4(1.0);                   // runtime tint (hit flash etc.)

void fragment() {
	float ndl = dot(normalize(NORMAL), normalize(light_dir_view));
	float tone = ndl > step_at ? 1.0 : 1.0 - shade_strength;
	ALBEDO = albedo.rgb * tone * tint.rgb;
}
