shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 danger_tint : source_color = vec4(0.62, 0.08, 0.11, 0.34);

void fragment() {
	vec2 edge_distance = min(UV, vec2(1.0) - UV);
	float nearest_edge = min(edge_distance.x, edge_distance.y);
	float edge_mask = 1.0 - smoothstep(0.0, 0.155, nearest_edge);
	float corner_weight = 1.0 - smoothstep(0.0, 0.42, length(UV - vec2(0.5)));
	float breath = 0.88 + sin(TIME * 5.2) * 0.12;
	float alpha = danger_tint.a * edge_mask * mix(1.0, 0.76, corner_weight) * breath * intensity;
	COLOR = vec4(danger_tint.rgb, alpha);
}
