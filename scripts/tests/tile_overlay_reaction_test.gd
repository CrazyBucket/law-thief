extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Tile Overlay Reaction Test ===")
	_test_fire_ignites_existing_poison_fog()
	_test_poison_fog_enters_existing_fire()
	_test_overlay_batch_waits_for_unit_entry()
	_test_path_applies_overlay_only_at_destination()
	_test_path_applies_spike_damage_per_crossed_cell()
	_test_forced_path_applies_spike_collision_damage()
	_test_large_unit_stay_checks_full_footprint()
	_test_refreshing_existing_fire_waits_for_entry()
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


func _test_overlay_batch_waits_for_unit_entry() -> void:
	var fixture := _large_unit_fixture(Vector2i(2, 2), Vector2i(2, 2))
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	TileRules.begin_overlay_batch(state)
	TileRules.create_fire(state, Vector2i(2, 2), 2)
	TileRules.create_poison_fog(state, Vector2i(2, 2), 2)
	TileRules.create_fire(state, Vector2i(3, 2), 2)
	TileRules.create_poison_fog(state, Vector2i(3, 2), 2)
	TileRules.create_fire(state, Vector2i(2, 3), 2)
	TileRules.end_overlay_batch(state)
	assert(not unit.has_status(Constants.STATUS_BURNING), "creating overlays under a unit must not apply burning")
	assert(not unit.has_status(Constants.STATUS_POISON), "creating overlays under a unit must not apply poison")
	TileRules.on_unit_entered(state, unit, Vector2i(1, 2))
	var burning := unit.get_status(Constants.STATUS_BURNING)
	var poison := unit.get_status(Constants.STATUS_POISON)
	assert(burning != null and burning.stacks == 1, "entering final firelike overlays should burn large unit once")
	assert(poison != null and poison.stacks == 1, "entering final toxic smoke should poison large unit once")
	assert(BattleInvariantChecker.assert_valid(state, "overlay_batch_large_unit"))
	print("  [OK] batched overlay waits for entry and applies once")


func _test_path_applies_overlay_only_at_destination() -> void:
	var fixture := _large_unit_fixture(Vector2i(1, 2), Vector2i.ONE)
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]:
		TileRules.create_poison_fog(state, cell, 2)
	var start := unit.pos
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]:
		state.move_unit(unit, cell)
		TileRules.on_unit_moved_through(state, unit, cell)
		assert(not unit.has_status(Constants.STATUS_POISON), "intermediate poison tiles must not apply poison")
	TileRules.finish_voluntary_move(state, unit, start)
	var poison := unit.get_status(Constants.STATUS_POISON)
	assert(poison != null and poison.stacks == 1, "only the destination tile should apply one poison stack")
	print("  [OK] path overlays resolve only at destination")


func _test_path_applies_spike_damage_per_crossed_cell() -> void:
	var fixture := _large_unit_fixture(Vector2i(1, 2), Vector2i.ONE)
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	state.add_entity(EntityState.create("path_spike", Constants.ENTITY_SPIKE, Vector2i(2, 2)))
	state.move_unit(unit, Vector2i(2, 2))
	TileRules.on_unit_moved_through(state, unit, unit.pos)
	assert(unit.hp == 15, "crossing a spike should immediately deal normal spike damage")
	state.move_unit(unit, Vector2i(3, 2))
	TileRules.on_unit_moved_through(state, unit, unit.pos)
	TileRules.finish_voluntary_move(state, unit, Vector2i(1, 2))
	assert(unit.hp == 15, "leaving the spike must not repeat its damage at the destination")
	print("  [OK] crossed spike resolves during path movement")


func _test_forced_path_applies_spike_collision_damage() -> void:
	var fixture := _large_unit_fixture(Vector2i(1, 3), Vector2i.ONE)
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	state.add_entity(EntityState.create("forced_path_spike", Constants.ENTITY_SPIKE, Vector2i(2, 3)))
	var events: Array[Dictionary] = []
	Displacement.push_cardinal(state, unit, Displacement.Direction.EAST, 2, "test_source", events)
	assert(unit.hp == 10, "forced movement through a spike should use collision damage")
	assert(unit.has_status(Constants.STATUS_VULNERABLE), "forced spike contact should apply vulnerable")
	assert(unit.pos == Vector2i(3, 3), "forced movement should continue after crossing a passable spike")
	print("  [OK] forced path resolves spike collision damage")


func _test_large_unit_stay_checks_full_footprint() -> void:
	var fixture := _large_unit_fixture(Vector2i(2, 2), Vector2i(2, 2))
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	state.get_tile(Vector2i(3, 2)).add_modifier(Constants.TILE_MOD_POISON_FOG, 2)
	var hp_before := unit.hp
	StatusRules.tick_turn_end(state)
	assert(unit.hp < hp_before, "large unit should suffer poison from any occupied footprint cell")
	assert(BattleInvariantChecker.assert_valid(state, "large_unit_stay_full_footprint"))
	print("  [OK] large unit stay checks full footprint")


func _test_refreshing_existing_fire_waits_for_entry() -> void:
	var fixture := _large_unit_fixture(Vector2i(2, 2), Vector2i(1, 1))
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	state.get_tile(unit.pos).add_modifier(Constants.TILE_MOD_FIRE, 1)
	TileRules.create_fire(state, unit.pos, 2)
	assert(not unit.has_status(Constants.STATUS_BURNING), "refreshing fire under occupant should not apply burning")
	TileRules.on_unit_entered(state, unit, unit.pos)
	var burning := unit.get_status(Constants.STATUS_BURNING)
	assert(burning != null and burning.stacks == 1, "moving onto fire should apply burning")
	assert(BattleInvariantChecker.assert_valid(state, "refresh_existing_fire"))
	print("  [OK] refreshing existing fire waits for entry")


func _large_unit_fixture(pos: Vector2i, footprint: Vector2i) -> Dictionary:
	var state := GameState.new()
	var unit := UnitState.new()
	unit.uid = "large_overlay_target"
	unit.unit_def_id = "test_large_overlay_target"
	unit.team = Constants.TEAM_PLAYER
	unit.pos = pos
	unit.hp = 20
	unit.max_hp = 20
	unit.alive = true
	unit.footprint_size = footprint
	state.register_unit(unit)
	assert(BattleInvariantChecker.assert_valid(state, "large_unit_fixture"))
	return {"state": state, "unit": unit}
