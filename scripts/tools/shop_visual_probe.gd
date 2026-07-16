extends SceneTree

const OUTPUT_PATH := "res://artifacts/verify/shop_scene_probe.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var adventure_service: Node = root.get_node("AdventureService")
	var economy_service: Node = root.get_node("EconomyService")
	adventure_service.start_new_run(20260716)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "SHOP"
	adventure_service.pending_room_label = "商店"
	var map_node = adventure_service.get_current_node()
	map_node.room_type = "SHOP"
	economy_service.grant("gold", 100, "probe_reward", {"transaction_id": "shop_visual_probe"})
	var scene := (load("res://scenes/adventure/shop_scene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var transition_manager := root.get_node_or_null("TransitionManager")
	if transition_manager != null and transition_manager.has_method("reset_immediately"):
		transition_manager.call("reset_immediately")
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	if transition_manager != null and transition_manager.has_method("reset_immediately"):
		transition_manager.call("reset_immediately")
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		print("SHOP_VISUAL_PROBE skipped: viewport texture unavailable")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/verify"))
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	print("SHOP_VISUAL_PROBE %s %s" % [error, OUTPUT_PATH])
	quit(0 if error == OK else 1)
