extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const RelicBattleRules = preload("res://scripts/rules/relic_battle_rules.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Simple Relics Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260812)
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	_test_defs_are_unique_and_match_rarity()
	_test_bandage_shields_extract_source()
	_test_knee_pad_waits_for_completed_move()
	_test_exit_whistle_requires_real_intent_change_once_per_turn()
	_test_flywheel_stores_unused_move_and_survives_a_miss()
	_test_relic_state_clones_without_aliasing()
	run_service.end_run()
	if _failed:
		push_error("SIMPLE_RELICS_TEST_FAIL")
		quit(1)
		return
	print("SIMPLE_RELICS_TEST_PASS")
	quit(0)


func _test_defs_are_unique_and_match_rarity() -> void:
	var registry: Node = root.get_node("DataRegistry")
	var expected := {
		"relic_bandage": "common",
		"relic_knee_pad": "common",
		"relic_exit_whistle": "common",
		"relic_flywheel": "boss",
	}
	for relic_id in expected:
		var relic_def: Dictionary = registry.get_relic_def(relic_id)
		_expect(not relic_def.is_empty(), "%s should be registered" % relic_id)
		_expect(bool(relic_def.get("unique", false)), "%s should be unique" % relic_id)
		_expect(str(relic_def.get("rarity", "")) == expected[relic_id], "%s rarity mismatch" % relic_id)
	print("  [OK] four simple relics are registered with unique acquisition")


func _test_bandage_shields_extract_source() -> void:
	_force_relic("relic_bandage")
	var state := _battle_state(11, Vector2i(2, 2), Vector2i(3, 2), true)
	var player := state.get_player()
	var enemy := state.units.get("simple_enemy") as UnitState
	var slot := enemy.get_slot(Constants.SLOT_RED)
	var result := GemRules.extract(state, player, enemy, slot)
	_expect(bool(result.get("ok", false)), "bandage setup extract should succeed")
	_expect(StatusRules.get_shield(enemy) == 2, "bandage should give the extracted unit two shield")
	_expect(StatusRules.get_shield(player) == 0, "bandage should not redirect enemy shield to the player")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "bandage should preserve battle invariants")
	print("  [OK] bandage shields the unit that lost its gem")


func _test_knee_pad_waits_for_completed_move() -> void:
	_force_relics(["relic_knee_pad", "relic_vernier_caliper"])
	var state := _battle_state(12, Vector2i(1, 2), Vector2i(3, 2), false)
	var controller := _controller_for(state)
	var first_result := controller.try_move(Vector2i(2, 2))
	_expect(bool(first_result.get("ok", false)), "first knee-pad movement segment should succeed")
	_expect(StatusRules.get_shield(state.get_player()) == 0, "knee pad should wait while split movement remains")
	var second_result := controller.try_move(Vector2i(3, 3))
	_expect(bool(second_result.get("ok", false)), "second knee-pad movement segment should succeed")
	_expect(StatusRules.get_shield(state.get_player()) == 3, "ending movement next to an enemy should grant three shield")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "knee pad should preserve battle invariants")
	print("  [OK] knee pad resolves after a completed voluntary move")


func _test_exit_whistle_requires_real_intent_change_once_per_turn() -> void:
	_force_relic("relic_exit_whistle")
	var state := _battle_state(13, Vector2i(2, 2), Vector2i(3, 2), true)
	var controller := _controller_for(state)
	var player := state.get_player()
	var enemy := state.units.get("simple_enemy") as UnitState
	var red_slot_index := enemy.slots.find(enemy.get_slot(Constants.SLOT_RED))
	var base_move := player.move_points
	root.get_node("RelicEffectRegistry").fire_event("after_gem_operation", state, {
		"actor_uid": player.uid,
		"enemy_intent_changed": false,
	})
	_expect(player.move_points == base_move, "an unchanged enemy intent should not trigger exit whistle")
	var extract_result := controller.try_extract("simple_enemy", red_slot_index)
	_expect(bool(extract_result.get("ok", false)), "exit-whistle extract should succeed")
	_expect(player.move_points == base_move + 1, "a real enemy intent change should grant one temporary move")
	var insert_result := controller.try_insert("simple_enemy", red_slot_index)
	_expect(bool(insert_result.get("ok", false)), "exit-whistle insert should succeed")
	_expect(player.move_points == base_move + 1, "exit whistle should trigger at most once per player turn")
	RelicBattleRules.clear_temp_move(state)
	_expect(player.move_points == base_move, "unused temporary movement should be removable at turn end")
	print("  [OK] exit whistle uses semantic intent change and a per-turn lock")


func _test_flywheel_stores_unused_move_and_survives_a_miss() -> void:
	_force_relic("relic_flywheel")
	var state := _battle_state(14, Vector2i(2, 2), Vector2i(5, 2), false)
	var player := state.get_player()
	var enemy := state.units.get("simple_enemy") as UnitState
	player.base_attack = 4
	player.move_points = 3
	enemy.hp = 100
	enemy.max_hp = 100
	RelicBattleRules.begin_player_turn(state)
	root.get_node("RelicEffectRegistry").fire_event("turn_end", state, {"turn_index": state.turn_index})
	_expect(state.relic_battle.flywheel_layers == 3, "three unused movement should become three flywheel layers")
	var miss_result := CombatRules.ranged_attack(state, player, enemy.pos, -1, {
		"manual_player_shot": true,
		"force_miss": true,
	})
	_expect(bool(miss_result.get("ok", false)), "forced-miss flywheel shot should resolve")
	_expect(enemy.hp == 100, "forced-miss flywheel shot should deal no damage")
	_expect(state.relic_battle.flywheel_layers == 3, "a missed shot should retain flywheel layers")
	var controller := _controller_for(state)
	var hit_result := controller.try_attack("simple_enemy")
	_expect(bool(hit_result.get("ok", false)), "flywheel hit should resolve")
	_expect(enemy.hp == 90, "three flywheel layers should add six damage to a four-damage shot")
	_expect(state.relic_battle.flywheel_layers == 0, "a direct manual-shot hit should clear flywheel layers")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "flywheel should preserve battle invariants")
	print("  [OK] flywheel stores unused move, buffs the shot, and survives a miss")


func _test_relic_state_clones_without_aliasing() -> void:
	var state := _battle_state(15, Vector2i(2, 2), Vector2i(5, 2), false)
	state.relic_battle.flywheel_layers = 4
	state.relic_battle.turn_flags["sample"] = true
	var snapshot := state.clone()
	snapshot.relic_battle.flywheel_layers = 1
	snapshot.relic_battle.turn_flags["sample"] = false
	_expect(state.relic_battle.flywheel_layers == 4, "cloned relic layers should not alias real state")
	_expect(bool(state.relic_battle.turn_flags.get("sample", false)), "cloned relic flags should not alias real state")
	print("  [OK] relic battle state is isolated in presentation clones")


func _battle_state(seed: int, player_pos: Vector2i, enemy_pos: Vector2i, with_red_gem: bool) -> GameState:
	var builder := ScenarioBuilder.new("template_a", seed, true)
	var player := builder.player()
	builder.move(player, player_pos)
	builder.clear_slots(player)
	var enemy := builder.add_unit("simple_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, enemy_pos, {
		"hp": 30,
		"max_hp": 30,
	})
	builder.clear_slots(enemy)
	if with_red_gem:
		builder.mount_gems(enemy, Constants.SLOT_RED, [Constants.GEM_EXPLOSION])
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


func _force_relic(relic_id: String) -> void:
	_force_relics([relic_id])


func _force_relics(relic_ids: Array) -> void:
	var run: RunState = root.get_node("RunService").get_run()
	if run == null:
		_fail("active run missing for simple relic test")
		return
	run.owned_relics.clear()
	for relic_id in relic_ids:
		run.owned_relics.append(str(relic_id))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
