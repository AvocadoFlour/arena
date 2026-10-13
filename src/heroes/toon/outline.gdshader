shader_type spatial;
// Inverted-hull outline: second pass that pushes the (skinned) surface out along its normal and draws
// only back faces in flat black. Width is in metres, optionally kept ~constant on screen.
render_mode unshaded, cull_front, depth_draw_opaque, skip_vertex_transform;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width = 0.008;
uniform float screen_scale : hint_range(0.0, 1.0) = 0.35;   // 0 = world width, 1 = grows with distance

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dist_k = mix(1.0, max(1.0, -view_pos.z / 4.0), screen_scale);
	view_pos.xyz += view_n * width * dist_k;
	VERTEX = view_pos.xyz;
	NORMAL = view_n;
}

void fragment() {
	ALBEDO = color.rgb;
}
