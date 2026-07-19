extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Economy Service Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var economy_service: Node = root.get_node("EconomyService")
	adventure_service.start_new_run(20260609)
	assert(economy_service.get_balance("gold") == 85, "starting gold should come from the economy baseline")
	assert(economy_service.get_model_price("basic_card") == 35, "model prices should scale from mu")
	var event_expectation: Dictionary = economy_service.get_event_economy_expectation()
	assert(int(event_expectation.get("positive_gold", 0)) == 20, "positive events should use the baseline unit")
	assert(int(event_expectation.get("negative_gold", 0)) == -30, "negative events should use the baseline unit")
	assert(int(event_expectation.get("expected_gold_per_event", 0)) == 2, "event expectation should include configured rates")
	var normal_range: Dictionary = economy_service.get_combat_reward_range("NORMAL_COMBAT")
	var elite_range: Dictionary = economy_service.get_combat_reward_range("ELITE_COMBAT")
	var boss_range: Dictionary = economy_service.get_combat_reward_range("END")
	var normal_reward: int = economy_service.get_combat_reward("NORMAL_COMBAT", "normal_room")
	var elite_reward: int = economy_service.get_combat_reward("ELITE_COMBAT", "elite_room")
	var boss_reward: int = economy_service.get_combat_reward("END", "boss_room")
	assert(normal_reward >= int(normal_range.get("min", 0)) and normal_reward <= int(normal_range.get("max", 0)), "normal reward should roll inside its configured range")
	assert(elite_reward >= int(elite_range.get("min", 0)) and elite_reward <= int(elite_range.get("max", 0)), "elite reward should roll inside its configured range")
	assert(boss_reward >= int(boss_range.get("min", 0)) and boss_reward <= int(boss_range.get("max", 0)), "boss reward should roll inside its configured range")
	assert(economy_service.get_combat_reward("NORMAL_COMBAT", "normal_room") == normal_reward, "same combat roll key should reproduce the same reward")
	for price_case in [
		{"item_type": "gem", "rarity": "common"},
		{"item_type": "gem", "rarity": "legendary"},
		{"item_type": "relic", "rarity": "rare"},
		{"item_type": "consumable", "rarity": "uncommon"},
	]:
		var item_type := str(price_case.get("item_type", ""))
		var rarity := str(price_case.get("rarity", ""))
		var price_range: Dictionary = economy_service.get_shop_price_range(item_type, rarity)
		var price: int = economy_service.roll_shop_price(item_type, rarity, "%s:%s" % [item_type, rarity])
		assert(price >= int(price_range.get("min", 0)) and price <= int(price_range.get("max", 0)), "shop price should roll inside the configured rarity range")
		assert(economy_service.roll_shop_price(item_type, rarity, "%s:%s" % [item_type, rarity]) == price, "same shop roll key should reproduce the same price")
	assert(economy_service.get_shop_price_range("gem", "common").get("min", 0) < economy_service.get_shop_price_range("gem", "common").get("max", 0), "price sigma should create a non-zero seeded price range")
	assert(economy_service.get_shop_price_range("consumable", "missing") == economy_service.get_shop_price_range("consumable", "default"), "unknown rarity should use the authored default price range")
	assert(economy_service.has_amount_ref("event_debug_cache_gold"), "amount ref should be available from config")
	assert(is_equal_approx(economy_service.get_amount_ref("event_debug_cache_gold"), 10.0), "debug amount ref should remain available")
	assert(is_equal_approx(economy_service.get_amount_ref("rest_site_heal_ratio"), 0.2), "ratio amount ref should resolve configured value")
	var rest_ref_def: Dictionary = economy_service.get_amount_ref_def("rest_site_heal_ratio")
	assert(str(rest_ref_def.get("kind", "")) == "ratio", "ratio amount ref should expose kind metadata")
	assert(str(rest_ref_def.get("unit", "")) == "max_hp", "ratio amount ref should expose unit metadata")
	var resolved_ratio: Dictionary = economy_service.resolve_numeric_field({"amount_ref": "rest_site_heal_ratio"}, "amount")
	assert(resolved_ratio.get("ok", false), "numeric resolver should accept amount refs")
	assert(is_equal_approx(float(resolved_ratio.get("value", 0.0)), 0.2), "numeric resolver should return referenced ratio")
	var grant: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "tx_grant"})
	assert(grant.get("ok", false), "grant should succeed")
	assert(economy_service.get_balance("gold") == 95, "grant should increase gold from the configured starting balance")
	var replay: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "tx_grant"})
	assert(replay.get("ok", false), "replayed grant should succeed")
	assert(economy_service.get_balance("gold") == 95, "replayed grant should not double count")
	var spend: Dictionary = economy_service.spend("gold", 4, "shop_purchase", {"transaction_id": "tx_spend"})
	assert(spend.get("ok", false), "spend should succeed")
	assert(economy_service.get_balance("gold") == 91, "spend should reduce gold")
	var insufficient: Dictionary = economy_service.spend("gold", 99, "shop_purchase", {"transaction_id": "tx_fail"})
	assert(not insufficient.get("ok", true), "overspend should fail")
	assert(str(insufficient.get("error", "")) == "insufficient_funds", "should report insufficient funds")
	assert(run_service.get_resource_ledger().size() == 2, "ledger should only contain successful entries")
	run_service.end_run()
	print("ECONOMY_SERVICE_TEST_PASS")
	quit()
