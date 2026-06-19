shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 core_color : source_color = vec4(0.72, 0.96, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.18, 0.58, 1.0, 0.95);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float jitter : hint_range(0.0, 0.35) = 0.16;
uniform float thickness : hint_range(0.005, 0.12) = 0.028;
uniform float branch_strength : hint_range(0.0, 1.0) = 0.55;

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453123);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), u);
}

float bolt_center(float x) {
	float jag = noise1(x * 13.0) - 0.5;
	float fine = noise1(x * 31.0 + 9.0) - 0.5;
	float wave = sin((x * 5.7 + seed) * 6.28318) * 0.14;
	float taper = smoothstep(0.0, 0.08, x) * (1.0 - smoothstep(0.86, 1.0, x));
	return 0.5 + (jag * 1.5 + fine * 0.55 + wave) * jitter * taper;
}

float branch_mask(vec2 uv, float start_x, float slope, float length, float side) {
	float local_x = uv.x - start_x;
	float gate = smoothstep(0.0, 0.018, local_x) * (1.0 - smoothstep(length - 0.05, length, local_x));
	float y = bolt_center(start_x) + side * slope * local_x;
	float d = abs(uv.y - y);
	return (1.0 - smoothstep(0.0, thickness * 1.2, d)) * gate;
}

void fragment() {
	vec2 uv = UV;
	float reveal = smoothstep(0.0, 0.08, progress - uv.x);
	float fade_tail = smoothstep(progress - 0.42, progress - 0.16, uv.x);
	float active = reveal * fade_tail;
	float center_y = bolt_center(uv.x);
	float dist = abs(uv.y - center_y);
	float core = 1.0 - smoothstep(0.0, thickness, dist);
	float glow = (1.0 - smoothstep(0.0, thickness * 5.6, dist)) * 0.42;
	float branch = 0.0;
	branch += branch_mask(uv, 0.18 + hash(4.0) * 0.08, 0.95 + hash(8.0) * 0.5, 0.22, -1.0);
	branch += branch_mask(uv, 0.36 + hash(12.0) * 0.07, 0.82 + hash(14.0) * 0.48, 0.19, 1.0);
	branch += branch_mask(uv, 0.58 + hash(16.0) * 0.07, 0.70 + hash(18.0) * 0.42, 0.17, -1.0);
	branch *= branch_strength;
	float edge_flash = (1.0 - smoothstep(0.0, 0.035, abs(uv.x - progress))) * 0.8;
	float alpha = clamp((glow + core + branch + edge_flash) * active, 0.0, 1.0);
	vec3 color = glow_color.rgb * (glow + branch * 0.7) + core_color.rgb * (core * 1.35 + edge_flash + branch);
	COLOR = vec4(color, alpha);
}
