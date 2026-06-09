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
	var choose_gold: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "choose_option",
		"option_id": "take_gold",
	})
	assert(choose_gold.get("ok", false), "gold option should succeed")
	assert(economy_service.get_balance("gold") == 8, "gold option should grant direct gold")
	run_service.end_run()
	print("EVENT_SERVICE_TEST_PASS")
	quit()
