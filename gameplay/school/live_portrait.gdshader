// A live portrait's canvas: the sitter's viewport given the paintings' oil varnish
// (tools/render_portrait.py): softened, warmed, lower blues, a gentle contrast curve
// and a vignette, then lit by the room like the painted canvas it covers. `fade`
// cross-fades from the painting, so the canvas stays opaque.
shader_type spatial;
render_mode cull_back;

// The viewport holds linear values; the varnish works in display space, as the
// numpy one did on the rendered PNG.
uniform sampler2D sitter : filter_linear;
uniform sampler2D painting : source_color, filter_linear_mipmap;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

vec3 display(vec2 uv) {
	return pow(max(texture(sitter, uv).rgb, vec3(0.0)), vec3(1.0 / 2.2));
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(sitter, 0));
	vec3 c = display(UV);
	vec3 soft = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			soft += display(UV + vec2(float(x), float(y)) * px);
		}
	}
	c = mix(c, soft / 9.0, 0.45);
	c = clamp(c * vec3(1.02, 0.95, 0.80), 0.0, 1.0);
	c = c * c * (3.0 - 2.0 * c) * 0.35 + c * 0.65;
	vec2 d = vec2((UV.x - 0.5) * 2.0, (UV.y - 0.55) * 2.0);
	c *= clamp(1.0 - 0.45 * pow(clamp(length(d) - 0.45, 0.0, 1.0), 1.4), 0.0, 1.0);
	ALBEDO = mix(texture(painting, UV).rgb, pow(c, vec3(2.2)), fade);
	ROUGHNESS = 0.65;
}
