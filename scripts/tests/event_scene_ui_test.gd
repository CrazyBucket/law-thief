extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260719)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	adventure_service.pending_room_label = "奇遇"
	var map_node = adventure_service.get_current_node()
	assert(map_node != null, "event UI test needs a current map node")
	map_node.room_type = "EVENT"
	map_node.properties["event_id"] = "event_field_medic"
	var room_id: String = str(adventure_service.current_room_id())

	var packed := load("res://scenes/adventure/event_scene.tscn") as PackedScene
	assert(packed != null, "dedicated event scene should load")
	var room_scene := packed.instantiate()
	root.add_child(room_scene)
	await process_frame

	var event_title := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/EventTitle") as Label
	var body := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/EventBody") as RichTextLabel
	var continue_button := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/ContinueButton") as Button
	var artwork := room_scene.get_node("SafeArea/Layout/Main/ArtFrame/ArtStack/EventArtwork") as TextureRect
	var art_fallback := room_scene.get_node("SafeArea/Layout/Main/ArtFrame/ArtStack/ArtFallback") as CenterContainer
	assert(event_title.text.contains("巷口的医生"), "event scene should render the configured title")
	assert(not body.text.contains("event_field_medic"), "normal event UI must not expose the internal event id")
	assert(not continue_button.visible, "unresolved events should require a configured choice")
	assert(artwork.texture == null and art_fallback.visible, "event scene should reserve a stable artwork slot with a neutral fallback")
	var art_frame := room_scene.get_node("SafeArea/Layout/Main/ArtFrame") as PanelContainer
	var story_column := room_scene.get_node("SafeArea/Layout/Main/StoryColumn") as VBoxContainer
	var story_panel := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel") as PanelContainer
	var choice_panel := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel") as PanelContainer
	assert(art_frame.position.x < story_column.position.x, "event artwork should stay in the left column")
	assert(story_panel.position.y < choice_panel.position.y, "event copy should stay above the choice area")
	assert(art_frame.size.y == story_column.size.y, "artwork and story columns should share the full scene height")
	var option_buttons := _event_option_buttons(room_scene)
	assert(option_buttons.size() == 2, "entry node should render both configured options")
	assert(option_buttons[0].disabled, "unaffordable event option should be visibly disabled")
	assert(option_buttons[0].text.contains("不足"), "disabled event option should explain why it is unavailable")
	assert(not option_buttons[0].text.contains("gold"), "disabled event copy must not expose internal resource ids")
	assert(not option_buttons[1].disabled, "decline option should remain available")
	option_buttons[1].emit_signal("pressed")
	await process_frame

	assert(event_title.text.contains("各走各路"), "choice should replace entry copy with the configured result node")
	option_buttons = _event_option_buttons(room_scene)
	assert(option_buttons.size() == 1, "result node should render its configured finish option")
	var safe_area := room_scene.get_node("SafeArea") as MarginContainer
	assert(choice_panel.get_rect().end.y <= safe_area.size.y, "event choices should fit inside the full-screen safe area")
	option_buttons[0].emit_signal("pressed")
	await process_frame
	assert(not run_service.get_resolved_room(room_id).is_empty(), "finishing an event should resolve its room immediately")
	assert(run_service.get_run_phase() == "MAP", "finishing an event should return to the map without a second continue step")
	await create_timer(0.5).timeout

	run_service.end_run()
	print("EVENT_SCENE_UI_TEST_PASS")
	quit()


func _event_option_buttons(room_scene: Node) -> Array[Button]:
	var result: Array[Button] = []
	var option_list := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/OptionList")
	for child in option_list.get_children():
		if child is Button:
			result.append(child as Button)
	return result
