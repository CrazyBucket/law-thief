shader_type canvas_item;
render_mode unshaded;

uniform vec4 ice_tint : source_color = vec4(0.68, 0.90, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.90, 0.98, 1.0, 1.0);
uniform vec4 unit_tint : source_color = vec4(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.78;
uniform float rim_width : hint_range(1.0, 3.0) = 1.6;
uniform float phase = 0.0;


float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 blend = local * local * (3.0 - 2.0 * local);
	float bottom = mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), blend.x);
	float top = mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), blend.x);
	return mix(bottom, top, blend.y);
}


float fbm(vec2 point) {
	float total = 0.0;
	float weight = 0.55;
	for (int octave = 0; octave < 4; octave++) {
		total += value_noise(point) * weight;
		point = point * 2.03 + vec2(17.3, 9.2);
		weight *= 0.5;
	}
	return total;
}


void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 pixel = TEXTURE_PIXEL_SIZE * rim_width;
	float alpha_left = texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a;
	float alpha_right = texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a;
	float alpha_up = texture(TEXTURE, UV - vec2(0.0, pixel.y)).a;
	float alpha_down = texture(TEXTURE, UV + vec2(0.0, pixel.y)).a;
	float neighbor_max = max(max(alpha_left, alpha_right), max(alpha_up, alpha_down));
	float neighbor_min = min(min(alpha_left, alpha_right), min(alpha_up, alpha_down));
	float outer_rim = clamp(neighbor_max - base.a, 0.0, 1.0);
	float inner_rim = clamp(base.a - neighbor_min, 0.0, 1.0);
	if (base.a <= 0.001 && outer_rim <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec3 tinted = base.rgb * unit_tint.rgb;
		float luminance = dot(tinted, vec3(0.299, 0.587, 0.114));
		vec3 cold = mix(tinted, ice_tint.rgb * (0.78 + luminance * 0.28), tint_strength);
		vec2 frost_uv = UV * 7.0 + vec2(phase * 3.1, -phase * 1.7);
		vec2 warp = vec2(
			fbm(frost_uv + vec2(2.4, 7.1)),
			fbm(frost_uv + vec2(8.3, 1.6))
		);
		float frost = fbm(frost_uv + warp * 2.2);
		float vein_field = fbm(frost_uv * 1.9 + warp * 3.4);
		float frost_veins = 1.0 - smoothstep(0.045, 0.13, abs(vein_field - 0.48));
		float frost_bloom = smoothstep(0.53, 0.82, frost);
		float shimmer = smoothstep(
			0.72,
			0.92,
			fbm(frost_uv * 2.7 + warp + vec2(TIME * 0.34, -TIME * 0.19))
		);
		cold += rim_color.rgb * (frost_bloom * 0.13 + frost_veins * 0.15 + shimmer * 0.22) * base.a;
		float rim = clamp(outer_rim + inner_rim * 0.72, 0.0, 1.0);
		vec3 frozen_color = mix(cold, rim_color.rgb, rim);
		float frozen_alpha = max(base.a * unit_tint.a * 0.96, outer_rim * 0.92);
		COLOR = vec4(frozen_color, frozen_alpha);
	}
}
