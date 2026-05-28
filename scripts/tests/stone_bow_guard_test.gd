extends SceneTree

const StoneBowGuardRules = preload("res://scripts/rules/stone_bow_guard_rules.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Stone Bow Guard Test ===")
	_test_spawn_stats()
	_test_deploy_range()
	_test_deploy_shot_damage()
	_test_faulty_blind_shot()
	_test_kite_retreat_then_shoot()
	_test_hold_position_when_in_range()
	_test_intent_tracks_player_after_move()
	print("STONE_BOW_GUARD_TEST_PASS")
	quit()


func _test_spawn_stats() -> void:
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 42)
	var bow := _find_bow(controller.state)
	assert(bow != null, "stone bow guard should exist")
	assert(bow.max_hp >= 14 and bow.max_hp <= 17, "hp 14+roll, got %d" % bow.max_hp)
	assert(bow.move_points == 2 and bow.base_attack == 4)
	print("  [OK] spawn hp=%d" % bow.max_hp)


func _test_deploy_range() -> void:
	assert(StoneBowGuardRules.attack_range_for(Vector2i.ZERO, []) == 4)
	assert(StoneBowGuardRules.attack_range_for(Vector2i.ZERO, [Vector2i(1, 0)]) == 3)
	print("  [OK] deploy range 4 / move range 3")


func _test_deploy_shot_damage() -> void:
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 42)
	var state := controller.state
	var bow := _find_bow(state)
	var player := state.get_player()
	var red := bow.get_slot(Constants.SLOT_RED)
	if red != null and not red.gem_uid.is_empty():
		state.gems.erase(red.gem_uid)
		red.gem_uid = ""
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent.type == "ranged_attack", "should shoot, got %s" % bow.intent.type)
	assert(bow.intent.path.is_empty(), "deployed shot should not move")
	assert(bow.intent.damage == 4, "normal shot 4, got %d" % bow.intent.damage)
	var hp_before := player.hp
	IntentSystem.execute_intent(state, bow)
	assert(player.hp < hp_before, "player should be hit")
	print("  [OK] deployed ranged hit for 4")


func _test_faulty_blind_shot() -> void:
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 99)
	var state := controller.state
	var bow := _find_bow(state)
	var player := state.get_player()
	var red := bow.get_slot(Constants.SLOT_RED)
	var gem_uid: String = red.gem_uid
	red.gem_uid = ""
	StoneBowGuardRules.on_red_gem_stolen(state, bow, gem_uid)
	assert(StoneBowGuardRules.is_faulty_blind_shot(bow))
	assert(StoneBowGuardRules.ranged_damage_preview(state, bow) == 5)
	var rng: Node = Engine.get_main_loop().root.get_node("RngService")
	rng.set_seed(1001)
	var hits := 0
	for i in range(20):
		if StoneBowGuardRules.roll_hit(state, bow.uid):
			hits += 1
	assert(hits >= 4 and hits <= 16, "hit rate should be near 50%%, got %d/20" % hits)
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	player.hp = player.max_hp
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent.preview_text.begins_with("盲射"), "faulty preview")
	rng.set_seed(7)
	IntentSystem.execute_intent(state, bow)
	assert(player.hp == player.max_hp, "seed 7 should miss")
	print("  [OK] faulty blind shot miss/damage rules")


func _test_kite_retreat_then_shoot() -> void:
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 42)
	var state := controller.state
	var bow := _find_bow(state)
	var player := state.get_player()
	bow.pos = Vector2i(4, 2)
	player.pos = Vector2i(4, 3)
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent.type == "ranged_attack", "should shoot after reposition, got %s" % bow.intent.type)
	assert(not bow.intent.path.is_empty(), "should move before shooting when player is adjacent")
	var dist_after := BoardUtils.manhattan(bow.intent.path[bow.intent.path.size() - 1], player.pos)
	assert(dist_after >= Constants.STONE_BOW_KITE_MIN_RANGE, "kite position should keep distance")
	var hp_before := player.hp
	IntentSystem.execute_intent(state, bow)
	assert(player.hp < hp_before, "kite shot should damage player")
	print("  [OK] kite retreat + ranged in one turn")


func _test_hold_position_when_in_range() -> void:
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 42)
	var state := controller.state
	var bow := _find_bow(state)
	var player := state.get_player()
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	assert(BoardUtils.manhattan(bow.pos, player.pos) == 4, "setup at max deploy range")
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent.type == "ranged_attack", "should shoot in place, got %s" % bow.intent.type)
	assert(bow.intent.path.is_empty(), "should not approach when already in 4-tile range")
	print("  [OK] hold position when already in range")


func _test_intent_tracks_player_after_move() -> void:
	var controller := BattleController.new()
	controller.start_encounter("stone_bow_test", 42)
	var state := controller.state
	var bow := _find_bow(state)
	var player := state.get_player()
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	IntentSystem.refresh_all_intents(state)
	assert(bow.intent.path.is_empty(), "bow should plan in-place shot before player moves")
	var move_result := controller.try_move(Vector2i(4, 2))
	assert(move_result.get("ok", false), "player move should succeed")
	assert(BoardUtils.manhattan(bow.pos, player.pos) == 1, "player should be adjacent after move")
	assert(not bow.intent.path.is_empty(), "bow intent should switch to kite retreat after player closes in")
	print("  [OK] enemy intent refreshes after player move")


func _find_bow(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_stone_bow_guard":
			return unit
	return null
