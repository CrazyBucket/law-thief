class_name ShallowWaterOverlayRenderer
extends Node2D

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const WATER_TILE_SHADER_PATH := "res://scenes/battle/water_tile.gdshader"
const WATER_BOTTOM_PATH := "res://assets/tiles/mew_water_bottom.png"
const WATER_TOP_PATH := "res://assets/tiles/mew_water_top.png"
const MASK_PATHS := [
	"res://assets/overlays/effects/overlay_shallow_water_puddle_01.png",
	"res://assets/overlays/effects/overlay_shallow_water_puddle_02.png",
	"res://assets/overlays/effects/overlay_shallow_water_puddle_03.png",
	"res://assets/overlays/effects/overlay_shallow_water_puddle_04.png",
	"res://assets/overlays/effects/overlay_shallow_water_puddle_05.png",
]

var cells: Array[Dictionary] = []
var _visual_signature := -1
var _masks: Array[Texture2D] = []
var sync_scan_count: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	_sync_cells()


func _draw() -> void:
	if _masks.size() != MASK_PATHS.size():
		return
	var size := Vector2(IsoCoordinates._tile_w(), IsoCoordinates._tile_h())
	for cell in cells:
		var texture := _masks[int(cell["variant"])]
		if texture == null:
			continue
		var center: Vector2 = cell["center"]
		draw_texture_rect(texture, Rect2(center - size * 0.5, size), false)


func _sync_cells() -> void:
	var board := get_parent()
	var state: GameState = board.get("state") if board != null else null
	var signature := hash([
		state.get_instance_id() if state != null else 0,
		state.revision if state != null else 0,
		IsoCoordinates.tile_scale,
		board.get("invert_origin") if board != null else false,
	])
	if signature == _visual_signature:
		return
	_visual_signature = signature
	sync_scan_count += 1
	var positions: Array[Vector2i] = []
	if state != null:
		for tile: TileState in state.tiles.values():
			if tile != null and tile.has_modifier(Constants.TILE_MOD_SHALLOW_WATER):
				positions.append(tile.pos)
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	if not positions.is_empty():
		_ensure_resources()
	cells.clear()
	for pos in positions:
		cells.append({
			"center": board.call("grid_to_screen", pos),
			"variant": variant_index(pos),
		})
	queue_redraw()


static func variant_index(pos: Vector2i) -> int:
	var mixed := pos.x * 92837111 + pos.y * 689287499 + pos.x * pos.y * 283923481
	return posmod(mixed, MASK_PATHS.size())


func _ensure_resources() -> void:
	if material is ShaderMaterial and _masks.size() == MASK_PATHS.size():
		return
	var water_material := ShaderMaterial.new()
	water_material.shader = ResourceLoader.load(WATER_TILE_SHADER_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as Shader
	water_material.set_shader_parameter("base_color", Color(0.58431375, 0.9137255, 0.98039216, 0.76))
	water_material.set_shader_parameter("water_bottom", ResourceLoader.load(WATER_BOTTOM_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D)
	water_material.set_shader_parameter("water_top", ResourceLoader.load(WATER_TOP_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D)
	material = water_material
	_masks.clear()
	for path in MASK_PATHS:
		_masks.append(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D)
