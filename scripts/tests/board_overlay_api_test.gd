extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Board Overlay API Test ===")
	var board_script := load("res://scripts/ui/isometric_board.gd") as GDScript
	assert(board_script != null, "board script should load after project autoloads are ready")
	var board: Control = board_script.new()
	assert(board.has_method("set_overlays"), "board should expose the unified overlay API")
	assert(board.has_method("clear_overlays"), "board should expose explicit overlay cleanup")
	assert(not board.has_method("set_highlights"), "legacy highlight API should be removed")

	var cell := Vector2i(2, 3)
	var destination := Vector2i(3, 3)
	var overlays := [{"kind": "move", "cells": [cell, destination]}]
	var routes := [{"kind": "move", "path": [cell, destination], "arrow_reverse": false}]
	board.set_overlays(overlays, routes)
	overlays[0]["cells"].clear()
	routes[0]["path"].clear()
	assert(board.overlay_specs[0].cells == [cell, destination], "board must own a deep copy of overlay specs")
	assert(board.overlay_routes[0].path == [cell, destination], "board must own a deep copy of overlay routes")
	assert(board.call("_tile_highlight", cell).a > 0.0, "overlay specs should drive tile highlighting")

	board.set_hover(cell)
	var reachable_hover: Color = board.call("_cell_hover_outline_color")
	board.set_overlays([{"kind": "danger", "cells": [cell]}])
	var danger_hover: Color = board.call("_cell_hover_outline_color")
	assert(reachable_hover != danger_hover, "hover affordance should derive from overlay kinds instead of legacy reachable cells")

	board.clear_overlays()
	assert(board.overlay_specs.is_empty() and board.overlay_routes.is_empty(), "clear_overlays should release both spec collections")
	board.free()
	print("BOARD_OVERLAY_API_TEST_PASS")
	quit()
