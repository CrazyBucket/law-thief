shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.68, 0.82, 0.90, 0.34);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 px = TEXTURE_PIXEL_SIZE;
	float near_alpha = 0.0;
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	float halo = max(near_alpha - base.a, 0.0) * glow_strength;
	vec3 lit_rgb = base.rgb + glow_color.rgb * halo * glow_color.a;
	COLOR = vec4(lit_rgb, max(base.a, halo * glow_color.a));
}
