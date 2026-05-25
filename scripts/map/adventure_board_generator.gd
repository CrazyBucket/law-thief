class_name AdventureBoardGenerator extends RefCounted

const _BoardMapGenerator := preload("res://scripts/map/board_map_generator.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")


static func build(matrix: Array, seed_value: int) -> GameState:
	var state := GameState.new()
	state.run_seed = seed_value
	state.encounter_id = "adventure_map"
	var gs: int = matrix.size()
	state.board_size = Vector2i(gs, gs)
	for x in range(gs):
		var col: Array = matrix[x]
		for y in range(col.size()):
			var node = col[y]
			var pos := Vector2i(x, y)
			var tile_id: String = _AdventureRoomDisplay.tile_id_for(node.room_type)
			var tile := TileState.create(pos, tile_id)
			tile.floor_variant = int(node.layer) % 3
			state.tiles[state.tile_key(pos)] = tile
	_BoardMapGenerator._compute_edge_masks(state)
	return state
