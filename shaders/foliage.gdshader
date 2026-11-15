shader_type spatial;
// Yaprak blob'ları ve çimen: noise ile dağınık kenar (alpha scissor),
// vertex shader ile rüzgârda hafif salınım. Işık modeli nesne shader'ıyla aynı.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/watercolor_common.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform sampler2D paint_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.12;
uniform float color_variation = 0.18;
uniform bool ragged_edges = true;
uniform float raggedness = 0.75;
uniform float edge_cut = 1.35;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.1;
uniform float sway_height = 0.0; // >0: salınım yüksekliğe göre artar (çimen)
uniform bool up_normals = false; // çimende düz, yukarı bakan normal

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.37 + origin.z * 0.23;
	float h = sway_height > 0.0 ? clamp(VERTEX.y * sway_height, 0.0, 1.0) : 1.0;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + origin.x * 0.05);
	VERTEX.x += sin(TIME * wind_speed + phase) * wind_strength * h * gust;
	VERTEX.z += cos(TIME * wind_speed * 0.77 + phase * 1.3) * wind_strength * 0.6 * h * gust;
	if (up_normals) {
		NORMAL = normalize(mix(NORMAL, (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.85));
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	vec2 n = wc_paint_noise(paint_noise, world_pos, world_normal, noise_scale);
	base = wc_pigment(base, n, color_variation);
	if (ragged_edges) {
		float fres = 1.0 - abs(dot(NORMAL, VIEW));
		float cut = texture(paint_noise, world_pos.xy * 1.9 + world_pos.zx * 0.9).r;
		float fine = texture(paint_noise, world_pos.zy * 5.5 + world_pos.x * 0.7).r;
		float a = 1.0 - fres * fres * edge_cut + (cut - 0.5) * raggedness + (fine - 0.5) * raggedness * 0.5;
		ALPHA = clamp(a, 0.0, 1.0);
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		// Kenarlara doğru pigment birikmesi
		base *= mix(1.08, 0.74, smoothstep(0.25, 0.9, fres));
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += wc_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
