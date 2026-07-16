extends SceneTree

const BattleSettlementService = preload("res://scripts/battle/battle_settlement_service.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Run Recovery Route Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var game_service: Node = root.get_node("GameService")

	adventure_service.start_new_run(20260616)
	run_service.set_run_phase("ROOM")
	run_service.set_pending_decision({
		"type": "room",
		"room_id": "chapter_1:1_0",
		"room_type": "SHOP",
	})
	run_service.save_run()
	run_service.reload_for_active_slot()
	assert(str(run_service.get_run_phase()) == "ROOM", "ROOM phase should survive reload")
	assert(str(run_service.get_pending_decision().get("room_type", "")) == "SHOP", "ROOM pending decision should survive reload")
	assert(game_service.continue_scene_for_active_run() == "res://scenes/adventure/shop_scene.tscn", "reloaded shop phase should route to the dedicated shop scene")

	adventure_service.start_new_run(20260619)
	run_service.set_run_phase("BATTLE")
	run_service.set_pending_decision({
		"type": "battle",
		"room_id": "chapter_1:1_1",
		"room_type": "ELITE_COMBAT",
		"encounter_id": "enforcer_gate",
	})
	run_service.save_run()
	run_service.reload_for_active_slot()
	assert(str(run_service.get_run_phase()) == "BATTLE", "BATTLE phase should survive reload")
	assert(str(run_service.get_pending_decision().get("encounter_id", "")) == "enforcer_gate", "battle pending decision should survive reload")
	assert(game_service.continue_scene_for_active_run() == "res://scenes/battle/battle_scene.tscn", "reloaded BATTLE phase should route to battle scene")
	assert(str(game_service.pending_room_id) == "chapter_1:1_1", "battle reload should restore room id")

	adventure_service.start_new_run(20260617)
	run_service.set_run_phase("BATTLE_REWARD")
	run_service.set_pending_decision({
		"type": "battle_reward",
		"room_id": "chapter_1:2_0",
		"room_type": "NORMAL_COMBAT",
		"encounter_id": "template_b",
		"battle_result": "win",
		"reward_kind": "gem",
	})
	run_service.save_run()
	run_service.reload_for_active_slot()
	assert(str(run_service.get_run_phase()) == "BATTLE_REWARD", "BATTLE_REWARD phase should survive reload")
	assert(str(run_service.get_pending_decision().get("encounter_id", "")) == "template_b", "reward pending decision should survive reload")
	assert(game_service.continue_scene_for_active_run() == "res://scenes/battle/battle_scene.tscn", "reloaded reward phase should route to battle scene")
	assert(str(game_service.pending_room_id) == "chapter_1:2_0", "battle reward reload should restore room id")

	_test_reward_claims_are_idempotent_and_drops_restore(adventure_service, run_service, game_service)
	run_service.end_run()
	print("RUN_RECOVERY_ROUTE_TEST_PASS")
	quit()


func _test_reward_claims_are_idempotent_and_drops_restore(adventure_service: Node, run_service: Node, game_service: Node) -> void:
	adventure_service.start_new_run(20260714)
	var room_id := "chapter_1:reward_recovery"
	game_service.pending_room_id = room_id
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	var state := ScenarioBuilder.new("fission_slime_test", 71401).finish()
	var gem := GemState.create("recovery_drop", Constants.GEM_FIRE)
	state.gems[gem.uid] = gem
	assert(GemTransfer.to_ground(state, gem, Vector2i(4, 4), {
		"source_unit_uid": "reward_enemy",
		"source_slot_type": Constants.SLOT_RED,
	}))
	BattleSettlementService.mark_reward_pending(
		"fission_slime_test", "dropped_gem", "win", false, room_id, "NORMAL_COMBAT", state
	)
	run_service.reload_for_active_slot()
	var restored_state := ScenarioBuilder.new("fission_slime_test", 71402).finish()
	BattleSettlementService.restore_pending_dropped_gems(restored_state)
	var offer := BattleSettlementService.dropped_gem_offer(restored_state)
	assert(offer.size() == 1 and str(offer[0].get("gem_id", "")) == Constants.GEM_FIRE, "pending dropped gem should survive process recovery")
	BattleSettlementService.skip_dropped_gem_reward(restored_state)
	var after_claim_state := ScenarioBuilder.new("fission_slime_test", 71403).finish()
	BattleSettlementService.restore_pending_dropped_gems(after_claim_state)
	assert(BattleSettlementService.dropped_gem_offer(after_claim_state).is_empty(), "claimed dropped reward must not restore twice")

	var first_relic: Dictionary = run_service.claim_battle_relic(room_id, "relic_prism", "NORMAL_COMBAT")
	var second_relic: Dictionary = run_service.claim_battle_relic(room_id, "relic_empty_coffin", "NORMAL_COMBAT")
	assert(first_relic.get("ok", false) and second_relic.get("duplicate", false), "relic reward claim should be idempotent by room")
	assert(run_service.get_run().owned_relics.has("relic_prism") and not run_service.get_run().owned_relics.has("relic_empty_coffin"), "retry must not grant a different second relic")
	print("  [OK] battle reward recovery and idempotent claims")
