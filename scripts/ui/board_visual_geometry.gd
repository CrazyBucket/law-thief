class_name BoardVisualGeometry
extends RefCounted


static func in_bounds(pos: Vector2i, board_size: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < board_size.x and pos.y < board_size.y


static func neighbors4(pos: Vector2i) -> Array[Vector2i]:
	return [pos + Vector2i.RIGHT, pos + Vector2i.LEFT, pos + Vector2i.DOWN, pos + Vector2i.UP]


static func cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) <= radius:
				cells.append(center + Vector2i(dx, dy))
	return cells
