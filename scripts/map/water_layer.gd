class_name WaterLayer
extends Node2D

enum LayerKind {
	FILL,
	EDGE,
}

var layer_kind := LayerKind.FILL
var cells: Array = []
var edge_texture_top: Texture2D
var edge_texture_right: Texture2D


func set_cells(value: Array) -> void:
	cells = value
	queue_redraw()


func _draw() -> void:
	for cell in cells:
		if layer_kind == LayerKind.FILL:
			_draw_fill(self, cell)
		else:
			draw_edges(self, cell, edge_texture_top, edge_texture_right)


static func draw_edges(
	canvas: CanvasItem,
	cell: Dictionary,
	top_texture: Texture2D,
	right_texture: Texture2D
) -> void:
	var center: Vector2 = cell["center"]
	var size := Vector2(float(cell["half_w"]) * 2.0, float(cell["half_h"]) * 2.0)
	_draw_frame(canvas, top_texture, int(cell["top"]), center, size, Vector2.ONE)
	_draw_frame(canvas, right_texture, int(cell["right"]), center, size, Vector2.ONE)
	_draw_frame(canvas, top_texture, int(cell["bottom"]), center, size, Vector2(1.0, -1.0))
	_draw_frame(canvas, right_texture, int(cell["left"]), center, size, Vector2(-1.0, 1.0))


static func _draw_fill(canvas: CanvasItem, cell: Dictionary) -> void:
	var center: Vector2 = cell["center"]
	var half_w: float = float(cell["half_w"])
	var half_h: float = float(cell["half_h"])
	canvas.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -half_h),
		center + Vector2(half_w, 0.0),
		center + Vector2(0.0, half_h),
		center + Vector2(-half_w, 0.0),
	]), Color.WHITE)


static func _draw_frame(
	canvas: CanvasItem,
	texture: Texture2D,
	frame: int,
	center: Vector2,
	size: Vector2,
	draw_scale: Vector2
) -> void:
	if frame == 0 or texture == null:
		return
	canvas.draw_set_transform(center, 0.0, draw_scale)
	canvas.draw_texture_rect_region(
		texture,
		Rect2(-size * 0.5, size),
		Rect2(frame * 128.0, 0.0, 128.0, 64.0)
	)
	canvas.draw_set_transform(Vector2.ZERO)
