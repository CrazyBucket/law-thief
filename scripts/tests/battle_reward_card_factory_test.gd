extends SceneTree

const _Factory = preload("res://scripts/ui/battle_reward_card_factory.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var registry: Node = root.get_node("DataRegistry")
	var looks: Node = root.get_node("UnitLooks")
	var gem_id := "gem_explosion"
	var gem_card := _Factory.gem_card(gem_id, Color.WHITE, registry, looks, Callable(self, "_no_op"))
	assert(gem_card is PanelContainer)
	assert(gem_card.get_child_count() == 1)

	var dropped_card := _Factory.dropped_gem_card({
		"gem_uid": "dropped_factory_test",
		"gem_id": gem_id,
		"pos": Vector2i(3, 4),
	}, Color.WHITE, registry, looks, Callable(self, "_no_op"))
	assert(dropped_card is PanelContainer)

	var slot_card := _Factory.slot_embed_card(null, 0, registry, looks, Callable(self, "_no_op"))
	assert(slot_card is PanelContainer)
	var slot_content := slot_card.get_child(0) as VBoxContainer
	var slot_button := slot_content.get_child(slot_content.get_child_count() - 1) as Button
	assert(slot_button.disabled)

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

	gem_card.free()
	dropped_card.free()
	slot_card.free()
	relic_card.free()
	print("BATTLE_REWARD_CARD_FACTORY_TEST_PASS")
	quit()


func _no_op() -> void:
	pass
