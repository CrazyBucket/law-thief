extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const ScavengerHookRules = preload("res://scripts/rules/scavenger_hook_rules.gd")
const FuseRules = preload("res://scripts/rules/fuse_rules.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Scavenger Hook Relic Test ===")
	root.get_node("AdventureService").start_new_run(20260812)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	_force_relic()
	_test_definition()
	_test_overload_echo_is_discarded_before_drop_and_hook()
	_test_hook_is_separate_from_normal_hand_and_can_insert()
	_test_hook_insert_obeys_overload_rules()
	_test_unused_hook_returns_at_player_turn_end()
	_test_non_player_phase_hook_waits_for_next_player_turn_end()
	_test_battle_win_returns_hook_before_settlement()
	root.get_node("RunService").end_run()
	if _failed:
		push_error("SCAVENGER_HOOK_RELIC_TEST_FAIL")
		quit(1)
		return
	print("SCAVENGER_HOOK_RELIC_TEST_PASS")
	quit(0)


func _test_definition() -> void:
	var relic_def: Dictionary = root.get_node("DataRegistry").get_relic_def("relic_scavenger_hook")
	_expect(str(relic_def.get("rarity", "")) == "rare", "scavenger hook should be rare")
	_expect(bool(relic_def.get("unique", false)), "scavenger hook should be unique")
	_expect((relic_def.get("effects", []) as Array).size() == 2, "scavenger hook should own hook and return effects")
	print("  [OK] definition is rare and unique")


func _test_overload_echo_is_discarded_before_drop_and_hook() -> void:
	var fixture := _battle_fixture(36)
	var state: GameState = fixture["state"]
	var source: UnitState = fixture["source"]
	var controller := _controller_for(state)
	var echo_uid := source.get_slot(Constants.SLOT_RED).gem_uid
	var real_uid := source.get_slot(Constants.SLOT_BLUE).gem_uid
	state.overload_echo_gems[echo_uid] = state.turn_index + 1
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "scavenger_hook_echo_drop")
	_expect(not state.gems.has(echo_uid), "an overload echo should be destroyed when its enemy owner dies")
	_expect(not state.overload_echo_gems.has(echo_uid), "destroying a death-time echo should clear its lifecycle record")
	_expect(not state.dropped_gems.has(echo_uid), "an overload echo must never become ground loot")
	_expect(controller.state == state, "echo/drop fixture should keep its relic signal controller alive")
	_expect(state.relic_battle.hooked_gem_uid == real_uid, "scavenger hook should choose the remaining real death drop")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "echo death cleanup and hook selection should preserve invariants")
	print("  [OK] overload echoes disappear before death drops and scavenger-hook selection")


func _test_hook_is_separate_from_normal_hand_and_can_insert() -> void:
	var fixture := _battle_fixture(31)
	var state: GameState = fixture["state"]
	var source: UnitState = fixture["source"]
	var target: UnitState = fixture["target"]
	var normal_uid := _give_normal_held_gem(state)
	var source_gems := _unit_gem_uids(source)
	var controller := _controller_for(state)
	var hook_visual_events: Array[Dictionary] = []
	controller.anim_gem_hooked.connect(func(gem_uid: String, from_pos: Vector2i) -> void:
		hook_visual_events.append({"gem_uid": gem_uid, "from_pos": from_pos})
	)
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "scavenger_hook_test")
	var hooked_uid: String = state.relic_battle.hooked_gem_uid
	_expect(hooked_uid in source_gems, "hook should choose one gem from this death")
	_expect(state.held_gem_uid == normal_uid, "hooked gem must not replace the ordinary held gem")
	_expect(not state.dropped_gems.has(hooked_uid), "hooked gem should leave the ground container")
	_expect(state.gems[hooked_uid].location.kind == GemLocation.HOOKED, "hooked gem should use its own location")
	_expect(hook_visual_events.size() == 1 and hook_visual_events[0].get("gem_uid") == hooked_uid, "hook should emit one grid-to-player visual event")
	controller.select_action(Constants.ACTION_INSERT_HOOKED)
	_expect(controller.can_use_action(Constants.ACTION_INSERT_HOOKED), "hook insert command should be available while a gem orbits")
	_expect(target.pos in controller.get_highlights().get("targets", []), "hook insert should expose normal in-range slot targets")
	var slot: SlotState = target.slots[0]
	var result := controller.try_insert_hooked(target.uid, target.slots.find(slot))
	_expect(bool(result.get("ok", false)), "dedicated hook insert should succeed under normal insert rules")
	_expect(slot.gem_uid == hooked_uid, "hooked gem should enter the chosen slot")
	_expect(state.held_gem_uid == normal_uid, "hook insert should preserve the ordinary held gem")
	_expect(state.relic_battle.hooked_gem_uid.is_empty(), "hook storage should clear after insertion")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "hook insertion should preserve gem location invariants")
	CombatRules.apply_damage(state, target, target.hp, state.player_uid, "scavenger_hook_second_death")
	_expect(state.relic_battle.hooked_gem_uid.is_empty(), "scavenger hook must not trigger twice in one battle")
	print("  [OK] hooked gem coexists with the hand and has one dedicated insert")


func _test_hook_insert_obeys_overload_rules() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.append("relic_fuse")
	var fixture := _battle_fixture(35)
	var state: GameState = fixture["state"]
	var source: UnitState = fixture["source"]
	var target: UnitState = fixture["target"]
	var controller := _controller_for(state)
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "scavenger_hook_overload")
	var hooked_uid: String = state.relic_battle.hooked_gem_uid
	var occupied_slot: SlotState = target.slots[0]
	var blocker := root.get_node("DataRegistry").create_gem_instance("hook_overload_blocker", Constants.GEM_POISON, {}) as GemState
	state.gems[blocker.uid] = blocker
	_expect(GemTransfer.to_unit_slot(state, blocker, target, occupied_slot), "overload blocker setup should succeed")
	var slot_index := target.slots.find(occupied_slot)
	var armed := controller.try_insert_hooked(target.uid, slot_index)
	_expect(bool(armed.get("overload_armed", false)), "occupied hook insert should arm overload")
	_expect(state.relic_battle.hooked_gem_uid == hooked_uid, "overload warning must leave the gem on the hook")
	var forced := controller.try_insert_hooked(target.uid, slot_index)
	_expect(bool(forced.get("overload_forced", false)), "second occupied hook insert should force overload")
	_expect(bool(forced.get("mutation_deferred", false)), "a hooked forced insert should pass through fuse deferral")
	_expect(state.relic_battle.hooked_gem_uid.is_empty(), "forced hook insert should consume the dedicated hook storage")
	_expect(state.relic_battle.fuse_triggered and FuseRules.has_deferred_mutation(state), "hook and fuse should share the formal overload lifecycle")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "hook overload should preserve invariants")
	run.owned_relics.erase("relic_fuse")
	print("  [OK] hook insert reuses ordinary overload and fuse rules")


func _test_unused_hook_returns_at_player_turn_end() -> void:
	var fixture := _battle_fixture(32)
	var state: GameState = fixture["state"]
	var source: UnitState = fixture["source"]
	var controller := _controller_for(state)
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "scavenger_hook_expiry")
	var hooked_uid: String = state.relic_battle.hooked_gem_uid
	var original_drop: Dictionary = state.relic_battle.hooked_drop_metadata.duplicate(true)
	controller.begin_enemy_phase()
	_expect(state.relic_battle.hooked_gem_uid.is_empty(), "player-phase hook should expire at this player turn end")
	_expect(state.dropped_gems.has(hooked_uid), "expired hooked gem should return to ground")
	_expect(state.dropped_gems[hooked_uid].get("pos") == original_drop.get("pos"), "returned gem should keep its original drop position")
	_expect(state.dropped_gems[hooked_uid].get("source_slot_type") == original_drop.get("source_slot_type"), "returned gem should keep drop metadata")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "hook expiry should preserve invariants")
	print("  [OK] unused player-phase hook returns to its exact drop")


func _test_non_player_phase_hook_waits_for_next_player_turn_end() -> void:
	var fixture := _battle_fixture(33)
	var state: GameState = fixture["state"]
	var source: UnitState = fixture["source"]
	var controller := _controller_for(state)
	state.phase = Constants.PHASE_ENEMY
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "scavenger_hook_enemy_phase")
	var hooked_uid: String = state.relic_battle.hooked_gem_uid
	_expect(state.relic_battle.hook_expires_after_turn == state.turn_index + 1, "enemy-phase hook should target the next player turn end")
	_expect(not ScavengerHookRules.expire_at_player_turn_end(state), "enemy-phase hook must survive the current turn index")
	controller.finish_enemy_phase()
	controller.begin_enemy_phase()
	_expect(state.dropped_gems.has(hooked_uid), "enemy-phase hook should return after the next player turn")
	print("  [OK] enemy-phase hook survives until the next player turn ends")


func _test_battle_win_returns_hook_before_settlement() -> void:
	var fixture := _battle_fixture(34)
	var state: GameState = fixture["state"]
	var source: UnitState = fixture["source"]
	var controller := _controller_for(state)
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "scavenger_hook_win")
	var hooked_uid: String = state.relic_battle.hooked_gem_uid
	root.get_node("RelicEffectRegistry").fire_event("battle_win", state, {"encounter_id": "test"})
	_expect(controller.state == state, "battle-win fixture controller should remain connected")
	_expect(state.dropped_gems.has(hooked_uid), "battle-win cleanup should return hooked reward gem")
	_expect(state.relic_battle.hooked_gem_uid.is_empty(), "battle-win cleanup should clear hook storage")
	print("  [OK] battle victory returns the hook before reward settlement")


func _battle_fixture(seed: int) -> Dictionary:
	var builder := ScenarioBuilder.new("template_a", seed, true)
	var player := builder.player()
	builder.move(player, Vector2i(2, 2))
	builder.clear_slots(player)
	var source := builder.add_unit("hook_source", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 2), {
		"hp": 10, "max_hp": 10,
	})
	builder.clear_slots(source)
	builder.mount_gems(source, Constants.SLOT_RED, [Constants.GEM_EXPLOSION])
	builder.mount_gems(source, Constants.SLOT_BLUE, [Constants.GEM_CONDUCTIVE])
	var target := builder.add_unit("hook_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(2, 3), {
		"hp": 30, "max_hp": 30,
	})
	builder.clear_slots(target)
	if target.get_slot(Constants.SLOT_RED) == null:
		target.slots.append(SlotState.create(Constants.SLOT_RED))
	if target.get_slot(Constants.SLOT_BLUE) == null:
		target.slots.append(SlotState.create(Constants.SLOT_BLUE))
	var state := builder.finish()
	state.phase = Constants.PHASE_PLAYER
	state.player_moved = false
	state.player_acted = false
	IntentSystem.refresh_all_intents(state)
	return {"state": state, "source": source, "target": target}


func _give_normal_held_gem(state: GameState) -> String:
	var gem_uid := "normal_held_gem"
	var gem: GemState = root.get_node("DataRegistry").create_gem_instance(gem_uid, Constants.GEM_POISON, {})
	state.gems[gem_uid] = gem
	_expect(GemTransfer.to_hand(state, gem, state.player_uid), "normal held gem setup should succeed")
	return gem_uid


func _unit_gem_uids(unit: UnitState) -> Array[String]:
	var result: Array[String] = []
	for slot: SlotState in unit.slots:
		if not slot.gem_uid.is_empty():
			result.append(slot.gem_uid)
	return result


func _controller_for(state: GameState) -> BattleController:
	var controller := BattleController.new()
	controller.state = state
	controller.selected_unit_uid = state.player_uid
	controller._connect_relic_signals(state)
	return controller


func _force_relic() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_scavenger_hook")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
