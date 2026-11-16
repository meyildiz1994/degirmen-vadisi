shader_type spatial;
// Sel suyu: köpük dışındaki her yer yarı saydam, çamurlu su. Yüzeyden aşağı ve geriye doğru
// kayan beyaz akıntı izleri var, köşeler hafifçe dalgalanır.
// COLOR: yerel renk; çok açık (beyaza yakın) köşeler köpük sayılır ve akıntı izi almaz.
render_mode blend_mix, depth_draw_always, cull_disabled, specular_disabled, shadows_disabled;

uniform sampler2D paint_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 stroke_color : source_color = vec4(0.97, 0.95, 0.90, 0.8);
uniform vec3 sunset_glint : source_color = vec3(0.99, 0.80, 0.58);
uniform float flow_speed = 0.32;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
	float w = sin(VERTEX.x * 3.1 + TIME * 4.2) * 0.025 + sin(VERTEX.z * 4.3 + TIME * 3.3) * 0.02;
	VERTEX += NORMAL * w;
}

float band(float n, float c, float w) {
	return smoothstep(c - w, c, n) * (1.0 - smoothstep(c, c + w * 1.8, n));
}

void fragment() {
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	float foam = smoothstep(0.72, 0.8, min(COLOR.r, min(COLOR.g, COLOR.b)));
	float t = TIME * flow_speed;
	float n1 = texture(paint_noise, vec2(lp.x * 0.55, (lp.y + lp.z) * 0.22 + t)).r;
	float n2 = texture(paint_noise, vec2(lp.x * 0.9 + 0.37, (lp.y + lp.z) * 0.34 + t * 1.5)).r;
	float s = band(n1, 0.64, 0.03) + band(n2, 0.32, 0.025) * 0.7;
	col = mix(col, stroke_color.rgb, clamp(s, 0.0, 1.0) * stroke_color.a * (1.0 - foam));
	float wash = texture(paint_noise, lp.xz * 0.3 + vec2(t * 0.1)).r;
	col *= 0.9 + wash * 0.2;
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sunset_glint, fres * 0.22);
	ALBEDO = col;
	ALPHA = mix(0.86, 1.0, foam);
}
