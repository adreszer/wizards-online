// The backdrop behind a window (UiRouter): the world as it was drawn, blurred from its
// mipmaps and dimmed toward `dim` (its alpha is how far).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 dim : source_color = vec4(0.04, 0.03, 0.02, 0.55);
uniform float lod = 3.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * exp2(lod);
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.36;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), lod).rgb * 0.16;
	COLOR = vec4(mix(c, dim.rgb, dim.a), 1.0);
}
