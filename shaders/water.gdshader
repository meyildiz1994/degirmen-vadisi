shader_type spatial;
// Su: yarı saydam mavi-yeşil, yüzeyde yavaşça kayan beyaz fırça izleri.
// UV.x: dere boyunca enine (0..1), UV.y: akış yönünde metre. COLOR.r: akış hızı çarpanı.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, specular_disabled, shadows_disabled;

uniform vec4 deep_color : source_color = vec4(0.18, 0.50, 0.70, 0.84);
uniform vec4 shallow_color : source_color = vec4(0.32, 0.76, 0.72, 0.66);
uniform vec4 stroke_color : source_color = vec4(0.98, 0.96, 0.91, 0.85);
uniform vec3 sunset_glint : source_color = vec3(0.99, 0.80, 0.58);
uniform vec3 paper_color : source_color = vec3(0.96, 0.92, 0.84);
uniform sampler2D paint_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float flow_speed = 0.09;
uniform float stroke_amount = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float stroke_band(float n, float center, float width) {
	return smoothstep(center - width, center, n) * (1.0 - smoothstep(center, center + width * 1.6, n));
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.15, 1.0, across));
	float speed = flow_speed * COLOR.r;
	// Akış yönünde uzatılmış iki katman fırça izi
	float n1 = texture(paint_noise, vec2(UV.x * 1.6, UV.y * 0.045 - TIME * speed)).r;
	float n2 = texture(paint_noise, vec2(UV.x * 2.3 + 0.37, UV.y * 0.07 - TIME * speed * 1.45)).r;
	float strokes = stroke_band(n1, 0.66, 0.025) + stroke_band(n2, 0.30, 0.02) * 0.7;
	strokes *= stroke_amount * (0.55 + 0.45 * smoothstep(0.1, 0.6, across));
	// Büyük, yavaş renk lekeleri
	float wash = texture(paint_noise, world_pos.xz * 0.045 + vec2(TIME * 0.004)).r;
	col *= 0.9 + wash * 0.2;
	// Gün batımı yansıması
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sunset_glint, fres * 0.35);
	col = mix(col, stroke_color.rgb, clamp(strokes, 0.0, 1.0) * stroke_color.a);
	// Kıyıda kâğıt beyazına açılma
	col = mix(col, paper_color, smoothstep(0.8, 1.0, across) * 0.45);
	ALBEDO = col;
	ALPHA = clamp(mix(deep_color.a, shallow_color.a, across) + strokes * 0.2, 0.0, 1.0);
}
