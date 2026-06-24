class_name WaterLayer
extends Node2D

const FRAME_SIZE := Vector2i(128, 64)

enum LayerKind {
	FILL,
	EDGE,
}

var layer_kind := LayerKind.FILL
var cells: Array = []
var fill_image_top: Image
var fill_image_right: Image
var edge_image_top: Image
var edge_image_right: Image

var _composed_textures: Dictionary = {}


func set_cells(value: Array) -> void:
	cells = value
	queue_redraw()


func _draw() -> void:
	for cell in cells:
		if layer_kind == LayerKind.FILL:
			_draw_fill_cell(self, cell)
		else:
			_draw_edge_cell(self, cell)


static func compose_fill_image(sheet_top: Image, sheet_right: Image, states: Vector4i) -> Image:
	var frames: Array[Image] = [
		_fill_mask_frame(sheet_top, states.x),
		_fill_mask_frame(sheet_right, states.y),
	]
	var bottom := _fill_mask_frame(sheet_top, states.z)
	bottom.flip_y()
	frames.append(bottom)
	var left := _fill_mask_frame(sheet_right, states.w)
	left.flip_x()
	frames.append(left)
	return _apply_diamond_alpha(_intersect_masks(frames))


static func compose_edge_image(sheet_top: Image, sheet_right: Image, states: Vector4i) -> Image:
	var composed := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	composed.fill(Color.TRANSPARENT)
	# Top and bottom corner frames uniquely own all four exposed edge bodies.
	# Right and left only contribute true inner corners, otherwise their two
	# edge bodies would duplicate the top/bottom frames.
	_blit_opaque(composed, _frame(sheet_top, states.x))
	_blit_opaque(composed, _frame(sheet_right, states.y & WaterAutotile.INNER_CORNER))
	var bottom := _frame(sheet_top, states.z)
	bottom.flip_y()
	_blit_opaque(composed, bottom)
	var left := _frame(sheet_right, states.w & WaterAutotile.INNER_CORNER)
	left.flip_x()
	_blit_opaque(composed, left)
	return _apply_diamond_alpha(composed)


static func _compose_frame_image(sheet_top: Image, sheet_right: Image, states: Vector4i) -> Image:
	var composed := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	composed.fill(Color.TRANSPARENT)
	_blit_opaque(composed, _frame(sheet_top, states.x))
	_blit_opaque(composed, _frame(sheet_right, states.y))
	var bottom := _frame(sheet_top, states.z)
	bottom.flip_y()
	_blit_opaque(composed, bottom)
	var left := _frame(sheet_right, states.w)
	left.flip_x()
	_blit_opaque(composed, left)
	return composed


static func _frame(sheet: Image, frame_index: int) -> Image:
	if frame_index == 0 or sheet == null:
		return Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	return sheet.get_region(Rect2i(frame_index * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y))


static func _fill_mask_frame(sheet: Image, frame_index: int) -> Image:
	if frame_index != 0:
		return _frame(sheet, frame_index)
	var unconstrained := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	unconstrained.fill(Color.WHITE)
	return unconstrained


static func _blit_opaque(target: Image, source: Image) -> void:
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			var color := source.get_pixel(x, y)
			if color.a > 0.01:
				target.set_pixel(x, y, color)


static func _intersect_masks(frames: Array[Image]) -> Image:
	var composed := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	composed.fill(Color.TRANSPARENT)
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			var alpha := 1.0
			for frame in frames:
				alpha = minf(alpha, frame.get_pixel(x, y).a)
			if alpha > 0.01:
				composed.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return composed


static func _apply_diamond_alpha(image: Image) -> Image:
	var half_w := float(FRAME_SIZE.x) * 0.5
	var half_h := float(FRAME_SIZE.y) * 0.5
	var center := Vector2(half_w - 0.5, half_h - 0.5)
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			var p := Vector2(float(x), float(y))
			var distance := absf(p.x - center.x) / half_w + absf(p.y - center.y) / half_h
			if distance <= 0.98:
				continue
			var color := image.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			var edge_alpha := clampf((1.02 - distance) / 0.04, 0.0, 1.0)
			color.a *= edge_alpha
			image.set_pixel(x, y, color)
	return image


func _draw_fill_cell(canvas: CanvasItem, cell: Dictionary) -> void:
	var texture := _composed_texture(fill_image_top, fill_image_right, _cell_states(cell), compose_fill_image)
	if texture == null:
		return
	_draw_composed_texture(canvas, cell, texture)


func _draw_edge_cell(canvas: CanvasItem, cell: Dictionary) -> void:
	var texture := _composed_texture(edge_image_top, edge_image_right, _cell_states(cell), compose_edge_image)
	if texture == null:
		return
	_draw_composed_texture(canvas, cell, texture)


func _draw_composed_texture(canvas: CanvasItem, cell: Dictionary, texture: Texture2D) -> void:
	var center: Vector2 = cell["center"]
	var size := Vector2(float(cell["half_w"]) * 2.0, float(cell["half_h"]) * 2.0)
	canvas.draw_texture_rect(texture, Rect2(center - size * 0.5, size), false, Color.WHITE)


func _composed_texture(
	top_sheet: Image,
	right_sheet: Image,
	states: Vector4i,
	compose_fn: Callable
) -> Texture2D:
	if top_sheet == null or right_sheet == null:
		return null
	var key := hash([top_sheet.get_instance_id(), right_sheet.get_instance_id(), states, compose_fn.get_method()])
	if _composed_textures.has(key):
		return _composed_textures[key]
	var image: Image = compose_fn.call(top_sheet, right_sheet, states)
	var texture := ImageTexture.create_from_image(image)
	_composed_textures[key] = texture
	return texture


func _cell_states(cell: Dictionary) -> Vector4i:
	return Vector4i(int(cell["top"]), int(cell["right"]), int(cell["bottom"]), int(cell["left"]))
