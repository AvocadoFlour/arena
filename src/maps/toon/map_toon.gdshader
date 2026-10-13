shader_type spatial;
// Map toon surface (maps-owned; heroes use src/heroes/toon/toon.gdshader, which is unshaded).
// Flat 2-tone: lit = exact albedo, shadow/away-from-sun = albedo * shade. Receives sun shadows.
// No ambient/specular so colours stay exactly as authored in the map JSON palette. Deterministic.
render_mode cull_back, specular_disabled, ambient_light_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float shade : hint_range(0.0, 1.0) = 0.74;
uniform sampler2D pattern : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_pattern = 0.0;
uniform float pattern_scale = 0.5;
uniform vec4 emission : source_color = vec4(0.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 a = abs(wnrm);
	vec2 uv = a.y > a.x && a.y > a.z ? wpos.xz : (a.x > a.z ? wpos.zy : wpos.xy);
	vec3 p = mix(vec3(1.0), texture(pattern, uv * pattern_scale).rgb, use_pattern);
	ALBEDO = albedo.rgb * p;
	EMISSION = emission.rgb * emission_energy;
}

void light() {
	float lit = step(0.02, dot(NORMAL, LIGHT)) * step(0.5, ATTENUATION);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(mix(shade, 1.0, lit)));
}
