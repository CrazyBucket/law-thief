extends SceneTree

const _Factory = preload("res://scripts/ui/battle_reward_card_factory.gd")

var _selection_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var registry: Node = root.get_node("DataRegistry")
	var looks: Node = root.get_node("UnitLooks")
	var gem_id := "gem_explosion"
	var gem_card := _Factory.gem_card(gem_id, Color.WHITE, registry, looks, Callable(self, "_no_op"))
	assert(gem_card is PanelContainer)
	assert(_all_text(gem_card).contains(registry.get_gem_display_name(GemState.create("preview", gem_id, {}))), "gem card should show the gem name")
	var gem_button := _button_by_text(gem_card, "选择")
	assert(gem_button != null and not gem_button.disabled, "gem reward should be selectable")
	gem_button.pressed.emit()
	assert(_selection_count == 1, "gem selection should invoke its callback once")

	var dropped_card := _Factory.dropped_gem_card({
		"gem_uid": "dropped_factory_test",
		"gem_id": gem_id,
		"pos": Vector2i(3, 4),
	}, Color.WHITE, registry, looks, Callable(self, "_no_op"))
	assert(dropped_card is PanelContainer)
	var dropped_button := _button_by_text(dropped_card, "选择")
	assert(dropped_button != null and not dropped_button.disabled, "dropped gem reward should be selectable")
	dropped_button.pressed.emit()
	assert(_selection_count == 2, "dropped gem selection should invoke its callback")

	var slot_card := _Factory.slot_embed_card(null, 0, registry, looks, Callable(self, "_no_op"))
	assert(slot_card is PanelContainer)
	var slot_content := slot_card.get_child(0) as VBoxContainer
	var slot_button := slot_content.get_child(slot_content.get_child_count() - 1) as Button
	assert(slot_button.disabled, "an invalid slot must not be actionable")
	var state: GameState = registry.create_battle_state("tutorial_001", 7, "reward_card_factory")
	var valid_slot_card := _Factory.slot_embed_card(state, 0, registry, looks, Callable(self, "_no_op"))
	var valid_slot_button := _button_by_text(valid_slot_card, "嵌入")
	assert(valid_slot_button != null and not valid_slot_button.disabled, "an existing player slot should be actionable")
	valid_slot_button.pressed.emit()
	assert(_selection_count == 3, "slot selection should invoke its callback")

	var relic_ids: Array = registry.get_relic_ids()
	assert(not relic_ids.is_empty())
	var relic_id := str(relic_ids[0])
	var relic_def: Dictionary = registry.get_relic_def(relic_id)
	var relic_card := _Factory.relic_card(
		relic_id,
		relic_def,
		registry.get_relic_rarity(relic_id),
		Color.WHITE,
		"测试说明",
		registry,
		looks,
		Callable(self, "_no_op")
	)
	assert(relic_card is PanelContainer)
	var relic_button := _button_by_text(relic_card, "选择")
	assert(relic_button != null and not relic_button.disabled, "a normal relic reward should be selectable")
	relic_button.pressed.emit()
	assert(_selection_count == 4, "relic selection should invoke its callback")

	gem_card.free()
	dropped_card.free()
	slot_card.free()
	valid_slot_card.free()
	relic_card.free()
	print("BATTLE_REWARD_CARD_FACTORY_TEST_PASS")
	quit()


func _no_op() -> void:
	_selection_count += 1


func _button_by_text(root_control: Control, text: String) -> Button:
	for button in root_control.find_children("*", "Button", true, false):
		if button is Button and (button as Button).text == text:
			return button as Button
	return null


func _all_text(root_control: Control) -> String:
	var parts: Array[String] = []
	for label in root_control.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return " ".join(parts)
