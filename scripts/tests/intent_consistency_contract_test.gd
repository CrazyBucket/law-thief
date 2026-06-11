extends SceneTree

const EventValidator = preload("res://scripts/debug/event_validator.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Intent Consistency Contract Test ===")
	_test_patrol_guard_charge_preview_matches_execution()
	_test_stone_bow_shot_preview_matches_execution()
	_test_move_preview_matches_executed_path()
	_test_explosion_preview_matches_blast_delivery()
	print("INTENT_CONSISTENCY_CONTRACT_TEST_PASS")
	quit()


func _test_patrol_guard_charge_preview_matches_execution() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("patrol_guard_test", 42)
	var state := ctrl.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	var player := state.get_player()
	assert(guard != null and player != null, "guard/player should exist")
	var red := guard.get_slot(Constants.SLOT_RED)
	if red != null and not red.gem_uid.is_empty():
		state.gems.erase(red.gem_uid)
		red.gem_uid = ""
	guard.pos = Vector2i(6, 2)
	player.pos = Vector2i(3, 2)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "melee_attack", "charge setup should preview melee attack")
	assert(guard.intent.damage == 8, "charge preview should show 8 damage")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	_assert_valid_events(events, "patrol_charge")
	var dealt := hp_before - player.hp
	assert(dealt == guard.intent.damage, "charge execution should match preview damage")
	_assert_valid_state(state, "patrol_charge")
	print("  [OK] patrol guard charge preview matches execution")


func _test_stone_bow_shot_preview_matches_execution() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "bow/player should exist")
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent.type == "ranged_attack", "bow should preview ranged attack")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, bow)
	_assert_valid_events(events, "stone_bow")
	var dealt := hp_before - player.hp
	assert(dealt == bow.intent.damage, "stone bow execution should match preview damage")
	_assert_valid_state(state, "stone_bow")
	print("  [OK] stone bow preview matches execution")


func _test_move_preview_matches_executed_path() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "move preview bow/player should exist")
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	var prop := EntityState.create("block_prop", Constants.ENTITY_PROP, Vector2i(3, 2))
	state.add_entity(prop)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(not bow.intent.path.is_empty(), "blocked bow should preview a movement path")
	var expected_end: Vector2i = bow.intent.path[bow.intent.path.size() - 1]
	var events := IntentSystem.execute_intent(state, bow)
	_assert_valid_events(events, "move_preview")
	var move_steps := events.filter(func(ev): return ev.get("type", "") == "move_step")
	assert(move_steps.size() == bow.intent.path.size(), "executed move steps should match preview path length")
	assert(bow.pos == expected_end, "executed move should end at preview destination")
	_assert_valid_state(state, "move_preview")
	print("  [OK] move preview matches executed path")


func _test_explosion_preview_matches_blast_delivery() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	var player := state.get_player()
	assert(guard != null and player != null, "explosion test guard/player should exist")
	_embed_red_gem(state, guard, Constants.GEM_EXPLOSION)
	guard.pos = player.pos + Vector2i(1, 0)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "explosion_attack", "explosion gem should preview explosion_attack")
	assert(player.pos in guard.intent.affected_cells, "explosion preview should include target cell")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	_assert_valid_events(events, "explosion_attack")
	var dealt := hp_before - player.hp
	assert(dealt >= guard.intent.damage, "explosion execution should deal at least preview base damage")
	assert(events.any(func(ev): return ev.get("type", "") == "explode"), "explosion execution should emit explode event")
	_assert_valid_state(state, "explosion_attack")
	print("  [OK] explosion preview matches blast delivery")


func _assert_valid_events(events: Array, label: String) -> void:
	assert(EventValidator.assert_valid(events, label), "event stream should stay valid for %s" % label)


func _assert_valid_state(state: GameState, label: String) -> void:
	assert(BattleInvariantChecker.assert_valid(state, label), "battle invariants should hold for %s" % label)


func _find_unit_by_def(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null


func _embed_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
	var red := unit.get_slot(Constants.SLOT_RED)
	assert(red != null, "unit should have red slot")
	var gem := GemState.new()
	gem.uid = "intent_contract_%s_%s" % [gem_id, unit.uid]
	gem.gem_id = gem_id
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(red)
	state.gems[gem.uid] = gem
	red.gem_uid = gem.uid
