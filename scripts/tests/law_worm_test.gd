extends SceneTree

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Law Worm Test ===")
	_test_worm_consumes_incubates_and_transforms()
	_test_broodmother_alternates_split_and_action()
	_test_empty_broodmother_stays_in_crisis_split()
	_test_stale_gem_plan_retargets_before_execution()
	print("LAW_WORM_TEST_PASS")
	quit()


func _test_worm_consumes_incubates_and_transforms() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 1001)
	var worm := builder.add_unit("law_worm", "unit_law_worm", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var state := builder.finish()
	var gem_uid := _add_ground_gem(state, Constants.GEM_SPLIT, Vector2i(4, 3), Constants.SLOT_BLACK)
	IntentSystem.refresh_unit_intent(state, worm)
	assert(worm.intent.type == "law_worm_consume", "adjacent ground gem should be consumed this action")
	var consume_events := IntentSystem.execute_intent(state, worm)
	assert(worm.pos == Vector2i(4, 3), "worm should move onto the gem cell")
	assert(not state.dropped_gems.has(gem_uid), "consumed gem should leave the ground")
	assert(worm.get_slot(Constants.SLOT_BLACK).gem_uid == gem_uid, "gem should enter its original black slot type")
	assert(StatusRules.law_worm_ready_turn(worm) == state.turn_index + 1, "worm should incubate for one own action cycle")
	var shield := worm.get_status(Constants.STATUS_ARMOR)
	assert(shield != null and shield.value == 5, "incubating worm should gain 5 shield")
	assert(EventValidator.assert_valid(consume_events, "law_worm.consume"))
	worm.hp = 3
	state.turn_index += 1
	IntentSystem.refresh_unit_intent(state, worm)
	assert(worm.intent.type == "law_worm_transform", "worm should transform on its next turn")
	var transform_events := IntentSystem.execute_intent(state, worm)
	assert(worm.uid == "law_worm" and worm.unit_def_id == "unit_broodmother", "transformation should preserve uid in place")
	assert(worm.max_hp == 20 and worm.hp == 18, "transformation should carry the two missing HP into the mother form")
	assert(worm.get_slot(Constants.SLOT_BLACK).gem_uid == gem_uid, "transformation should preserve the swallowed gem")
	assert(worm.get_status(Constants.STATUS_LAW_WORM_INCUBATING) == null, "incubation should end after transformation")
	assert(worm.get_status(Constants.STATUS_ARMOR) == null, "temporary incubation shield should be removed")
	assert(EventValidator.assert_valid(transform_events, "law_worm.transform"))
	assert(BattleInvariantChecker.assert_valid(state, "law_worm.transform"))
	print("  [OK] worm consumes, incubates, and transforms in place")


func _test_broodmother_alternates_split_and_action() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 1002)
	var mother := builder.add_unit("broodmother", "unit_broodmother", Constants.TEAM_ENEMY, Vector2i(5, 4))
	builder.mount_gems(mother, Constants.SLOT_RED, [Constants.GEM_FIRE])
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, mother)
	assert(mother.intent.type == "broodmother_split", "mother's first action should split")
	var planned_spawn_cells: Array[Vector2i] = mother.intent.affected_cells.duplicate()
	assert(planned_spawn_cells.size() <= 2, "spawn preview should show only the two committed brood cells")
	assert(mother.intent.preview_effects.any(func(effect): return effect.kind == "spawn" and effect.cells == planned_spawn_cells), "spawn preview should be a typed effect captured by the action plan")
	var events := IntentSystem.execute_intent(state, mother)
	assert(_living_worm_count(state) == 2, "normal split should hatch two worms")
	var actual_spawn_cells: Array[Vector2i] = []
	for event in events:
		if str(event.get("type", "")) == "spawn" and str(event.get("unit_id", "")) == "unit_law_worm":
			actual_spawn_cells.append(event.get("pos", Vector2i(-1, -1)))
	assert(actual_spawn_cells == planned_spawn_cells, "brood execution must consume the exact cells shown by preview")
	IntentSystem.refresh_unit_intent(state, mother)
	assert(mother.intent.type in ["broodmother_ranged_attack", "broodmother_wait"], "normal mother should alternate to an attack or wait action")
	events.append_array(IntentSystem.execute_intent(state, mother))
	IntentSystem.refresh_unit_intent(state, mother)
	assert(mother.intent.type == "broodmother_split", "attack or wait should alternate back to split")
	assert(EventValidator.assert_valid(events, "broodmother.alternation"))
	assert(BattleInvariantChecker.assert_valid(state, "broodmother.alternation"))
	print("  [OK] gem-bearing mother alternates split and combat action")


func _test_empty_broodmother_stays_in_crisis_split() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 1003)
	var mother := builder.add_unit("crisis_mother", "unit_broodmother", Constants.TEAM_ENEMY, Vector2i(5, 4))
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, mother)
	assert(mother.intent.type == "broodmother_split", "empty mother should enter crisis split")
	var events := IntentSystem.execute_intent(state, mother)
	assert(mother.get_status(Constants.STATUS_BROODMOTHER_CRISIS) != null, "empty mother should show crisis status")
	IntentSystem.refresh_unit_intent(state, mother)
	assert(mother.intent.type == "broodmother_split", "crisis mother should split every action without alternating")
	assert(_living_worm_count(state) == 2, "crisis split should hatch two worms per action")
	assert(EventValidator.assert_valid(events, "broodmother.crisis"))
	assert(BattleInvariantChecker.assert_valid(state, "broodmother.crisis"))
	print("  [OK] empty mother remains in crisis reproduction")


func _test_stale_gem_plan_retargets_before_execution() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 1004)
	var first := builder.add_unit("first_worm", "unit_law_worm", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var second := builder.add_unit("second_worm", "unit_law_worm", Constants.TEAM_ENEMY, Vector2i(5, 3))
	var state := builder.finish()
	var gem_uid := _add_ground_gem(state, Constants.GEM_SPLIT, Vector2i(4, 3), Constants.SLOT_BLACK)
	IntentSystem.refresh_unit_intent(state, first)
	IntentSystem.refresh_unit_intent(state, second)
	assert(first.intent.target_uid == gem_uid and second.intent.target_uid == gem_uid, "both worms should initially plan against the same drop")
	IntentSystem.execute_intent(state, first)
	assert(not second.intent.action_plan.is_applicable(state, second), "consumed gem must invalidate another worm's captured plan")
	IntentSystem.execute_intent(state, second)
	assert(StatusRules.law_worm_ready_turn(second) < 0, "second worm must not consume a stale gem target")
	assert(second.get_slot(Constants.SLOT_BLACK).gem_uid.is_empty(), "stale execution must not duplicate the consumed gem")
	assert(BattleInvariantChecker.assert_valid(state, "law_worm.stale_target"))
	print("  [OK] stale gem plans are invalidated before execution")


func _add_ground_gem(state: GameState, gem_id: String, pos: Vector2i, source_slot_type: String) -> String:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem_uid: String = registry.next_runtime_uid("ground_gem")
	var gem: GemState = registry.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	assert(GemTransfer.to_ground(state, gem, pos, {
		"gem_uid": gem_uid,
		"gem_id": gem_id,
		"source_unit_uid": "fixture_enemy",
		"source_slot_type": source_slot_type,
	}))
	return gem_uid


func _living_worm_count(state: GameState) -> int:
	var count := 0
	for unit: UnitState in state.units.values():
		if unit.alive and unit.unit_def_id == "unit_law_worm":
			count += 1
	return count
