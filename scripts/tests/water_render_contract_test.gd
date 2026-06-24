extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	var board := battle.get_node("BoardLayer/IsometricBoard")
	var fill := board.get_node("WaterFillLayer") as Node2D
	var edge := board.get_node("WaterEdgeLayer") as Node2D
	var grids := board.get_node("Grids") as Sprite2D
	_require(fill.show_behind_parent, "water fill must render below units")
	_require(edge.show_behind_parent, "water shore must render below units")
	_require(fill.z_index == grids.z_index, "shader fill and board texture must stay behind the board draw")
	_require(fill.get_index() > grids.get_index(), "shader fill must render over the board texture")
	_require(edge.z_index == fill.z_index, "shore must stay behind the board draw")
	_require(edge.get_index() > fill.get_index(), "shore must render over the shader fill")
	_require(not board.has_node("WaterBackEdgeLayer"), "legacy split shore layer must be removed")
	_require(not board.has_node("WaterFrontEdgeLayer"), "legacy front shore layer must be removed")
	_require(fill.material is ShaderMaterial, "water fill must have a shader")
	var source := FileAccess.get_file_as_string("res://scripts/ui/isometric_board.gd")
	var entities_at := source.find("\t\t_draw_entity_at_grid(grid, drawn_entities)\n")
	var unit_body_at := source.find("\t\t\t_draw_unit_body(unit)\n")
	var unit_ui_at := source.find("\t\t\t_draw_unit_ui(unit)\n")
	_require(entities_at >= 0 and unit_body_at >= 0 and unit_ui_at >= 0, "failed to locate entity/unit draw commands")
	_require(entities_at < unit_body_at, "entities must draw before unit bodies")
	_require(unit_body_at < unit_ui_at, "unit UI must draw above unit bodies")
	_require(source.find("_draw_water_edges") < 0, "board redraw must not redraw cached water shores")
	var water_layer_source := FileAccess.get_file_as_string("res://scripts/map/water_layer.gd")
	_require(water_layer_source.find("func compose_edge_image") >= 0, "water shore frames must be composed before rendering")
	_require(water_layer_source.find("_draw_frame(canvas") < 0, "water shore must not alpha-blend overlapping corner frames")
	_require(board.find_children("*", "WaterLayer", true, false).size() == 2, "water must use exactly two cached nodes")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		battle.queue_free()
		quit(1)
		return
	print("  [OK] order: board texture < shader fill < cached shore < every entity/unit")
	print("  [OK] performance: 2 cached water nodes, 0 per-tile nodes")
	print("WATER_RENDER_CONTRACT_TEST_PASS")
	battle.queue_free()
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
