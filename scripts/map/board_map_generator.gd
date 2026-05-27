class_name BoardMapGenerator
extends RefCounted

const _NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]


static func build(state: GameState, encounter: Dictionary) -> void:
	state.tiles.clear()
	for y in range(state.board_size.y):
		for x in range(state.board_size.x):
			var pos := Vector2i(x, y)
			var tile := TileState.create(pos, Constants.TILE_FLOOR)
			state.tiles[state.tile_key(pos)] = tile
	for tile_data in encounter.get("tiles", []):
		var pos: Vector2i = tile_data.get("pos", Vector2i.ZERO)
		if not BoardUtils.in_bounds(state, pos):
			continue
		var tile_id: String = tile_data.get("tile_id", Constants.TILE_FLOOR)
		var slot_defs: Array = tile_data.get("slots", [])
		if not slot_defs.is_empty():
			# 带槽位的特殊地块（祭坛、机关柱等）
			var slotted_tile := TileState.create_with_slots(pos, tile_id, slot_defs)
			state.tiles[state.tile_key(pos)] = slotted_tile
		else:
			var placed: TileState = state.tiles[state.tile_key(pos)]
			placed.tile_id = tile_id
			placed._init_ground_tags()
	_apply_floor_variation(state, encounter)
	_compute_edge_masks(state)


static func _apply_floor_variation(state: GameState, encounter: Dictionary) -> void:
	var seed_value: int = int(encounter.get("floor_seed", state.run_seed))
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		if tile.tile_id != Constants.TILE_FLOOR:
			continue
		var roll: int = _hash_cell(tile.pos, seed_value) % 100
		tile.floor_variant = roll % 3


static func _compute_edge_masks(state: GameState) -> void:
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		var mask: int = 0
		for i in range(_NEIGHBOR_DIRS.size()):
			var neighbor_pos: Vector2i = tile.pos + _NEIGHBOR_DIRS[i]
			if not BoardUtils.in_bounds(state, neighbor_pos):
				continue
			var neighbor: TileState = state.tiles[state.tile_key(neighbor_pos)]
			if neighbor.tile_id == tile.tile_id:
				mask |= 1 << i
		tile.edge_mask = mask
		tile.edge_variant = _edge_variant_name(tile.tile_id, mask)


static func _edge_variant_name(tile_id: String, mask: int) -> String:
	if tile_id == Constants.TILE_WATER:
		return "water_%d" % mask
	if tile_id == Constants.TILE_SPIKE:
		return "spike_%d" % mask
	return "floor_%d" % mask


static func _hash_cell(pos: Vector2i, seed_value: int) -> int:
	return absi(hash(str(seed_value, pos.x, pos.y)))
