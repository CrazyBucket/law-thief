extends SceneTree

const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")
const EventResolutionFx = preload("res://scripts/ui/event_resolution_fx.gd")


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
	var story_vbox := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox") as VBoxContainer
	var copy_stack := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/CopyStack") as VBoxContainer
	var body := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/CopyStack/EventBody") as VBoxContainer
	var choice_vbox := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox") as VBoxContainer
	var resolved_vbox := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ResolvedVBox") as VBoxContainer
	var continue_button := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ResolvedVBox/ContinueButton") as Button
	var feedback_label := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/CopyStack/FeedbackLabel") as RichTextLabel
	var artwork := room_scene.get_node("SafeArea/Layout/Main/ArtFrame/ArtStack/EventArtwork") as TextureRect
	var art_fallback := room_scene.get_node("SafeArea/Layout/Main/ArtFrame/ArtStack/ArtFallback") as CenterContainer
	var eyebrow := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/Eyebrow") as Label
	var choice_heading := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/ChoiceHeading") as Label
	assert(event_title.text.contains("巷口的医生"), "event scene should render the configured title")
	assert(not str(body.get_meta("event_body_text", "")).contains("event_field_medic"), "normal event UI must not expose the internal event id")
	assert(not eyebrow.visible and eyebrow.text.is_empty(), "event UI should not repeat a generic encounter eyebrow")
	assert(not choice_heading.visible and choice_heading.text.is_empty(), "event choices should not spend space on a redundant heading")
	assert(room_scene.theme.default_font is SystemFont, "event UI should inherit the shared system-font theme")
	assert((room_scene.theme.default_font as SystemFont).font_names == PackedStringArray(["Noto Serif SC", "Cinzel", "serif"]), "event copy should use the dedicated Noto Serif SC, Cinzel, serif stack")
	assert(event_title.get_theme_font_size("font_size") <= 26, "event titles should stay restrained")
	assert(story_vbox.get_theme_constant("separation") == 32, "event title and body should keep a deliberate 32px gap")
	assert(copy_stack.get_theme_constant("separation") == 12 and body.get_theme_constant("separation") == 12, "event paragraphs and outcome should use a compact 12px rhythm")
	var first_paragraph := body.get_child(0) as RichTextLabel
	assert(first_paragraph != null and first_paragraph.get_theme_font_size("normal_font_size") <= 18, "event body copy should use an adaptive readable size")
	assert(first_paragraph.size.x >= copy_stack.size.x - 1.0, "event paragraphs should fill the story width instead of collapsing into a narrow column")
	assert(first_paragraph.get_theme_color("default_color") == Color("#bebad2"), "event body copy should use the specified #BEBAD2 color")
	var paragraph_font_size := first_paragraph.get_theme_font_size("normal_font_size")
	var paragraph_line_height := first_paragraph.get_theme_font("normal_font").get_height(paragraph_font_size) + first_paragraph.get_theme_constant("line_separation")
	assert(absf(float(paragraph_line_height) / float(paragraph_font_size) - 1.6) <= 0.08, "event body line height should stay near 1.6")
	assert(not continue_button.visible, "unresolved events should require a configured choice")
	assert(artwork.texture == null and art_fallback.visible, "event scene should reserve a stable artwork slot with a neutral fallback")
	var art_frame := room_scene.get_node("SafeArea/Layout/Main/ArtFrame") as PanelContainer
	var story_column := room_scene.get_node("SafeArea/Layout/Main/StoryColumn") as VBoxContainer
	var story_panel := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel") as PanelContainer
	var choice_panel := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel") as PanelContainer
	assert(art_frame.position.x < story_column.position.x, "event artwork should stay in the left column")
	assert(story_panel.position.y < choice_panel.position.y, "event copy should stay above the choice area")
	assert(absf(story_panel.size.y - choice_panel.size.y) <= 1.0, "event copy and choices should split the right column evenly")
	assert(event_title.global_position.x - story_column.global_position.x <= 28.0, "event copy should begin near the artwork blend instead of drifting right")
	assert(art_frame.size.y == story_column.size.y, "artwork and story columns should share the full scene height")
	assert(art_frame.get_theme_stylebox("panel") is StyleBoxEmpty, "event artwork should not be framed as a panel")
	assert(first_paragraph.get_theme_stylebox("normal") is StyleBoxEmpty, "event body copy should sit directly in the scene instead of a text panel")
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
	assert(option_buttons[1].get_global_rect().encloses(enabled_effect.get_global_rect()), "an option effect must stay inside its own interaction row")
	assert(str(option_buttons[1].get_script().resource_path).ends_with("event_choice_button.gd"), "event choices should use the dedicated interaction component")
	assert(option_buttons[1].get_theme_stylebox("normal") is StyleBoxEmpty and option_buttons[1].get_theme_stylebox("hover") is StyleBoxEmpty and option_buttons[1].get_theme_stylebox("pressed") is StyleBoxEmpty, "event choice hover and active states should never paint a card background")
	var normal_title_color := (option_buttons[1].get_node("OptionContent/ChoiceTitle") as Label).get_theme_color("font_color")
	option_buttons[1].set("_hover_amount", 1.0)
	option_buttons[1].call("refresh_visual_state")
	var hovered_title_color := (option_buttons[1].get_node("OptionContent/ChoiceTitle") as Label).get_theme_color("font_color")
	assert(hovered_title_color != normal_title_color, "event choice hover should be communicated by restrained text emphasis")
	assert(option_buttons[1].focus_mode == Control.FOCUS_NONE, "clicking an event choice should not leave a persistent active/focus treatment")
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
	assert(run_service.get_run_phase() == "ROOM", "a resolved event should remain open until its outcome is acknowledged")
	assert(not choice_vbox.visible and resolved_vbox.visible, "resolved event should replace the option list with a dedicated outcome block")
	assert(continue_button.visible, "resolved event should show a deliberate return action")
	assert(feedback_label.visible and feedback_label.get_parsed_text() == str(run_service.get_resolved_room(room_id).get("summary", "")), "resolved event should render the applied outcome instead of silently returning to the map")
	assert(feedback_label.bbcode_enabled and feedback_label.custom_effects.size() == 1, "resolved event copy should use the dedicated semantic rich-text treatment")
	var last_paragraph := body.get_child(body.get_child_count() - 1) as RichTextLabel
	assert(feedback_label.global_position.y - last_paragraph.get_global_rect().end.y <= 13.0, "the resolved outcome should follow the event copy with the 12px content rhythm")
	assert(story_panel.get_global_rect().encloses(feedback_label.get_global_rect()), "the resolved outcome must remain in the upper story area")
	assert(continue_button.position.y <= 1.0, "the continue action should begin at the top of the lower action area")
	assert(continue_button.size.x <= 224.0 and continue_button.position.x <= 1.0, "the continue action should stay compact and left-aligned with the outcome")
	assert(str(continue_button.get_script().resource_path).ends_with("event_choice_button.gd"), "continue should reuse the event interaction component")
	assert(continue_button.get_theme_stylebox("normal") is StyleBoxEmpty and continue_button.get_theme_stylebox("hover") is StyleBoxEmpty and continue_button.get_theme_stylebox("pressed") is StyleBoxEmpty, "continue must not draw a full-width underline or card state")
	continue_button.emit_signal("pressed")
	await process_frame
	assert(run_service.get_run_phase() == "MAP", "acknowledging the result should return to the map")
	await create_timer(0.5).timeout
	await _test_event_artwork(adventure_service, run_service, "event_misaccounting_scribe", "event_misaccounting_scribe.png", 20260722, 1)
	await _test_event_artwork(adventure_service, run_service, "event_sealed_gem_furnace", "event_sealed_gem_furnace.png", 20260723, 2)
	await _test_event_artwork(adventure_service, run_service, "event_injury_appraisal", "event_injury_appraisal.png", 20260725, 1)
	await _test_event_artwork(adventure_service, run_service, "event_counterfeit_auction", "event_counterfeit_auction.png", 20260726, 2)
	await _test_event_reward_embed_dialog(adventure_service, run_service)
	await _test_gem_embed_choice(adventure_service, run_service)
	await _test_event_resolution_effects(adventure_service, run_service)

	run_service.end_run()
	print("EVENT_SCENE_UI_TEST_PASS")
	quit()


func _test_event_resolution_effects(adventure_service: Node, run_service: Node) -> void:
	adventure_service.start_new_run(20260823)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	var injury_node = adventure_service.get_current_node()
	assert(injury_node != null, "event FX test needs an injury event node")
	injury_node.room_type = "EVENT"
	injury_node.properties["event_id"] = "event_injury_appraisal"
	var injury_run = run_service.get_run()
	injury_run.player_hp = int(run_service.get_player_run_snapshot().get("max_hp", 1))
	var hp_before := int(injury_run.player_hp)
	var gold_before := int(run_service.get_balance("gold"))
	var packed := load("res://scenes/adventure/event_scene.tscn") as PackedScene
	var injury_scene := packed.instantiate()
	root.add_child(injury_scene)
	await process_frame
	var sell_blood := _event_option_by_id(injury_scene, "sell_blood")
	assert(sell_blood != null and not sell_blood.disabled, "injury FX fixture should expose blood sale")
	sell_blood.emit_signal("pressed")
	await process_frame
	var injury_fx := injury_scene.get_node("EventResolutionFx")
	var injury_delta: Dictionary = injury_fx.get("last_delta")
	var hp_after := int(run_service.get_player_run_snapshot().get("hp", 0))
	assert(
		int(injury_delta.get("hp", 0)) == hp_after - hp_before and int(injury_delta.get("hp", 0)) < 0,
		"damage FX must use the actual HP delta (fx=%d, before=%d, after=%d)" % [int(injury_delta.get("hp", 0)), hp_before, hp_after]
	)
	assert(int(injury_delta.get("gold", 0)) == run_service.get_balance("gold") - gold_before and int(injury_delta.get("gold", 0)) > 0, "coin FX must use the actual gold delta")
	assert(int(injury_fx.get("damage_shake_count")) == 1, "a damaging event should trigger one restrained screen shake")
	assert(int(injury_fx.get("coin_burst_count")) == 1 and int(injury_fx.get("delta_text_count")) >= 2, "blood sale should spawn semantic damage/gold numbers and a coin burst")
	var animated_coins := injury_fx.get_node("EventResolutionFxRoot").find_children("*", "TextureRect", false, false)
	assert(not animated_coins.is_empty(), "gold gain feedback should keep at least one coin alive for the first animation frame")
	var animated_coin := animated_coins[0] as TextureRect
	assert(
		animated_coin.size.x <= EventResolutionFx.COIN_SIZE.x and animated_coin.size.y <= EventResolutionFx.COIN_SIZE.y,
		"animated coins must remain 16 px after entering the scene tree (actual=%s, minimum=%s, expand=%d)" % [animated_coin.size, animated_coin.get_combined_minimum_size(), animated_coin.expand_mode]
	)
	var injury_feedback := injury_scene.get_node("SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/CopyStack/FeedbackLabel") as RichTextLabel
	assert(injury_feedback.text.contains("kind=danger") and injury_feedback.text.contains("kind=gold"), "resolved damage and gold numbers should carry semantic rich-text colors")
	assert(injury_feedback.get_theme_color("default_color") == Color("#ded8e8"), "resolved copy should use its own result style instead of inheriting ordinary body copy")
	root.get_node("AdventureStatusHud").call("finish_gold_gain_feedback")
	injury_scene.queue_free()
	await process_frame

	adventure_service.start_new_run(20260824)
	var low_run = run_service.get_run()
	adventure_service._begin_chapter_map(2, low_run.map_seed)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "EVENT"
	var furnace_node = adventure_service.get_current_node()
	assert(furnace_node != null, "event FX test needs a furnace event node")
	furnace_node.room_type = "EVENT"
	furnace_node.properties["event_id"] = "event_sealed_gem_furnace"
	low_run.player_hp = 9
	var furnace_scene := packed.instantiate()
	root.add_child(furnace_scene)
	await process_frame
	var take_gem := _event_option_by_id(furnace_scene, "take")
	assert(take_gem != null and not take_gem.disabled, "low-health FX fixture should expose bare-handed gem taking")
	take_gem.emit_signal("pressed")
	await process_frame
	var furnace_fx := furnace_scene.get_node("EventResolutionFx")
	assert(int(furnace_fx.get("damage_shake_count")) == 1, "bare-handed gem taking should shake the event scene")
	assert(int(furnace_fx.get("low_health_vignette_count")) == 1, "dropping to ten percent HP or below should trigger the red edge vignette")
	assert(EventResolutionFx.LOW_HEALTH_DURATION == 2.0, "the low-health vignette contract should last exactly two seconds")
	var vignette := furnace_fx.get_node("LowHealthVignette") as ColorRect
	assert(vignette.visible and vignette.material is ShaderMaterial, "low-health feedback should be a live edge shader rather than a flat web overlay")
	furnace_scene.queue_free()
	await process_frame


func _event_option_by_id(room_scene: Node, option_id: String) -> Button:
	for button in _event_option_buttons(room_scene):
		if str(button.get_meta("event_option_id", "")) == option_id:
			return button
	return null


func _event_option_buttons(room_scene: Node) -> Array[Button]:
	var result: Array[Button] = []
	var option_scroll := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/OptionScroll")
	assert(option_scroll is ScrollContainer, "event choice list must be scrollable so long option sets cannot soft-lock the encounter")
	var option_list := room_scene.get_node("SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/OptionScroll/OptionList")
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
	assert(artwork.material is ShaderMaterial, "event artwork should use the edge-blend material")
	var art_material := artwork.material as ShaderMaterial
	assert(art_material.shader != null and art_material.shader.resource_path.ends_with("event_art_blend.gdshader"), "event artwork should soften and feather its edges into the story column")
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
