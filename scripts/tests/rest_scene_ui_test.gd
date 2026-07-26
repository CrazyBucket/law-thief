extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var room_flow_service: Node = root.get_node("RoomFlowService")
	var game_service: Node = root.get_node("GameService")
	adventure_service.start_new_run(20260721)
	run_service.get_run().player_hp = 30
	run_service.get_run().player_max_hp = 100
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "REST_SITE"
	adventure_service.pending_room_label = "营地"
	var map_node = adventure_service.get_current_node()
	assert(map_node != null, "rest UI test needs a current map node")
	map_node.room_type = "REST_SITE"
	var room_id: String = str(adventure_service.current_room_id())
	assert(adventure_service.get_room_scene_path("REST_SITE") == "res://scenes/adventure/rest_scene.tscn", "map entry should route rest sites to the dedicated camp scene")
	room_flow_service.enter_room(room_id)
	assert(game_service.continue_scene_for_active_run() == "res://scenes/adventure/rest_scene.tscn", "rest rooms should route to the dedicated camp scene")

	var packed := load("res://scenes/adventure/rest_scene.tscn") as PackedScene
	assert(packed != null, "dedicated rest scene should load")
	var room_scene := packed.instantiate()
	root.add_child(room_scene)
	await process_frame

	var card := room_scene.get_node("SafeArea/Layout/Main/RestCard") as PanelContainer
	var rest_button := room_scene.get_node("SafeArea/Layout/Main/RestCard/Margin/VBox/RestButton") as Button
	var leave_button := room_scene.get_node("SafeArea/Layout/Main/RestCard/Margin/VBox/LeaveButton") as Button
	var result_label := room_scene.get_node("SafeArea/Layout/Main/RestCard/Margin/VBox/ResultLabel") as Label
	var backdrop := room_scene.get_node("Backdrop") as TextureRect
	assert(card.size.x >= 500.0, "rest decision card should remain comfortably actionable")
	assert(rest_button.visible and not rest_button.disabled, "rest action should be available before resolving")
	assert(leave_button.visible, "unresolved rest site should keep a leave option")
	assert(not result_label.visible, "rest result should stay hidden before resting")
	assert(backdrop.texture.resource_path == "res://assets/ui/rest_campfire_bg.png", "rest scene should use the dedicated campfire background")

	rest_button.emit_signal("pressed")
	await process_frame
	assert(not run_service.get_resolved_room(room_id).is_empty(), "rest action should resolve the room")
	assert(int(run_service.get_run().player_hp) == 62, "rest UI should preserve the configured 20 percent plus 12 HP reward")
	assert(result_label.visible and result_label.text.contains("62 / 100"), "rest UI should show the resulting health state")
	assert(not leave_button.visible, "resolved rest site should continue forward instead of offering a second exit")

	run_service.end_run()
	print("REST_SCENE_UI_TEST_PASS")
	quit()
