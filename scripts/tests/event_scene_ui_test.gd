extends SceneTree

const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260719)
	assert(run_service.acquire_gem("gem_explosion").get("ok", false), "event popup regression fixture should carry a pre-existing gem")
	run_service.get_run().resources["gold"] = 0
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
	assert(room_scene.get("_gem_embed_overlay") == null, "entering an event with a pre-existing carried gem must not open the embed dialog")

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
	var disabled_title := option_buttons[0].get_node("OptionContent/ChoiceTitle") as Label
	assert(disabled_title.text.contains("不足"), "disabled event option should explain why it is unavailable")
	assert(not disabled_title.text.contains("gold"), "disabled event copy must not expose internal resource ids")
	var disabled_effect := option_buttons[0].get_node("OptionContent/EffectText") as Label
	assert(not disabled_effect.text.contains("实际效果"), "effect copy should not repeat a generic prefix")
	assert(not option_buttons[1].disabled, "decline option should remain available")
	var enabled_effect := option_buttons[1].get_node("OptionContent/EffectText") as Label
	assert(not enabled_effect.text.is_empty(), "enabled event option should show its result copy")
	option_buttons[1].emit_signal("pressed")
	await process_frame
	assert(room_scene.get("_gem_embed_overlay") == null, "a non-gem event choice must not offer embedding for a pre-existing carried gem")

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
	await _test_event_artwork(adventure_service, run_service, "event_misaccounting_scribe", "event_misaccounting_scribe.png", 20260722, 1)
	await _test_event_artwork(adventure_service, run_service, "event_sealed_gem_furnace", "event_sealed_gem_furnace.png", 20260723, 2)
	await _test_event_artwork(adventure_service, run_service, "event_injury_appraisal", "event_injury_appraisal.png", 20260725, 1)
	await _test_event_artwork(adventure_service, run_service, "event_counterfeit_auction", "event_counterfeit_auction.png", 20260726, 2)
	await _test_event_reward_embed_dialog(adventure_service, run_service)
	await _test_gem_embed_choice(adventure_service, run_service)

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


func _test_event_artwork(adventure_service: Node, run_service: Node, event_id: String, artwork_file: String, seed: int, chapter: int) -> void:
	adventure_service.start_new_run(seed)
	if chapter > 1:
		var run = run_service.get_run()
		assert(run != null, "event artwork test needs an active run")
		adventure_service._begin_chapter_map(chapter, run.map_seed)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	var map_node = adventure_service.get_current_node()
	assert(map_node != null, "event artwork test needs a current map node")
	map_node.room_type = "EVENT"
	map_node.properties["event_id"] = event_id
	var packed := load("res://scenes/adventure/event_scene.tscn") as PackedScene
	var room_scene := packed.instantiate()
	root.add_child(room_scene)
	await process_frame
	var artwork := room_scene.get_node("SafeArea/Layout/Main/ArtFrame/ArtStack/EventArtwork") as TextureRect
	var art_fallback := room_scene.get_node("SafeArea/Layout/Main/ArtFrame/ArtStack/ArtFallback") as CenterContainer
	assert(artwork.texture != null, "event should render its dedicated artwork")
	assert(not art_fallback.visible, "dedicated event artwork should replace the neutral fallback")
	assert(artwork.texture.resource_path.ends_with(artwork_file), "event should use its supplied illustration asset")
	assert(room_scene.get_node_or_null("SafeArea/Layout/Main/ArtFrame/ArtStack/TopFade") == null, "event artwork should not add a black top band")
	assert(room_scene.get_node_or_null("SafeArea/Layout/Main/ArtFrame/ArtStack/BottomFade") == null, "event artwork should not add a black bottom band")
	room_scene.queue_free()
	await process_frame


func _test_event_reward_embed_dialog(adventure_service: Node, run_service: Node) -> void:
	adventure_service.start_new_run(20260724)
	var run = run_service.get_run()
	assert(run != null, "event reward dialog test needs an active run")
	adventure_service._begin_chapter_map(2, run.map_seed)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	var map_node = adventure_service.get_current_node()
	assert(map_node != null, "event reward dialog test needs a current map node")
	map_node.room_type = "EVENT"
	map_node.properties["event_id"] = "event_sealed_gem_furnace"
	var room_id := str(adventure_service.current_room_id())
	var packed := load("res://scenes/adventure/event_scene.tscn") as PackedScene
	var room_scene := packed.instantiate()
	root.add_child(room_scene)
	await process_frame
	var entry_options := _event_option_buttons(room_scene)
	assert(not entry_options.is_empty(), "sealed furnace should offer a gem-taking action")
	entry_options[0].emit_signal("pressed")
	await process_frame
	var embed_overlay: CanvasLayer = room_scene.get("_gem_embed_overlay") as CanvasLayer
	assert(embed_overlay != null and is_instance_valid(embed_overlay), "event reward placement should open the shared embed dialog")
	assert(_event_option_buttons(room_scene).is_empty(), "event reward placement must not render slot actions in the event choice list")
	var choice_panel := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel") as PanelContainer
	assert(not choice_panel.visible, "shared embed dialog should replace the event choice panel during placement")
	var dialog_labels := embed_overlay.find_children("*", "Label", true, false)
	var has_reward_title := false
	for raw_label in dialog_labels:
		if raw_label is Label and (raw_label as Label).text.contains("嵌入"):
			has_reward_title = true
			break
	assert(has_reward_title, "embed dialog should render a dedicated title")
	var abandon_button := embed_overlay.find_child("AbandonButton", true, false) as Button
	assert(abandon_button != null and abandon_button.visible, "event reward dialog should allow abandoning the pending gem")
	var slot_button: Button = null
	for raw_button in embed_overlay.find_children("*", "Button", true, false):
		var button := raw_button as Button
		if button.name.begins_with("SlotButton_"):
			slot_button = button
			break
	assert(slot_button != null, "event reward dialog should provide a reusable slot action")
	slot_button.emit_signal("pressed")
	await process_frame
	assert(not run_service.get_resolved_room(room_id).is_empty(), "selecting a dialog slot should resolve the original event reward")
	await create_timer(0.5).timeout
	if is_instance_valid(room_scene):
		room_scene.queue_free()
	await process_frame


func _test_gem_embed_choice(adventure_service: Node, run_service: Node) -> void:
	adventure_service.start_new_run(20260721)
	var filled_slots := RunPlayerGemService.slot_snapshots(run_service.get_run())
	for index in range(filled_slots.size()):
		var snapshot := (filled_slots[index] as Dictionary).duplicate(true)
		snapshot["gem_id"] = "gem_poison"
		filled_slots[index] = snapshot
	run_service.get_run().player_slot_gems = filled_slots
	var slot_count_before := filled_slots.size()
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	var map_node = adventure_service.get_current_node()
	assert(map_node != null, "gem event UI test needs a current map node")
	map_node.room_type = "EVENT"
	map_node.properties["event_id"] = "event_cracked_forge"
	var packed := load("res://scenes/adventure/event_scene.tscn") as PackedScene
	var room_scene := packed.instantiate()
	root.add_child(room_scene)
	await process_frame
	var option_buttons := _event_option_buttons(room_scene)
	assert(not option_buttons.is_empty(), "gem event should provide a reward option")
	option_buttons[0].emit_signal("pressed")
	await process_frame
	var embed_overlay: CanvasLayer = room_scene.get("_gem_embed_overlay") as CanvasLayer
	assert(embed_overlay != null and is_instance_valid(embed_overlay), "event gem reward should immediately offer an out-of-battle embed")
	var pending_response: Dictionary = room_scene.get("_pending_embed_response")
	room_scene.call("_show_gem_embed_choice", pending_response)
	assert(room_scene.get("_gem_embed_overlay") == embed_overlay, "repeated event refresh should reuse the active embed dialog")
	var embed_buttons := embed_overlay.find_children("*", "Button", true, false)
	assert(not embed_buttons.is_empty(), "event embed overlay should expose a slot button")
	var overload_button: Button = null
	for raw_button in embed_buttons:
		var button := raw_button as Button
		if bool(button.get_meta("force_overload", false)):
			overload_button = button
			break
	assert(overload_button != null, "full event loadout should expose an overload embed choice")
	overload_button.emit_signal("pressed")
	await process_frame
	assert(run_service.get_run().carried_gem.is_empty(), "event embed should clear the carried gem")
	assert(run_service.get_run().player_slot_gems.size() == slot_count_before + 1, "event overload embed should append a persistent slot")
	var overload_slot: Dictionary = run_service.get_run().player_slot_gems[-1]
	assert(str(overload_slot.get("lock_type", "")) == Constants.LOCK_OVERLOAD_SLOT, "event overload slot should carry its lock marker")
	room_scene.queue_free()
