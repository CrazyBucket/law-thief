extends SceneTree

const FRAME_SIZE := Vector2i(128, 64)


func _initialize() -> void:
	var top_source := Image.load_from_file("res://assets/tiles/waterEdge1.png")
	var right_source := Image.load_from_file("res://assets/tiles/waterEdge2.png")
	_require(top_source != null and right_source != null, "failed to load source water edge sheets")
	var top_frames: Array[Image] = []
	var right_frames: Array[Image] = []
	for state in range(8):
		top_frames.append(_frame(top_source, state))
		right_frames.append(_frame(right_source, state))
	# waterEdge2 frames 1 and 3 contain an unwanted lower-right body. Rebuild
	# those two states from the valid upper-right stroke and right-tip cap.
	right_frames[1] = _frame(top_source, 1)
	right_frames[3] = _merge_frames([_frame(top_source, 1), _frame(right_source, 2)])
	_build_sheet("res://assets/tiles/waterEdgeTop.generated.png", top_frames)
	_build_sheet("res://assets/tiles/waterEdgeRight.generated.png", right_frames)
	print("WATER_EDGE_STATE_SHEETS_BUILT")
	quit()


func _frame(source: Image, state: int) -> Image:
	return source.get_region(Rect2i(state * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y))


func _merge_frames(frames: Array) -> Image:
	var merged := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	merged.fill(Color.TRANSPARENT)
	for frame: Image in frames:
		_copy_shore(merged, frame, Vector2i.ZERO)
	return merged


func _build_sheet(path: String, frames: Array[Image]) -> void:
	var sheet := Image.create(8 * FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for state in range(8):
		_copy_shore(sheet, frames[state], Vector2i(state * FRAME_SIZE.x, 0))
	var err := sheet.save_png(path)
	_require(err == OK, "failed to save %s: %d" % [path, err])


func _copy_shore(target: Image, source: Image, offset: Vector2i) -> void:
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			var c := source.get_pixel(x, y)
			if c.a > 0.01 and not _is_green_mask(c):
				target.set_pixelv(offset + Vector2i(x, y), c)


func _is_green_mask(c: Color) -> bool:
	return c.g > 0.8 and c.r < 0.25 and c.b < 0.25


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
