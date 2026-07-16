extends SceneTree

const Presenter = preload("res://scripts/ui/battle_overlay_presenter.gd")
const PreviewEffect = preload("res://scripts/data/intent_preview_effect.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Battle Overlay Presenter Test ===")
	_test_empty_contract()
	_test_move_overlay_and_route()
	_test_attack_and_gem_action_metadata()
	_test_selected_intent_overlays()
	print("BATTLE_OVERLAY_PRESENTER_TEST_PASS")
	quit()


func _test_empty_contract() -> void:
	var result := Presenter.empty_highlights()
	for key in ["reachable", "targets", "attack_range", "paths", "danger", "effect_preview", "overlays", "routes"]:
		assert(result.has(key), "empty highlight contract should include %s" % key)
		assert((result[key] as Array).is_empty(), "empty highlight field should start empty: %s" % key)
	print("  [OK] empty compatibility contract")


func _test_move_overlay_and_route() -> void:
	var presenter := Presenter.new()
	var origin := Vector2i(1, 1)
	var step := Vector2i(2, 1)
	var target := Vector2i(3, 1)
	var legacy := Presenter.empty_highlights()
	legacy["reachable"] = [step, target, step]
	var result := presenter.present(legacy, {
		"action": Constants.ACTION_MOVE,
		"move_route": [origin, step, target],
	})

	assert(result.overlays.size() == 1, "move action should produce one overlay")
	assert(result.overlays[0].kind == "move", "move overlay kind should stay compatible")
	assert(result.overlays[0].cells == [step, target], "overlay cells should preserve order while removing duplicates")
	assert(result.routes.size() == 1, "move action should produce one route")
	assert(result.routes[0].path == [origin, step, target], "move route should preserve the queried path")
	assert(not bool(result.routes[0].arrow_reverse), "move route arrow should follow path direction")
	result.reachable.clear()
	assert(legacy.reachable.size() == 3, "presenter must not mutate the legacy read model")
	print("  [OK] move overlay and route")


func _test_attack_and_gem_action_metadata() -> void:
	var presenter := Presenter.new()
	var range_cell := Vector2i(4, 2)
	var effect_cell := Vector2i(5, 2)
	var attack := Presenter.empty_highlights()
	attack["attack_range"] = [range_cell]
	attack["effect_preview"] = [effect_cell]
	var attack_result := presenter.present(attack, {
		"action": Constants.ACTION_ATTACK,
		"source_uid": "player_1",
		"target_cell": range_cell,
	})

	assert(attack_result.overlays.size() == 2, "attack should produce range and effect overlays")
	assert(attack_result.overlays[0].kind == "attack_range", "attack range overlay should be first")
	assert(attack_result.overlays[1].kind == "effect", "attack effect overlay should follow range")
	assert(attack_result.overlays[1].source_uid == "player_1", "effect overlay should retain source identity")
	assert(attack_result.overlays[1].target_cell == range_cell, "hovered target should remain explicit")

	var target_cell := Vector2i(6, 3)
	var gem_action := Presenter.empty_highlights()
	gem_action["targets"] = [target_cell]
	var gem_result := presenter.present(gem_action, {"action": Constants.ACTION_EXTRACT})
	assert(gem_result.overlays.size() == 1, "gem action should produce one target overlay")
	assert(gem_result.overlays[0].kind == "target", "gem target overlay kind should stay compatible")
	assert(gem_result.overlays[0].action == Constants.ACTION_EXTRACT, "target overlay should retain the selected action")
	print("  [OK] attack and gem action metadata")


func _test_selected_intent_overlays() -> void:
	var presenter := Presenter.new()
	var unit := UnitState.new()
	unit.uid = "enemy_1"
	unit.pos = Vector2i(5, 5)
	unit.intent = IntentState.new()
	var path_cell := Vector2i(4, 5)
	var danger_cell := Vector2i(3, 5)
	var spawn_cell := Vector2i(2, 5)
	unit.intent.preview_effects = [
		PreviewEffect.create("movement", [path_cell]),
		PreviewEffect.create("damage", [danger_cell]),
		PreviewEffect.create("spawn", [spawn_cell], {"certainty": "conditional"}),
	]
	var legacy := Presenter.empty_highlights()
	legacy["paths"] = [path_cell]
	legacy["danger"] = [danger_cell]
	var result := presenter.present(legacy, {"selected_unit": unit})

	assert(result.overlays.size() == 3, "intent should produce path, danger, and extra effect overlays")
	assert(result.overlays[0].kind == "intent_path", "intent path should be emitted first")
	assert(result.overlays[1].kind == "danger", "intent danger should follow the path")
	assert(result.overlays[2].preview_kind == "spawn", "non-movement intent effects should retain their kind")
	assert(result.overlays[2].certainty == "conditional", "intent effect certainty should remain explicit")
	assert(result.routes.size() == 1, "selected movement intent should produce a route")
	assert(result.routes[0].kind == "intent", "selected intent route kind should stay compatible")
	assert(result.routes[0].path == [unit.pos, path_cell], "intent route should start at the selected unit")
	assert(result.routes[0].unit_uid == unit.uid, "intent overlays should retain unit identity")
	print("  [OK] selected intent overlays")
