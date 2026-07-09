extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Event Service Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var room_flow_service: Node = root.get_node("RoomFlowService")
	var economy_service: Node = root.get_node("EconomyService")
	adventure_service.start_new_run(20260612)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	adventure_service.pending_room_label = "事件"
	var node = adventure_service.get_current_node()
	assert(node != null, "current node should exist")
	node.room_type = "EVENT"
	node.properties["event_id"] = "event_debug_cache"
	var room_id: String = str(adventure_service.current_room_id())
	var view: Dictionary = room_flow_service.enter_room(room_id)
	var event_view: Dictionary = view.get("payload", {}).get("event", {})
	assert(str(event_view.get("event_id", "")) == "event_debug_cache", "event view should load configured event")
	var options: Array = event_view.get("options", [])
	assert(options.size() == 2, "debug event should expose two options")
	assert(bool((options[0] as Dictionary).get("enabled", false)), "unconditional option should be enabled")
	var choose_rule: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "choose_option",
		"option_id": "install_rule",
	})
	assert(choose_rule.get("ok", false), "choosing rule option should succeed")
	assert((run_service.get_adventure_rules() as Array).size() == 1, "rule option should append run rule")
	var grant: Dictionary = economy_service.grant("gold", 10, "combat_reward", {"transaction_id": "event_rule_gold"})
	assert(int((grant.get("entry", {}) as Dictionary).get("after", 0)) == 11, "event-added rule should modify later gold gains")

	adventure_service.start_new_run(20260613)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	adventure_service.pending_room_label = "事件"
	node = adventure_service.get_current_node()
	node.room_type = "EVENT"
	node.properties["event_id"] = "event_debug_relief"
	room_id = str(adventure_service.current_room_id())
	room_flow_service.enter_room(room_id)
	event_view = root.get_node("EventService").get_event_view(room_id)
	options = event_view.get("options", [])
	assert(str((options[0] as Dictionary).get("label", "")) == "拿 8 金币", "amount-ref label should render configured gold")
	assert(str((options[1] as Dictionary).get("label", "")) == "恢复 4 点生命", "amount-ref label should render configured heal")
	var choose_gold: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "choose_option",
		"option_id": "take_gold",
	})
	assert(choose_gold.get("ok", false), "gold option should succeed")
	assert(economy_service.get_balance("gold") == 8, "gold option should grant direct gold")

	adventure_service.start_new_run(20260614)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	adventure_service.pending_room_label = "事件"
	node = adventure_service.get_current_node()
	node.room_type = "EVENT"
	node.properties["event_id"] = "event_debug_toll"
	room_id = str(adventure_service.current_room_id())
	view = room_flow_service.enter_room(room_id)
	event_view = view.get("payload", {}).get("event", {})
	options = event_view.get("options", [])
	assert(options.size() == 2, "toll event should expose two options")
	assert(str(event_view.get("body", "")) == "一台还在运转的旧闸机要求你缴纳 5 金币，否则什么都不给。", "amount-ref body should render configured toll text")
	assert(str((options[0] as Dictionary).get("label", "")) == "支付 5 金币并恢复 4 点生命", "amount-ref option label should render configured numbers")
	assert(not bool((options[0] as Dictionary).get("enabled", true)), "pay option should be disabled without gold")
	assert(str((options[0] as Dictionary).get("disabled_reason", "")) != "", "disabled option should explain reason")
	var blocked: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "choose_option",
		"option_id": "pay_for_heal",
	})
	assert(not blocked.get("ok", true), "blocked option should fail")
	economy_service.grant("gold", 5, "test_reward", {"transaction_id": "event_toll_seed"})
	var refreshed: Dictionary = root.get_node("EventService").get_event_view(room_id)
	var refreshed_options: Array = refreshed.get("options", [])
	assert(bool((refreshed_options[0] as Dictionary).get("enabled", false)), "pay option should enable after getting gold")
	var pay: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "choose_option",
		"option_id": "pay_for_heal",
	})
	assert(pay.get("ok", false), "pay option should succeed after meeting condition")
	run_service.end_run()
	print("EVENT_SERVICE_TEST_PASS")
	quit()
