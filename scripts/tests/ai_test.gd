extends SceneTree
## AI 系统测试

const Builder = preload("res://scripts/testkit/scenario_builder.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== AI System Test ===")
	_test_patrol_guard_ai()
	_test_patrol_guard_detours_around_prop()
	_test_patrol_guard_crosses_poison_fog_to_attack()
	_test_enemy_turn_execution()
	_test_multi_enemy_coordination()
	_test_enemy_extra_action_consumes_bonus()
	print("AI_TEST_PASS")
	quit()


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


func _test_patrol_guard_detours_around_prop() -> void:
	print("--- Test: Patrol Guard Detour ---")
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	var player := state.get_player()
	assert(guard != null and player != null, "guard/player should exist")
	player.pos = Vector2i(1, 6)
	state.rebuild_occupancy()
	var before := BoardUtils.path_distance_to_cell(state, guard.pos, player.pos, guard.uid, {}, guard)
	var decision: Dictionary = EnemyAI.decide(state, guard)
	var path: Array[Vector2i] = decision.get("move_path", [] as Array[Vector2i])
	assert(not path.is_empty(), "guard should plan a detour path")
	var after_pos := path[path.size() - 1]
	var after := BoardUtils.path_distance_to_cell(state, after_pos, player.pos, guard.uid, {}, guard)
	assert(after >= 0 and after < before, "guard should reduce full path distance around prop (%d -> %d)" % [before, after])
	print("  [OK] patrol guard detours around prop")


func _test_patrol_guard_crosses_poison_fog_to_attack() -> void:
	print("--- Test: Patrol Guard Crosses Poison Fog ---")
	var controller := BattleController.new()
	controller.start_encounter("template_a", 42)
	var state := controller.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	var player := state.get_player()
	assert(guard != null and player != null, "guard/player should exist")
	for slot: SlotState in guard.slots:
		if not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
			slot.gem_uid = ""
	state.move_unit(guard, Vector2i(1, 2))
	state.move_unit(player, Vector2i(1, 4))
	TileRules.create_poison_fog(state, Vector2i(1, 3), 2)
	var blockers := {}
	for cell in [
		Vector2i(0, 2),
		Vector2i(2, 2),
		Vector2i(0, 3),
		Vector2i(2, 3),
		Vector2i(0, 4),
		Vector2i(2, 4),
	]:
		blockers[state.tile_key(cell)] = "test_blocker"
	var decision: Dictionary = EnemyAI.decide(state, guard, blockers)
	var action: EnemyAI.ActionCandidate = decision.get("action", null)
	var path: Array[Vector2i] = decision.get("move_path", [] as Array[Vector2i])
	assert(action != null, "guard should choose an action through poison fog")
	assert(action.action_target_uid == player.uid, "guard should attack the player after crossing poison fog")
	assert(action.type != EnemyAI.ActionType.WAIT and action.type != EnemyAI.ActionType.MOVE, "guard should not only move or wait after crossing poison fog")
	assert(
		Vector2i(1, 3) in path or action.move_target == Vector2i(1, 3),
		"guard should cross poison fog to attack: path=%s origin=%s" % [path, action.move_target]
	)
	print("  [OK] patrol guard crosses poison fog to attack")


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


func _test_enemy_extra_action_consumes_bonus() -> void:
	print("--- Test: Enemy Extra Action Consumption ---")
	var builder := Builder.new("fission_slime_test", 9912, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(2, 2))
	builder.set_stats(player, {"hp": 20, "max_hp": 20})
	var enemy := builder.add_unit("extra_action_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 2), {
		"hp": 20,
		"max_hp": 20,
		"base_attack": 4,
	})
	builder.clear_slots(enemy)
	var state := builder.finish()
	StatusRules.grant_extra_attack(state, enemy, 1)
	var controller := BattleController.new()
	controller.state = state
	controller.begin_enemy_phase()
	var hp_before := player.hp
	var result := controller.execute_single_enemy(enemy)
	var events: Array = result.get("events", [])
	assert(player.hp == hp_before - 8, "enemy with one bonus action should deal damage twice")
	assert(_count_damage_events_to(events, player.uid) >= 2, "enemy bonus action should emit two damage events")
	assert(not StatusRules.has_extra_attack(enemy), "bonus action charge should be consumed")
	print("  [OK] enemy extra action consumed")


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null


func _count_damage_events_to(events: Array, victim_uid: String) -> int:
	var count := 0
	for raw_event in events:
		var event: Dictionary = raw_event
		if str(event.get("type", "")) == "damage" and str(event.get("uid", "")) == victim_uid:
			count += 1
	return count
