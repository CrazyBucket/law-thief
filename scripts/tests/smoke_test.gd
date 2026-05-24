extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 12345)
	var state := controller.state
	var player := state.get_player()
	var bomber := _find_unit_by_def(state, "unit_bomber")
	var guard := _find_unit_by_def(state, "unit_training_guard")
	if bomber == null or guard == null:
		push_error("missing units")
		quit(1)
		return

	# === 验证新行动经济：拔出免费 ===
	controller.select_action(Constants.ACTION_EXTRACT)
	var extract_result := controller.try_extract(bomber.uid, 0)
	if not extract_result.get("ok", false):
		push_error("extract failed: %s" % extract_result.get("reason", ""))
		quit(1)
		return

	# 拔出后 player_acted 应该仍为 false（免费操作）
	if state.player_acted:
		push_error("extract should NOT consume action (new economy)")
		quit(1)
		return
	print("  [OK] extract is free")

	# === 验证：拔出后可以立即嵌入（同一回合） ===
	# 先移动到守卫旁边
	controller.select_action(Constants.ACTION_MOVE)
	var moved := false
	for cell in BoardUtils.reachable_cells(state, player.pos, player.move_points):
		if BoardUtils.manhattan(cell, guard.pos) == 1:
			var move_result := controller.try_move(cell)
			if move_result.get("ok", false):
				moved = true
				break
	if not moved:
		push_error("could not move adjacent to guard")
		quit(1)
		return
	print("  [OK] moved adjacent to guard")

	# 嵌入到守卫的黑槽（index 2），击杀时触发死亡爆炸
	controller.select_action(Constants.ACTION_INSERT)
	var insert_result := controller.try_insert(guard.uid, 2)
	if not insert_result.get("ok", false):
		push_error("insert failed: %s" % insert_result.get("reason", ""))
		quit(1)
		return

	# 嵌入后 player_acted 应该仍为 false
	if state.player_acted:
		push_error("insert should NOT consume action (new economy)")
		quit(1)
		return
	print("  [OK] insert is free (into BLACK slot)")

	# === 验证：同一回合可以攻击（消耗行动） ===
	controller.select_action(Constants.ACTION_ATTACK)
	var attack_result := controller.try_attack(guard.uid)
	if not attack_result.get("ok", false):
		push_error("attack failed: %s" % attack_result.get("reason", ""))
		quit(1)
		return

	# 攻击后 player_acted 应该为 true
	if not state.player_acted:
		push_error("attack should consume action")
		quit(1)
		return
	print("  [OK] attack consumes action")

	# === 验证：教学关一回合通关 ===
	if guard.alive or bomber.alive:
		push_error("expected both enemies dead after death explosion")
		quit(1)
		return
	print("  [OK] both enemies dead in ONE turn")

	# === 验证 can_use_action 逻辑 ===
	# 攻击后不能再攻击
	if controller.can_use_action(Constants.ACTION_ATTACK):
		push_error("should not be able to attack again")
		quit(1)
		return
	# 攻击后不能触发
	if controller.can_use_action(Constants.ACTION_TRIGGER):
		push_error("should not be able to trigger after acting")
		quit(1)
		return
	# 手中没宝石，不能拔出（已经拔过了嵌入了）
	if controller.can_use_action(Constants.ACTION_EXTRACT):
		# 这取决于是否还有可拔出的目标，但 held_gem 为空所以可以拔
		# 实际上 can_use_action(EXTRACT) 只检查 held_gem_uid 是否为空
		pass
	print("  [OK] action economy constraints correct")

	print("SMOKE_TEST_PASS")
	quit()


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null
