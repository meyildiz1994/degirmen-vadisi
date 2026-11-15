shader_type canvas_item;
// Arayüz panelleri: suluboya lekesi ya da kart. Düzensiz noise maskeli kenar,
// yarı saydam krem zemin, koyulaşan pigment kenarı ve isteğe bağlı yumuşak gölge.

uniform vec4 wash_color : source_color = vec4(0.97, 0.93, 0.85, 0.86);
uniform vec4 rim_color : source_color = vec4(0.80, 0.70, 0.58, 0.9);
uniform vec4 shadow_color : source_color = vec4(0.42, 0.32, 0.24, 0.0);
uniform sampler2D mask_noise : hint_default_white, filter_linear, repeat_enable;
uniform float seed = 0.0;
uniform float softness = 0.08;
uniform float edge_noise = 0.35;   // kenar düzensizliği (kart: düşük)
uniform float corner = 0.8;        // köşe yuvarlaklığı (kısa kenara oranla)
uniform float rim_width = 0.16;
uniform vec2 shadow_offset_px = vec2(5.0, 7.0);
uniform vec2 rect_size = vec2(300.0, 120.0);

float shape_dist(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	vec2 s = rect_size / max(rect_size.x, rect_size.y);
	float m = min(s.x, s.y);
	float r = m * corner;
	vec2 q = abs(p * s) - (s - vec2(r));
	float d = (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r) / m;
	float n = texture(mask_noise, uv * vec2(rect_size.x / 260.0, rect_size.y / 260.0) + vec2(seed)).r;
	float n2 = texture(mask_noise, uv * 3.7 + vec2(seed * 1.7)).r;
	return d + (n - 0.5) * edge_noise + (n2 - 0.5) * edge_noise * 0.35 + edge_noise * 0.35;
}

void fragment() {
	float d = shape_dist(UV);
	float inside = 1.0 - smoothstep(-softness * 2.0, 0.0, d);
	float rim = smoothstep(-rim_width, -0.02, d) * inside;
	float n2 = texture(mask_noise, UV * 3.7 + vec2(seed * 1.7)).r;
	vec4 col = mix(wash_color, rim_color, rim * 0.7);
	col.rgb *= 0.97 + n2 * 0.06;
	float a = col.a * inside;
	// Gölge: kaydırılmış şekil, kartın altında yumuşak kahve leke
	float sd = shape_dist(UV - shadow_offset_px / rect_size);
	float shadow = (1.0 - smoothstep(-0.25, 0.1, sd)) * shadow_color.a;
	vec3 rgb = mix(shadow_color.rgb, col.rgb, a / max(a + shadow * (1.0 - a), 0.001));
	COLOR = vec4(rgb, a + shadow * (1.0 - a));
}
