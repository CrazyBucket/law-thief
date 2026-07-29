extends SceneTree

const ShallowWaterLayerClass := preload("res://scripts/map/shallow_water_overlay_renderer.gd")

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
	var shallow := board.get_node("ShallowWaterLayer") as Node2D
	var edge := board.get_node("WaterEdgeLayer") as Node2D
	var grids := board.get_node("Grids") as Sprite2D
	_require(fill.show_behind_parent, "water fill must render below units")
	_require(shallow.show_behind_parent, "shallow water must render below units")
	_require(edge.show_behind_parent, "water shore must render below units")
	_require(fill.z_index == grids.z_index, "shader fill and board texture must stay behind the board draw")
	_require(fill.get_index() > grids.get_index(), "shader fill must render over the board texture")
	_require(shallow.z_index == fill.z_index, "shallow water and water fill must share board depth")
	_require(shallow.get_index() > fill.get_index(), "shallow water must render over the board texture")
	_require(edge.z_index == fill.z_index, "shore must stay behind the board draw")
	_require(edge.get_index() > shallow.get_index(), "shore must render over all water fills")
	_require(not board.has_node("WaterBackEdgeLayer"), "legacy split shore layer must be removed")
	_require(not board.has_node("WaterFrontEdgeLayer"), "legacy front shore layer must be removed")
	_require(fill.material is ShaderMaterial, "water fill must have a shader")
	_require(shallow.material is ShaderMaterial, "shallow water must have a shader")
	var fill_material := fill.material as ShaderMaterial
	var shallow_material := shallow.material as ShaderMaterial
	_require(shallow_material.shader == fill_material.shader, "shallow water must reuse the water-tile shader")
	var fill_color: Color = fill_material.get_shader_parameter("base_color")
	var shallow_color: Color = shallow_material.get_shader_parameter("base_color")
	_require(shallow_color.is_equal_approx(Color(fill_color.r, fill_color.g, fill_color.b, 0.76)), "shallow water must reuse the water-tile RGB palette")
	var state: GameState = board.state
	state.get_tile(Vector2i(0, 0)).add_modifier(Constants.TILE_MOD_SHALLOW_WATER, 2)
	await process_frame
	await process_frame
	var shallow_cells: Array = shallow.get("cells")
	_require(shallow_cells.size() == 1, "shallow water layer must track modifier cells")
	var selected_variants := {}
	for y in range(5):
		for x in range(5):
			var pos := Vector2i(x, y)
			var variant := ShallowWaterLayerClass.variant_index(pos)
			_require(variant == ShallowWaterLayerClass.variant_index(pos), "shallow-water selection must stay stable per cell")
			selected_variants[variant] = true
	_require(selected_variants.size() == 5, "shallow-water coordinate selection must expose all five variants")
	var source := FileAccess.get_file_as_string("res://scripts/ui/isometric_board.gd")
	var entities_at := source.find("\t\t_draw_entity_at_grid(grid, drawn_entities)")
	var unit_body_at := source.find("\t\t\t_draw_unit_body(unit)")
	var unit_ui_at := source.find("\t\t\t_draw_unit_ui(unit)")
	_require(entities_at >= 0 and unit_body_at >= 0 and unit_ui_at >= 0, "failed to locate entity/unit draw commands")
	_require(entities_at < unit_body_at, "entities must draw before unit bodies")
	_require(unit_body_at < unit_ui_at, "unit UI must draw above unit bodies")
	_require(source.find("_draw_water_edges") < 0, "board redraw must not redraw cached water shores")
	var water_layer_source := FileAccess.get_file_as_string("res://scripts/map/water_layer.gd")
	_require(water_layer_source.find("func compose_edge_image") >= 0, "water shore frames must be composed before rendering")
	_require(water_layer_source.find("_draw_frame(canvas") < 0, "water shore must not alpha-blend overlapping corner frames")
	_require(board.find_children("*", "WaterLayer", true, false).size() == 2, "water must use exactly two cached nodes")
	_require(board.find_children("*", "ShallowWaterOverlayRenderer", true, false).size() == 1, "shallow water must use one shared shader layer")
	var tile_renderer_source := FileAccess.get_file_as_string("res://scripts/map/tile_renderer.gd")
	_require(not tile_renderer_source.contains("ShallowWaterOverlayRenderer"), "board draw calls must not duplicate shallow-water rendering")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		battle.queue_free()
		await process_frame
		quit(1)
		return
	print("  [OK] order: board texture < water fill < shallow water < cached shore < every entity/unit")
	print("  [OK] performance: 2 cached water nodes + 1 shared shallow-water node, 0 per-tile nodes")
	print("WATER_RENDER_CONTRACT_TEST_PASS")
	battle.queue_free()
	await process_frame
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
