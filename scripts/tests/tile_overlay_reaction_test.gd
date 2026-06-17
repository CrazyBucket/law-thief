extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Tile Overlay Reaction Test ===")
	_test_fire_ignites_existing_poison_fog()
	_test_poison_fog_enters_existing_fire()
	print("TILE_OVERLAY_REACTION_TEST_PASS")
	quit()


func _test_fire_ignites_existing_poison_fog() -> void:
	var state := GameState.new()
	var cell := Vector2i(2, 2)
	TileRules.create_poison_fog(state, cell, 2)
	TileRules.create_fire(state, cell, 2)
	_assert_toxic_smoke_only(state, cell, "fire should turn existing poison fog into toxic smoke")
	print("  [OK] fire + poison fog -> toxic smoke")


func _test_poison_fog_enters_existing_fire() -> void:
	var state := GameState.new()
	var cell := Vector2i(3, 2)
	TileRules.create_fire(state, cell, 2)
	TileRules.create_poison_fog(state, cell, 2)
	_assert_toxic_smoke_only(state, cell, "poison fog should turn existing fire into toxic smoke")
	print("  [OK] poison fog + fire -> toxic smoke")


func _assert_toxic_smoke_only(state: GameState, cell: Vector2i, message: String) -> void:
	var tile := state.get_tile(cell)
	assert(tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE), message)
	assert(not tile.has_modifier(Constants.TILE_MOD_FIRE), "toxic smoke reaction should consume fire")
	assert(not tile.has_modifier(Constants.TILE_MOD_POISON_FOG), "toxic smoke reaction should consume poison fog")
