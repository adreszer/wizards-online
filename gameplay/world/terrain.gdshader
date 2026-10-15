// Grounds terrain: blends grass, rock, path dirt and shore sand by the splat map that
// tools/grounds writes (R grass, G rock, B path, A sand), with world-space variation so
// large areas never look tiled. Rock uses the castle's stone texture, triplanar on X/Z.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 splat_origin;
uniform vec2 splat_size;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = (world_pos.xz - splat_origin) / splat_size;
	vec4 w = texture(splat, uv);
	float macro = fbm(world_pos.xz * 0.012);
	float micro = fbm(world_pos.xz * 0.35);
	vec3 grass = mix(vec3(0.16, 0.26, 0.09), vec3(0.27, 0.34, 0.13), macro) * (0.85 + 0.3 * micro);
	vec3 dirt = mix(vec3(0.30, 0.23, 0.15), vec3(0.40, 0.32, 0.21), micro);
	vec3 sand = mix(vec3(0.52, 0.47, 0.35), vec3(0.60, 0.55, 0.42), micro);
	vec3 n = abs(world_normal);
	vec3 rx = texture(rock_albedo, world_pos.zy * 0.12).rgb;
	vec3 rz = texture(rock_albedo, world_pos.xy * 0.12).rgb;
	vec3 ry = texture(rock_albedo, world_pos.xz * 0.12).rgb;
	vec3 rock = (rx * n.x + ry * n.y + rz * n.z) / (n.x + n.y + n.z) * vec3(0.85, 0.82, 0.78);
	float total = max(w.r + w.g + w.b + w.a, 0.001);
	ALBEDO = (grass * w.r + rock * w.g + dirt * w.b + sand * w.a) / total;
	ROUGHNESS = 0.92;
}
