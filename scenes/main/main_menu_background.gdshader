shader_type canvas_item;

uniform vec3 mist_teal : source_color = vec3(0.12, 0.72, 0.58);
uniform vec3 mist_violet : source_color = vec3(0.30, 0.22, 0.72);
uniform float motion_speed : hint_range(0.0, 1.0) = 0.16;
uniform float mist_strength : hint_range(0.0, 1.0) = 0.58;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	float t = TIME * motion_speed;
	vec2 centered = UV - vec2(0.5);
	float breathe = sin(t * 0.48) * 0.004;
	vec2 uv = centered * (0.955 - breathe) + vec2(0.5);
	uv += vec2(sin(t * 0.31), cos(t * 0.27)) * 0.004;
	vec4 base = texture(TEXTURE, uv);

	vec2 mist_uv = UV * vec2(2.2, 1.45);
	float cloud_a = fbm(mist_uv + vec2(t * 0.08, -t * 0.055));
	float cloud_b = fbm(mist_uv * 1.4 + vec2(-t * 0.05, t * 0.035) + 8.4);
	float ribbon = sin(UV.x * 7.0 - UV.y * 4.2 + t * 0.7 + cloud_a * 3.2) * 0.5 + 0.5;
	ribbon = smoothstep(0.55, 0.96, ribbon) * smoothstep(0.28, 0.82, cloud_b);
	float haze = smoothstep(0.48, 0.82, cloud_a) * (0.65 + 0.35 * sin(t * 0.42 + UV.x * 4.0));

	float rays = pow(max(0.0, sin(UV.x * 11.0 - UV.y * 2.8 + t * 0.9)), 7.0);
	rays *= smoothstep(0.04, 0.62, 1.0 - UV.y) * (0.55 + cloud_b * 0.45);
	vec3 mist = mist_teal * ribbon * 0.48 + mist_violet * haze * 0.34;
	mist += mix(mist_violet, mist_teal, UV.x) * rays * 0.16;
	float center_light = max(0.0, 1.0 - length((UV - vec2(0.5)) * vec2(1.05, 1.35)));
	vec3 color = base.rgb * (1.08 + center_light * 0.10);
	color += mist * mist_strength;
	COLOR = vec4(color, base.a);
}
