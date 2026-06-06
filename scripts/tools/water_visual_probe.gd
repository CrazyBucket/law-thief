extends SceneTree

const OUTPUT := "/tmp/law_thief_water_probe_final.png"


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
	for pos in [
		Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(4, 3),
	]:
		controller.run_editor_action("set_tile", {"tile_id": Constants.TILE_WATER, "pos": pos})
	scene.call("_refresh")
	await create_timer(0.5).timeout
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		push_error("water visual probe could not capture viewport")
		quit(1)
		return
	var error := image.save_png(OUTPUT)
	if error != OK:
		push_error("water visual probe failed to save screenshot")
		quit(1)
		return
	print("WATER_VISUAL_PROBE_PASS %s" % OUTPUT)
	quit()
