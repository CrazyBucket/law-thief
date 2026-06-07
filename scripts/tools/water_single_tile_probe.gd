extends SceneTree

const OUTPUT := "/tmp/law_thief_water_single_probe.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("SettingsService").set_value("battle_editor_enabled", true)
	root.get_node("GameService").start_editor_battle("tutorial_001")
	var scene: Control = load("res://scenes/battle/battle_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var controller: BattleController = scene.get("_controller")
	controller.run_editor_action("set_tile", {"tile_id": Constants.TILE_WATER, "pos": Vector2i(2, 2)})
	scene.call("_refresh")
	await create_timer(0.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		push_error("water single probe could not capture viewport")
		quit(1)
		return
	var error := image.save_png(OUTPUT)
	if error != OK:
		push_error("water single probe failed to save screenshot")
		quit(1)
		return
	print("WATER_SINGLE_PROBE_PASS %s" % OUTPUT)
	quit()
