// Lake and river water: dark, slightly see-through, with moving ripples for the moon to
// glint on. No refraction or reflection probes (kept cheap until the lighting pass).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform vec3 deep_colour : source_color = vec3(0.03, 0.07, 0.10);
uniform vec3 shallow_colour : source_color = vec3(0.07, 0.15, 0.18);
uniform float alpha_amount = 0.86;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * 0.25;
	float t = TIME * 0.35;
	float e = 0.08;
	float h0 = vnoise(p + vec2(t, t * 0.6)) + 0.5 * vnoise(p * 2.3 - vec2(t * 0.8, -t));
	float hx = vnoise(p + vec2(e, 0) + vec2(t, t * 0.6)) + 0.5 * vnoise((p + vec2(e, 0)) * 2.3 - vec2(t * 0.8, -t));
	float hz = vnoise(p + vec2(0, e) + vec2(t, t * 0.6)) + 0.5 * vnoise((p + vec2(0, e)) * 2.3 - vec2(t * 0.8, -t));
	vec3 nw = normalize(vec3(-(hx - h0) / e * 0.18, 1.0, -(hz - h0) / e * 0.18));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_colour, shallow_colour, fres);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	ALPHA = mix(alpha_amount, 1.0, fres);
}
