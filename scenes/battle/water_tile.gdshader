shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.58431375, 0.9137255, 0.98039216, 1.0);
uniform sampler2D water_bottom : repeat_enable, filter_linear;
uniform sampler2D water_top : repeat_enable, filter_linear;
uniform float texture_scale = 0.0015;
uniform vec4 scroll = vec4(-0.01, 0.05, -0.10, -0.01);
uniform vec2 distort_scale = vec2(1.0, 1.0);
uniform float distort_strength : hint_range(0.0, 0.08) = 0.015;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Same coordinate, scroll, and sine-distortion structure as Mewgenics water.shader.
	vec2 screen_scale = vec2(2.0, 9.0 / 8.0);
	vec2 tex_scale = vec2(3.0, 6.0);
	vec2 coord = world_pos * texture_scale * screen_scale * tex_scale * 0.5;
	vec2 distortion_coord = coord * 2.7215;
	vec2 bottom_p = distortion_coord * distort_scale.x;
	vec2 top_p = distortion_coord * distort_scale.y;
	vec2 bottom_distort = vec2(
		sin(bottom_p.y + TIME * 0.5) + sin(bottom_p.y * 1.8 + TIME * 0.75) + sin(bottom_p.y * 2.9 + TIME * 0.25),
		sin(bottom_p.x + TIME * 0.25) + sin(bottom_p.x * 1.4 + TIME * 1.45) + sin(bottom_p.x * 2.5 + TIME * 0.5)
	) * distort_strength * 0.5;
	vec2 top_distort = vec2(
		sin(top_p.y + TIME * 0.5) + sin(top_p.y * 1.8 + TIME * 0.75) + sin(top_p.y * 2.9 + TIME * 0.25),
		sin(top_p.x + TIME * 0.25) + sin(top_p.x * 1.4 + TIME * 1.45) + sin(top_p.x * 2.5 + TIME * 0.5)
	) * distort_strength * 0.5;
	vec4 bottom = texture(water_bottom, coord + scroll.xy * TIME * 0.15 + bottom_distort);
	vec4 top = texture(water_top, coord + scroll.zw * TIME * 0.15 + top_distort);
	vec3 texture_color = bottom.rgb * (1.0 - top.a) + top.rgb;
	float luminance = smoothstep(0.16, 0.72, dot(texture_color, vec3(0.299, 0.587, 0.114)));
	vec3 tinted = base_color.rgb * mix(0.72, 1.22, luminance);
	COLOR = vec4(tinted, base_color.a);
}
