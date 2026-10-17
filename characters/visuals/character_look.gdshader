shader_type spatial;
// A character's look over its baked texture: the Meshy character textures paint
// every part in one atlas, so parts are told apart by colour. The violet trim
// takes the house colour (unsorted characters keep it), skin is tinted toward the
// chosen tone, and the dark cloth is shaded toward the chosen robe colour. Normal,
// roughness and metallic maps behave as in the imported StandardMaterial3D.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
// House trim: the colour, and 0 (keep the violet) … 1 (fully the house colour).
uniform vec3 house_color : source_color = vec3(0.6, 0.4, 0.9);
uniform float house_amount = 0.0;
// Skin tone as a multiplier on the painted skin (white = as painted).
uniform vec3 skin_tint : source_color = vec3(1.0);
// Robe cloth: a colour blended over the dark grey cloth by robe_amount.
uniform vec3 robe_color : source_color = vec3(0.2);
uniform float robe_amount = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	vec3 hsv = rgb2hsv(base);
	// Violet trim: hue around 0.70–0.80, clearly saturated.
	float violet = smoothstep(0.62, 0.68, hsv.x) * (1.0 - smoothstep(0.82, 0.88, hsv.x)) * smoothstep(0.18, 0.3, hsv.y);
	vec3 house_hsv = rgb2hsv(house_color);
	vec3 trim = hsv2rgb(vec3(house_hsv.x, clamp(hsv.y * 0.6 + house_hsv.y * 0.5, 0.0, 1.0), hsv.z * (0.55 + house_hsv.z * 0.75)));
	base = mix(base, trim, violet * house_amount);
	// Skin: warm hue (0.03–0.11), light, moderately saturated.
	float skin = smoothstep(0.0, 0.03, hsv.x) * (1.0 - smoothstep(0.1, 0.13, hsv.x)) * smoothstep(0.18, 0.28, hsv.y) * (1.0 - smoothstep(0.62, 0.75, hsv.y)) * smoothstep(0.5, 0.65, hsv.z);
	base = mix(base, base * skin_tint, skin);
	// Cloth: dark and nearly grey.
	// (Values are linear: the painted charcoal cloth sits near 0.05.)
	float cloth = (1.0 - smoothstep(0.25, 0.35, hsv.y)) * smoothstep(0.01, 0.025, hsv.z) * (1.0 - smoothstep(0.18, 0.28, hsv.z)) * (1.0 - violet);
	base = mix(base, robe_color * clamp(hsv.z / 0.05, 0.0, 3.0), cloth * robe_amount);
	ALBEDO = base;
	if (has_orm) {
		vec4 orm = texture(orm_texture, UV);
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	} else {
		ROUGHNESS = 0.8;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
}
