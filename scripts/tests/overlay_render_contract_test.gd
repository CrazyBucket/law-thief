extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var battle := packed.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var board := battle.get_node("BoardLayer/IsometricBoard") as Control
	var state: GameState = board.state
	state.get_tile(Vector2i(0, 0)).tile_id = Constants.TILE_GRASS
	state.get_tile(Vector2i(1, 0)).add_modifier(Constants.TILE_MOD_POISON_FOG, 2)
	state.get_tile(Vector2i(2, 0)).add_modifier(Constants.TILE_MOD_TOXIC_SMOKE, 1)
	await process_frame
	await process_frame
	var viewports := board.find_children("OverlayShaderViewport*", "SubViewport", true, false)
	_require(viewports.size() == 6, "grass, fog, and smoke must keep six shader-backed texture sources")
	for viewport in viewports:
		var overlay_viewport := viewport as SubViewport
		_require(overlay_viewport.transparent_bg, "%s must render with transparency" % overlay_viewport.name)
		_require(overlay_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "%s must animate continuously" % overlay_viewport.name)
		_require(overlay_viewport.get_child_count() == 1, "%s must contain one shader sprite" % overlay_viewport.name)
		if overlay_viewport.get_child_count() == 1:
			var sprite := overlay_viewport.get_child(0) as Sprite2D
			_require(sprite != null and sprite.material is ShaderMaterial, "%s must use a shader material" % overlay_viewport.name)
	var board_source := FileAccess.get_file_as_string("res://scripts/ui/isometric_board.gd")
	var unit_body_draw := board_source.find("\t\t\t_draw_unit_body(unit)\n")
	var front_overlay_draw := board_source.find("\t\t\t_draw_front_tile_overlay_at(grid, true)\n", unit_body_draw)
	var unit_ui_draw := board_source.find("\t\t\t_draw_unit_ui(unit)\n", front_overlay_draw)
	var highlight_draw := board_source.find("\t\t_draw_highlight_outlines()\n", front_overlay_draw)
	_require(unit_body_draw >= 0 and front_overlay_draw > unit_body_draw, "front overlay pass must render after unit bodies")
	_require(board_source.find("func _draw_front_tile_overlays") < 0, "front overlays must not be drawn as a global post-unit pass")
	_require(unit_ui_draw > front_overlay_draw, "unit UI must render above front overlays")
	_require(highlight_draw > front_overlay_draw, "selection outlines must remain above front overlays")
	var unit_ui_fn := board_source.substr(board_source.find("func _draw_unit_ui"), 900)
	_require(unit_ui_fn.contains("_draw_hp_bar") and unit_ui_fn.contains("_draw_unit_statuses") and unit_ui_fn.contains("_draw_gem_icons"), "unit UI pass must own hp, statuses, and gems")
	var shader_source := FileAccess.get_file_as_string("res://scenes/battle/overlay_drift.gdshader")
	_require(shader_source.contains("TIME") and shader_source.contains("VERTEX"), "overlay drift must remain GPU animated")
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		battle.queue_free()
		quit(1)
		return
	print("OVERLAY_RENDER_CONTRACT_TEST_PASS")
	battle.queue_free()
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
