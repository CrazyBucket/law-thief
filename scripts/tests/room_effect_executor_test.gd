extends SceneTree

const Validator = preload("res://scripts/services/adventure_config_validator.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Room Effect Executor Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var executor: Node = root.get_node("RoomEffectExecutor")
	adventure_service.start_new_run(20260615)

	var blocked_condition: Dictionary = executor.evaluate_conditions([
		{"type": "resource_gte", "resource_id": "gold", "amount": 1}
	], {"room_id": "chapter_1:0_0"})
	assert(not blocked_condition.get("ok", true), "resource gate should fail without gold")

	var grant_effects: Dictionary = executor.apply_effects([
		{"action": "grant_resource", "resource_id": "gold", "amount": 6},
		{"action": "heal_player", "amount": 2}
	], {"room_id": "chapter_1:0_0", "transaction_id": "executor_chain"})
	assert(grant_effects.get("ok", false), "effect chain should succeed")
	assert(run_service.get_balance("gold") == 6, "grant_resource should change balance")

	var open_condition: Dictionary = executor.evaluate_conditions([
		{"type": "resource_gte", "resource_id": "gold", "amount": 5}
	], {"room_id": "chapter_1:0_0"})
	assert(open_condition.get("ok", false), "resource gate should pass after grant")

	var add_rule: Dictionary = executor.apply_effects([
		{"action": "add_adventure_rule", "rule_id": "map_rule_gold_gain_10"}
	], {"room_id": "chapter_1:0_0", "transaction_id": "executor_rule"})
	assert(add_rule.get("ok", false), "add rule effect should succeed")
	assert((run_service.get_adventure_rules() as Array).size() == 1, "rule should be added")

	var remove_rule: Dictionary = executor.apply_effects([
		{"action": "remove_adventure_rule", "rule_id": "map_rule_gold_gain_10"}
	], {"room_id": "chapter_1:0_0", "transaction_id": "executor_rule_remove"})
	assert(remove_rule.get("ok", false), "remove rule effect should succeed")
	assert((run_service.get_adventure_rules() as Array).is_empty(), "rule should be removed")

	var invalid_effects := Validator.validate_event_defs({
		"broken_event": {
			"title": "broken",
			"body": "broken",
			"options": [
				{
					"id": "x",
					"label": "x",
					"conditions": [{"type": "unknown_condition"}],
					"effects": [{"action": "unknown_effect"}]
				}
			]
		}
	})
	assert(not invalid_effects.is_empty(), "validator should flag unknown condition/effect")
	run_service.end_run()
	print("ROOM_EFFECT_EXECUTOR_TEST_PASS")
	quit()
