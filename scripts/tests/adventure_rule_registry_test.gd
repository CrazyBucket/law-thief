extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Adventure Rule Registry Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var registry: Node = root.get_node("AdventureRuleRegistry")
	var economy_service: Node = root.get_node("EconomyService")
	adventure_service.start_new_run(20260611)
	var added: Dictionary = registry.add_rule("map_rule_gold_gain_10", "run", "test", {"room_id": "chapter_1:0_0"})
	assert(added.get("ok", false), "rule add should succeed")
	var query: Dictionary = registry.query_modifier("gold_gain_mult", 10, {})
	assert(int(round(query.get("final_value", 0.0))) == 11, "gold gain should become 11 with +10% rule")
	var grant: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "rule_gold_tx"})
	assert(grant.get("ok", false), "grant should succeed under rule")
	var entry: Dictionary = grant.get("entry", {})
	assert(int(entry.get("after", 0)) == 11, "ledger after should reflect modified gain")
	assert((entry.get("modifiers", []) as Array).size() == 1, "modifier trace should be recorded")
	run_service.end_run()
	print("ADVENTURE_RULE_REGISTRY_TEST_PASS")
	quit()
