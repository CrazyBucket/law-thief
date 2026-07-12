class_name BoardInputAdapter
extends RefCounted

var _board = null
var _last_hover_cell: Vector2i = Vector2i(-1, -1)
var _has_last_hover_cell: bool = false


func setup(board) -> void:
	teardown()
	_board = board
	if _board == null:
		return
	var input_cb := Callable(self, "_on_board_gui_input")
	if not _board.gui_input.is_connected(input_cb):
		_board.gui_input.connect(input_cb)


func teardown() -> void:
	_last_hover_cell = Vector2i(-1, -1)
	_has_last_hover_cell = false
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
		if _board.has_method("set_slot_hover"):
			_board.set_slot_hover(event.position)
		var hover_cell: Vector2i = _board.pick_cell(event.position)
		if _has_last_hover_cell and hover_cell == _last_hover_cell:
			return
		_last_hover_cell = hover_cell
		_has_last_hover_cell = true
		_board.cell_hovered.emit(hover_cell, hover_cell.x >= 0)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _board.has_method("pick_unit_slot"):
				var slot_hit: Dictionary = _board.pick_unit_slot(event.position)
				if not slot_hit.is_empty():
					_board.unit_slot_clicked.emit(str(slot_hit.get("unit_uid", "")), int(slot_hit.get("slot_index", -1)))
					return
			var click_cell: Vector2i = _board.pick_cell(event.position)
			if click_cell.x >= 0:
				_board.cell_clicked.emit(click_cell)
			return
		var release_cell: Vector2i = _board.pick_cell(event.position)
		_board.cell_released.emit(release_cell, release_cell.x >= 0)
