class_name TileRenderer
extends RefCounted

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const OVERLAY_FIRE_TEXTURE := preload("res://assets/overlays/overlay_fire.svg")
const OVERLAY_POISON_FOG_TEXTURE := preload("res://assets/overlays/overlay_poison_fog.svg")
const OVERLAY_TOXIC_SMOKE_TEXTURE := preload("res://assets/overlays/overlay_toxic_smoke.svg")
const OVERLAY_POISON_PUDDLE_TEXTURE := preload("res://assets/overlays/overlay_poison_puddle.svg")
const SIDE_DEPTH := 10.0


static func _time_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

static func draw_tile(canvas: Control, center: Vector2, tile: TileState, highlight_color: Color = Color.TRANSPARENT) -> void:
	var palette: Dictionary = _palette(tile)
	var top_color: Color = palette["top"]
	if highlight_color.a > 0.0:
		top_color = top_color.lerp(highlight_color, highlight_color.a)
	_draw_block(canvas, center, top_color, palette["left"], palette["right"])
	_draw_tile_detail(canvas, center, tile)
	if tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE):
		_draw_overlay_texture(canvas, center, OVERLAY_POISON_PUDDLE_TEXTURE)
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
		_draw_overlay_texture(canvas, center, OVERLAY_POISON_FOG_TEXTURE)
		_draw_poison_fog(canvas, center)
	if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		_draw_overlay_texture(canvas, center, OVERLAY_TOXIC_SMOKE_TEXTURE)
		_draw_poison_fog(canvas, center)
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		_draw_overlay_texture(canvas, center, OVERLAY_FIRE_TEXTURE)
		_draw_fire(canvas, center)


## 仅绘制叠加层（高亮、特殊地块、状态），不画地砖底块——底块改由贴图统一渲染
static func draw_tile_overlays(canvas: Control, center: Vector2, tile: TileState, highlight_color: Color = Color.TRANSPARENT) -> void:
	if highlight_color.a > 0.0:
		draw_highlight_fill(canvas, center, highlight_color)
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		_draw_room_label(canvas, center, tile.tile_id)
	elif tile.tile_id == Constants.TILE_PILLAR:
		_draw_pillar(canvas, center)
	if tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE):
		_draw_overlay_texture(canvas, center, OVERLAY_POISON_PUDDLE_TEXTURE)
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
		_draw_overlay_texture(canvas, center, OVERLAY_POISON_FOG_TEXTURE)
		_draw_poison_fog(canvas, center)
	if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		_draw_overlay_texture(canvas, center, OVERLAY_TOXIC_SMOKE_TEXTURE)
		_draw_poison_fog(canvas, center)
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		_draw_overlay_texture(canvas, center, OVERLAY_FIRE_TEXTURE)
		_draw_fire(canvas, center)


static func draw_hover_outline(canvas: Control, center: Vector2, color: Color = Color(0.95, 0.95, 1.0, 0.95)) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	var closed: PackedVector2Array = corners.duplicate()
	closed.append(corners[0])
	canvas.draw_polyline(closed, color, 2.5 * IsoCoordinates.tile_scale, false)


static func draw_highlight_fill(canvas: Control, center: Vector2, color: Color) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	canvas.draw_colored_polygon(corners, color)


static func _draw_block(canvas: Control, center: Vector2, top: Color, left: Color, right: Color) -> void:
	var half_w := IsoCoordinates._half_w()
	var half_h := IsoCoordinates._half_h()
	var depth := SIDE_DEPTH * IsoCoordinates.tile_scale
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
	var half_w := IsoCoordinates._half_w() * 0.7
	var half_h := IsoCoordinates._half_h() * 0.55
	var points := PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
	])
	canvas.draw_colored_polygon(points, color)


static func _draw_overlay_texture(canvas: Control, center: Vector2, texture: Texture2D) -> void:
	if texture == null:
		return
	var width := IsoCoordinates._half_w() * 2.0
	var height := width * float(texture.get_height()) / maxf(float(texture.get_width()), 1.0)
	var rect := Rect2(center.x - width * 0.5, center.y - height * 0.68, width, height)
	canvas.draw_texture_rect(texture, rect, false, Color.WHITE)


static func _draw_tile_detail(canvas: Control, center: Vector2, tile: TileState) -> void:
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		_draw_room_label(canvas, center, tile.tile_id)
		return
	match tile.tile_id:
		Constants.TILE_FLOOR:
			_draw_floor_noise(canvas, center, tile.floor_variant)
		Constants.TILE_PILLAR:
			_draw_pillar(canvas, center)


static func draw_spikes(canvas: Control, center: Vector2) -> void:
	var offsets := [Vector2(-10, 2), Vector2(0, -4), Vector2(10, 2)]
	for offset in offsets:
		var base: Vector2 = center + offset
		canvas.draw_line(base + Vector2(-4, 4), base + Vector2(0, -10), Color(0.95, 0.55, 0.45), 2.0)
		canvas.draw_line(base + Vector2(4, 4), base + Vector2(0, -10), Color(0.95, 0.55, 0.45), 2.0)


static func draw_entity_texture(canvas: Control, center: Vector2, texture: Texture2D, scale_factor: float = 1.0) -> void:
	if texture == null:
		return
	var target_h := IsoCoordinates.visual(76.0) * scale_factor
	var target_w := target_h * float(texture.get_width()) / maxf(float(texture.get_height()), 1.0)
	var foot := center + IsoCoordinates.entity_foot_offset()
	var rect := Rect2(foot.x - target_w * 0.5, foot.y - target_h, target_w, target_h)
	canvas.draw_texture_rect(texture, rect, false, Color.WHITE)


static func draw_prop_sprite(canvas: Control, center: Vector2, texture: Texture2D, foot_ratio: float = 1.0) -> void:
	if texture == null:
		return
	var rect := IsoCoordinates.prop_draw_rect(center, texture, foot_ratio)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	canvas.draw_texture_rect(texture, rect, false, Color.WHITE)


static func draw_prop_fallback(canvas: Control, center: Vector2) -> void:
	var foot := center + IsoCoordinates.entity_foot_offset()
	var half_w := IsoCoordinates._half_w() * 0.28
	var half_h := IsoCoordinates._half_h() * 0.32
	var rock := PackedVector2Array([
		foot + Vector2(-half_w, -half_h * 0.1),
		foot + Vector2(0.0, -half_h * 1.15),
		foot + Vector2(half_w, -half_h * 0.1),
		foot + Vector2(0.0, half_h * 0.02),
	])
	canvas.draw_colored_polygon(rock, Color(0.42, 0.44, 0.48, 0.95))
	canvas.draw_polyline(rock, Color(0.28, 0.3, 0.34, 0.9), IsoCoordinates.visual(1.2), true)


static func _draw_floor_noise(canvas: Control, center: Vector2, variant: int) -> void:
	var dot_color := Color(1, 1, 1, 0.04 + variant * 0.015)
	canvas.draw_circle(center + Vector2(-8, -2), 1.5, dot_color)
	canvas.draw_circle(center + Vector2(6, 4), 1.2, dot_color)


static func _draw_room_label(canvas: Control, center: Vector2, tile_id: String) -> void:
	var room_type: String = _AdventureRoomDisplay.room_type_from_tile(tile_id)
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
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
	var base: Color = _AdventureRoomDisplay.get_display(
		room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)["color"]
	return {
		"top": base.darkened(0.15),
		"left": base.darkened(0.35),
		"right": base.darkened(0.25),
	}


static func _palette(tile: TileState) -> Dictionary:
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		return _room_palette(tile.tile_id)
	match tile.tile_id:
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

static func _draw_pillar(canvas: Control, center: Vector2) -> void:
	# 机关柱，画一个带有槽位暗示的柱子
	var base := center + Vector2(0, -5)
	var pts := PackedVector2Array([
		base + Vector2(-12, 0),
		base + Vector2(-12, -25),
		base + Vector2(0, -32),
		base + Vector2(12, -25),
		base + Vector2(12, 0),
		base + Vector2(0, 6)
	])
	canvas.draw_colored_polygon(pts, Color(0.2, 0.25, 0.3))
	canvas.draw_polyline(pts, Color(0.1, 0.15, 0.2), 2.0, true)
	
	var t := _time_sec()
	var pulse := sin(t * 3.0) * 0.5 + 0.5
	canvas.draw_circle(base + Vector2(0, -18), 5.0, Color(0.2, 0.6, 1.0, 0.5 + pulse * 0.5))


static func _draw_fire(canvas: Control, center: Vector2) -> void:
	var t := _time_sec()
	var offset := Vector2(0, -10)
	for i in range(5):
		var phase := t * (3.0 + i * 0.5) + i * 1.2
		var px := sin(phase) * 12.0
		var py := -fmod(phase * 15.0, 25.0)
		var p_center := center + offset + Vector2(px, py)
		var size := maxf(2.0, 10.0 - py * 0.4)
		var color := Color(1.0, 0.5 + py * 0.02, 0.1, 0.8 - py * 0.03)
		canvas.draw_circle(p_center, size, color)


static func _draw_poison_fog(canvas: Control, center: Vector2) -> void:
	var t := _time_sec()
	_draw_overlay(canvas, center, Color(0.35, 0.92, 0.4, 0.25))
	for i in range(6):
		var phase := t * 1.5 + i * 2.1
		var px := sin(phase * 1.3) * 18.0
		var py := cos(phase * 0.9) * 8.0 - 5.0
		var r := 4.0 + sin(phase * 2.0) * 2.0
		canvas.draw_circle(center + Vector2(px, py), r, Color(0.2, 0.8, 0.3, 0.6))
