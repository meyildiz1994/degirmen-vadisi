shader_type sky;
// Kodla üretilmiş gün batımı gökyüzü: yumuşak gradyan + kenarları dağınık bulutlar.

uniform vec3 zenith_color : source_color = vec3(0.30, 0.56, 0.92);
uniform vec3 mid_color : source_color = vec3(0.92, 0.70, 0.78);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.68, 0.38);
uniform vec3 paper_color : source_color = vec3(0.96, 0.92, 0.84);
uniform vec3 sun_color : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.92, 0.82);
uniform vec3 cloud_shadow : source_color = vec3(0.76, 0.68, 0.80);
uniform sampler2D cloud_noise : hint_default_white, filter_linear, repeat_enable;
uniform float cloud_coverage = 0.52;
uniform float cloud_drift = 0.0025;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.02, 0.22, h));
	col = mix(col, zenith_color, smoothstep(0.18, 0.75, h));
	// Ufkun altı kâğıt rengine solar
	col = mix(col, paper_color, smoothstep(0.02, -0.12, h));
	// Güneş parıltısı
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(sd, 6.0) * 0.35 + pow(sd, 60.0) * 0.4);
	// Bulutlar
	if (h > 0.0) {
		vec2 cuv = d.xz / (h + 0.18) * 0.22 + vec2(TIME * cloud_drift, 0.0);
		float n1 = texture(cloud_noise, cuv).r;
		float n2 = texture(cloud_noise, cuv * 2.9 + vec2(3.1, 7.7)).r;
		float n3 = texture(cloud_noise, cuv * 7.3 + vec2(1.7, 2.2)).r;
		float shape = n1 * 0.65 + n2 * 0.25 + n3 * 0.10;
		float c = smoothstep(cloud_coverage, cloud_coverage + 0.12, shape);
		// Dağınık, suluboya gibi kenarlar: kenarda hafif koyulaşma
		float rim = smoothstep(cloud_coverage, cloud_coverage + 0.05, shape) - smoothstep(cloud_coverage + 0.05, cloud_coverage + 0.14, shape);
		float fade = smoothstep(0.02, 0.18, h) * (1.0 - smoothstep(0.55, 0.95, h) * 0.6);
		vec3 ccol = mix(cloud_shadow, cloud_light, smoothstep(0.4, 0.8, n2));
		ccol = mix(ccol, sun_color, pow(sd, 4.0) * 0.35);
		col = mix(col, ccol, c * fade * 0.9);
		col = mix(col, cloud_shadow * 0.92, rim * fade * 0.25);
	}
	COLOR = col;
}
