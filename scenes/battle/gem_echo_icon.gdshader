shader_type canvas_item;
render_mode unshaded;

uniform vec4 echo_shadow : source_color = vec4(0.16, 0.07, 0.24, 1.0);
uniform vec4 echo_tint : source_color = vec4(0.68, 0.34, 0.88, 1.0);
uniform vec4 echo_highlight : source_color = vec4(0.92, 0.76, 1.0, 1.0);
uniform float pulse_speed : hint_range(0.1, 4.0) = 1.10;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 px = TEXTURE_PIXEL_SIZE * 1.35;
	float nearby_alpha = max(
		max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		max(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a)
	);
	float edge = max(nearby_alpha - base.a, 0.0);
	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 purple_value = mix(echo_shadow.rgb, echo_tint.rgb, smoothstep(0.05, 0.72, luma));
	purple_value = mix(purple_value, echo_highlight.rgb, smoothstep(0.72, 1.0, luma));
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float recolor_strength = 0.76 + pulse * 0.08;
	vec3 recolored = mix(base.rgb, purple_value, recolor_strength);
	COLOR = vec4(recolored + echo_highlight.rgb * edge * 0.28, max(base.a, edge * 0.42));
}
