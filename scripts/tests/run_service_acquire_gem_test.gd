extends SceneTree

const BattleSettlementService = preload("res://scripts/battle/battle_settlement_service.gd")


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
	game_service.set("pending_room_id", "run_service_slot_relic_test")
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	assert(BattleSettlementService.acquire_run_relic("relic_phase_wrench", scenario.state), "settlement relic claim should succeed")
	assert(player.slots.size() == slots_before + 1, "slot relic must affect the current reward-state player immediately")
	assert(run_service.get_run().player_slot_gems.size() == player.slots.size(), "new slot must be captured before the next reward is shown")
	game_service.set("pending_room_id", "")
	adventure_service.pending_room_type = ""
	run_service.end_run()
	print("RUN_SERVICE_ACQUIRE_GEM_TEST_PASS")
	quit()
