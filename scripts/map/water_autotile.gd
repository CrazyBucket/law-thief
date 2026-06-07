class_name WaterAutotile
extends RefCounted

const BACK_RIGHT := Vector2i(0, -1)
const FRONT_RIGHT := Vector2i(1, 0)
const FRONT_LEFT := Vector2i(0, 1)
const BACK_LEFT := Vector2i(-1, 0)

# Mewgenics-style corner state for this project:
# bit 1 = first adjacent edge exposed
# bit 2 = true inner corner only (both adjacent tiles are water, diagonal is not)
# bit 4 = second adjacent edge exposed
const SIDE_A := 1
const INNER_CORNER := 2
const SIDE_B := 4


static func states(pos: Vector2i, water: Dictionary) -> Vector4i:
	# Sprite 468: top, vertically mirrored bottom.
	# Sprite 469: right, horizontally mirrored left.
	return Vector4i(
		_corner_state(pos, water, BACK_RIGHT, BACK_LEFT),
		_corner_state(pos, water, BACK_RIGHT, FRONT_RIGHT),
		_corner_state(pos, water, FRONT_RIGHT, FRONT_LEFT),
		_corner_state(pos, water, BACK_LEFT, FRONT_LEFT)
	)


static func _corner_state(pos: Vector2i, water: Dictionary, bit_one_dir: Vector2i, bit_four_dir: Vector2i) -> int:
	var bit_one_water := water.has(pos + bit_one_dir)
	var bit_four_water := water.has(pos + bit_four_dir)
	return (
		(SIDE_A if not bit_one_water else 0)
		| (INNER_CORNER if bit_one_water and bit_four_water and not water.has(pos + bit_one_dir + bit_four_dir) else 0)
		| (SIDE_B if not bit_four_water else 0)
	)


static func exposed_edge_count(water: Dictionary) -> int:
	var count := 0
	for pos: Vector2i in water:
		for direction in [BACK_RIGHT, FRONT_RIGHT, FRONT_LEFT, BACK_LEFT]:
			if not water.has(pos + direction):
				count += 1
	return count


static func inner_corner_count(water: Dictionary) -> int:
	var count := 0
	for pos: Vector2i in water:
		var value := states(pos, water)
		count += 1 if value.x == INNER_CORNER else 0
		count += 1 if value.y == INNER_CORNER else 0
		count += 1 if value.z == INNER_CORNER else 0
		count += 1 if value.w == INNER_CORNER else 0
	return count
