class_name FootprintRules
extends RefCounted


static func cells_at(unit: UnitState, anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if unit == null:
		return cells
	for dx in range(unit.footprint_size.x):
		for dy in range(unit.footprint_size.y):
			cells.append(anchor + Vector2i(dx, dy))
	return cells


static func nearest_cell_to(
	unit: UnitState,
	target: Vector2i,
	anchor: Vector2i,
	use_chebyshev: bool = false
) -> Vector2i:
	if unit == null:
		return target
	var best := anchor
	var best_distance := 999999
	for cell in cells_at(unit, anchor):
		var delta := cell - target
		var distance := maxi(absi(delta.x), absi(delta.y)) \
			if use_chebyshev else absi(delta.x) + absi(delta.y)
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


## A touching pair appears once regardless of how many footprint edges meet.
static func adjacent_units(state: GameState, unit: UnitState) -> Array[UnitState]:
	var result: Array[UnitState] = []
	var seen: Dictionary = {unit.uid: true}
	for cell in unit.occupied_cells():
		for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var other := state.get_unit_at(cell + step)
			if other == null or not other.alive or seen.has(other.uid):
				continue
			seen[other.uid] = true
			result.append(other)
	return result
