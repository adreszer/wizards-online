shader_type spatial;
render_mode cull_disabled;
// Stone wall material for wall_plain.glb (replaces its imported BakedMaterial).
//
// Castle lights cast no shadows, so a torch in the next room would light every
// stone face pointing its way, including the bevelled stone sides at module
// seams, which then glow like cracks letting light through. The wall is a thin
// slab: a light only counts when it is on the same side of the wall's plane
// (mesh-local XY) as the camera. Everything else is ordinary PBR shading.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// glTF packing: roughness in G, metallic in B.
uniform sampler2D metallic_roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 viewer_side;

void vertex() {
	vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	float side = camera_local.z >= 0.0 ? 1.0 : -1.0;
	viewer_side = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, side, 0.0)).xyz);
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	vec4 mr = texture(metallic_roughness_texture, UV);
	ROUGHNESS = mr.g;
	METALLIC = mr.b;
}

void light() {
	float same_side = smoothstep(-0.02, 0.02, dot(LIGHT, viewer_side));
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 radiance = LIGHT_COLOR * ATTENUATION * same_side * n_dot_l;
	DIFFUSE_LIGHT += radiance / PI;

	vec3 h = normalize(VIEW + LIGHT);
	float n_dot_h = clamp(dot(NORMAL, h), 0.0, 1.0);
	float n_dot_v = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
	float l_dot_h = clamp(dot(LIGHT, h), 0.0, 1.0);
	float a = max(ROUGHNESS * ROUGHNESS, 1e-3);
	float a2 = a * a;
	float d_term = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	float distribution = a2 / (PI * d_term * d_term);
	float k = a * 0.5;
	float visibility = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	vec3 fresnel = f0 + (1.0 - f0) * pow(1.0 - l_dot_h, 5.0);
	SPECULAR_LIGHT += distribution * visibility * fresnel * radiance * SPECULAR_AMOUNT;
}
