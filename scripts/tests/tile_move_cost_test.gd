extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Tile Move Cost Test ===")
	_test_overlay_move_cost_matches_floor()
	_test_reachable_with_one_move_point()
	print("TILE_MOVE_COST_TEST_PASS")
	quit()


func _test_overlay_move_cost_matches_floor() -> void:
	var state := GameState.new()
	var floor := Vector2i(2, 2)
	var fog := Vector2i(3, 2)
	var fire := Vector2i(4, 2)
	var water := Vector2i(5, 2)
	state.tiles[state.tile_key(water)] = TileState.create(water, Constants.TILE_WATER)
	TileRules.create_poison_fog(state, fog, 2)
	TileRules.create_fire(state, fire, 2)
	assert(is_equal_approx(BoardUtils.tile_move_cost(state, floor), 1.0), "floor move cost should be 1")
	assert(is_equal_approx(BoardUtils.tile_move_cost(state, fog), 1.0), "poison fog move cost should be 1")
	assert(is_equal_approx(BoardUtils.tile_move_cost(state, fire), 1.0), "fire move cost should be 1")
	assert(is_equal_approx(BoardUtils.tile_move_cost(state, water), 2.0), "water move cost should be 2")
	print("  [OK] overlay move cost matches design")


func _test_reachable_with_one_move_point() -> void:
	var state := GameState.new()
	var start := Vector2i(2, 2)
	TileRules.create_poison_fog(state, Vector2i(3, 2), 2)
	TileRules.create_fire(state, Vector2i(2, 3), 2)
	state.tiles[state.tile_key(Vector2i(1, 2))] = TileState.create(Vector2i(1, 2), Constants.TILE_WATER)
	var reachable := BoardUtils.reachable_cells(state, start, 1)
	assert(Vector2i(3, 2) in reachable, "adjacent poison fog should be reachable with 1 move point")
	assert(Vector2i(2, 3) in reachable, "adjacent fire should be reachable with 1 move point")
	assert(not (Vector2i(1, 2) in reachable), "adjacent water should need 2 move points")
	print("  [OK] one move point reaches fog/fire but not water")
