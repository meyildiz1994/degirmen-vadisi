shader_type spatial;
// Otomatik hedeflenen kaynağın çevresindeki yumuşak, nefes alan ışık çizgisi.
// Ters kabuk (inverted hull): nesnenin arkasında, normal boyunca şişirilmiş yüzeyler.
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.46, 0.62);
uniform float width = 0.05;
uniform float pulse_speed = 3.2;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	float pulse = 0.72 + 0.28 * sin(TIME * pulse_speed);
	ALBEDO = glow_color.rgb;
	ALPHA = glow_color.a * pulse;
}
