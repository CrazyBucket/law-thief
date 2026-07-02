extends SceneTree


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
	assert(game_service.continue_scene_for_active_run() == "res://scenes/adventure/room_placeholder.tscn", "reloaded ROOM phase should route to room scene")

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
	run_service.end_run()
	print("RUN_RECOVERY_ROUTE_TEST_PASS")
	quit()
