shader_type canvas_item;
render_mode unshaded;

uniform float edge_blur_width : hint_range(0.02, 0.25) = 0.105;
uniform float right_feather : hint_range(0.08, 0.4) = 0.24;
uniform float blur_radius_px : hint_range(1.0, 18.0) = 8.0;
uniform float motion_amount : hint_range(0.0, 0.08) = 0.018;
uniform vec4 atmosphere_tint : source_color = vec4(0.88, 0.84, 1.0, 1.0);

void fragment() {
	vec4 vertex_color = COLOR;
	float wave = sin(TIME * 0.52 + UV.y * 8.5) * 0.55
		+ sin(TIME * 0.31 - UV.y * 15.0) * 0.45;
	float moving_edge = motion_amount * wave;
	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float blur_mask = 1.0 - smoothstep(0.012, edge_blur_width + moving_edge, edge_distance);
	float right_distance = 1.0 - UV.x;
	float right_blur = 1.0 - smoothstep(0.025, right_feather + moving_edge, right_distance);
	blur_mask = max(blur_mask, right_blur);

	vec2 spread = TEXTURE_PIXEL_SIZE * blur_radius_px * (0.28 + blur_mask * 0.92);
	vec4 center = texture(TEXTURE, UV) * 4.0;
	vec4 cardinal = texture(TEXTURE, clamp(UV + vec2(spread.x, 0.0), vec2(0.0), vec2(1.0)))
		+ texture(TEXTURE, clamp(UV - vec2(spread.x, 0.0), vec2(0.0), vec2(1.0)))
		+ texture(TEXTURE, clamp(UV + vec2(0.0, spread.y), vec2(0.0), vec2(1.0)))
		+ texture(TEXTURE, clamp(UV - vec2(0.0, spread.y), vec2(0.0), vec2(1.0)));
	vec4 diagonal = texture(TEXTURE, clamp(UV + spread, vec2(0.0), vec2(1.0)))
		+ texture(TEXTURE, clamp(UV - spread, vec2(0.0), vec2(1.0)))
		+ texture(TEXTURE, clamp(UV + vec2(spread.x, -spread.y), vec2(0.0), vec2(1.0)))
		+ texture(TEXTURE, clamp(UV + vec2(-spread.x, spread.y), vec2(0.0), vec2(1.0)));
	vec4 softened = (center + cardinal * 2.0 + diagonal) / 16.0;
	vec4 color = mix(texture(TEXTURE, UV), softened, blur_mask * 0.96);

	float left_alpha = smoothstep(0.0, 0.032 + moving_edge * 0.3, UV.x);
	float top_alpha = smoothstep(0.0, 0.026, UV.y);
	float bottom_alpha = smoothstep(0.0, 0.032, 1.0 - UV.y);
	float right_alpha = smoothstep(0.0, right_feather + moving_edge, right_distance);
	color.rgb *= atmosphere_tint.rgb;
	color.a *= left_alpha * top_alpha * bottom_alpha * right_alpha;
	COLOR = color * vertex_color;
}
