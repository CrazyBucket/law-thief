shader_type canvas_item;
render_mode unshaded;

uniform float sway_px : hint_range(0.0, 32.0) = 18.0;
uniform float vertical_px : hint_range(0.0, 12.0) = 0.0;
uniform float speed : hint_range(0.1, 3.0) = 1.4;
uniform float phase = 0.0;
uniform float tip_bias : hint_range(0.0, 1.0) = 1.0;
uniform float tip_power : hint_range(0.3, 3.0) = 1.6;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_boost : hint_range(0.2, 2.5) = 1.0;
uniform float saturation_boost : hint_range(0.0, 2.0) = 1.0;
uniform float alpha_breathe : hint_range(0.0, 0.3) = 0.0;

void vertex() {
	float tip = pow(max(1.0 - UV.y, 0.0), tip_power);
	float weight = mix(1.0, tip, tip_bias);
	float primary = sin(TIME * speed + phase + UV.x * 5.2);
	float secondary = sin(TIME * speed * 0.63 + phase * 1.7 + UV.x * 11.0);
	VERTEX.x += (primary + secondary * 0.24) * sway_px * weight;
	VERTEX.y += cos(TIME * speed * 0.71 + phase + UV.x * 3.7) * vertical_px * weight;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	base.rgb = mix(vec3(luma), base.rgb, saturation_boost) * tint.rgb;
	float breathe = 1.0 + sin(TIME * speed * 0.72 + phase) * alpha_breathe;
	base.a = clamp(base.a * tint.a * alpha_boost * breathe, 0.0, 1.0);
	COLOR = base;
}
