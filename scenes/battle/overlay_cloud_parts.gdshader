shader_type canvas_item;
render_mode unshaded;

uniform vec4 shadow_color : source_color = vec4(0.22, 0.34, 0.18, 1.0);
uniform vec4 mid_color : source_color = vec4(0.43, 0.64, 0.30, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.68, 0.84, 0.48, 1.0);
uniform float midpoint : hint_range(0.2, 0.8) = 0.52;
uniform float opacity : hint_range(0.0, 1.0) = 0.92;
uniform float breathe : hint_range(0.0, 0.2) = 0.06;
uniform float speed : hint_range(0.1, 2.0) = 0.7;
uniform float phase = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float lower = smoothstep(0.0, midpoint, luma);
	float upper = smoothstep(midpoint, 1.0, luma);
	vec3 palette = mix(shadow_color.rgb, mid_color.rgb, lower);
	palette = mix(palette, highlight_color.rgb, upper);
	float pulse = 1.0 + sin(TIME * speed + phase) * breathe;
	COLOR = vec4(palette, clamp(source.a * opacity * pulse, 0.0, 1.0));
}
