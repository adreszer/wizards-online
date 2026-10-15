// Map relief of the grounds, drawn on a rect that covers the terrain grid
// (Terrain.extent()). Heights come as Terrain.height_image() (R low byte, G high
// byte); the splat map tints land (R grass, G rock, B path, A sand), water lies
// below water_level, with hill shading and faint 10 m contours, in muted inks.
shader_type canvas_item;

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 grid_size;      // samples (size_x, size_z)
uniform vec2 extent_size;    // metres covered by the grid
uniform vec2 splat_scale;    // grid metres / splat metres
uniform float h_min;
uniform float h_scale;
uniform float water_level;

float sample_q(ivec2 at) {
	vec4 c = texelFetch(heights, clamp(at, ivec2(0), ivec2(grid_size) - 1), 0);
	return floor(c.r * 255.0 + 0.5) + floor(c.g * 255.0 + 0.5) * 256.0;
}

// Bilinear by hand: the bytes must be decoded before they are blended.
float height_at(vec2 uv) {
	vec2 f = uv * (grid_size - 1.0);
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	float a = mix(sample_q(i), sample_q(i + ivec2(1, 0)), t.x);
	float b = mix(sample_q(i + ivec2(0, 1)), sample_q(i + ivec2(1, 1)), t.x);
	return h_min + mix(a, b, t.y) * h_scale;
}

void fragment() {
	vec2 texel = 1.0 / grid_size;
	float h = height_at(UV);
	float hx = height_at(UV + vec2(texel.x, 0.0)) - height_at(UV - vec2(texel.x, 0.0));
	float hz = height_at(UV + vec2(0.0, texel.y)) - height_at(UV - vec2(0.0, texel.y));
	vec2 metres_per_texel = extent_size * texel * 2.0;
	vec3 n = normalize(vec3(-hx / metres_per_texel.x, 1.0, -hz / metres_per_texel.y));
	float shade = clamp(dot(n, normalize(vec3(-0.6, 0.8, -0.5))) * 1.15, 0.55, 1.15);

	vec4 w = texture(splat, UV * splat_scale);
	float total = w.r + w.g + w.b + w.a;
	// Cells the generator left unpainted (river beds, under the castle) read as grass.
	w = total > 0.01 ? w / total : vec4(1.0, 0.0, 0.0, 0.0);
	vec3 land = w.r * vec3(0.45, 0.53, 0.32) + w.g * vec3(0.56, 0.54, 0.49) + w.b * vec3(0.72, 0.62, 0.44) + w.a * vec3(0.78, 0.72, 0.53);
	land *= shade;
	float contour = abs(fract(h / 10.0 + 0.5) - 0.5) * 10.0;
	float line_w = max(fwidth(h), 0.05);
	land = mix(land * 0.82, land, smoothstep(0.0, line_w * 1.5, contour));

	float depth = clamp((water_level - h) / 12.0, 0.0, 1.0);
	vec3 water = mix(vec3(0.42, 0.56, 0.62), vec3(0.22, 0.35, 0.46), depth);
	float wet = smoothstep(-0.15, 0.15, water_level - h);
	COLOR = vec4(mix(land, water, wet), 1.0);
}
