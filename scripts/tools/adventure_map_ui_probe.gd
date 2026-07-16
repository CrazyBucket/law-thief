extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var adventure_service: Node = root.get_node("AdventureService")
	adventure_service.call("start_new_run", 12345)
	var packed := load("res://scenes/map/adventure_map.tscn") as PackedScene
	assert(packed != null, "adventure map scene should load")
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var preview := scene.get_node("HudLayer/PreviewPanel") as Control
	assert(preview != null, "map preview panel should exist")
	assert(not preview.visible, "map preview should not be a permanent right-side tooltip")
	var reachable: Array = adventure_service.call("get_reachable_cells")
	assert(not reachable.is_empty(), "fresh map should expose route choices")
	scene.call("_on_cell_hovered", reachable[0], true)
	await process_frame
	assert(preview.visible, "hovering a room should show the compact room preview")
	var outlook := scene.get_node("HudLayer/PreviewPanel/VBox/OutlookBody") as RichTextLabel
	assert(outlook != null, "map preview should expose the route outlook copy")
	assert(outlook.text.contains("[DEBUG] cell="), "debug builds should expose coordinates only in the debug metadata block")
	assert(outlook.text.contains("[DEBUG] room_id="), "debug builds should retain room ids for diagnosis")
	scene.call("_on_cell_hovered", Vector2i.ZERO, false)
	await process_frame
	assert(not preview.visible, "leaving a room should hide the compact room preview")
	print("ADVENTURE_MAP_UI_PROBE_PASS")
	quit(0)
