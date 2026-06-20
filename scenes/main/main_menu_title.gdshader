shader_type canvas_item;

uniform vec3 glow_color : source_color = vec3(0.38, 1.0, 0.73);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * 2.5;
	float halo = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	halo += texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	halo += texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	halo += texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	halo = max(0.0, halo * 0.25 - tex.a);

	float sweep_pos = fract(TIME * 0.075);
	float diagonal = UV.x * 0.72 + (1.0 - UV.y) * 0.28;
	float sweep = smoothstep(0.0, 0.08, diagonal - sweep_pos) * (1.0 - smoothstep(0.08, 0.18, diagonal - sweep_pos));
	float pulse = 0.84 + sin(TIME * 1.25) * 0.10;
	vec3 lit = tex.rgb * pulse + vec3(0.36, 0.95, 0.72) * sweep * tex.a * 0.42;
	COLOR = vec4(lit + glow_color * halo * glow_strength, max(tex.a, halo * glow_strength));
}
