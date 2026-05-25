class_name TileRenderer
extends RefCounted

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const SIDE_DEPTH := 10.0


static func draw_tile(canvas: Control, center: Vector2, tile: TileState, highlight_color: Color = Color.TRANSPARENT) -> void:
	var palette: Dictionary = _palette(tile)
	var top_color: Color = palette["top"]
	if highlight_color.a > 0.0:
		top_color = top_color.lerp(highlight_color, highlight_color.a)
	_draw_block(canvas, center, top_color, palette["left"], palette["right"])
	_draw_tile_detail(canvas, center, tile)
	if tile.has_modifier("poison_fog"):
		_draw_overlay(canvas, center, Color(0.35, 0.92, 0.4, 0.38))


static func draw_hover_outline(canvas: Control, center: Vector2) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	var closed: PackedVector2Array = corners.duplicate()
	closed.append(corners[0])
	canvas.draw_polyline(closed, Color(0.95, 0.95, 1.0, 0.95), 2.5, false)


static func draw_highlight_fill(canvas: Control, center: Vector2, color: Color) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	canvas.draw_colored_polygon(corners, color)


static func _draw_block(canvas: Control, center: Vector2, top: Color, left: Color, right: Color) -> void:
	var half_w := Constants.ISO_TILE_W * 0.5
	var half_h := Constants.ISO_TILE_H * 0.5
	var depth := SIDE_DEPTH
	var top_pts: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	# top_pts: [0]=top, [1]=right, [2]=bottom, [3]=left
	var left_face := PackedVector2Array([
		top_pts[3],
		top_pts[2],
		top_pts[2] + Vector2(0, depth),
		top_pts[3] + Vector2(0, depth),
	])
	var right_face := PackedVector2Array([
		top_pts[2],
		top_pts[1],
		top_pts[1] + Vector2(0, depth),
		top_pts[2] + Vector2(0, depth),
	])
	canvas.draw_colored_polygon(left_face, left)
	canvas.draw_colored_polygon(right_face, right)
	canvas.draw_colored_polygon(top_pts, top)
	canvas.draw_polyline(top_pts, top.darkened(0.28), 1.2, true)


static func _draw_overlay(canvas: Control, center: Vector2, color: Color) -> void:
	var half_w := Constants.ISO_TILE_W * 0.35
	var half_h := Constants.ISO_TILE_H * 0.275
	var points := PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
	])
	canvas.draw_colored_polygon(points, color)


static func _draw_tile_detail(canvas: Control, center: Vector2, tile: TileState) -> void:
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		_draw_room_label(canvas, center, tile.tile_id)
		return
	match tile.tile_id:
		Constants.TILE_SPIKE:
			_draw_spikes(canvas, center)
		Constants.TILE_WATER:
			_draw_water(canvas, center, tile.edge_mask)
		Constants.TILE_FLOOR:
			_draw_floor_noise(canvas, center, tile.floor_variant)


static func _draw_spikes(canvas: Control, center: Vector2) -> void:
	var offsets := [Vector2(-10, 2), Vector2(0, -4), Vector2(10, 2)]
	for offset in offsets:
		var base: Vector2 = center + offset
		canvas.draw_line(base + Vector2(-4, 4), base + Vector2(0, -10), Color(0.95, 0.55, 0.45), 2.0)
		canvas.draw_line(base + Vector2(4, 4), base + Vector2(0, -10), Color(0.95, 0.55, 0.45), 2.0)


static func _draw_water(canvas: Control, center: Vector2, edge_mask: int) -> void:
	var ripple := Color(0.45, 0.78, 1.0, 0.55)
	canvas.draw_arc(center + Vector2(-6, 0), 5.0, 0.0, TAU, 12, ripple, 1.5)
	canvas.draw_arc(center + Vector2(8, 2), 4.0, 0.0, TAU, 12, ripple, 1.5)
	if edge_mask & (1 << 0) == 0:
		canvas.draw_line(center + Vector2(0, -Constants.ISO_TILE_H * 0.5), center + Vector2(-Constants.ISO_TILE_W * 0.25, -Constants.ISO_TILE_H * 0.25), ripple, 1.0)
	if edge_mask & (1 << 2) == 0:
		canvas.draw_line(center + Vector2(0, Constants.ISO_TILE_H * 0.5), center + Vector2(Constants.ISO_TILE_W * 0.25, Constants.ISO_TILE_H * 0.25), ripple, 1.0)


static func _draw_floor_noise(canvas: Control, center: Vector2, variant: int) -> void:
	var dot_color := Color(1, 1, 1, 0.04 + variant * 0.015)
	canvas.draw_circle(center + Vector2(-8, -2), 1.5, dot_color)
	canvas.draw_circle(center + Vector2(6, 4), 1.2, dot_color)


static func _draw_room_label(canvas: Control, center: Vector2, tile_id: String) -> void:
	var room_type: String = _AdventureRoomDisplay.room_type_from_tile(tile_id)
	var display: Dictionary = _AdventureRoomDisplay.get_display(room_type)
	var font: Font = ThemeDB.fallback_font
	var glyph: String = display["glyph"]
	var label: String = display["label"]
	var glyph_size: int = 22
	var label_size: int = 12
	var glyph_dims: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size)
	var label_dims: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
	var text_y: float = center.y - (glyph_dims.y + label_dims.y) * 0.5
	canvas.draw_string(
		font, Vector2(center.x - glyph_dims.x * 0.5, text_y + glyph_dims.y),
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, Color(1, 1, 1, 0.95)
	)
	canvas.draw_string(
		font, Vector2(center.x - label_dims.x * 0.5, text_y + glyph_dims.y + label_dims.y + 2.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(0.92, 0.92, 0.96, 0.9)
	)


static func _room_palette(tile_id: String) -> Dictionary:
	var room_type: String = _AdventureRoomDisplay.room_type_from_tile(tile_id)
	var base: Color = _AdventureRoomDisplay.get_display(room_type)["color"]
	return {
		"top": base.darkened(0.15),
		"left": base.darkened(0.35),
		"right": base.darkened(0.25),
	}


static func _palette(tile: TileState) -> Dictionary:
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		return _room_palette(tile.tile_id)
	match tile.tile_id:
		Constants.TILE_SPIKE:
			return {
				"top": Color(0.48, 0.24, 0.2),
				"left": Color(0.34, 0.16, 0.14),
				"right": Color(0.4, 0.2, 0.17),
			}
		Constants.TILE_WATER:
			return {
				"top": Color(0.18, 0.34, 0.58),
				"left": Color(0.12, 0.24, 0.42),
				"right": Color(0.14, 0.28, 0.48),
			}
		_:
			var even := (tile.pos.x + tile.pos.y) % 2 == 0
			var variant := tile.floor_variant
			var base_color: Color = Color(0.26, 0.26, 0.32) if even else Color(0.22, 0.22, 0.28)
			base_color = base_color.lightened(variant * 0.015)
			return {
				"top": base_color,
				"left": base_color.darkened(0.18),
				"right": base_color.darkened(0.1),
			}
