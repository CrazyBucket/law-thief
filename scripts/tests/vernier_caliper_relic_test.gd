extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Vernier Caliper Relic Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260718)
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	_test_attack_between_two_move_segments()
	_test_rooted_and_paralyzed_cancel_stored_move()
	_test_movement_loss_reduces_stored_move()
	_test_turn_end_clears_stored_move()
	_test_without_relic_move_stays_single_use()
	run_service.end_run()
	if _failed:
		push_error("VERNIER_CALIPER_RELIC_TEST_FAIL")
		quit(1)
		return
	print("VERNIER_CALIPER_RELIC_TEST_PASS")
	quit(0)


func _test_attack_between_two_move_segments() -> void:
	_force_relic(true)
	var controller := _build_controller(true)
	var state := controller.state
	var player := state.get_player()
	var enemy: UnitState = state.units["caliper_target"]
	var first := controller.try_move(Vector2i(2, 1))
	_expect(bool(first.get("ok", false)), "first move segment should succeed")
	_expect(state.player_moved, "first segment should consume the normal move use")
	_expect(state.split_move_remaining == 2, "first segment should store two movement points")
	_expect_valid(state, first.get("move_events", []))

	var attack := controller.try_attack(enemy.uid)
	_expect(bool(attack.get("ok", false)), "normal attack should fit between move segments")
	_expect(state.split_move_remaining == 2, "attack should preserve stored movement")
	_expect(controller.can_use_action(Constants.ACTION_MOVE), "stored movement should reactivate the move command")

	var second := controller.try_move(Vector2i(2, 3))
	_expect(bool(second.get("ok", false)), "second move segment should succeed within the stored budget")
	_expect(state.split_move_remaining == 0, "second segment should consume the stored movement")
	_expect(not controller.can_use_action(Constants.ACTION_MOVE), "a third move should not be available")
	_expect_valid(state, second.get("move_events", []))
	print("  [OK] attack can be inserted between two bounded move segments")


func _test_rooted_and_paralyzed_cancel_stored_move() -> void:
	_force_relic(true)
	var rooted_controller := _build_controller(false)
	var rooted_state := rooted_controller.state
	var rooted_player := rooted_state.get_player()
	_expect(bool(rooted_controller.try_move(Vector2i(2, 1)).get("ok", false)), "rooted setup move should succeed")
	StatusRules.apply_rooted(rooted_state, rooted_player, 1, "caliper_hazard")
	_expect(rooted_state.split_move_remaining == 0, "rooted should immediately clear stored movement")

	var paralyzed_controller := _build_controller(false)
	var paralyzed_state := paralyzed_controller.state
	var paralyzed_player := paralyzed_state.get_player()
	_expect(bool(paralyzed_controller.try_move(Vector2i(2, 1)).get("ok", false)), "paralyzed setup move should succeed")
	StatusRules.apply_paralyzed(paralyzed_state, paralyzed_player, 1, "caliper_hazard")
	_expect(paralyzed_state.split_move_remaining == 0, "paralyzed should immediately clear stored movement")
	print("  [OK] rooted and paralyzed invalidate the second segment")


func _test_movement_loss_reduces_stored_move() -> void:
	_force_relic(true)
	var controller := _build_controller(false)
	var state := controller.state
	var player := state.get_player()
	_expect(bool(controller.try_move(Vector2i(2, 1)).get("ok", false)), "movement-loss setup move should succeed")
	StatusRules.apply_slowed(state, player, 1, "caliper_hazard", 0)
	_expect(state.split_move_remaining == 1, "slowed should immediately reduce stored movement by one")
	player.move_points = 2
	_expect(controller.stored_split_move_remaining(player) == 0, "stored movement should expire when its remainder reaches zero")
	_expect(not controller.can_use_action(Constants.ACTION_MOVE), "expired stored movement should not enable movement")
	print("  [OK] movement capacity loss reduces and can exhaust the stored remainder")


func _test_turn_end_clears_stored_move() -> void:
	_force_relic(true)
	var controller := _build_controller(false)
	_expect(bool(controller.try_move(Vector2i(2, 1)).get("ok", false)), "turn-end setup move should succeed")
	controller.begin_enemy_phase()
	_expect(controller.state.split_move_remaining == 0, "ending the player turn should clear stored movement")
	print("  [OK] turn end clears stored movement")


func _test_without_relic_move_stays_single_use() -> void:
	_force_relic(false)
	var controller := _build_controller(false)
	var first := controller.try_move(Vector2i(2, 1))
	_expect(bool(first.get("ok", false)), "baseline move should succeed")
	_expect(controller.state.split_move_remaining == 0, "baseline movement should not create stored movement")
	_expect(not controller.can_use_action(Constants.ACTION_MOVE), "baseline movement should remain single use")
	print("  [OK] movement remains unchanged without the relic")


func _build_controller(with_enemy: bool) -> BattleController:
	var builder := ScenarioBuilder.new("template_a", 1818, true)
	var player := builder.player()
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"move_points": 3})
	if with_enemy:
		builder.add_unit("caliper_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 1), {
			"hp": 100,
			"max_hp": 100,
		})
	else:
		builder.add_unit("caliper_witness", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(7, 7), {
			"hp": 100,
			"max_hp": 100,
		})
	var controller := BattleController.new()
	controller.state = builder.finish()
	controller.selected_unit_uid = player.uid
	return controller


func _force_relic(enabled: bool) -> void:
	var run: RunState = root.get_node("RunService").get_run()
	if run == null:
		_fail("active run missing for relic test")
		return
	run.owned_relics.clear()
	if enabled:
		run.owned_relics.append("relic_vernier_caliper")


func _expect_valid(state: GameState, events: Array) -> void:
	var invariant_errors := BattleInvariantChecker.check_all(state)
	var event_errors := EventValidator.validate_events(events)
	_expect(invariant_errors.is_empty(), "battle invariants should hold: %s" % [invariant_errors])
	_expect(event_errors.is_empty(), "movement events should have the required shape: %s" % [event_errors])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
