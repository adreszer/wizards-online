shader_type spatial;
// A fake light shaft: the open sides of a slanted prism from a window into the room,
// added onto what is behind (no real light, no shadows). Brightest at the window,
// gone at its far end, soft at its edges, and faded when the camera is inside it.
// WallWindow.set_daylight drives `shaft` (rgb colour, a strength) on the shared material.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 shaft : source_color = vec4(1.0, 0.92, 0.75, 0.0);

void fragment() {
	// UV.x: 0..1 across a side; UV.y: 0 at the window .. 1 at the far end.
	float edge = sin(UV.x * PI);
	float along = (1.0 - UV.y) * smoothstep(0.0, 0.12, UV.y);
	float facing = pow(abs(dot(NORMAL, VIEW)), 1.5);
	float near = smoothstep(0.4, 2.5, -VERTEX.z);
	ALBEDO = shaft.rgb * (shaft.a * edge * along * facing * near);
}
