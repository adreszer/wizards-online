shader_type spatial;
render_mode cull_disabled;
// wall_stone with a window opening cut out of it (used by wall_window.tscn).
// The opening is a pointed arch in the wall module's own space (origin at the
// bottom centre of the 4 m module, wall plane XY): straight jambs from `bottom`
// to `spring`, then two circular arcs meeting at `apex`. WallWindow sets the
// instance uniforms from its window's outline and builds the matching stone
// reveal, so the cut and the reveal can never disagree.

#include "res://objects/environment/modular/wall_stone.gdshaderinc"

// Mesh-local → module space (the wrapper's Model node scale and offset).
instance uniform vec3 mesh_scale = vec3(1.0);
instance uniform vec3 mesh_offset = vec3(0.0);
// half width, bottom, spring, apex (m, module space); half width 0 = no opening.
instance uniform vec4 opening = vec4(0.0);

varying vec2 module_xy;

void vertex() {
	vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	float side = camera_local.z >= 0.0 ? 1.0 : -1.0;
	viewer_side = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, side, 0.0)).xyz);
	module_xy = (VERTEX * mesh_scale + mesh_offset).xy;
}

bool inside_opening(vec2 p) {
	float w = opening.x;
	if (w <= 0.0 || p.y < opening.y || abs(p.x) > w) {
		return false;
	}
	float dy = p.y - opening.z;
	if (dy <= 0.0) {
		return true;
	}
	float h = opening.w - opening.z;
	float c = (h * h - w * w) / (2.0 * w);   // arc centres sit at x = ±c on the springing line
	float r = w + c;
	float dx = abs(p.x) + c;
	return dx * dx + dy * dy <= r * r;
}

void fragment() {
	if (inside_opening(module_xy)) {
		discard;
	}
	ALBEDO = texture(albedo_texture, UV).rgb;
	vec4 mr = texture(metallic_roughness_texture, UV);
	ROUGHNESS = mr.g;
	METALLIC = mr.b;
}
