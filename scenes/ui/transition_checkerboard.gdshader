shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 grid_size = vec2(10.0, 6.0);
uniform float stagger : hint_range(0.0, 0.35) = 0.16;
uniform float edge_width : hint_range(0.0, 0.12) = 0.035;
uniform vec4 cover_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);


void fragment() {
	vec2 safe_grid = max(grid_size, vec2(1.0));
	vec2 cell_id = floor(UV * safe_grid);
	vec2 cell_uv = fract(UV * safe_grid);
	float parity = mod(cell_id.x + cell_id.y, 2.0);
	float diagonal = 0.5 * (
		cell_id.x / max(safe_grid.x - 1.0, 1.0)
		+ cell_id.y / max(safe_grid.y - 1.0, 1.0)
	);
	float delay = parity * stagger + diagonal * stagger * 0.55;
	float local_progress = smoothstep(delay, min(delay + 0.72, 1.0), progress);
	float half_size = local_progress * 0.54;
	float cell_distance = max(abs(cell_uv.x - 0.5), abs(cell_uv.y - 0.5));
	float body = step(cell_distance, half_size);
	float outer = step(cell_distance, half_size + edge_width);
	float edge = clamp(outer - body, 0.0, 1.0);
	vec3 color = mix(cover_color.rgb, edge_color.rgb, edge);
	float alpha = max(body, edge * edge_color.a) * cover_color.a;
	COLOR = vec4(color, alpha);
}
