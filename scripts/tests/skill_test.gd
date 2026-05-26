extends SceneTree
## 技能系统测试：验证玩家拔出宝石→装入红槽→释放技能的完整流程


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Skill System Test ===")
	_test_skill_not_available_without_gem()
	_test_extract_to_red_slot_enables_skill()
	_test_skill_deals_damage()
	_test_poison_skill_stacks_twice_on_enemy()
	print("SKILL_TEST_PASS")
	quit()


func _test_skill_not_available_without_gem() -> void:
	print("--- Test: Skill unavailable without gem ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	# 玩家刚开始没有宝石在红槽
	var can_skill: bool = ctrl.can_use_action(Constants.ACTION_SKILL)
	assert(not can_skill, "should not be able to use skill without gem")
	print("  [OK] skill disabled when red slot empty")


func _test_extract_to_red_slot_enables_skill() -> void:
	print("--- Test: Extract gem to red slot enables skill ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	# 找到 bomber（有爆炸宝石在红槽）
	var bomber: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_bomber":
			bomber = unit
			break
	assert(bomber != null, "bomber should exist")
	# 拔出 bomber 的红槽宝石
	var player := state.get_player()
	var result := ctrl.try_extract(bomber.uid, 0)
	assert(result.get("ok", false), "extract should succeed")
	# 现在玩家手里有宝石，需要嵌入自己的红槽（index 0）
	var insert_result := ctrl.try_insert(player.uid, 0)
	assert(insert_result.get("ok", false), "insert to own red slot should succeed")
	# 现在应该能使用技能了
	var can_skill: bool = ctrl.can_use_action(Constants.ACTION_SKILL)
	assert(can_skill, "should be able to use skill after inserting gem in red slot")
	print("  [OK] skill enabled after gem in red slot")


func _test_skill_deals_damage() -> void:
	print("--- Test: Explosion skill deals damage ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	# 快速设置：直接给玩家红槽放一个爆炸宝石
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_gem_1"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	var red_slot := player.get_slot(Constants.SLOT_RED)
	red_slot.gem_uid = gem.uid
	# 找到守卫
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_training_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var guard_hp_before: int = guard.hp
	# 对守卫位置使用技能
	var result := ctrl.try_skill(guard.pos)
	assert(result.get("ok", false), "skill should succeed: %s" % result.get("reason", ""))
	assert(guard.hp < guard_hp_before, "guard should take damage from explosion")
	assert(state.player_acted, "skill should consume action")
	var events: Array = result.get("events", [])
	assert(not events.is_empty(), "should return animation events")
	print("  [OK] explosion skill dealt %d damage" % (guard_hp_before - guard.hp))
	print("  [OK] skill consumed action")
	print("  [OK] returned %d animation events" % events.size())


func _test_poison_skill_stacks_twice_on_enemy() -> void:
	print("--- Test: Poison skill stacking on 3x3 ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_training_guard":
			guard = unit
			break
	assert(guard != null)
	var poison_gem := GemState.new()
	poison_gem.uid = "test_poison_skill_gem"
	poison_gem.gem_id = Constants.GEM_POISON
	state.gems[poison_gem.uid] = poison_gem
	player.get_slot(Constants.SLOT_RED).gem_uid = poison_gem.uid
	var ev1: Array = GemEffects.player_use_skill(state, player, guard.pos)
	var ev2: Array = GemEffects.player_use_skill(state, player, guard.pos)
	var ps: StatusInstance = guard.get_status(Constants.STATUS_POISON)
	assert(ps != null, "poison status should apply on units in AoE")
	assert(ps.stacks == 2, "two casts should stack poison: got %d" % ps.stacks)
	assert(ev1.any(func(e): return e.get("type", "") == "poison_burst"), "skill should emit poison_burst vfx event")
	print("  [OK] double poison_skill merged stacks (%d layers)" % ps.stacks)


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
