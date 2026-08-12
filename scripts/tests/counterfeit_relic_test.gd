extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const RelicBattleRules = preload("res://scripts/rules/relic_battle_rules.gd")
const CounterfeitRules = preload("res://scripts/rules/counterfeit_rules.gd")
const EventValidator = preload("res://scripts/debug/event_validator.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Counterfeit Relic Test ===")
	root.get_node("AdventureService").start_new_run(20260812)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	_test_definition_and_pool_exclusion()
	_test_counterfeit_delays_lawless_until_enemy_finishes_action()
	_test_only_first_enemy_extraction_each_turn_is_counterfeited()
	_test_counterfeit_disappears_before_enemy_death_hooks_and_drops()
	_test_special_lawless_behavior_is_deferred()
	root.get_node("RunService").end_run()
	if _failed:
		push_error("COUNTERFEIT_RELIC_TEST_FAIL")
		quit(1)
		return
	print("COUNTERFEIT_RELIC_TEST_PASS")
	quit(0)


func _test_definition_and_pool_exclusion() -> void:
	var registry: Node = root.get_node("DataRegistry")
	var relic_def: Dictionary = registry.get_relic_def("relic_counterfeit")
	var gem_def: Dictionary = registry.get_gem_def(Constants.GEM_COUNTERFEIT)
	_expect(str(relic_def.get("rarity", "")) == "rare", "counterfeit relic should be rare")
	_expect(bool(relic_def.get("unique", false)), "counterfeit relic should be unique")
	_expect(not bool(gem_def.get("allow_random_pool", true)), "counterfeit gem must opt out of random pools")
	_expect((gem_def.get("ability_profiles", {}) as Dictionary).is_empty(), "counterfeit gem must have no abilities")
	for source_id in registry.get_gem_pool_source_ids():
		var candidates: Array[String] = registry.get_spawnable_gem_ids_for_source(str(source_id))
		_expect(
			Constants.GEM_COUNTERFEIT not in candidates,
			"counterfeit gem leaked into ordinary pool %s" % source_id
		)
	print("  [OK] special gem is effectless and excluded from every ordinary pool")


func _test_counterfeit_delays_lawless_until_enemy_finishes_action() -> void:
	_force_relic()
	var state := _single_enemy_state(11, "unit_patrol_guard", Constants.GEM_EXPLOSION)
	var player := state.get_player()
	var enemy := state.units.get("counterfeit_enemy") as UnitState
	var slot := enemy.get_slot(Constants.SLOT_RED)
	var original_uid := slot.gem_uid
	var result := GemRules.extract(state, player, enemy, slot)
	_expect(bool(result.get("ok", false)), "counterfeit setup extraction should succeed")
	var fake: GemState = state.gems.get(slot.gem_uid, null)
	_expect(state.held_gem_uid == original_uid, "the real gem should enter the player's hand")
	_expect(fake != null and fake.gem_id == Constants.GEM_COUNTERFEIT, "the original slot should contain a counterfeit gem")
	_expect(slot.locked and slot.lock_type == Constants.LOCK_COUNTERFEIT, "counterfeit slot should be locked")
	_expect(not StatusRules.is_lawless(enemy), "enemy should not enter lawless immediately")
	var gem_context := GemTagResolver.build_context(state, enemy, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
	_expect((gem_context.get("tags", []) as Array).is_empty(), "locked counterfeit should contribute no gem tag")
	var fake_uid := slot.gem_uid
	var execution := _controller_for(state).execute_single_enemy(enemy)
	_expect(EventValidator.validate_events(execution.get("events", [])).is_empty(), "enemy action events should stay valid")
	_expect(slot.gem_uid.is_empty() and not slot.locked, "counterfeit should break and unlock its slot after the action")
	_expect(not state.gems.has(fake_uid), "broken counterfeit gem should leave the gem registry")
	_expect(StatusRules.is_lawless(enemy), "enemy should enter lawless after its counterfeit breaks")
	_expect(StatusRules.get_lawless_gem_uid(enemy) == original_uid, "lawless should still track the real stolen gem")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "counterfeit action lifecycle should preserve invariants")
	print("  [OK] real gem is stolen now and lawless is deferred until the enemy action ends")


func _test_only_first_enemy_extraction_each_turn_is_counterfeited() -> void:
	_force_relic()
	var builder := ScenarioBuilder.new("template_a", 12, true)
	var player := builder.player()
	builder.move(player, Vector2i(2, 2))
	builder.clear_slots(player)
	var first := builder.add_unit("first_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 2))
	var second := builder.add_unit("second_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(2, 3))
	builder.clear_slots(first).mount_gems(first, Constants.SLOT_RED, [Constants.GEM_EXPLOSION])
	builder.clear_slots(second).mount_gems(second, Constants.SLOT_RED, [Constants.GEM_POISON])
	var state := _finish_state(builder)
	var first_slot := first.get_slot(Constants.SLOT_RED)
	var second_slot := second.get_slot(Constants.SLOT_RED)
	_expect(bool(GemRules.extract(state, player, first, first_slot).get("ok", false)), "first extraction should succeed")
	var player_red := player.get_slot(Constants.SLOT_RED)
	_expect(player_red != null, "player fixture should have a red slot")
	_expect(bool(GemRules.insert(state, player, player, player_red).get("ok", false)), "real gem should be stowed before second extraction")
	_expect(bool(GemRules.extract(state, player, second, second_slot).get("ok", false)), "second extraction should succeed")
	_expect(second_slot.gem_uid.is_empty(), "second extraction in the turn should not leave another counterfeit")
	_expect(StatusRules.is_lawless(second), "second extracted enemy should resolve lawless immediately")
	_expect(state.relic_battle.counterfeits.size() == 1, "only one counterfeit record should exist per player turn")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "once-per-turn extraction should preserve invariants")
	print("  [OK] only the first enemy extraction in a player turn leaves a counterfeit")


func _test_counterfeit_disappears_before_enemy_death_hooks_and_drops() -> void:
	_force_relic()
	var state := _single_enemy_state(13, "unit_patrol_guard", Constants.GEM_EXPLOSION)
	var player := state.get_player()
	var enemy := state.units.get("counterfeit_enemy") as UnitState
	var slot := enemy.get_slot(Constants.SLOT_RED)
	_expect(bool(GemRules.extract(state, player, enemy, slot).get("ok", false)), "death cleanup extraction should succeed")
	var fake_uid := slot.gem_uid
	CombatRules.apply_damage(state, enemy, enemy.hp + 10, player.uid, "counterfeit_test")
	_expect(not enemy.alive, "enemy should die in cleanup scenario")
	_expect(not state.gems.has(fake_uid), "counterfeit should be removed on death")
	_expect(not state.dropped_gems.has(fake_uid), "counterfeit should never become a drop")
	_expect(state.relic_battle.counterfeits.is_empty(), "death should clear counterfeit runtime records")
	_expect(not StatusRules.is_lawless(enemy), "death cleanup should not resolve delayed lawless")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "counterfeit death cleanup should preserve invariants")
	print("  [OK] dying before action removes the counterfeit without drops or gem death effects")


func _test_special_lawless_behavior_is_deferred() -> void:
	_force_relic()
	var state := _single_enemy_state(14, "unit_ruffled_crow", Constants.GEM_FLURRY)
	var enemy := state.units.get("counterfeit_enemy") as UnitState
	var slot := enemy.get_slot(Constants.SLOT_RED)
	var original_uid := slot.gem_uid
	_expect(bool(GemRules.extract(state, state.get_player(), enemy, slot).get("ok", false)), "ruffled crow extraction should succeed")
	_expect(not StatusRules.is_lawless(enemy), "special lawless hook should be deferred while counterfeit remains")
	CounterfeitRules.break_after_action(state, enemy)
	_expect(StatusRules.is_lawless(enemy), "special lawless hook should run when counterfeit breaks")
	_expect(StatusRules.get_lawless_gem_uid(enemy) == original_uid, "special lawless hook should receive the original gem uid")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "special lawless deferral should preserve invariants")
	print("  [OK] behavior-specific lawless hooks receive the original extraction when the fake breaks")


func _single_enemy_state(seed: int, unit_def_id: String, gem_id: String) -> GameState:
	var builder := ScenarioBuilder.new("template_a", seed, true)
	var player := builder.player()
	builder.move(player, Vector2i(2, 2))
	builder.clear_slots(player)
	var enemy := builder.add_unit(
		"counterfeit_enemy",
		unit_def_id,
		Constants.TEAM_ENEMY,
		Vector2i(3, 2),
		{"hp": 30, "max_hp": 30}
	)
	builder.clear_slots(enemy)
	builder.mount_gems(enemy, Constants.SLOT_RED, [gem_id])
	return _finish_state(builder)


func _finish_state(builder: ScenarioBuilder) -> GameState:
	var state := builder.finish()
	state.phase = Constants.PHASE_PLAYER
	state.player_moved = false
	state.player_acted = false
	IntentSystem.refresh_all_intents(state)
	RelicBattleRules.begin_player_turn(state)
	return state


func _controller_for(state: GameState) -> BattleController:
	var controller := BattleController.new()
	controller.state = state
	controller.selected_unit_uid = state.player_uid
	return controller


func _force_relic() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	if run == null:
		_fail("active run missing for counterfeit relic test")
		return
	run.owned_relics.clear()
	run.owned_relics.append("relic_counterfeit")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
