shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 cloud_color : source_color = vec4(0.28, 0.95, 0.36, 0.58);
uniform vec4 rim_color : source_color = vec4(0.76, 1.0, 0.58, 0.38);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float density : hint_range(0.1, 2.0) = 1.0;
uniform float seed = 0.0;
uniform float squash : hint_range(0.45, 1.5) = 0.72;

float hash(vec2 p) {
	return fract(sin(dot(p + vec2(seed, seed * 1.37), vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y /= squash;
	float r = length(p);
	float radius = mix(0.24, 0.98, progress);
	float body = 1.0 - smoothstep(max(0.0, radius - 0.42), radius, r);
	float outer_shell = 1.0 - smoothstep(max(0.0, radius - 0.06), radius + 0.06, r);
	float inner_shell = 1.0 - smoothstep(max(0.0, radius - 0.36), max(0.001, radius - 0.18), r);
	float edge = max(0.0, outer_shell - inner_shell);
	float n = noise(p * 4.0 + vec2(progress * 0.7, -progress * 0.45));
	float n2 = noise(p * 9.0 + vec2(-progress * 1.4, progress * 0.9));
	float puffs = smoothstep(0.26, 0.9, n * 0.72 + n2 * 0.42) * density;
	float fade = 1.0 - smoothstep(0.72, 1.0, progress);
	float alpha = clamp((body * (0.34 + puffs * 0.36) + edge * 0.28) * fade, 0.0, 0.92);
	vec3 color = mix(cloud_color.rgb, rim_color.rgb, clamp(edge + n2 * 0.2, 0.0, 1.0));
	COLOR = vec4(color, alpha * cloud_color.a);
}
