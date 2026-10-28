shader_type spatial;
// A fake light shaft: the open sides of a prism from a window into the room, added onto
// what is behind (no real light, no shadows). The mesh is flat in the window plane; its
// far end (UV.y = 1) is pushed along the light's direction here, so every shaft slants
// with the sun (or moon). Only windows the light shines into show one: the light's
// horizontal direction has to point into the room (+Z of the window module).
// Brightest at the window, gone at its far end, soft at its edges, faded near the camera.
// DayNightCycle → WallWindow.set_shaft_light sets both uniforms on the shared material;
// WallWindow.shaft_reach and shaft_facing mirror the maths for tests.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec4 shaft : source_color = vec4(1.0, 0.92, 0.75, 0.0);
// The direction the light travels (from the sun or moon toward the ground), world space.
uniform vec3 light_dir = vec3(0.0, -0.7, 0.7);
// Vertical drop of a shaft and its longest reach, metres.
uniform float drop = 3.6;
uniform float max_reach = 7.0;

varying float facing_k;

void vertex() {
	vec3 inward = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 l = normalize(light_dir);
	vec2 lh = l.xz;
	float h = length(lh);
	float into = h > 0.001 ? dot(lh / h, normalize(inward.xz)) : 0.0;
	facing_k = smoothstep(0.2, 0.45, into) * step(l.y, -0.02);
	float reach = min(drop / max(-l.y, 0.05), max_reach);
	VERTEX += UV.y * l * reach;
	if (facing_k < 0.001) {
		// Not lit: collapse the shaft to a point, so it costs no fill.
		VERTEX = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	}
}

void fragment() {
	// UV.x: 0..1 across a side; UV.y: 0 at the window .. 1 at the far end.
	float edge = sin(UV.x * PI);
	float along = (1.0 - UV.y) * smoothstep(0.0, 0.12, UV.y);
	float near = smoothstep(0.4, 2.5, -VERTEX.z);
	ALBEDO = shaft.rgb * (shaft.a * facing_k * edge * along * near);
}
