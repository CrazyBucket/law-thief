extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Prop Entity Test ===")
	_test_prop_blocks_movement()
	_test_prop_blocks_projectile()
	_test_prop_indestructible()
	print("PROP_ENTITY_TEST_PASS")
	quit()


func _test_prop_blocks_movement() -> void:
	var state := _mini_state()
	var prop := EntityState.create("prop_a", Constants.ENTITY_PROP, Vector2i(3, 3))
	prop.prop_sprite = "Post1_0"
	state.add_entity(prop)
	assert(not BoardUtils.is_passable(state, prop.pos), "prop cell should block movement")
	print("  [OK] prop blocks movement")


func _test_prop_blocks_projectile() -> void:
	var state := _mini_state()
	var prop := EntityState.create("prop_b", Constants.ENTITY_PROP, Vector2i(3, 2))
	state.add_entity(prop)
	var from := Vector2i(1, 2)
	var aim := Vector2i(5, 2)
	assert(
		BoardUtils.projectile_blocked_before_aim(state, from, aim),
		"projectile should stop at prop before aim"
	)
	var impact := BoardUtils.resolve_projectile_impact(state, from, aim)
	assert(impact == prop.pos, "impact should be prop cell, got %s" % impact)
	print("  [OK] prop blocks projectile")


func _test_prop_indestructible() -> void:
	var prop := EntityState.create("test_prop", Constants.ENTITY_PROP, Vector2i(0, 0))
	assert(prop.take_damage(99) == 0, "prop should ignore damage")
	assert(prop.alive, "prop should stay alive")
	print("  [OK] prop is indestructible")


func _mini_state() -> GameState:
	var state := GameState.new()
	state.board_size = Vector2i(8, 8)
	for y in range(8):
		for x in range(8):
			var pos := Vector2i(x, y)
			state.tiles[state.tile_key(pos)] = TileState.create(pos, Constants.TILE_FLOOR)
	return state
