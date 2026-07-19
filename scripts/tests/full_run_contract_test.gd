extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Full Run Contract Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var room_flow_service: Node = root.get_node("RoomFlowService")
	var economy_service: Node = root.get_node("EconomyService")
	var history_service: Node = root.get_node("RunHistoryService")
	history_service.clear()
	adventure_service.start_new_run(20260611)

	var path_cells := _build_path(adventure_service, 6)
	assert(path_cells.size() >= 6, "generated map should provide at least six reachable rooms")

	var combat_room_id := _room_id_for(adventure_service, path_cells[0], "NORMAL_COMBAT")
	var combat_tx := "contract:combat:chapter1"
	var combat_reward_1: int = economy_service.get_combat_reward("NORMAL_COMBAT", combat_room_id)
	var combat_result: Dictionary = economy_service.grant("gold", combat_reward_1, "normal_combat_reward", {
		"transaction_id": combat_tx,
		"room_id": combat_room_id,
	})
	assert(combat_result.get("ok", false), "combat gold grant should succeed")
	var combat_entry_1: Dictionary = combat_result.get("entry", {})
	var normal_reward_range: Dictionary = economy_service.get_combat_reward_range("NORMAL_COMBAT")
	assert(int(combat_entry_1.get("final_amount", 0)) >= int(normal_reward_range.get("min", 0)) and int(combat_entry_1.get("final_amount", 0)) <= int(normal_reward_range.get("max", 0)), "first combat reward should stay inside the configured range")
	run_service.mark_room_resolved(combat_room_id, {
		"room_id": combat_room_id,
		"room_type": "NORMAL_COMBAT",
		"summary": "普通战胜利。",
	})
	var event_room_id := _room_id_for(adventure_service, path_cells[1], "EVENT", {"event_id": "event_debug_cache"})
	var event_view: Dictionary = room_flow_service.enter_room(event_room_id)
	assert(event_view.get("ok", false), "event enter should succeed")
	var event_result: Dictionary = room_flow_service.submit_room_command(event_room_id, {
		"action": "choose_option",
		"option_id": "install_rule",
	})
	assert(event_result.get("ok", false), "event option should succeed")
	assert((run_service.get_adventure_rules() as Array).size() >= 1, "event should install run rule")

	var combat_room_id_2 := _room_id_for(adventure_service, path_cells[2], "NORMAL_COMBAT")
	var combat_reward_2: int = economy_service.get_combat_reward("NORMAL_COMBAT", combat_room_id_2)
	var combat_result_2: Dictionary = economy_service.grant("gold", combat_reward_2, "normal_combat_reward", {
		"transaction_id": "contract:combat:chapter1:rule",
		"room_id": combat_room_id_2,
	})
	assert(combat_result_2.get("ok", false), "second combat gold grant should succeed")
	var combat_entry_2: Dictionary = combat_result_2.get("entry", {})
	assert(int(combat_entry_2.get("final_amount", 0)) == roundi(float(combat_reward_2) * 1.1), "gold gain rule should modify later combat reward")
	run_service.mark_room_resolved(combat_room_id_2, {
		"room_id": combat_room_id_2,
		"room_type": "NORMAL_COMBAT",
		"summary": "规则加成后的普通战胜利。",
	})

	var shop_room_id := _room_id_for(adventure_service, path_cells[3], "SHOP")
	root.get_node("AdventureRuleRegistry").add_rule("map_rule_shop_discount_20", "run", "contract", {"room_id": shop_room_id})
	var shop_view: Dictionary = room_flow_service.enter_room(shop_room_id)
	assert(shop_view.get("ok", false), "shop enter should succeed")
	var offers: Array = shop_view.get("payload", {}).get("shop", {}).get("offers", [])
	assert(not offers.is_empty(), "shop should expose offers")
	var offer: Dictionary = offers[0]
	for candidate in offers:
		if candidate is Dictionary and int(candidate.get("final_price", 0)) < int(offer.get("final_price", 0)):
			offer = candidate
	assert(int(offer.get("final_price", 0)) < int(offer.get("base_price", 0)), "shop discount rule should reduce price")
	assert(int(offer.get("final_price", 0)) <= economy_service.get_balance("gold"), "the contract shop should expose an affordable offer")
	var purchase: Dictionary = room_flow_service.submit_room_command(shop_room_id, {
		"action": "purchase",
		"offer_id": str(offer.get("offer_id", "")),
	})
	assert(purchase.get("ok", false), "shop purchase should succeed")
	var expected_gold_after_purchase: int = int(economy_service.get_balance("gold"))
	room_flow_service.leave_room(shop_room_id)

	var rest_room_id := _room_id_for(adventure_service, path_cells[4], "REST_SITE")
	root.get_node("AdventureRuleRegistry").add_rule("map_rule_rest_heal_50", "run", "contract", {"room_id": rest_room_id})
	run_service.get_run().player_hp = 5
	run_service.get_run().player_max_hp = 10
	var hp_before_rest: int = int(run_service.get_run().player_hp)
	var rest_view: Dictionary = room_flow_service.enter_room(rest_room_id)
	assert(rest_view.get("ok", false), "rest enter should succeed")
	var rest_result: Dictionary = room_flow_service.submit_room_command(rest_room_id, {})
	assert(rest_result.get("ok", false), "rest resolve should succeed")
	var heal: Dictionary = rest_result.get("result", {}).get("heal", {})
	var heal_trace: Dictionary = rest_result.get("result", {}).get("heal_trace", {})
	assert(absf(float(heal_trace.get("base_value", 0.0)) - 0.2) < 0.001, "rest heal trace should start from configured base ratio")
	assert(absf(float(heal_trace.get("final_value", 0.0)) - 0.3) < 0.001, "rest heal trace should become 0.3")
	assert(run_service.get_run().player_hp - hp_before_rest == 3, "rest heal should increase hp by 3, heal=%s after_hp=%d" % [JSON.stringify(heal), run_service.get_run().player_hp])

	run_service.set_progress_payload(adventure_service.export_progress())
	run_service.save_run()
	run_service.reload_for_active_slot()
	assert(run_service.is_run_active(), "run should reload after save")
	assert(int(run_service.get_balance("gold")) == expected_gold_after_purchase, "reloaded run should keep the exact post-purchase gold")
	assert((run_service.get_adventure_rules() as Array).size() >= 3, "reloaded run should keep installed rules")

	run_service.complete_run("win")
	run_service.end_run()
	assert(history_service.get_total_runs() == 1, "completed run should record one run history")
	assert(history_service.get_total_wins() == 1, "completed run should count as a win")
	print("FULL_RUN_CONTRACT_TEST_PASS")
	quit()


func _build_path(adventure_service: Node, steps: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := Vector2i.ZERO
	for _i in range(steps):
		adventure_service.current_pos = current
		var reachable: Array[Vector2i] = adventure_service.get_reachable_cells()
		if reachable.is_empty():
			break
		var next: Vector2i = reachable[0]
		path.append(next)
		current = next
	return path


func _room_id_for(adventure_service: Node, cell: Vector2i, room_type: String, props: Dictionary = {}) -> String:
	adventure_service.current_pos = cell
	adventure_service.pending_room_type = room_type
	adventure_service.pending_room_label = room_type
	var node = adventure_service.get_current_node()
	assert(node != null, "node at %s should exist" % [cell])
	node.room_type = room_type
	for key in props.keys():
		node.properties[key] = props[key]
	return str(adventure_service.current_room_id())
