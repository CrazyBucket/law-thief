extends SceneTree
## 红槽宝石攻击触发测试：验证玩家装备红槽宝石后，攻击命中时附带效果正确触发


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Red Gem Attack Trigger Test ===")
	_test_attack_without_red_gem()
	_test_explosion_triggers_on_attack_hit()
	_test_poison_triggers_on_attack_hit()
	print("SKILL_TEST_PASS")
	quit()


func _test_attack_without_red_gem() -> void:
	print("--- Test: Attack without red gem produces no bonus events ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_training_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	assert(player.get_slot(Constants.SLOT_RED).gem_uid.is_empty(), "red slot should be empty")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	var events: Array = result.get("attack_events", [])
	var has_explode := events.any(func(e): return e.get("type", "") == "explode")
	assert(not has_explode, "no explosion without red gem")
	print("  [OK] no bonus effect without red gem")


func _test_explosion_triggers_on_attack_hit() -> void:
	print("--- Test: Explosion red gem triggers on attack hit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_explosion_red"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_training_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var hp_before := guard.hp
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed: %s" % result.get("reason", ""))
	assert(guard.hp < hp_before, "guard should take damage")
	assert(state.player_acted, "attack should consume action")
	var events: Array = result.get("attack_events", [])
	assert(not events.is_empty(), "should return animation events")
	var has_explode := events.any(func(e): return e.get("type", "") == "explode")
	assert(has_explode, "explosion gem should produce explode event on hit")
	print("  [OK] explosion gem triggered on attack hit, dealt %d total damage" % (hp_before - guard.hp))


func _test_poison_triggers_on_attack_hit() -> void:
	print("--- Test: Poison red gem triggers on attack hit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_poison_red"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_training_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	var events: Array = result.get("attack_events", [])
	var has_poison := events.any(func(e): return e.get("type", "") == "poison_burst")
	assert(has_poison, "poison gem should produce poison_burst event on hit")
	print("  [OK] poison gem triggered on attack hit")


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
