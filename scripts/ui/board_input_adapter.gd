class_name BoardInputAdapter
extends RefCounted

var _board = null


func setup(board) -> void:
	teardown()
	_board = board
	if _board == null:
		return
	var input_cb := Callable(self, "_on_board_gui_input")
	if not _board.gui_input.is_connected(input_cb):
		_board.gui_input.connect(input_cb)


func teardown() -> void:
	if _board == null:
		return
	var input_cb := Callable(self, "_on_board_gui_input")
	if _board.gui_input.is_connected(input_cb):
		_board.gui_input.disconnect(input_cb)
	_board = null


func _on_board_gui_input(event: InputEvent) -> void:
	if _board == null:
		return
	if event is InputEventMouseMotion:
		var hover_cell: Vector2i = _board.pick_cell(event.position)
		_board.cell_hovered.emit(hover_cell, hover_cell.x >= 0)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_cell: Vector2i = _board.pick_cell(event.position)
		if click_cell.x >= 0:
			_board.cell_clicked.emit(click_cell)
