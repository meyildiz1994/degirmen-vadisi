shader_type spatial;
// Tüm 3D modellerin ortak suluboya shader'ı.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/watercolor_common.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform sampler2D paint_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.09;
uniform float color_variation = 0.16;
uniform float granulation = 0.10;
uniform float edge_darken = 0.55;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
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
	// İnce pigment granülasyonu
	float g = texture(paint_noise, world_pos.xz * noise_scale * 11.0 + world_pos.y * 0.7).r;
	base *= 1.0 - granulation * smoothstep(0.45, 0.85, g);
	base = wc_edge_pigment(base, NORMAL, VIEW, edge_darken);
	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += wc_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
