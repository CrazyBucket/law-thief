shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 beam_color : source_color = vec4(1.0, 0.95, 0.55, 1.0);
uniform float pulse = 0.0;
uniform float core_width = 0.34;

void fragment() {
	float y = abs(UV.y - 0.5) * 2.0;
	float core = smoothstep(core_width + 0.16, core_width, y);
	float halo = smoothstep(1.0, 0.12, y) * 0.42;
	float scan = 0.82 + 0.18 * sin((UV.x + pulse) * 36.0);
	COLOR = beam_color * (core + halo) * scan;
}
