shader_type canvas_item;
// Arayüz panelleri için suluboya lekesi: düzensiz noise maskesi, yarı saydam krem zemin.

uniform vec4 wash_color : source_color = vec4(0.97, 0.93, 0.85, 0.86);
uniform vec4 rim_color : source_color = vec4(0.80, 0.70, 0.58, 0.9);
uniform sampler2D mask_noise : hint_default_white, filter_linear, repeat_enable;
uniform float seed = 0.0;
uniform float softness = 0.08;
uniform vec2 rect_size = vec2(300.0, 120.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Yuvarlatılmış dikdörtgen mesafesi, piksel oranına göre
	vec2 s = rect_size / max(rect_size.x, rect_size.y);
	float m = min(s.x, s.y);
	float r = m * 0.8;
	vec2 q = abs(p * s) - (s - vec2(r));
	float d = (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r) / m;
	float n = texture(mask_noise, UV * vec2(rect_size.x / 260.0, rect_size.y / 260.0) + vec2(seed)).r;
	float n2 = texture(mask_noise, UV * 3.7 + vec2(seed * 1.7)).r;
	d += (n - 0.5) * 0.35 + (n2 - 0.5) * 0.12 + 0.12;
	float inside = 1.0 - smoothstep(-softness * 2.0, 0.0, d);
	float rim = smoothstep(-0.16, -0.02, d) * inside;
	vec4 col = mix(wash_color, rim_color, rim * 0.7);
	col.rgb *= 0.97 + n2 * 0.06;
	COLOR = vec4(col.rgb, col.a * inside);
}
