// Değirmen Vadisi — suluboya ışık modeli (tüm 3D shader'lar paylaşır).
// Işık 2-3 yumuşak basamağa bölünür; aydınlık taraf sıcak sarıya kayar.
// Gölge tarafı siyah değil: Environment'taki lavanta ortam ışığı görünür.

uniform vec3 light_tint : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 mid_tint : source_color = vec3(1.0, 0.80, 0.66);
uniform float band_low = 0.06;
uniform float band_high = 0.50;
uniform float band_softness = 0.045;
uniform float light_strength = 1.05;
uniform float terminator_darken = 0.18;
uniform float pigment_vibrance = 1.45;

vec3 wc_light(vec3 n, vec3 l, vec3 light_color, float attenuation) {
	float ndl = dot(n, l);
	float v = clamp(ndl, 0.0, 1.0) * attenuation;
	float b1 = smoothstep(band_low - band_softness, band_low + band_softness, v);
	float b2 = smoothstep(band_high - band_softness, band_high + band_softness, v);
	// İki basamak: gölge → orta ton (gül/lavanta) → sıcak aydınlık
	vec3 tone = mix(vec3(0.0), mid_tint * 0.55, b1);
	tone = mix(tone, light_tint, b2);
	// Basamak sınırında pigment birikmesi ("ıslak kenar")
	float edge = exp(-pow((v - band_high) / (band_softness * 1.6), 2.0));
	tone *= 1.0 - terminator_darken * edge;
	return tone * light_color / PI * light_strength;
}

// Dünya koordinatına bağlı triplanar boya dalgalanması.
vec2 wc_paint_noise(sampler2D tex, vec3 wpos, vec3 wnormal, float scale) {
	vec3 w = abs(wnormal) + 0.001;
	w /= (w.x + w.y + w.z);
	float a = texture(tex, wpos.zy * scale).r * w.x
		+ texture(tex, wpos.xz * scale).r * w.y
		+ texture(tex, wpos.xy * scale).r * w.z;
	vec3 o = wpos * 0.61 + vec3(17.3, 5.1, 9.7);
	float b = texture(tex, o.zy * scale).r * w.x
		+ texture(tex, o.xz * scale).r * w.y
		+ texture(tex, o.xy * scale).r * w.z;
	return vec2(a, b);
}

vec3 wc_pigment(vec3 base, vec2 n, float variation) {
	// Değer dalgalanması (boya kâğıtta dağılıyor)
	base *= 1.0 + (n.x - 0.5) * 2.0 * variation;
	// Hafif sıcak/soğuk ton kayması
	vec3 warm = vec3(1.06, 0.99, 0.88);
	vec3 cool = vec3(0.93, 0.97, 1.07);
	base *= mix(cool, warm, smoothstep(0.3, 0.7, n.y));
	// Canlılık: pigment doygunluğunu biraz artır
	float l = dot(base, vec3(0.299, 0.587, 0.114));
	return max(mix(vec3(l), base, pigment_vibrance), vec3(0.0));
}

vec3 wc_edge_pigment(vec3 base, vec3 normal, vec3 view, float amount) {
	float fres = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 2.4);
	// Kenarda koyulaşma + hafif doygunluk artışı
	vec3 pooled = base * base * 1.05;
	return mix(base, pooled, clamp(fres * amount, 0.0, 1.0));
}
