extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Prop Entity Test ===")
	_test_prop_blocks_movement()
	_test_prop_blocks_projectile()
	_test_prop_indestructible()
	_test_barrel_blocks_movement_and_projectile()
	_test_barrel_has_hp_and_explodes_on_ranged_hit()
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


func _test_barrel_blocks_movement_and_projectile() -> void:
	var state := _mini_state()
	var barrel := EntityState.create("barrel_a", Constants.ENTITY_BARREL, Vector2i(3, 3))
	state.add_entity(barrel)
	assert(barrel.max_hp == Constants.BARREL_HP and barrel.hp == Constants.BARREL_HP, "barrel should start with hp")
	assert(not BoardUtils.is_passable(state, barrel.pos), "barrel cell should block movement")
	assert(
		BoardUtils.projectile_blocked_before_aim(state, Vector2i(1, 3), Vector2i(5, 3)),
		"barrel should block projectile before aim"
	)
	assert(
		BoardUtils.resolve_projectile_impact(state, Vector2i(1, 3), Vector2i(5, 3)) == barrel.pos,
		"barrel should be projectile impact cell"
	)
	print("  [OK] barrel blocks movement and projectile")


func _test_barrel_has_hp_and_explodes_on_ranged_hit() -> void:
	var state := _mini_state()
	var attacker := UnitState.new()
	attacker.uid = "attacker"
	attacker.team = Constants.TEAM_PLAYER
	attacker.pos = Vector2i(1, 3)
	attacker.hp = 20
	attacker.max_hp = 20
	attacker.base_attack = Constants.BARREL_HP
	attacker.alive = true
	state.register_unit(attacker)
	var victim := UnitState.new()
	victim.uid = "victim"
	victim.team = Constants.TEAM_ENEMY
	victim.pos = Vector2i(4, 3)
	victim.hp = 20
	victim.max_hp = 20
	victim.alive = true
	state.register_unit(victim)
	var barrel := EntityState.create("barrel_b", Constants.ENTITY_BARREL, Vector2i(3, 3))
	state.add_entity(barrel)
	var result := CombatRules.ranged_attack(state, attacker, victim.pos)
	assert(result.get("ok", false), "ranged attack toward barrel lane should succeed")
	assert(not barrel.alive and barrel.hp == 0, "barrel should be destroyed by the shot")
	assert(victim.hp < 20, "barrel explosion should damage the unit behind it")
	assert((result.get("events", []) as Array).any(func(ev): return str(ev.get("type", "")) == "explode"), "barrel hit should emit explode event")
	print("  [OK] barrel has hp and explodes on ranged hit")


func _mini_state() -> GameState:
	var state := GameState.new()
	state.board_size = Vector2i(8, 8)
	for y in range(8):
		for x in range(8):
			var pos := Vector2i(x, y)
			state.tiles[state.tile_key(pos)] = TileState.create(pos, Constants.TILE_FLOOR)
	return state
