extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var packed_scene := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var battle := packed_scene.instantiate()
	root.add_child(battle)
	await process_frame
	assert(battle.call("_battle_reward_view") != null, "reward view should load on first reward use")

	var gem_offer: Array[String] = [Constants.GEM_EXPLOSION]
	var no_relics: Array[String] = []
	var gem_overlay := battle.call("_build_gem_overlay", gem_offer, no_relics, "win") as CanvasLayer
	assert(gem_overlay != null, "gem reward should build through the lazy reward view")
	battle.add_child(gem_overlay)
	assert(_has_label(gem_overlay, "选择宝石"))
	gem_overlay.queue_free()
	await process_frame

	var relic_offer: Array[String] = ["relic_placeholder"]
	var relic_overlay := battle.call("_build_relic_overlay", relic_offer, "win") as CanvasLayer
	assert(relic_overlay != null, "relic reward should build through the lazy reward view")
	battle.add_child(relic_overlay)
	assert(_has_label(relic_overlay, "无可选遗物"))
	relic_overlay.queue_free()
	await process_frame

	var drops: Array[Dictionary] = [{
		"gem_uid": "reward_view_drop",
		"gem_id": Constants.GEM_EXPLOSION,
	}]
	var dropped_overlay := battle.call("_build_dropped_gem_overlay", drops, no_relics, "win") as CanvasLayer
	assert(dropped_overlay != null, "dropped-gem reward should build through the lazy reward view")
	battle.add_child(dropped_overlay)
	assert(_has_label(dropped_overlay, "选择一颗掉落宝石嵌入"))
	dropped_overlay.queue_free()
	await process_frame

	battle.queue_free()
	await process_frame
	print("BATTLE_REWARD_VIEW_TEST_PASS")
	quit()


func _has_label(root_node: Node, text: String) -> bool:
	for node in root_node.find_children("*", "Label", true, false):
		if node is Label and (node as Label).text == text:
			return true
	return false
