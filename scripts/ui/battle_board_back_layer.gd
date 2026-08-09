class_name BattleBoardBackLayer
extends Control

const TileRenderer = preload("res://scripts/map/tile_renderer.gd")

var _board: Control = null
var draw_count: int = 0


func configure(board: Control) -> void:
	_board = board
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _draw() -> void:
	draw_count += 1
	if _board == null:
		return
	var state: GameState = _board.get("state")
	if state == null:
		return
	for grid in _board.call("_sorted_cells"):
		_board.call("_draw_tile", self, grid)
	_board.call("_draw_overlay_routes", self)
	_board.call("_draw_editor_preview", self)
	_board.call("_draw_overlay_outlines", self)
	var hover_cell: Vector2i = _board.get("hover_cell")
	if hover_cell.x < 0:
		return
	var hover_unit := state.get_unit_at(hover_cell)
	if hover_unit == null or not hover_unit.alive:
		TileRenderer.draw_hover_outline(
			self,
			_board.call("grid_to_screen", hover_cell),
			_board.call("_cell_hover_outline_color")
		)
