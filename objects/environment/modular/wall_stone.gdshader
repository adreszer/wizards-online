shader_type spatial;
render_mode cull_disabled;
// Stone wall material for wall_plain.glb (replaces its imported BakedMaterial).
//
// Castle lights cast no shadows, so a torch in the next room would light every
// stone face pointing its way, including the bevelled stone sides at module
// seams, which then glow like cracks letting light through. The wall is a thin
// slab: a light only counts when it is on the same side of the wall's plane
// (mesh-local XY) as the camera. Everything else is ordinary PBR shading.

#include "res://objects/environment/modular/wall_stone.gdshaderinc"

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
