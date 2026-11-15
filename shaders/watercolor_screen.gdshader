shader_type canvas_item;
// Tam ekran suluboya efekti: kâğıt dokusu, renk taşması, kenar beyazlatma,
// doygunluk/sıcaklık ayarı, ıslak kenarlar ve (yüksek kalitede) Kuwahara filtresi.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D paper_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D blot_noise : hint_default_white, filter_linear, repeat_enable;
uniform vec3 paper_color : source_color = vec3(0.96, 0.92, 0.84);
uniform float paper_strength = 0.16;
uniform float paper_scale = 2.2;
uniform float saturation = 0.9;
uniform vec3 warm_tint : source_color = vec3(1.03, 0.99, 0.92);
uniform bool bleed_enabled = true;
uniform float bleed_amount = 0.0022;
uniform bool wet_edges_enabled = true;
uniform float wet_edge_strength = 0.35;
uniform bool kuwahara_enabled = false;
uniform int kuwahara_radius = 2;
uniform float vignette_start = 0.62;
uniform float vignette_width = 0.38;
uniform float vignette_strength = 0.92;

vec3 sample_screen(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).rgb;
}

vec3 kuwahara(vec2 uv, vec2 px) {
	vec3 mean[4];
	vec3 sq[4];
	for (int k = 0; k < 4; k++) { mean[k] = vec3(0.0); sq[k] = vec3(0.0); }
	int r = kuwahara_radius;
	float count = float((r + 1) * (r + 1));
	for (int j = -r; j <= r; j++) {
		for (int i = -r; i <= r; i++) {
			vec3 c = sample_screen(uv + vec2(float(i), float(j)) * px);
			vec3 c2 = c * c;
			if (i <= 0 && j <= 0) { mean[0] += c; sq[0] += c2; }
			if (i >= 0 && j <= 0) { mean[1] += c; sq[1] += c2; }
			if (i <= 0 && j >= 0) { mean[2] += c; sq[2] += c2; }
			if (i >= 0 && j >= 0) { mean[3] += c; sq[3] += c2; }
		}
	}
	vec3 best = mean[0] / count;
	float best_var = 1e9;
	for (int k = 0; k < 4; k++) {
		vec3 m = mean[k] / count;
		vec3 v = abs(sq[k] / count - m * m);
		float var = v.r + v.g + v.b;
		if (var < best_var) { best_var = var; best = m; }
	}
	return best;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 auv = vec2(uv.x * aspect, uv.y);

	float blot = texture(blot_noise, auv * 1.3).r;
	if (bleed_enabled) {
		// Renk taşması: ekran UV'sini noise ile çok hafif kaydır
		float bx = texture(blot_noise, auv * 3.1 + vec2(0.3, 0.0)).r - 0.5;
		float by = texture(blot_noise, auv * 3.1 + vec2(0.0, 0.7)).r - 0.5;
		uv += vec2(bx, by) * bleed_amount;
	}

	vec3 col = kuwahara_enabled ? kuwahara(uv, px) : sample_screen(uv);

	if (wet_edges_enabled) {
		// Renk alanlarının sınırında pigment birikmesi
		vec2 o = px * 1.5;
		float gx = luma(sample_screen(uv + vec2(o.x, 0.0))) - luma(sample_screen(uv - vec2(o.x, 0.0)));
		float gy = luma(sample_screen(uv + vec2(0.0, o.y))) - luma(sample_screen(uv - vec2(0.0, o.y)));
		float edge = smoothstep(0.03, 0.18, length(vec2(gx, gy)));
		col *= 1.0 - edge * wet_edge_strength * 0.45;
	}

	// Doygunluğu biraz düşür, sıcak tona kaydır
	float l = luma(col);
	col = mix(vec3(l), col, saturation) * warm_tint;

	// Kâğıt dokusu (multiply): ince tane + lif
	vec2 puv = auv * paper_scale;
	float grain = texture(paper_noise, puv * 3.0).r;
	float fiber = texture(paper_noise, puv * vec2(0.6, 4.5) + vec2(0.5)).r;
	float tooth = texture(paper_noise, puv * 9.0 + vec2(0.21, 0.77)).r;
	float paper = grain * 0.55 + fiber * 0.25 + tooth * 0.20;
	col *= mix(1.0 - paper_strength, 1.0 + paper_strength * 0.25, paper);
	// Koyu alanlarda granülasyon biraz daha görünür
	col *= 1.0 - (1.0 - l) * (tooth - 0.5) * 0.08;

	// Kenar lekeleri: vinyet ama karartma değil, kâğıt beyazına açılma
	vec2 c = uv - 0.5;
	c.x *= mix(1.0, aspect, 0.5);
	float d = max(length(c) * 1.05, max(abs(c.x) * 1.1, abs(c.y) * 1.35));
	float mask = smoothstep(vignette_start, vignette_start + vignette_width, d + (blot - 0.5) * 0.28);
	col = mix(col, paper_color * mix(0.96, 1.01, grain), mask * vignette_strength);

	COLOR = vec4(col, 1.0);
}
