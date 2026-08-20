extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const StateSnapshot = preload("res://scripts/testkit/state_snapshot.gd")
const StateDiff = preload("res://scripts/testkit/state_diff.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const SwapRules = preload("res://scripts/rules/swap_rules.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Swap Relic Test ===")
	root.get_node("AdventureService").start_new_run(20260813)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	_force_relic()
	_test_definition()
	_test_atomic_swap_ignores_distance_and_preserves_invariants()
	_test_once_per_turn_and_next_turn_reset()
	_test_swap_cancels_pending_overload_chain()
	_test_invalid_targets_do_not_mutate()
	_test_controller_two_click_flow_and_cancel()
	root.get_node("RunService").end_run()
	if _failed:
		push_error("SWAP_RELIC_TEST_FAIL")
		quit(1)
		return
	print("SWAP_RELIC_TEST_PASS")
	quit(0)


func _test_definition() -> void:
	var relic_def: Dictionary = root.get_node("DataRegistry").get_relic_def("relic_swap")
	_expect(str(relic_def.get("rarity", "")) == "boss", "swap should be a boss relic")
	_expect(bool(relic_def.get("unique", false)), "swap should be unique")
	_expect(relic_def.get("pool_types", []) == ["boss_drop"], "swap should only enter boss drops")
	_expect((relic_def.get("effects", []) as Array).is_empty(), "swap should not fake extraction or insertion events")
	print("  [OK] definition is unique and boss-only")


func _test_atomic_swap_ignores_distance_and_preserves_invariants() -> void:
	var fixture := _fixture(81)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var enemy: UnitState = fixture["enemy"]
	var player_index: int = fixture["player_index"]
	var enemy_index: int = fixture["enemy_index"]
	var first_uid := str(player.slots[player_index].gem_uid)
	var second_uid := str(enemy.slots[enemy_index].gem_uid)
	var before := StateSnapshot.capture(state, [], false)
	var result := SwapRules.try_swap(state, player, player_index, enemy, enemy_index)
	var after := StateSnapshot.capture(state, [], false)
	var diff := StateDiff.between(before, after)
	_expect(bool(result.get("ok", false)), "far player/enemy gems should swap without a distance check")
	_expect(player.slots[player_index].gem_uid == second_uid, "player slot should receive the enemy gem")
	_expect(enemy.slots[enemy_index].gem_uid == first_uid, "enemy slot should receive the player gem")
	_expect(state.gems[first_uid].owner_uid == enemy.uid and state.gems[first_uid].slot_index == enemy_index, "first gem ownership mirror should follow the swap")
	_expect(state.gems[second_uid].owner_uid == player.uid and state.gems[second_uid].slot_index == player_index, "second gem ownership mirror should follow the swap")
	_expect(not state.player_moved and not state.player_acted, "swap should consume neither move nor attack")
	_expect(state.held_gem_uid.is_empty() and not state.overload_pending, "swap should bypass hand and overload semantics")
	_expect(not diff["units"]["changed"].is_empty() and not diff["gems"]["changed"].is_empty(), "snapshot diff should contain both slot and ownership changes")
	_expect(after["invariants"].is_empty(), "swap should preserve battle invariants: %s" % str(after["invariants"]))
	_expect(after["event_violations"].is_empty(), "event shape validation should remain clean when swap emits no combat event")
	print("  [OK] atomic cross-board swap preserves gem ownership and action economy")


func _test_once_per_turn_and_next_turn_reset() -> void:
	var fixture := _fixture(82)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var enemy: UnitState = fixture["enemy"]
	var player_index: int = fixture["player_index"]
	var enemy_index: int = fixture["enemy_index"]
	_expect(SwapRules.try_swap(state, player, player_index, enemy, enemy_index).get("ok", false), "first swap should succeed")
	var first_uid := str(player.slots[player_index].gem_uid)
	var second_uid := str(enemy.slots[enemy_index].gem_uid)
	var blocked := SwapRules.try_swap(state, player, player_index, enemy, enemy_index)
	_expect(not blocked.get("ok", false), "second swap in the same turn should fail")
	_expect(player.slots[player_index].gem_uid == first_uid and enemy.slots[enemy_index].gem_uid == second_uid, "blocked second use should not move either gem")
	state.turn_index += 1
	_expect(SwapRules.try_swap(state, player, player_index, enemy, enemy_index).get("ok", false), "a new player turn should restore swap")
	print("  [OK] swap is consumed once per turn and resets by turn index")


func _test_swap_cancels_pending_overload_chain() -> void:
	var fixture := _fixture(85)
	var state: GameState = fixture["state"]
	state.overload_pending = true
	state.overload_pending_turn = state.turn_index
	state.overload_last_action = Constants.ACTION_INSERT
	state.overload_last_insert_turn = state.turn_index
	var result := SwapRules.try_swap(
		state,
		fixture["player"],
		fixture["player_index"],
		fixture["enemy"],
		fixture["enemy_index"]
	)
	_expect(bool(result.get("ok", false)), "swap should succeed while an overload warning is pending")
	_expect(not state.overload_pending, "swap is a non-insert action and should cancel the pending overload warning")
	_expect(state.overload_last_action == Constants.ACTION_RELIC_SWAP, "swap should become the last overload-chain action")
	print("  [OK] swap cannot carry a pending insert chain into the next insertion")


func _test_invalid_targets_do_not_mutate() -> void:
	var fixture := _fixture(83)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var enemy: UnitState = fixture["enemy"]
	var player_index: int = fixture["player_index"]
	var enemy_index: int = fixture["enemy_index"]
	var player_uid := str(player.slots[player_index].gem_uid)
	var enemy_uid := str(enemy.slots[enemy_index].gem_uid)
	enemy.slots[enemy_index].locked = true
	enemy.slots[enemy_index].lock_type = Constants.LOCK_ARMOR
	var locked := SwapRules.try_swap(state, player, player_index, enemy, enemy_index)
	_expect(not locked.get("ok", false), "locked target should be rejected")
	_expect(player.slots[player_index].gem_uid == player_uid and enemy.slots[enemy_index].gem_uid == enemy_uid, "locked rejection should be atomic")
	enemy.slots[enemy_index].locked = false
	enemy.slots[enemy_index].lock_type = ""
	state.gems[enemy_uid].gem_id = Constants.GEM_COUNTERFEIT
	_expect(not SwapRules.can_select_slot(state, enemy, enemy_index).get("ok", false), "counterfeit should not be selectable")
	state.gems[enemy_uid].gem_id = Constants.GEM_POISON
	state.overload_echo_gems[enemy_uid] = state.turn_index + 1
	_expect(not SwapRules.can_select_slot(state, enemy, enemy_index).get("ok", false), "overload echo should not be selectable")
	state.overload_echo_gems.erase(enemy_uid)
	GemTransfer.remove(state, enemy_uid)
	var vanished := SwapRules.try_swap(state, player, player_index, enemy, enemy_index)
	_expect(not vanished.get("ok", false), "an empty second target should fail at confirmation")
	_expect(player.slots[player_index].gem_uid == player_uid, "vanished target should leave the first gem untouched")
	print("  [OK] locks, special gems, and invalidated targets fail without partial writes")


func _test_controller_two_click_flow_and_cancel() -> void:
	var fixture := _fixture(84)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var enemy: UnitState = fixture["enemy"]
	var player_index: int = fixture["player_index"]
	var enemy_index: int = fixture["enemy_index"]
	var controller := _controller_for(state)
	controller.select_action(Constants.ACTION_RELIC_SWAP)
	var first := controller.try_select_swap_slot(player.uid, player_index)
	_expect(first.get("stage", "") == "source" and controller.has_swap_source(), "first click should store the source gem")
	_expect(not controller.check_slot_action(player.uid, player_index).get("ok", false), "source slot should not be a legal second target")
	controller.select_action(Constants.ACTION_NONE)
	_expect(not controller.has_swap_source() and not SwapRules.was_used_this_turn(state), "cancelling after the first click should not consume swap")
	controller.select_action(Constants.ACTION_RELIC_SWAP)
	controller.try_select_swap_slot(player.uid, player_index)
	var second := controller.try_select_swap_slot(enemy.uid, enemy_index)
	_expect(second.get("stage", "") == "complete", "second click should immediately complete the swap")
	_expect(controller.selected_action == Constants.ACTION_NONE and not controller.has_swap_source(), "completed swap should exit active mode")
	_expect(SwapRules.was_used_this_turn(state), "completed two-click flow should consume this turn's use")
	print("  [OK] controller follows button -> first gem -> second gem -> complete")


func _fixture(seed: int) -> Dictionary:
	var builder := ScenarioBuilder.new("fission_slime_test", seed, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_EXPLOSION])
	var enemy := builder.add_unit(
		"swap_far_enemy_%d" % seed,
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(7, 7),
		{"hp": 40, "max_hp": 40}
	)
	builder.clear_slots(enemy)
	builder.mount_gems(enemy, Constants.SLOT_BLUE, [Constants.GEM_POISON])
	var state := builder.finish()
	state.phase = Constants.PHASE_PLAYER
	IntentSystem.refresh_all_intents(state)
	return {
		"state": state,
		"player": player,
		"enemy": enemy,
		"player_index": _occupied_index(player),
		"enemy_index": _occupied_index(enemy),
	}


func _controller_for(state: GameState) -> BattleController:
	var controller := BattleController.new()
	controller.state = state
	controller.selected_unit_uid = state.player_uid
	return controller


func _occupied_index(unit: UnitState) -> int:
	for index in range(unit.slots.size()):
		if not unit.slots[index].gem_uid.is_empty():
			return index
	return -1


func _force_relic() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_swap")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
