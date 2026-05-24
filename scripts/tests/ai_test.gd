extends SceneTree
## AI 系统测试
## 验证 Utility AI 决策逻辑、怪物行动经济、意图生成


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== AI System Test ===")
	_test_bomber_ai()
	_test_melee_chase_ai()
	_test_guard_ai()
	_test_puller_ai()
	_test_enemy_turn_execution()
	_test_multi_enemy_coordination()
	_test_bomber_close_range()
	print("AI_TEST_PASS")
	quit()


func _test_bomber_ai() -> void:
	print("--- Test: Bomber AI (far range) ---")
	var controller := BattleController.new()
	controller.start_encounter("template_a", 42)
	var state := controller.state

	var bomber := _find_unit_by_def(state, "unit_bomber")
	assert(bomber != null, "bomber should exist")

	# 玩家在 (1,6)，bomber 在 (4,2)，距离 7 > 冲刺范围 3
	# AI 应该选择移动靠近玩家
	assert(bomber.intent != null, "bomber should have intent")
	# 距离太远时，bomber 应该先移动
	assert(bomber.intent.type == "move" or bomber.intent.type == "charge_explode",
		"bomber should move or charge, got: %s" % bomber.intent.type)
	print("  [OK] bomber intent at far range: %s" % bomber.intent.preview_text)

	# 验证 AI 决策
	var decision: Dictionary = EnemyAI.decide(state, bomber)
	var action: EnemyAI.ActionCandidate = decision.get("action", null)
	assert(action != null, "bomber should have a decision")
	print("  [OK] bomber AI decision: %s (score: %.1f)" % [action.description, action.score])


func _test_bomber_close_range() -> void:
	print("--- Test: Bomber AI (close range) ---")
	# 使用 tutorial_001 场景，bomber 在 (2,4)，玩家在 (3,2)，距离 3
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 42)
	var state := controller.state

	var bomber := _find_unit_by_def(state, "unit_bomber")
	assert(bomber != null, "bomber should exist")

	# 距离 3，在冲刺爆炸范围内
	var player := state.get_player()
	var dist: int = BoardUtils.manhattan(bomber.pos, player.pos)
	assert(dist <= 3, "bomber should be within charge range, dist=%d" % dist)

	# AI 应该选择冲刺爆炸
	assert(bomber.intent != null, "bomber should have intent")
	assert(bomber.intent.type == "charge_explode",
		"bomber at close range should charge_explode, got: %s" % bomber.intent.type)
	print("  [OK] bomber at dist %d chooses: %s" % [dist, bomber.intent.preview_text])


func _test_melee_chase_ai() -> void:
	print("--- Test: Melee Chase AI ---")
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state

	# 找到小怪
	var grunts: Array = []
	for unit in state.units.values():
		if unit.unit_def_id == "unit_grunt":
			grunts.append(unit)
	assert(grunts.size() >= 1, "should have grunts")

	var grunt: UnitState = grunts[0]
	var player := state.get_player()
	var initial_dist: int = BoardUtils.manhattan(grunt.pos, player.pos)

	# AI 决策应该是靠近玩家或攻击
	var decision: Dictionary = EnemyAI.decide(state, grunt)
	var action: EnemyAI.ActionCandidate = decision.get("action", null)
	assert(action != null, "grunt should have a decision")

	# 小怪应该想靠近玩家
	if action.type == EnemyAI.ActionType.ATTACK:
		print("  [OK] grunt wants to attack (already adjacent)")
	elif action.type == EnemyAI.ActionType.MOVE:
		# 移动目标应该比当前位置更靠近玩家
		var new_dist: int = BoardUtils.manhattan(action.move_target, player.pos)
		assert(new_dist < initial_dist, "grunt should move closer to player")
		print("  [OK] grunt moves closer: %d -> %d" % [initial_dist, new_dist])
	else:
		print("  [OK] grunt decision: %s" % action.description)


func _test_guard_ai() -> void:
	print("--- Test: Guard AI ---")
	var controller := BattleController.new()
	controller.start_encounter("template_a", 42)
	var state := controller.state

	var guard := _find_unit_by_def(state, "unit_heavy_guard")
	assert(guard != null, "guard should exist")

	# 守卫应该有意图
	assert(guard.intent != null, "guard should have intent")
	print("  [OK] guard intent: %s" % guard.intent.preview_text)

	# 守卫的 AI 应该倾向于靠近友军
	var decision: Dictionary = EnemyAI.decide(state, guard)
	var action: EnemyAI.ActionCandidate = decision.get("action", null)
	assert(action != null, "guard should have a decision")
	print("  [OK] guard AI decision: %s (score: %.1f)" % [action.description, action.score])


func _test_puller_ai() -> void:
	print("--- Test: Puller AI ---")
	var controller := BattleController.new()
	controller.start_encounter("template_b", 42)
	var state := controller.state

	var puller := _find_unit_by_def(state, "unit_gravity_eye")
	assert(puller != null, "puller should exist")
	assert(puller.move_points == 0, "puller should not move")

	# 引力眼在 (4,3)，玩家在 (1,6)，距离 6 > 引力范围 3
	# 所以 AI 正确选择等待（无法移动也无法攻击）
	var player := state.get_player()
	var dist: int = BoardUtils.manhattan(puller.pos, player.pos)
	print("  [INFO] puller at %s, player at %s, dist=%d" % [puller.pos, player.pos, dist])

	assert(puller.intent != null, "puller should have intent")
	if dist > 3:
		# 超出范围，应该等待
		assert(puller.intent.type == "wait", "puller out of range should wait, got: %s" % puller.intent.type)
		print("  [OK] puller correctly waits when out of range (dist=%d > 3)" % dist)
	else:
		assert(puller.intent.type == "pull", "puller in range should pull, got: %s" % puller.intent.type)
		print("  [OK] puller uses pull at dist=%d" % dist)

	# 验证 move_points=0 时不会生成移动路径
	var decision: Dictionary = EnemyAI.decide(state, puller)
	var move_path: Array = decision.get("move_path", [])
	assert(move_path.is_empty(), "puller should not move (0 move points)")
	print("  [OK] puller stays in place")


func _test_enemy_turn_execution() -> void:
	print("--- Test: Enemy Turn Execution ---")
	var controller := BattleController.new()
	controller.start_encounter("template_a", 42)
	var state := controller.state
	var player := state.get_player()
	var initial_hp: int = player.hp

	# 记录所有敌人初始位置
	var initial_positions: Dictionary = {}
	for unit in state.get_alive_enemies():
		initial_positions[unit.uid] = unit.pos

	# 结束玩家回合，触发敌人行动（新 API：逐个执行）
	controller.begin_enemy_phase()
	for enemy in controller.get_sorted_enemies():
		controller.execute_single_enemy(enemy)
	controller.finish_enemy_phase()

	# 验证敌人确实行动了（位置变化或玩家受伤）
	var any_moved: bool = false
	for unit in state.units.values():
		if unit.team == Constants.TEAM_ENEMY and unit.alive:
			if unit.pos != initial_positions.get(unit.uid, unit.pos):
				any_moved = true
				break

	var player_damaged: bool = player.hp < initial_hp
	assert(any_moved or player_damaged, "enemies should have acted (moved or attacked)")
	print("  [OK] enemies acted: moved=%s, player_damaged=%s (HP: %d->%d)" % [any_moved, player_damaged, initial_hp, player.hp])

	# 验证回合正确切换回玩家
	assert(state.phase == Constants.PHASE_PLAYER or state.phase == Constants.PHASE_ENDED,
		"phase should be player or ended after enemy turn")
	print("  [OK] turn correctly advanced")


func _test_multi_enemy_coordination() -> void:
	print("--- Test: Multi-Enemy Coordination ---")
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state

	# template_c 有 4 个敌人：毒虫、引力眼、2个小怪
	var enemies := state.get_alive_enemies()
	assert(enemies.size() == 4, "should have 4 enemies, got: %d" % enemies.size())

	# 所有敌人都应该有意图
	for enemy in enemies:
		assert(enemy.intent != null, "enemy %s should have intent" % enemy.uid)

	print("  [OK] all %d enemies have intents:" % enemies.size())
	for enemy in enemies:
		print("    %s (%s): %s" % [enemy.unit_def_id, enemy.uid, enemy.intent.preview_text])

	# 执行一个完整回合（新 API：逐个执行）
	controller.begin_enemy_phase()
	for enemy in controller.get_sorted_enemies():
		controller.execute_single_enemy(enemy)
	controller.finish_enemy_phase()

	# 验证没有崩溃，游戏状态正常
	assert(state.phase == Constants.PHASE_PLAYER or state.phase == Constants.PHASE_ENDED,
		"game should still be in valid state")
	print("  [OK] multi-enemy turn completed without errors")


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null
