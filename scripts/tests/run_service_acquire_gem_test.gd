extends SceneTree

const BattleSettlementService = preload("res://scripts/battle/battle_settlement_service.gd")
const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Run Service Acquire Gem Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var game_service: Node = root.get_node("GameService")
	var run_service: Node = root.get_node("RunService")
	var scenario := ScenarioBuilder.new("fission_slime_test", 20260718)
	var player := scenario.player()
	var slots_before := player.slots.size()
	adventure_service.start_new_run(20260608)
	var first: Dictionary = run_service.acquire_gem("gem_explosion")
	assert(first.get("ok", false), "first gem acquire should succeed")
	var second: Dictionary = run_service.acquire_gem("gem_poison")
	assert(not second.get("ok", true), "second gem acquire should fail while carrying one gem")
	assert(str(second.get("error", "")) == "carried_gem_occupied", "should report carried gem conflict")
	assert(str(run_service.get_run().carried_gem.get("gem_id", "")) == "gem_explosion", "carried gem should remain unchanged")
	var slot_snapshots: Array = RunPlayerGemService.slot_snapshots(run_service.get_run())
	assert(slot_snapshots.size() >= 3, "out-of-battle embed should expose the player's persistent slots")
	var embedded: Dictionary = RunPlayerGemService.embed_carried_gem(run_service.get_run(), 0)
	assert(embedded.get("ok", false), "carried gem should embed into an empty persistent slot")
	assert(run_service.get_run().carried_gem.is_empty(), "embedding should clear the carried gem")
	assert(str((RunPlayerGemService.slot_snapshots(run_service.get_run())[0] as Dictionary).get("gem_id", "")) == "gem_explosion", "embedded gem should persist in the selected slot")
	var filled_slots := RunPlayerGemService.slot_snapshots(run_service.get_run())
	for index in range(filled_slots.size()):
		var snapshot := (filled_slots[index] as Dictionary).duplicate(true)
		snapshot["gem_id"] = "gem_poison"
		filled_slots[index] = snapshot
	run_service.get_run().player_slot_gems = filled_slots
	assert(run_service.acquire_gem("gem_fire").get("ok", false), "overload fixture should acquire a carried gem")
	var overload_options := RunPlayerGemService.embed_options(run_service.get_run())
	assert(overload_options.size() == filled_slots.size(), "full loadout should expose every operable slot as an overload target")
	assert(bool(overload_options[0].get("overload", false)), "occupied slot should be marked as an overload choice")
	var overload_size_before: int = run_service.get_run().player_slot_gems.size()
	var overload_result: Dictionary = RunPlayerGemService.embed_carried_gem(run_service.get_run(), 0, true)
	assert(overload_result.get("ok", false) and bool(overload_result.get("overload_forced", false)), "out-of-battle overload embed should succeed")
	assert(run_service.get_run().player_slot_gems.size() == overload_size_before + 1, "overload embed should append a slot")
	var overload_slot: Dictionary = run_service.get_run().player_slot_gems[-1]
	assert(str(overload_slot.get("lock_type", "")) == Constants.LOCK_OVERLOAD_SLOT, "appended slot should carry the overload lock")
	assert(str((run_service.get_run().player_slot_gems[0] as Dictionary).get("gem_id", "")) == "gem_poison", "overload embed should preserve the selected slot gem")
	game_service.set("pending_room_id", "run_service_slot_relic_test")
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	assert(BattleSettlementService.acquire_run_relic("relic_phase_wrench", scenario.state), "settlement relic claim should succeed")
	assert(player.slots.size() == slots_before + 1, "slot relic must affect the current reward-state player immediately")
	assert(run_service.get_run().player_slot_gems.size() == player.slots.size(), "new slot must be captured before the next reward is shown")
	StatusRules.apply_shield(scenario.state, player, 9, 0)
	run_service.capture_player_battle_state(scenario.state)
	var next_battle: GameState = root.get_node("DataRegistry").create_battle_state(
		"tutorial_001",
		20260805,
		"shield_lifecycle_next_battle",
		true
	)
	assert(StatusRules.get_shield(next_battle.get_player()) == 0, "remaining shield must not cross battle boundaries")
	game_service.set("pending_room_id", "")
	adventure_service.pending_room_type = ""
	run_service.end_run()
	print("RUN_SERVICE_ACQUIRE_GEM_TEST_PASS")
	quit()
