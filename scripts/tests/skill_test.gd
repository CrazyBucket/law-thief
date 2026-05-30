extends SceneTree
## 红槽宝石攻击触发测试：验证玩家装备红槽宝石后，攻击命中时附带效果正确触发


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Red Gem Attack Trigger Test ===")
	_test_attack_without_red_gem()
	_test_explosion_triggers_on_attack_hit()
	_test_poison_triggers_on_attack_hit()
	_test_explosion_on_empty_cell()
	_test_explosion_splash_damages_neighbor()
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
		if unit.unit_def_id == "unit_patrol_guard":
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
		if unit.unit_def_id == "unit_patrol_guard":
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
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	var events: Array = result.get("attack_events", [])
	var has_poison := events.any(func(e): return e.get("type", "") == "poison_burst")
	assert(has_poison, "poison gem should produce poison_burst event on hit")
	print("  [OK] poison gem triggered on attack hit")


func _test_explosion_on_empty_cell() -> void:
	print("--- Test: Explosion red gem triggers on empty cell ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_explosion_empty"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var empty := player.pos + Vector2i(2, 0)
	if state.get_unit_at(empty) != null:
		empty = player.pos + Vector2i(0, 2)
	var result := ctrl.try_attack_cell(empty)
	assert(result.get("ok", false), "attack empty should succeed")
	var events: Array = result.get("attack_events", [])
	var explode_ev: Dictionary = {}
	for ev in events:
		if ev.get("type", "") == "explode":
			explode_ev = ev
			break
	assert(not explode_ev.is_empty(), "should emit explode on empty cell")
	assert(explode_ev.get("pattern", "") == "cross", "should be cross pattern")
	var cells: Array = explode_ev.get("cells", [])
	assert(cells.size() == 5, "cross should cover 5 cells, got %d" % cells.size())
	print("  [OK] explosion on empty cell")


func _test_explosion_splash_damages_neighbor() -> void:
	print("--- Test: Explosion red gem splash damages adjacent unit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_explosion_splash"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guards: Array[UnitState] = []
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard" and unit.alive:
			guards.append(unit)
	assert(guards.size() >= 2, "need at least 2 guards")
	var primary := guards[0]
	var neighbor := guards[1]
	neighbor.pos = primary.pos + Vector2i(1, 0)
	assert(BoardUtils.chebyshev(primary.pos, neighbor.pos) == 1, "neighbor setup")
	var primary_hp := primary.hp
	var neighbor_hp := neighbor.hp
	var result := ctrl.try_attack_cell(primary.pos)
	assert(result.get("ok", false), "attack should succeed")
	assert(primary.hp < primary_hp, "primary target should take hit damage")
	assert(neighbor.hp < neighbor_hp, "neighbor should take explosion splash (%d -> %d)" % [neighbor_hp, neighbor.hp])
	var splash_events := 0
	for ev in result.get("attack_events", []):
		if ev.get("type", "") == "damage" and ev.get("pos", Vector2i.ZERO) == neighbor.pos:
			splash_events += 1
	assert(splash_events >= 1, "should emit neighbor damage event")
	print("  [OK] explosion splash damages neighbor (%d -> %d)" % [neighbor_hp, neighbor.hp])


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
