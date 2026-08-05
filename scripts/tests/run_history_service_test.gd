extends SceneTree

var _failures: Array[String] = []


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
	_check(history_service.get_encounter_win_count("tutorial_001") == 1, "encounter history should still count wins")
	_check(history_service.get_total_runs() == 1, "run history should count only run records")
	_check(history_service.get_total_wins() == 1, "run wins should count only run records")
	var recent: Array = history_service.get_recent(5)
	_check(recent.size() == 2, "recent should include both encounter and run entries")
	var run_entry: Dictionary = recent[1] if recent.size() > 1 else {}
	var summary: Dictionary = run_entry.get("summary", {})
	_check(summary.get("gold_earned", -1) == 10, "run history should preserve earned gold")
	_check(summary.get("gold_spent", -1) == 4, "run history should preserve spent gold")
	_check(summary.get("owned_relics", []) == ["relic_chaos_launcher"], "run history should preserve relics")
	_check(summary.get("active_rule_ids", []) == ["map_rule_gold_gain_10"], "run history should preserve active rules")
	history_service.reload_for_active_slot()
	var reloaded: Array = history_service.get_recent(5)
	_check(reloaded.size() == 2, "history records should survive a disk reload")
	var reloaded_entry: Dictionary = reloaded[1] if reloaded.size() > 1 else {}
	var reloaded_summary: Dictionary = reloaded_entry.get("summary", {})
	_check(reloaded_summary.get("gold_earned", -1) == 10, "earned gold should round-trip through persistence")
	_check(reloaded_summary.get("gold_spent", -1) == 4, "spent gold should round-trip through persistence")
	_check(reloaded_summary.get("owned_relics", []) == ["relic_chaos_launcher"], "relics should round-trip through persistence")
	_check(reloaded_summary.get("active_rule_ids", []) == ["map_rule_gold_gain_10"], "active rules should round-trip through persistence")
	history_service.clear()
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("RUN_HISTORY_SERVICE_TEST_PASS")
	quit()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
