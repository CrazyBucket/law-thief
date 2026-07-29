class_name ShallowWaterOverlayRenderer
extends Node2D

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const WaterTileShader := preload("res://scenes/battle/water_tile.gdshader")
const WATER_BOTTOM := preload("res://assets/tiles/mew_water_bottom.png")
const WATER_TOP := preload("res://assets/tiles/mew_water_top.png")
const MASKS: Array[Texture2D] = [
	preload("res://assets/overlays/effects/overlay_shallow_water_puddle_01.png"),
	preload("res://assets/overlays/effects/overlay_shallow_water_puddle_02.png"),
	preload("res://assets/overlays/effects/overlay_shallow_water_puddle_03.png"),
	preload("res://assets/overlays/effects/overlay_shallow_water_puddle_04.png"),
	preload("res://assets/overlays/effects/overlay_shallow_water_puddle_05.png"),
]

var cells: Array[Dictionary] = []
var _visual_signature := -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var water_material := ShaderMaterial.new()
	water_material.shader = WaterTileShader
	water_material.set_shader_parameter("base_color", Color(0.58431375, 0.9137255, 0.98039216, 0.76))
	water_material.set_shader_parameter("water_bottom", WATER_BOTTOM)
	water_material.set_shader_parameter("water_top", WATER_TOP)
	material = water_material


func _process(_delta: float) -> void:
	_sync_cells()


func _draw() -> void:
	var size := Vector2(IsoCoordinates._tile_w(), IsoCoordinates._tile_h())
	for cell in cells:
		var texture := MASKS[int(cell["variant"])]
		var center: Vector2 = cell["center"]
		draw_texture_rect(texture, Rect2(center - size * 0.5, size), false)


func _sync_cells() -> void:
	var board := get_parent()
	var state: GameState = board.get("state") if board != null else null
	var positions: Array[Vector2i] = []
	if state != null:
		for tile: TileState in state.tiles.values():
			if tile != null and tile.has_modifier(Constants.TILE_MOD_SHALLOW_WATER):
				positions.append(tile.pos)
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var signature := hash([
		state.get_instance_id() if state != null else 0,
		positions,
		IsoCoordinates.tile_scale,
		board.get("invert_origin") if board != null else false,
	])
	if signature == _visual_signature:
		return
	_visual_signature = signature
	cells.clear()
	for pos in positions:
		cells.append({
			"center": board.call("grid_to_screen", pos),
			"variant": variant_index(pos),
		})
	queue_redraw()


static func variant_index(pos: Vector2i) -> int:
	var mixed := pos.x * 92837111 + pos.y * 689287499 + pos.x * pos.y * 283923481
	return posmod(mixed, MASKS.size())
