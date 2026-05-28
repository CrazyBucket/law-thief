extends SceneTree
## AI 系统测试


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== AI System Test ===")
	_test_bomb_rat_ai()
	_test_patrol_guard_ai()
	_test_stone_bow_ai()
	_test_enemy_turn_execution()
	_test_multi_enemy_coordination()
	print("AI_TEST_PASS")
	quit()


func _test_bomb_rat_ai() -> void:
	print("--- Test: Bomb Rat AI ---")
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var state := controller.state
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	assert(rat != null, "bomb rat should exist")
	assert(rat.intent != null, "bomb rat should have intent")
	print("  [OK] bomb rat intent: %s" % rat.intent.preview_text)


func _test_patrol_guard_ai() -> void:
	print("--- Test: Patrol Guard AI ---")
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	assert(guard != null, "patrol guard should exist")
	var decision: Dictionary = EnemyAI.decide(state, guard)
	var action: EnemyAI.ActionCandidate = decision.get("action", null)
	assert(action != null, "patrol guard should have a decision")
	print("  [OK] patrol guard AI: %s" % action.description)


func _test_stone_bow_ai() -> void:
	print("--- Test: Stone Bow AI ---")
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 42)
	var state := controller.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	assert(bow != null, "stone bow should exist")
	assert(bow.intent != null, "stone bow should have intent")
	print("  [OK] stone bow intent: %s" % bow.intent.preview_text)


func _test_enemy_turn_execution() -> void:
	print("--- Test: Enemy Turn Execution ---")
	var controller := BattleController.new()
	controller.start_encounter("template_a", 42)
	var state := controller.state
	var player := state.get_player()
	var initial_hp: int = player.hp
	var initial_positions: Dictionary = {}
	for unit in state.get_alive_enemies():
		initial_positions[unit.uid] = unit.pos
	controller.begin_enemy_phase()
	for enemy in controller.get_sorted_enemies():
		controller.execute_single_enemy(enemy)
	controller.finish_enemy_phase()
	var any_moved: bool = false
	for unit in state.units.values():
		if unit.team == Constants.TEAM_ENEMY and unit.alive:
			if unit.pos != initial_positions.get(unit.uid, unit.pos):
				any_moved = true
				break
	var player_damaged: bool = player.hp < initial_hp
	assert(any_moved or player_damaged, "enemies should have acted")
	print("  [OK] enemies acted: moved=%s, damaged=%s" % [any_moved, player_damaged])


func _test_multi_enemy_coordination() -> void:
	print("--- Test: Multi-Enemy Coordination ---")
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state
	var enemies := state.get_alive_enemies()
	assert(enemies.size() == 4, "should have 4 enemies, got %d" % enemies.size())
	for enemy in enemies:
		assert(enemy.intent != null, "enemy %s should have intent" % enemy.uid)
	controller.begin_enemy_phase()
	for enemy in controller.get_sorted_enemies():
		controller.execute_single_enemy(enemy)
	controller.finish_enemy_phase()
	assert(state.phase == Constants.PHASE_PLAYER or state.phase == Constants.PHASE_ENDED)
	print("  [OK] %d enemies completed turn" % enemies.size())


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null
