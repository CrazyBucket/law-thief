extends SceneTree

const _Settlement = preload("res://scripts/battle/battle_settlement_service.gd")
const _SpawnService = preload("res://scripts/rules/unit_spawn_service.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _GemLocation = preload("res://scripts/data/gem_location.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Battle Architecture Test ===")
	_test_settlement_service_owns_gem_mutation()
	_test_spawn_provenance_and_reward_eligibility()
	_test_transaction_covers_spawn_status_gem_and_kill()
	_test_action_plan_is_shared_and_immutable()
	print("BATTLE_ARCHITECTURE_TEST_PASS")
	quit()


func _test_settlement_service_owns_gem_mutation() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 8101)
	var player := builder.player()
	builder.clear_slots(player)
	var state := builder.finish()
	var held := _new_gem(state, Constants.GEM_POISON, "settlement_held")
	var dropped := _new_gem(state, Constants.GEM_FIRE, "settlement_drop")
	assert(_GemTransfer.to_hand(state, held, player.uid))
	assert(_GemTransfer.to_ground(state, dropped, Vector2i(4, 4)))
	assert(_Settlement.has_pending_dropped_gem_reward(state))
	assert(_Settlement.dropped_gem_offer(state).size() == 1)
	var slot_index := player.slots.find(player.get_slot(Constants.SLOT_RED))
	var result := _Settlement.embed_dropped_gem(state, dropped.uid, slot_index)
	assert(bool(result.get("ok", false)), str(result))
	assert(player.get_slot_by_index(slot_index).gem_uid == dropped.uid)
	assert(state.held_gem_uid == held.uid, "pre-settlement hand gem should be restored")
	assert(not state.dropped_gems.has(dropped.uid))
	assert(not _Settlement.has_pending_dropped_gem_reward(state))
	_assert_valid(state, [], "settlement_service")
	print("  [OK] settlement service owns dropped gem mutation")


func _test_spawn_provenance_and_reward_eligibility() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 8102)
	var origin := builder.add_unit("summoner", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(5, 5))
	var state := builder.finish()
	var no_reward_events: Array[Dictionary] = []
	var no_reward_result := _SpawnService.spawn_from_def(
		state, "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 5), no_reward_events,
		{"uid": "summon_no_reward", "origin": origin, "temporary": true, "grants_death_rewards": false}
	)
	assert(bool(no_reward_result.get("ok", false)), str(no_reward_result))
	var summon: UnitState = no_reward_result.get("unit", null)
	assert(summon.spawn_origin_uid == origin.uid)
	assert(summon.reward_origin_uid == origin.uid)
	assert(summon.is_temporary_summon and not summon.grants_death_rewards)
	var suppressed_gem := _mount_gem(state, summon, Constants.GEM_FIRE, "suppressed_reward_gem")
	var no_reward_tx := _CombatTransaction.begin(state, no_reward_events)
	assert(no_reward_tx.kill_unit(summon, state.player_uid, "architecture_test"))
	no_reward_tx.finish("battle_architecture.no_reward")
	assert(not state.gems.has(suppressed_gem.uid))
	assert(not state.dropped_gems.has(suppressed_gem.uid))

	var reward_events: Array[Dictionary] = []
	var reward_result := _SpawnService.spawn_from_def(
		state, "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 6), reward_events,
		{"uid": "reward_root", "root_spawn": true}
	)
	assert(bool(reward_result.get("ok", false)), str(reward_result))
	var reward_unit: UnitState = reward_result.get("unit", null)
	var reward_gem := _mount_gem(state, reward_unit, Constants.GEM_FIRE, "eligible_reward_gem")
	var reward_tx := _CombatTransaction.begin(state, reward_events)
	assert(reward_tx.kill_unit(reward_unit, state.player_uid, "architecture_test"))
	reward_tx.finish("battle_architecture.reward")
	assert(reward_unit.get_slot(Constants.SLOT_RED).gem_uid == reward_gem.uid)
	assert(
		_Settlement.dropped_gem_offer(state).any(
			func(entry: Dictionary) -> bool: return str(entry.get("gem_uid", "")) == reward_gem.uid
		)
	)
	_assert_valid(state, no_reward_events, "spawn_no_reward")
	_assert_valid(state, reward_events, "spawn_reward")
	print("  [OK] spawn provenance is independent from reward eligibility")


func _test_transaction_covers_spawn_status_gem_and_kill() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 8103)
	var state := builder.finish()
	var events: Array[Dictionary] = []
	var result := _SpawnService.spawn_from_def(
		state, "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 6), events,
		{"uid": "transaction_target", "root_spawn": true}
	)
	assert(bool(result.get("ok", false)), str(result))
	var unit: UnitState = result.get("unit", null)
	var gem := _new_gem(state, Constants.GEM_POISON, "transaction_gem")
	var tx := _CombatTransaction.begin(state, events)
	assert(tx.apply_status(unit, StatusInstance.create(Constants.STATUS_POISON, 1, 2, state.player_uid)))
	assert(tx.transfer_gem(gem, _GemLocation.ground(Vector2i(3, 3)), {"reason": "transaction_test"}))
	assert(tx.kill_unit(unit, state.player_uid, "transaction_test"))
	tx.finish("battle_architecture.transaction")
	assert(events.any(func(ev: Dictionary) -> bool: return ev.get("type", "") == "spawn"))
	assert(events.any(func(ev: Dictionary) -> bool: return ev.get("type", "") == "status"))
	assert(events.any(func(ev: Dictionary) -> bool: return ev.get("type", "") == "gem_transfer"))
	assert(events.any(func(ev: Dictionary) -> bool: return ev.get("type", "") == "die"))
	_assert_valid(state, events, "transaction_extended")
	print("  [OK] transaction covers spawn, status, gem transfer, and kill")


func _test_action_plan_is_shared_and_immutable() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 8104)
	var enemy := builder.add_unit("plan_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(7, 7))
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, enemy)
	assert(enemy.intent != null and enemy.intent.action_plan != null)
	var signature: String = enemy.intent.action_plan.signature()
	var planned_path: Array[Vector2i] = enemy.intent.action_plan.path.duplicate()
	enemy.intent.path.clear()
	var execution_view := enemy.intent.execution_view(state.turn_index, enemy.pos)
	assert(execution_view.path == planned_path, "execution must read the captured plan, not mutable preview fields")
	assert(execution_view.action_plan.signature() == signature)
	_assert_valid(state, [], "action_plan")
	print("  [OK] preview and execution share one immutable action plan")


func _new_gem(state: GameState, gem_id: String, uid: String) -> GemState:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem: GemState = registry.create_gem_instance(uid, gem_id, {})
	state.gems[uid] = gem
	return gem


func _mount_gem(state: GameState, unit: UnitState, gem_id: String, uid: String) -> GemState:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if not slot.gem_uid.is_empty():
		_GemTransfer.remove(state, slot.gem_uid)
	var gem := _new_gem(state, gem_id, uid)
	assert(_GemTransfer.to_unit_slot(state, gem, unit, slot))
	return gem


func _assert_valid(state: GameState, events: Array, context: String) -> void:
	assert(EventValidator.assert_valid(events, context))
	assert(BattleInvariantChecker.assert_valid(state, context))
