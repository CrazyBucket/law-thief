extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Game Service Continue Route Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var game_service: Node = root.get_node("GameService")
	adventure_service.start_new_run(20260615)
	run_service.set_run_phase("MAP")
	assert(game_service.continue_scene_for_active_run() == "res://scenes/map/adventure_map.tscn", "MAP phase should continue to map")
	run_service.set_run_phase("ROOM")
	run_service.set_pending_decision({"type": "room", "room_id": "chapter_1:0_0"})
	assert(game_service.continue_scene_for_active_run() == "res://scenes/adventure/room_placeholder.tscn", "ROOM phase should continue to room")
	run_service.set_pending_decision({"type": "room", "room_id": "chapter_1:1_0", "room_type": "SHOP"})
	assert(game_service.continue_scene_for_active_run() == "res://scenes/adventure/shop_scene.tscn", "SHOP phase should continue to the dedicated shop scene")
	run_service.set_run_phase("BATTLE")
	run_service.set_pending_decision({
		"type": "battle",
		"room_id": "chapter_1:0_1",
		"room_type": "ELITE_COMBAT",
		"encounter_id": "enforcer_gate",
	})
	assert(game_service.continue_scene_for_active_run() == "res://scenes/battle/battle_scene.tscn", "BATTLE phase should continue to battle scene")
	assert(str(game_service.pending_room_id) == "chapter_1:0_1", "battle continue route should restore pending room id")
	assert(str(game_service.pending_encounter_id) == "enforcer_gate", "battle continue route should restore pending encounter id")
	run_service.set_run_phase("BATTLE_REWARD")
	run_service.set_pending_decision({
		"type": "battle_reward",
		"room_id": "chapter_1:0_0",
		"room_type": "NORMAL_COMBAT",
		"encounter_id": "template_a",
	})
	assert(game_service.continue_scene_for_active_run() == "res://scenes/battle/battle_scene.tscn", "BATTLE_REWARD phase should continue to battle scene")
	assert(str(game_service.pending_room_id) == "chapter_1:0_0", "continue route should restore pending room id")
	assert(str(game_service.pending_encounter_id) == "template_a", "continue route should restore pending encounter id")
	run_service.end_run()
	print("GAME_SERVICE_CONTINUE_ROUTE_TEST_PASS")
	quit()
