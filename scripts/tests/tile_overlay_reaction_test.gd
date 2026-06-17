extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Tile Overlay Reaction Test ===")
	_test_fire_ignites_existing_poison_fog()
	_test_poison_fog_enters_existing_fire()
	_test_overlay_batch_applies_final_effect_once_per_large_unit()
	_test_large_unit_stay_checks_full_footprint()
	_test_refreshing_existing_fire_applies_to_occupant()
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


func _test_overlay_batch_applies_final_effect_once_per_large_unit() -> void:
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
	var burning := unit.get_status(Constants.STATUS_BURNING)
	var poison := unit.get_status(Constants.STATUS_POISON)
	assert(burning != null and burning.stacks == 1, "batch firelike overlays should burn large unit once")
	assert(poison != null and poison.stacks == 1, "batch toxic smoke should poison large unit once")
	assert(BattleInvariantChecker.assert_valid(state, "overlay_batch_large_unit"))
	print("  [OK] batched overlay applies final effect once per large unit")


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


func _test_refreshing_existing_fire_applies_to_occupant() -> void:
	var fixture := _large_unit_fixture(Vector2i(2, 2), Vector2i(1, 1))
	var state: GameState = fixture["state"]
	var unit: UnitState = fixture["unit"]
	state.get_tile(unit.pos).add_modifier(Constants.TILE_MOD_FIRE, 1)
	TileRules.create_fire(state, unit.pos, 2)
	var burning := unit.get_status(Constants.STATUS_BURNING)
	assert(burning != null and burning.stacks == 1, "refreshing fire under occupant should apply burning")
	assert(BattleInvariantChecker.assert_valid(state, "refresh_existing_fire"))
	print("  [OK] refreshing existing fire applies to occupant")


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
