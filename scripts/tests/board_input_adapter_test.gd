extends SceneTree

const BoardInputAdapterType = preload("res://scripts/ui/board_input_adapter.gd")


class FakeBoard extends Control:
	signal cell_hovered(cell: Vector2i, valid: bool)
	signal cell_clicked(cell: Vector2i)
	signal cell_released(cell: Vector2i, valid: bool)
	signal unit_slot_clicked(unit_uid: String, slot_index: int)

	var picked_cell := Vector2i(2, 3)
	var slot_hover_updates := 0


	func set_slot_hover(_screen_pos: Vector2) -> void:
		slot_hover_updates += 1


	func pick_cell(_screen_pos: Vector2) -> Vector2i:
		return picked_cell


	func pick_unit_slot(_screen_pos: Vector2) -> Dictionary:
		return {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Board Input Adapter Test ===")
	var board := FakeBoard.new()
	root.add_child(board)
	var adapter := BoardInputAdapterType.new()
	var hovered: Array[Vector2i] = []
	var clicked: Array[Vector2i] = []
	var released: Array[Vector2i] = []
	board.cell_hovered.connect(func(cell: Vector2i, _valid: bool) -> void: hovered.append(cell))
	board.cell_clicked.connect(func(cell: Vector2i) -> void: clicked.append(cell))
	board.cell_released.connect(func(cell: Vector2i, _valid: bool) -> void: released.append(cell))
	adapter.setup(board)

	_emit_motion(board, Vector2(10, 10))
	_emit_motion(board, Vector2(12, 12))
	assert(hovered == [Vector2i(2, 3)], "same-cell mouse motion should emit hover once")
	assert(board.slot_hover_updates == 2, "slot hover must still update for every mouse motion")

	board.picked_cell = Vector2i(3, 3)
	_emit_motion(board, Vector2(20, 10))
	board.picked_cell = Vector2i(-1, -1)
	_emit_motion(board, Vector2(-10, -10))
	_emit_motion(board, Vector2(-12, -12))
	assert(hovered == [Vector2i(2, 3), Vector2i(3, 3), Vector2i(-1, -1)], "cell changes and first invalid cell should emit exactly once")

	board.picked_cell = Vector2i(2, 3)
	adapter.teardown()
	adapter.setup(board)
	_emit_motion(board, Vector2(10, 10))
	assert(hovered[-1] == Vector2i(2, 3) and hovered.size() == 4, "setup should reset hover deduplication")

	_emit_left_button(board, true)
	_emit_left_button(board, false)
	assert(clicked == [Vector2i(2, 3)], "left press should still click the picked cell")
	assert(released == [Vector2i(2, 3)], "left release should still emit the picked cell")

	adapter.teardown()
	board.queue_free()
	await process_frame
	print("BOARD_INPUT_ADAPTER_TEST_PASS")
	quit()


func _emit_motion(board: Control, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	board.gui_input.emit(event)


func _emit_left_button(board: Control, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(10, 10)
	board.gui_input.emit(event)
