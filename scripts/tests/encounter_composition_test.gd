extends SceneTree

const BattleInvariantChecker = preload("res://scripts/debug/battle_invariant_checker.gd")

const DESIGNED_ENCOUNTERS: Array[String] = [
	"crossfire_courtyard", "rat_run", "flooded_crossing", "spike_corridor",
	"burning_storehouse", "poison_marsh", "frozen_gallery", "barrel_maze",
	"shifting_quarry", "split_sanctum", "enforcer_gate", "law_beast_arena",
	"toxic_furnace", "storm_pillars",
]

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var same_a: GameState = registry.create_battle_state("crossfire_courtyard", 77, "room_a")
	var same_b: GameState = registry.create_battle_state("crossfire_courtyard", 77, "room_a")
	assert(_formation(same_a) == _formation(same_b), "same run and room seed must reproduce composition")
	assert(same_a.get_alive_enemies().size() == 3, "crossfire courtyard should resolve fixed plus random enemies")
	assert(_has_enemy_at(same_a, Vector2i(6, 1)), "fixed bow position must be preserved")
	assert(_has_enemy_at(same_a, Vector2i(5, 5)), "random slot position must be preserved")

	for seed_value in range(1, 12):
		var state: GameState = registry.create_battle_state("shifting_quarry", seed_value, "quarry")
		assert(state.get_alive_enemies().size() == 3, "one complete enemy group should be selected")
		assert(_has_enemy_at(state, Vector2i(5, 2)), "group formation first anchor must be preserved")
		assert(_has_enemy_at(state, Vector2i(5, 5)), "group formation second anchor must be preserved")

	for encounter_id in DESIGNED_ENCOUNTERS:
		for seed_value in [1, 7, 42]:
			var state: GameState = registry.create_battle_state(encounter_id, seed_value, "map_contract")
			assert(BattleInvariantChecker.check_all(state).is_empty(), "%s must preserve battle invariants" % encounter_id)
			assert(not state.get_alive_enemies().is_empty(), "%s must spawn enemies" % encounter_id)
			assert(not _unit_overlaps_blocking_entity(state), "%s must not spawn units inside blocking entities" % encounter_id)
	print("ENCOUNTER_COMPOSITION_TEST_PASS")
	quit()


func _formation(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for enemy in state.get_alive_enemies():
		result.append("%s@%d,%d" % [enemy.unit_def_id, enemy.pos.x, enemy.pos.y])
	result.sort()
	return result


func _has_enemy_at(state: GameState, pos: Vector2i) -> bool:
	for enemy in state.get_alive_enemies():
		if enemy.pos == pos:
			return true
	return false


func _unit_overlaps_blocking_entity(state: GameState) -> bool:
	var blocked_cells: Dictionary = {}
	for entity in state.entities.values():
		if entity.alive and entity.blocks_movement():
			blocked_cells[state.tile_key(entity.pos)] = true
	for unit in state.units.values():
		if not unit.alive:
			continue
		for cell in unit.occupied_cells():
			if blocked_cells.has(state.tile_key(cell)):
				return true
	return false
