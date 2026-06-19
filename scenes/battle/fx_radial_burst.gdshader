shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 inner_color : source_color = vec4(1.0, 0.92, 0.42, 1.0);
uniform vec4 outer_color : source_color = vec4(1.0, 0.28, 0.08, 0.8);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float ring_width : hint_range(0.01, 0.3) = 0.085;
uniform float ray_count : hint_range(0.0, 32.0) = 12.0;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.45;
uniform float core_strength : hint_range(0.0, 1.0) = 0.28;
uniform float squash : hint_range(0.45, 1.4) = 0.78;
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n * 91.17) * 43758.5453123);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y /= squash;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float ring_r = mix(0.08, 0.92, progress);
	float ring = 1.0 - smoothstep(0.0, ring_width, abs(r - ring_r));
	float ray_wave = sin(angle * ray_count + progress * 15.0);
	float rays = pow(max(ray_wave, 0.0), 5.0) * (1.0 - smoothstep(0.18, 0.92, r)) * ray_strength;
	float core_radius = max(0.001, 0.34 * (1.0 - progress));
	float core = (1.0 - smoothstep(0.0, core_radius, r)) * core_strength;
	float vignette = 1.0 - smoothstep(0.18, 1.05, r);
	float fade = 1.0 - smoothstep(0.72, 1.0, progress);
	vec3 color = mix(outer_color.rgb, inner_color.rgb, clamp(ring + core, 0.0, 1.0));
	float alpha = clamp((ring + rays * ring + core) * vignette * fade, 0.0, 1.0);
	COLOR = vec4(color, alpha);
}
