shader_type spatial;
// Low-quality map toon path (maps perf pass). Same flat 2-tone look as map_toon.gdshader without shadows
// (which low quality turns off): lit = albedo, faces turned from the sun = albedo * shade. Unshaded, so the
// renderer skips the per-pixel light pass entirely; the tone is decided per vertex (map geometry is flat boxes,
// so every face has one tone). sun_to = world direction towards the sun (set by MapLoader from theme sun_rot).
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float shade : hint_range(0.0, 1.0) = 0.74;
uniform sampler2D pattern : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_pattern = 0.0;
uniform float pattern_scale = 0.5;
uniform vec4 emission : source_color = vec4(0.0);
uniform float emission_energy = 0.0;
uniform vec3 sun_to = vec3(0.0, 1.0, 0.0);

varying vec3 wpos;
varying vec3 wnrm;
varying float tone;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tone = mix(shade, 1.0, step(0.02, dot(wnrm, sun_to)));
}

// The Compatibility renderer writes an unshaded ALBEDO straight to the sRGB target, while the lit path
// shades in linear space; convert so the shadow tone and emission match map_toon.gdshader exactly.
vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
vec3 to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

void fragment() {
	vec3 a = abs(wnrm);
	vec2 uv = a.y > a.x && a.y > a.z ? wpos.xz : (a.x > a.z ? wpos.zy : wpos.xy);
	vec3 p = mix(vec3(1.0), texture(pattern, uv * pattern_scale).rgb, use_pattern);
	vec3 lin = to_lin(albedo.rgb * p) * tone + to_lin(emission.rgb) * emission_energy;
	ALBEDO = to_srgb(clamp(lin, 0.0, 1.0));
}
