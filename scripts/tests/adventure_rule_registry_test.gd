extends SceneTree

const Validator = preload("res://scripts/services/adventure_config_validator.gd")


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
	var gold_display: Dictionary = registry.get_rule_display("map_rule_gold_gain_10")
	assert(str(gold_display.get("desc", "")) == "后续获得的金币 +10%。", "rule desc should render effect percent delta")
	var query: Dictionary = registry.query_modifier("gold_gain_mult", 10, {})
	assert(int(round(query.get("final_value", 0.0))) == 11, "gold gain should become 11 with +10% rule")
	var price_rule: Dictionary = registry.add_rule("map_rule_shop_discount_20", "run", "test", {"room_id": "chapter_1:0_1"})
	assert(price_rule.get("ok", false), "shop price rule should add")
	var price_display: Dictionary = registry.get_rule_display("map_rule_shop_discount_20")
	assert(str(price_display.get("desc", "")) == "后续商店价格 -20%。", "shop rule desc should render effect percent delta")
	var price_query: Dictionary = registry.query_modifier("shop_price_mult", 15, {})
	assert(int(round(price_query.get("final_value", 0.0))) == 12, "shop price should become 12 with -20% rule")
	var rest_rule: Dictionary = registry.add_rule("map_rule_rest_heal_50", "run", "test", {"room_id": "chapter_1:0_2"})
	assert(rest_rule.get("ok", false), "rest heal rule should add")
	var rest_display: Dictionary = registry.get_rule_display("map_rule_rest_heal_50")
	assert(str(rest_display.get("desc", "")) == "营地回复效果 +50%。", "rest rule desc should render effect percent delta")
	var rest_query: Dictionary = registry.query_modifier("rest_heal_mult", 0.2, {})
	assert(absf(float(rest_query.get("final_value", 0.0)) - 0.3) < 0.001, "rest heal multiplier should become 0.3")
	var invalid_rules := Validator.validate_map_rule_defs({
		"broken_rule": {
			"name": "broken",
			"desc": "broken",
			"effects": [
				{"modifier": "shop_offer_count_bonus", "value": 1.0},
			],
		},
	})
	assert(invalid_rules.has("map_rule_defs.broken_rule.effects[0].modifier unknown: shop_offer_count_bonus"), "validator should reject unhandled adventure modifiers")
	var grant: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "rule_gold_tx"})
	assert(grant.get("ok", false), "grant should succeed under rule")
	var entry: Dictionary = grant.get("entry", {})
	assert(int(entry.get("after", 0)) == 11, "ledger after should reflect modified gain")
	assert((entry.get("modifiers", []) as Array).size() == 1, "modifier trace should be recorded")
	run_service.end_run()
	print("ADVENTURE_RULE_REGISTRY_TEST_PASS")
	quit()
