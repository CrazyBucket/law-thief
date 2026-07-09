extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Economy Service Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var economy_service: Node = root.get_node("EconomyService")
	adventure_service.start_new_run(20260609)
	assert(economy_service.get_balance("gold") == 0, "starting gold should come from config")
	assert(economy_service.has_amount_ref("event_debug_cache_gold"), "amount ref should be available from config")
	assert(is_equal_approx(economy_service.get_amount_ref("event_debug_cache_gold"), 10.0), "amount ref should resolve configured value")
	assert(is_equal_approx(economy_service.get_amount_ref("rest_site_heal_ratio"), 0.2), "ratio amount ref should resolve configured value")
	var rest_ref_def: Dictionary = economy_service.get_amount_ref_def("rest_site_heal_ratio")
	assert(str(rest_ref_def.get("kind", "")) == "ratio", "ratio amount ref should expose kind metadata")
	assert(str(rest_ref_def.get("unit", "")) == "max_hp", "ratio amount ref should expose unit metadata")
	var resolved_ratio: Dictionary = economy_service.resolve_numeric_field({"amount_ref": "rest_site_heal_ratio"}, "amount")
	assert(resolved_ratio.get("ok", false), "numeric resolver should accept amount refs")
	assert(is_equal_approx(float(resolved_ratio.get("value", 0.0)), 0.2), "numeric resolver should return referenced ratio")
	var grant: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "tx_grant"})
	assert(grant.get("ok", false), "grant should succeed")
	assert(economy_service.get_balance("gold") == 10, "grant should increase gold")
	var replay: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "tx_grant"})
	assert(replay.get("ok", false), "replayed grant should succeed")
	assert(economy_service.get_balance("gold") == 10, "replayed grant should not double count")
	var spend: Dictionary = economy_service.spend("gold", 4, "shop_purchase", {"transaction_id": "tx_spend"})
	assert(spend.get("ok", false), "spend should succeed")
	assert(economy_service.get_balance("gold") == 6, "spend should reduce gold")
	var insufficient: Dictionary = economy_service.spend("gold", 99, "shop_purchase", {"transaction_id": "tx_fail"})
	assert(not insufficient.get("ok", true), "overspend should fail")
	assert(str(insufficient.get("error", "")) == "insufficient_funds", "should report insufficient funds")
	assert(run_service.get_resource_ledger().size() == 2, "ledger should only contain successful entries")
	run_service.end_run()
	print("ECONOMY_SERVICE_TEST_PASS")
	quit()
