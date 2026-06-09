extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Room Flow Service Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var room_flow_service: Node = root.get_node("RoomFlowService")
	adventure_service.start_new_run(20260608)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "REST_SITE"
	adventure_service.pending_room_label = "营地"
	var node = adventure_service.get_current_node()
	assert(node != null, "current node should exist")
	node.room_type = "REST_SITE"

	var room_id: String = str(adventure_service.current_room_id())
	assert(room_id == "chapter_1:0_0", "room id should include chapter, got %s" % room_id)

	var entered: Dictionary = room_flow_service.enter_room(room_id)
	assert(entered.get("ok", false), "enter_room should succeed")
	assert(str(entered.get("state", "")) == "AWAITING_DECISION", "room should wait for decision after entering")

	var resolved: Dictionary = room_flow_service.submit_room_command(room_id, {})
	assert(resolved.get("ok", false), "submit_room_command should succeed")
	assert(str(resolved.get("state", "")) == "RESOLVED", "room should resolve after submit")

	var resolved_again: Dictionary = room_flow_service.submit_room_command(room_id, {})
	assert(str(resolved_again.get("summary", "")) == str(resolved.get("summary", "")), "repeat submit should be idempotent")
	var room_state: Dictionary = run_service.get_room_state(room_id)
	var transactions: Array = room_state.get("transactions", [])
	assert(transactions.size() == 1, "room should only record one transaction")

	var left: Dictionary = room_flow_service.leave_room(room_id)
	assert(str(left.get("state", "")) == "LEFT", "leave_room should mark LEFT")
	run_service.end_run()
	print("ROOM_FLOW_SERVICE_TEST_PASS")
	quit()
