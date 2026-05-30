extends SceneTree

const PatrolGuardRules = preload("res://scripts/rules/patrol_guard_rules.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Patrol Guard Test ===")
	_test_spawn_stats()
	_test_charge_bonus_path()
	_test_charge_melee_damage()
	_test_blind_rampage()
	print("PATROL_GUARD_TEST_PASS")
	quit()


func _test_spawn_stats() -> void:
	var controller := BattleController.new()
	controller.start_encounter("patrol_guard_test", 42)
	var guard := _find_guard(controller.state)
	assert(guard != null, "patrol guard should exist")
	assert(guard.max_hp >= 24 and guard.max_hp <= 28, "hp should be 24+roll, got %d" % guard.max_hp)
	assert(guard.move_points == 3, "base move should be 3")
	assert(guard.base_attack == 6, "atk should be 6")
	print("  [OK] spawn hp=%d mv=%d atk=%d" % [guard.max_hp, guard.move_points, guard.base_attack])


func _test_charge_bonus_path() -> void:
	var ctx := _charge_test_context()
	var state: GameState = ctx["state"]
	var unit: UnitState = ctx["unit"]
	var on_line: Array[Vector2i] = [Vector2i(5, 2), Vector2i(4, 2)]
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(6, 2), on_line) == Constants.PATROL_GUARD_CHARGE_BONUS)
	var off_line: Array[Vector2i] = [Vector2i(5, 2), Vector2i(5, 3)]
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(6, 2), off_line) == 0)
	var line_then_break: Array[Vector2i] = [Vector2i(5, 2), Vector2i(4, 2), Vector2i(4, 3)]
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(6, 2), line_then_break) == 0)
	var turn_then_charge: Array[Vector2i] = [Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3), Vector2i(3, 3)]
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(6, 2), turn_then_charge) == Constants.PATROL_GUARD_CHARGE_BONUS)
	var one_step: Array[Vector2i] = [Vector2i(4, 2)]
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(5, 2), one_step) == 0)
	_set_tile(state, Vector2i(5, 2), Constants.TILE_WATER)
	var water_charge: Array[Vector2i] = [Vector2i(5, 2), Vector2i(4, 2)]
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(6, 2), water_charge) == 0)
	unit.statuses.append(StatusInstance.create(Constants.STATUS_SLOWED, 1))
	assert(PatrolGuardRules.charge_bonus(state, unit, Vector2i(6, 2), on_line) == 0)
	print("  [OK] charge: final straight segment, no slow, move cost <=2")


func _charge_test_context() -> Dictionary:
	var state := GameState.new()
	var unit := UnitState.new()
	unit.uid = "guard"
	unit.team = Constants.TEAM_ENEMY
	state.units[unit.uid] = unit
	return {"state": state, "unit": unit}


func _set_tile(state: GameState, pos: Vector2i, tile_id: String) -> void:
	state.tiles[state.tile_key(pos)] = TileState.create(pos, tile_id)


func _test_charge_melee_damage() -> void:
	var controller := BattleController.new()
	controller.start_encounter("patrol_guard_test", 42)
	var state := controller.state
	var guard := _find_guard(state)
	var player := state.get_player()
	var red := guard.get_slot(Constants.SLOT_RED)
	if red != null and not red.gem_uid.is_empty():
		state.gems.erase(red.gem_uid)
		red.gem_uid = ""
	guard.pos = Vector2i(6, 2)
	player.pos = Vector2i(3, 2)
	var path: Array[Vector2i] = [Vector2i(5, 2), Vector2i(4, 2)]
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "melee_attack", "should attack after move, got %s" % guard.intent.type)
	assert(guard.intent.damage == 8, "charge attack should be 8, got %d" % guard.intent.damage)
	var hp_before := player.hp
	guard.intent.path = path
	IntentSystem.execute_intent(state, guard)
	var dealt := hp_before - player.hp
	assert(dealt == 8, "charge attack should deal 8, got %d" % dealt)
	print("  [OK] charge melee deals 8 damage")


func _test_blind_rampage() -> void:
	var controller := BattleController.new()
	controller.start_encounter("patrol_guard_test", 42)
	var state := controller.state
	var guard := _find_guard(state)
	var red := guard.get_slot(Constants.SLOT_RED)
	var gem_uid: String = red.gem_uid
	red.gem_uid = ""
	PatrolGuardRules.on_red_gem_stolen(state, guard, gem_uid)
	assert(StatusRules.is_lawless(guard), "should be lawless")
	assert(StatusRules.is_vulnerable(guard), "rampage should apply vulnerable")
	assert(PatrolGuardRules.rampage_move_points(guard) == 4, "rampage move should be 4")
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.preview_text.begins_with("暴走"), "intent should show rampage prefix")
	print("  [OK] blind rampage: vulnerable + 4 move + 暴走 intent")


func _find_guard(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			return unit
	return null
