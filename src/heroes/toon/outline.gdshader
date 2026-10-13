shader_type spatial;
// Inverted-hull outline: second pass that pushes the (skinned) surface out along its normal and draws
// only back faces in flat black. Width is in metres, optionally kept ~constant on screen.
render_mode unshaded, cull_front, depth_draw_opaque, skip_vertex_transform;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width = 0.011;
// 0 = constant world width, 1 = constant on-screen width (relative to `ref_dist`); clamped so close-ups
// stay thin and far heroes keep a readable line.
uniform float screen_scale : hint_range(0.0, 1.0) = 0.85;
uniform float ref_dist = 4.0;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dist_k = clamp(mix(1.0, -view_pos.z / ref_dist, screen_scale), 0.6, 6.0);
	view_pos.xyz += view_n * width * dist_k;
	VERTEX = view_pos.xyz;
	NORMAL = view_n;
}

void fragment() {
	ALBEDO = color.rgb;
}
