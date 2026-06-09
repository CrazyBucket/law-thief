extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Run History Service Test ===")
	var history_service: Node = root.get_node("RunHistoryService")
	history_service.clear()
	history_service.record_encounter({
		"encounter_id": "tutorial_001",
		"result": "win",
	})
	history_service.record_run({
		"run_id": "run_test",
		"result": "win",
		"chapter_reached": 3,
		"master_seed": 42,
		"summary": {
			"gold_earned": 10,
			"gold_spent": 4,
			"owned_relics": ["relic_chaos_launcher"],
			"active_rule_ids": ["map_rule_gold_gain_10"],
		},
	})
	assert(history_service.get_encounter_win_count("tutorial_001") == 1, "encounter history should still count wins")
	assert(history_service.get_total_runs() == 1, "run history should count only run records")
	assert(history_service.get_total_wins() == 1, "run wins should count only run records")
	var recent: Array = history_service.get_recent(5)
	assert(recent.size() == 2, "recent should include both encounter and run entries")
	history_service.clear()
	print("RUN_HISTORY_SERVICE_TEST_PASS")
	quit()
