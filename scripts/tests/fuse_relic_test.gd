extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const FuseRules = preload("res://scripts/rules/fuse_rules.gd")

var _failed := false
var _gem_serial := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Fuse Relic Test ===")
	root.get_node("AdventureService").start_new_run(20260813)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	_force_relic()
	_test_definition()
	_test_preview_does_not_consume_and_first_overload_is_deferred()
	_test_existing_mutation_and_second_overload_remain_active()
	_test_removed_deferred_slot_does_not_materialize()
	_test_victory_materializes_and_persists_mutation()
	_test_post_battle_embed_does_not_consume_fuse()
	_test_mid_battle_restore_keeps_fuse_consumed()
	root.get_node("RunService").end_run()
	if _failed:
		push_error("FUSE_RELIC_TEST_FAIL")
		quit(1)
		return
	print("FUSE_RELIC_TEST_PASS")
	quit(0)


func _test_definition() -> void:
	var relic_def: Dictionary = root.get_node("DataRegistry").get_relic_def("relic_fuse")
	_expect(str(relic_def.get("rarity", "")) == "rare", "fuse should be rare")
	_expect(bool(relic_def.get("unique", false)), "fuse should be unique")
	_expect((relic_def.get("effects", []) as Array).size() == 2, "fuse should own overload and victory effects")
	print("  [OK] definition is rare and unique")


func _test_preview_does_not_consume_and_first_overload_is_deferred() -> void:
	var fixture := _battle_fixture(51)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var controller: BattleController = fixture["controller"]
	_give_held_gem(state)
	var preview := controller.try_insert(player.uid, 0)
	_expect(bool(preview.get("overload_armed", false)), "occupied slot should show an overload preview first")
	_expect(not state.relic_battle.fuse_triggered, "overload preview must not consume fuse")
	controller.select_action("")
	var preview_again := controller.try_insert(player.uid, 0)
	var forced := controller.try_insert(player.uid, 0)
	_expect(bool(preview_again.get("overload_armed", false)), "cancelled preview should be available again")
	_expect(bool(forced.get("overload_forced", false)), "second confirmed insert should create a formal overload slot")
	_expect(bool(forced.get("mutation_deferred", false)), "first formal overload should report fuse deferral")
	_expect(state.relic_battle.fuse_triggered, "formal overload should consume fuse for this battle")
	var deferred_slot: SlotState = player.slots.back()
	_expect(deferred_slot.overload_mutation_deferred, "new overload slot should own the fuse placeholder")
	_expect(not deferred_slot.gem_uid.is_empty(), "deferred overload gem should still be installed immediately")
	_expect(OverloadRules.overload_gem_count(state) == 1, "deferred slot should remain an ordinary overload layer")
	_expect(OverloadRules.overload_gem_count(state) - FuseRules.deferred_mutation_count(state) == 0, "deferred slot should not enable a mutation this battle")
	OverloadRules.activate_pending(state)
	_expect(state.overload_active_mutations.is_empty(), "first deferred overload must not activate a mutation")
	_expect(not state.overload_pending, "fuse should settle the pending overload at phase transition")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "fuse deferral should preserve battle invariants")
	print("  [OK] preview is free and first formal overload is deferred")


func _test_existing_mutation_and_second_overload_remain_active() -> void:
	var fixture := _battle_fixture(52)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var controller: BattleController = fixture["controller"]
	_add_existing_overload(state, player)
	state.overload_active_mutations = [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT]
	_force_overload(controller, state, player)
	OverloadRules.activate_pending(state)
	_expect(state.overload_active_mutations == [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT], "fuse must not pause or remove an existing mutation")
	state.turn_index += 1
	state.phase = Constants.PHASE_PLAYER
	OverloadRules.record_non_insert_action(state, "next_turn")
	var second := _force_overload(controller, state, player)
	_expect(not bool(second.get("mutation_deferred", false)), "second overload in the same battle should not be deferred")
	OverloadRules.activate_pending(state)
	_expect(state.overload_active_mutations == [
		Constants.OVERLOAD_LAWLESS_ANY_EXTRACT,
		Constants.OVERLOAD_GEM_OP_DAMAGE,
	], "second overload should activate the next deterministic mutation")
	_expect(FuseRules.deferred_mutation_count(state) == 1, "only the first overload slot should remain deferred")
	print("  [OK] existing and later mutations remain active")


func _test_removed_deferred_slot_does_not_materialize() -> void:
	var fixture := _battle_fixture(53)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	var forced := _force_overload(fixture["controller"], state, player)
	var deferred_slot: SlotState = player.slots.back()
	_expect(bool(forced.get("mutation_deferred", false)), "removal fixture should start with a deferred overload")
	var extracted := GemRules.extract(state, player, player, deferred_slot)
	_expect(bool(extracted.get("ok", false)), "deferred overload gem should remain operable")
	_expect(not FuseRules.has_deferred_mutation(state), "removing the corresponding slot should remove its placeholder")
	root.get_node("RelicEffectRegistry").fire_event("battle_win", state, {"encounter_id": "fuse_removed"})
	_expect(state.overload_active_mutations.is_empty(), "removed deferred slot must not create a post-battle mutation")
	print("  [OK] removed placeholder does not materialize")


func _test_victory_materializes_and_persists_mutation() -> void:
	var fixture := _battle_fixture(54)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	_force_overload(fixture["controller"], state, player)
	OverloadRules.activate_pending(state)
	state.phase = Constants.PHASE_ENDED
	root.get_node("RelicEffectRegistry").fire_event("battle_win", state, {"encounter_id": "fuse_win"})
	_expect(state.overload_active_mutations == [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT], "victory should materialize the normal next mutation")
	_expect(not FuseRules.has_deferred_mutation(state), "victory should clear the fuse placeholder")
	root.get_node("RunService").capture_player_battle_state(state)
	var run: RunState = root.get_node("RunService").get_run()
	_expect(run.overload_active_mutations == [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT], "materialized mutation should enter the run save")
	for raw_slot in run.player_slot_gems:
		if raw_slot is Dictionary:
			_expect(not bool(raw_slot.get("overload_mutation_deferred", false)), "settled save must not retain a fuse placeholder")
	var restored: GameState = root.get_node("DataRegistry").create_battle_state("tutorial_001", 5401, "", true)
	_expect(restored.overload_active_mutations == [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT], "next battle should restore the materialized mutation")
	_expect(not FuseRules.has_deferred_mutation(restored), "next battle should restore an ordinary overload slot")
	_expect(BattleInvariantChecker.check_all(restored).is_empty(), "restored fuse state should preserve invariants")
	print("  [OK] victory materializes and persists the mutation")


func _test_post_battle_embed_does_not_consume_fuse() -> void:
	var fixture := _battle_fixture(55)
	var state: GameState = fixture["state"]
	var player: UnitState = fixture["player"]
	state.phase = Constants.PHASE_ENDED
	_give_held_gem(state)
	var result := GemRules.insert(state, player, player, player.slots[0], true)
	_expect(bool(result.get("overload_forced", false)), "post-battle reward setup should still create an overload slot")
	_expect(not bool(result.get("mutation_deferred", false)), "post-battle reward embed must not arm fuse")
	_expect(not state.relic_battle.fuse_triggered, "post-battle embed must leave the battle trigger unused")
	print("  [OK] post-battle reward embed is outside fuse timing")


func _test_mid_battle_restore_keeps_fuse_consumed() -> void:
	var fixture := _battle_fixture(56)
	var state: GameState = fixture["state"]
	_force_overload(fixture["controller"], state, fixture["player"])
	root.get_node("RunService").capture_player_battle_state(state)
	var restored: GameState = root.get_node("DataRegistry").create_battle_state("tutorial_001", 5601, "", true)
	_expect(FuseRules.has_deferred_mutation(restored), "mid-battle recovery should restore the fuse placeholder")
	_expect(restored.relic_battle.fuse_triggered, "restored placeholder should keep fuse consumed for this battle")
	print("  [OK] mid-battle recovery cannot trigger fuse twice")


func _battle_fixture(seed: int) -> Dictionary:
	var builder := ScenarioBuilder.new("template_a", seed, true)
	var player := builder.player()
	builder.move(player, Vector2i(2, 2))
	builder.clear_slots(player)
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_EXPLOSION])
	var enemy := builder.add_unit("fuse_guard", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 5), {
		"hp": 30, "max_hp": 30,
	})
	builder.clear_slots(enemy)
	var state := builder.finish()
	state.phase = Constants.PHASE_PLAYER
	state.player_acted = false
	var controller := BattleController.new()
	controller.state = state
	controller.selected_unit_uid = state.player_uid
	controller._connect_relic_signals(state)
	return {"state": state, "player": player, "controller": controller}


func _force_overload(controller: BattleController, state: GameState, player: UnitState) -> Dictionary:
	_give_held_gem(state)
	var armed := controller.try_insert(player.uid, 0)
	_expect(bool(armed.get("overload_armed", false)), "formal overload helper should arm before confirming")
	return controller.try_insert(player.uid, 0)


func _add_existing_overload(state: GameState, player: UnitState) -> void:
	var slot := SlotState.create(Constants.SLOT_RED, "", false, Constants.LOCK_OVERLOAD_SLOT)
	player.slots.append(slot)
	var gem := _make_gem(state)
	_expect(GemTransfer.to_unit_slot(state, gem, player, slot), "existing overload setup should mount its gem")


func _give_held_gem(state: GameState) -> void:
	var gem := _make_gem(state)
	_expect(GemTransfer.to_hand(state, gem, state.player_uid), "held overload gem setup should succeed")


func _make_gem(state: GameState) -> GemState:
	_gem_serial += 1
	var gem: GemState = root.get_node("DataRegistry").create_gem_instance(
		"fuse_gem_%d" % _gem_serial, Constants.GEM_EXPLOSION, {}
	)
	state.gems[gem.uid] = gem
	return gem


func _force_relic() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_fuse")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
