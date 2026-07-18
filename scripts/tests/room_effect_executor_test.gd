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
		{"type": "resource_gte", "resource_id": "gold", "amount_ref": "event_debug_toll_cost"}
	], {"room_id": "chapter_1:0_0"})
	assert(not blocked_condition.get("ok", true), "resource gate should fail without gold")

	var grant_effects: Dictionary = executor.apply_effects([
		{"action": "grant_resource", "resource_id": "gold", "amount_ref": "event_debug_relief_gold"},
		{"action": "heal_player", "amount_ref": "event_debug_relief_heal"}
	], {"room_id": "chapter_1:0_0", "transaction_id": "executor_chain"})
	assert(grant_effects.get("ok", false), "effect chain should succeed")
	assert(run_service.get_balance("gold") == 8, "grant_resource should change balance")

	var open_condition: Dictionary = executor.evaluate_conditions([
		{"type": "resource_gte", "resource_id": "gold", "amount_ref": "event_debug_toll_cost"}
	], {"room_id": "chapter_1:0_0"})
	assert(open_condition.get("ok", false), "resource gate should pass after grant")

	var unknown_amount_ref: Dictionary = executor.apply_effects([
		{"action": "grant_resource", "resource_id": "gold", "amount_ref": "missing_ref"}
	], {"room_id": "chapter_1:0_0", "transaction_id": "executor_bad_ref"})
	assert(not unknown_amount_ref.get("ok", true), "unknown amount ref should fail at runtime")
	assert(str(unknown_amount_ref.get("error", "")) == "unknown_amount_ref", "runtime should report unknown amount refs")

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
					"conditions": [
						{"type": "unknown_condition"},
						{"type": "resource_gte", "resource_id": "gold", "amount_ref": ""},
						{"type": "resource_gte", "resource_id": "gold", "amount_ref": "rest_site_heal_ratio"}
					],
					"effects": [
						{"action": "unknown_effect"},
						{"action": "grant_resource", "resource_id": "gold"},
						{"action": "heal_player", "amount_ref": "missing_ref"},
						{"action": "spend_resource", "resource_id": "gold", "amount_ref": "rest_site_heal_ratio"},
						{"action": "heal_player_percent", "amount_ref": "event_debug_toll_heal"},
						{"action": "heal_player", "amount": 4}
					]
				}
			]
		}
	}, root.get_node("EconomyService").get_amount_refs())
	assert(not invalid_effects.is_empty(), "validator should flag unknown condition/effect")
	assert(invalid_effects.has("event_defs.broken_event.options[0].conditions[1].amount_ref should not be empty"), "validator should reject empty amount refs")
	assert(invalid_effects.has("event_defs.broken_event.options[0].effects[1].amount or amount_ref missing"), "validator should require numeric payload")
	assert(invalid_effects.has("event_defs.broken_event.options[0].effects[2].amount_ref unknown: missing_ref"), "validator should reject unknown amount refs")
	assert(invalid_effects.has("event_defs.broken_event.options[0].conditions[2].amount_ref kind mismatch: rest_site_heal_ratio expected flat got ratio"), "resource gates should reject ratio amount refs")
	assert(invalid_effects.has("event_defs.broken_event.options[0].effects[3].amount_ref unit mismatch: rest_site_heal_ratio expected gold got max_hp"), "resource costs should reject non-resource units")
	assert(invalid_effects.has("event_defs.broken_event.options[0].effects[4].amount_ref kind mismatch: event_debug_toll_heal expected ratio got flat"), "percent heals should reject flat amount refs")
	assert(invalid_effects.has("event_defs.broken_event.options[0].effects[5].amount should use amount_ref in authored config"), "authored numeric payloads should use amount refs")
	var invalid_graph := Validator.validate_event_defs({
		"broken_graph": {
			"entry": "missing",
			"nodes": {
				"start": {
					"title": "broken",
					"body": "broken",
					"options": [
						{
							"id": "unsafe",
							"label": "unsafe",
							"conditions": [],
							"calls": [{"function": "queue_free", "args": {}}],
							"next": "missing"
						}
					]
				}
			}
		}
	}, root.get_node("EconomyService").get_amount_refs())
	assert(invalid_graph.has("event_defs.broken_graph.entry references unknown node: missing"), "graph validator should reject an unknown entry node")
	assert(invalid_graph.has("event_defs.broken_graph.nodes.start.options[0].calls[0].function unknown: queue_free"), "graph validator should reject arbitrary function calls")
	assert(invalid_graph.has("event_defs.broken_graph.nodes.start.options[0].next references unknown node: missing"), "graph validator should reject an unknown next node")
	var invalid_economy := Validator.validate_economy_config({
		"starting_gold": 0,
		"combat_rewards": {
			"normal": {"min": 10, "max": 10},
			"elite": {"min": 20, "max": 20},
			"boss": {"min": 40, "max": 40},
		},
		"shop_prices": {
			"gem": {"default": {"min": 15, "max": 15}},
			"relic": {"default": {"min": 30, "max": 30}},
			"consumable": {"default": {"min": 10, "max": 10}},
		},
		"amount_refs": {
			"broken_ratio": {"value": 0.2, "kind": "ratio"}
		}
	})
	assert(invalid_economy.has("economy_config.amount_refs.broken_ratio.unit missing"), "typed amount refs should require unit metadata")
	var valid_shop_pools := Validator.validate_shop_pools({
		"default": {
			"gem_offer_count": 2,
			"relic_offer_count": 1,
			"gem_source": "shop",
			"relic_source": "shop",
		}
	})
	assert(valid_shop_pools.is_empty(), "valid shop pools should pass")
	var invalid_shop_pools := Validator.validate_shop_pools({
		"default": {
			"gem_offer_count": 1.5,
			"relic_offer_count": -1,
			"gem_source": "",
			"relic_source": "shop",
		}
	})
	assert(invalid_shop_pools.has("shop_pools.default.gem_offer_count should be integer"), "shop pool counts should be integers")
	assert(invalid_shop_pools.has("shop_pools.default.relic_offer_count should be non-negative"), "shop pool counts should be non-negative")
	assert(invalid_shop_pools.has("shop_pools.default.gem_source should not be empty"), "shop pool sources should not be empty")
	run_service.end_run()
	print("ROOM_EFFECT_EXECUTOR_TEST_PASS")
	quit()
