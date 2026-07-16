shader_type canvas_item;
render_mode unshaded;

uniform sampler2D mask_texture : source_color, filter_linear, repeat_disable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 viewport_size = vec2(1600.0, 900.0);
uniform vec2 center = vec2(0.5, 0.5);
uniform float mask_aspect : hint_range(0.05, 20.0) = 1.0;
uniform float maximum_scale : hint_range(0.1, 4.0) = 1.15;
uniform float fill_start : hint_range(0.25, 0.9) = 0.6;
uniform int mask_channel : hint_enum("Alpha", "Luminance", "Inverse Luminance") = 0;
uniform vec4 cover_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);


float sample_mask(vec4 sample_color) {
	if (mask_channel == 1) {
		return dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
	}
	if (mask_channel == 2) {
		return 1.0 - dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
	}
	return sample_color.a;
}


void fragment() {
	float safe_height = max(viewport_size.y, 1.0);
	float viewport_aspect = max(viewport_size.x / safe_height, 0.05);
	float reveal_progress = 1.0 - progress;
	float shape_progress = smoothstep(0.0, fill_start, reveal_progress);
	float stamp_scale = mix(0.055, maximum_scale, shape_progress);

	vec2 centered_uv = UV - center;
	vec2 mask_uv = centered_uv;
	mask_uv.x *= viewport_aspect / max(mask_aspect, 0.05);
	mask_uv = mask_uv / max(stamp_scale, 0.001) + vec2(0.5);
	float inside_mask = (
		step(0.0, mask_uv.x) * step(mask_uv.x, 1.0)
		* step(0.0, mask_uv.y) * step(mask_uv.y, 1.0)
	);
	float mask_value = sample_mask(texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))));
	float silhouette_window = step(0.5, mask_value) * inside_mask;
	silhouette_window *= step(0.001, reveal_progress);

	vec2 radial_uv = centered_uv;
	radial_uv.x *= viewport_aspect;
	float maximum_radius = length(vec2(max(viewport_aspect, 1.0) * 0.5, 0.5));
	float open_progress = smoothstep(fill_start, 1.0, reveal_progress);
	float open_radius = open_progress * maximum_radius;
	float radial_window = step(length(radial_uv), open_radius);
	radial_window *= step(fill_start, reveal_progress);

	float open_mask = max(silhouette_window, radial_window);
	COLOR = vec4(cover_color.rgb, (1.0 - open_mask) * cover_color.a);
}
