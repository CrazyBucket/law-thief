extends SceneTree

const OUTPUT_PATH := "/tmp/law_thief_editor_visual_probe.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings: Node = root.get_node("SettingsService")
	var game_service: Node = root.get_node("GameService")
	var run_service: Node = root.get_node("RunService")
	settings.set_value("battle_editor_enabled", true)
	game_service.start_editor_battle("tutorial_001")
	run_service.start_run(101, 202)
	run_service.acquire_relic("relic_prism")
	run_service.acquire_relic("relic_boots")
	var scene: Control = load("res://scenes/battle/battle_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var controller: BattleController = scene.get("_controller")
	controller.select_action(Constants.ACTION_ATTACK)
	scene.call("_on_editor_mode_toggled", false)
	assert(controller.selected_action == Constants.ACTION_ATTACK, "closing placement tools must preserve combat action")
	assert(controller.state.get_entity_at(Vector2i(0, 0)) == null, "probe cell should start empty")
	scene.call("_on_editor_mode_toggled", true)
	assert(controller.selected_action == Constants.ACTION_ATTACK, "opening placement tools must preserve combat action")
	var board: Control = scene.get_node("BoardLayer/IsometricBoard")
	var rock_drop := {
		"battle_editor_tool": {"kind": "entity", "id": Constants.ENTITY_ROCK, "label": "Rock"},
	}
	board.call("_drop_data", board.grid_to_screen(Vector2i(0, 0)), rock_drop)
	assert(controller.state.get_entity_at(Vector2i(0, 0)) != null, "native editor drop should place entity")
	assert(controller.selected_action == Constants.ACTION_ATTACK, "editor drop must not clear combat action")
	scene.call("_on_editor_mode_toggled", false)
	assert(controller.state.get_entity_at(Vector2i(0, 0)) != null, "closing placement tools must preserve editor mutations")
	scene.call("_on_editor_mode_toggled", true)
	controller.run_editor_action("spawn_entity", {"entity_id": Constants.ENTITY_BARREL, "pos": Vector2i(1, 0)})
	controller.run_editor_action("spawn_entity", {"entity_id": Constants.ENTITY_SPIKE, "pos": Vector2i(2, 0)})
	controller.run_editor_action("spawn_overlay", {"overlay_id": Constants.TILE_MOD_FIRE, "pos": Vector2i(0, 1)})
	controller.run_editor_action("spawn_overlay", {"overlay_id": Constants.TILE_MOD_POISON_FOG, "pos": Vector2i(1, 1)})
	controller.run_editor_action("spawn_overlay", {"overlay_id": Constants.TILE_MOD_TOXIC_SMOKE, "pos": Vector2i(2, 1)})
	controller.run_editor_action("set_tile", {"tile_id": Constants.TILE_WATER, "pos": Vector2i(3, 1)})
	controller.run_editor_action("spawn_overlay", {"overlay_id": Constants.TILE_MOD_POISON_PUDDLE, "pos": Vector2i(3, 1)})
	controller.run_editor_action("set_tile", {"tile_id": Constants.TILE_GRASS, "pos": Vector2i(0, 2)})
	controller.run_editor_action("set_tile", {"tile_id": Constants.TILE_BUSH, "pos": Vector2i(1, 2)})
	controller.run_editor_action("spawn_overlay", {"overlay_id": Constants.TILE_MOD_FIRE, "pos": Vector2i(0, 2)})
	var player := controller.state.get_player()
	if player != null:
		controller.run_editor_action("set_tile", {"tile_id": Constants.TILE_GRASS, "pos": player.pos})
	scene.call("_refresh")
	await create_timer(0.4).timeout
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		print("EDITOR_VISUAL_PROBE skipped screenshot: viewport texture unavailable")
		quit(0)
		return
	var error := image.save_png(OUTPUT_PATH)
	print("EDITOR_VISUAL_PROBE %s %s" % [error, OUTPUT_PATH])
	quit(0 if error == OK else 1)
