shader_type canvas_item;
render_mode unshaded;

uniform vec4 smoke_color : source_color = vec4(0.64, 0.16, 0.96, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.96, 0.68, 1.0, 1.0);
uniform float speed : hint_range(0.1, 2.0) = 0.78;
uniform float density : hint_range(0.1, 1.0) = 0.90;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float weight = 0.56;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * weight;
		p = p * 2.03 + vec2(1.7, -0.9);
		weight *= 0.48;
	}
	return total;
}

vec2 quadratic_bezier(vec2 a, vec2 b, vec2 c, float t) {
	vec2 ab = mix(a, b, t);
	vec2 bc = mix(b, c, t);
	return mix(ab, bc, t);
}

vec2 smoke_puff(vec2 p, vec2 center, float radius, float life, float noise) {
	vec2 local = p - center;
	local.x *= 1.08 - life * 0.16;
	local.y *= 0.82;
	float ragged_radius = radius * (0.84 + noise * 0.30);
	float distance_to_puff = length(local);
	float core = 1.0 - smoothstep(ragged_radius * 0.16, ragged_radius * 0.82, distance_to_puff);
	float haze = 1.0 - smoothstep(ragged_radius * 0.48, ragged_radius * 1.32, distance_to_puff);
	float life_fade = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.82, 1.0, life));
	return vec2(core, haze) * life_fade;
}

// Three detached puffs travel along each open path. Their positions change by
// several gameplay pixels per second, so the effect reads as smoke, never a line.
vec2 smoke_stream(
	vec2 p,
	vec2 start,
	vec2 control,
	vec2 finish,
	float phase,
	float time,
	float noise
) {
	vec2 smoke = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		float life = fract(time * 0.31 + phase + float(i) / 3.0);
		vec2 center = quadratic_bezier(start, control, finish, life);
		center.x += sin(time * 1.7 + life * 5.4 + phase * 7.0) * 0.045;
		center.y += cos(time * 1.1 + life * 4.2 + phase * 5.0) * 0.025;
		float radius = mix(0.120, 0.225, life);
		smoke += smoke_puff(p, center, radius, life, noise);
	}
	return smoke;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float time = TIME * speed;
	float noise = fbm(p * 4.1 + vec2(time * 0.28, -time * 0.34));

	vec2 left_smoke = smoke_stream(
		p,
		vec2(-0.16, 0.32),
		vec2(-0.70, 0.04),
		vec2(-0.34, -0.74),
		0.07,
		time,
		noise
	);
	vec2 right_smoke = smoke_stream(
		p,
		vec2(0.16, 0.32),
		vec2(0.70, 0.02),
		vec2(0.34, -0.72),
		0.53,
		time * 0.93,
		noise
	);

	float cores = left_smoke.x + right_smoke.x * 0.90;
	float haze = left_smoke.y + right_smoke.y * 0.88;
	float alpha = clamp(cores + haze * 0.62, 0.0, 1.0) * density;
	vec3 color = mix(smoke_color.rgb, highlight_color.rgb, clamp(cores * 0.62 + noise * 0.24, 0.0, 1.0));
	COLOR = vec4(color, alpha * COLOR.a);
}
