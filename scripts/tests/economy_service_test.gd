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
