class_name OldMageBoardVisuals
extends RefCounted


static func draw_pool_marker(canvas: CanvasItem, pos: Vector2, gem_size: float) -> void:
	canvas.draw_arc(
		pos + Vector2(0.0, gem_size * 0.04),
		gem_size * 0.48,
		0.0,
		TAU,
		18,
		Color(UiPalette.TEXT_GOLD, 0.84),
		maxf(1.0, gem_size * 0.1),
		true
	)
