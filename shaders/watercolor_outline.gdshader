shader_type spatial;
// Inverted hull kenar çizgisi: ince, koyu kahve, kalınlığı noise ile değişen
// kurşun kalem / mürekkep hissi. Kalite "Orta" ve üstünde next_pass olarak eklenir.
render_mode unshaded, cull_front, depth_draw_opaque, specular_disabled, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.32, 0.22, 0.15, 1.0);
uniform float thickness = 0.022;
uniform float thickness_variation = 0.75;
uniform sampler2D paint_noise : hint_default_white, filter_linear, repeat_enable;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = textureLod(paint_noise, wp.xz * 0.45 + vec2(wp.y * 0.31), 0.0).r;
	float view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	// Uzakta çizgi incelmesin diye mesafeyle hafif kalınlaşır (sınırlı)
	float dist_scale = clamp(view_dist * 0.09, 0.7, 2.2);
	float t = thickness * mix(1.0 - thickness_variation, 1.0 + thickness_variation * 0.6, n) * dist_scale;
	VERTEX += NORMAL * t;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
