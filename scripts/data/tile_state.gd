class_name TileState
extends RefCounted

var pos: Vector2i = Vector2i.ZERO
var tile_id: String = "tile_floor"
var modifiers: Array = []
var edge_mask: int = 0
var edge_variant: String = ""
var floor_variant: int = 0
var surface_variant: String = ""
## 地面固有属性标签（由 tile_id 决定，运行时不可变）
## 使用字符串集合而非枚举，支持一块地同时具有多个属性
var ground_tags: Array[String] = []


static func create(pos: Vector2i, tile_id: String = "tile_floor") -> TileState:
	var tile := TileState.new()
	tile.pos = pos
	tile.tile_id = tile_id
	tile._init_ground_tags()
	return tile


## 根据 tile_id 初始化固有地面标签，新增 tile 种类时只需在此处登记
func _init_ground_tags() -> void:
	ground_tags.clear()
	match tile_id:
		Constants.TILE_WATER:
			ground_tags.append(Constants.GROUND_TAG_WATER)
		Constants.TILE_ICE:
			ground_tags.append(Constants.GROUND_TAG_ICE)
		Constants.TILE_GRASS:
			ground_tags.append(Constants.GROUND_TAG_FLAMMABLE)
		Constants.TILE_BUSH:
			ground_tags.append(Constants.GROUND_TAG_FLAMMABLE)


func has_ground_tag(tag: String) -> bool:
	return tag in ground_tags


func has_modifier(modifier_type: String) -> bool:
	for modifier in modifiers:
		if String(modifier.get("type", "")) == modifier_type:
			return true
	return false


func get_modifier(modifier_type: String) -> Dictionary:
	for modifier in modifiers:
		if String(modifier.get("type", "")) == modifier_type:
			return modifier
	return {}


func add_modifier(modifier_type: String, duration: int, payload: Dictionary = {}) -> void:
	modifiers.append({
		"type": modifier_type,
		"duration": duration,
		"payload": payload,
	})


func remove_modifier(modifier_type: String) -> void:
	modifiers = modifiers.filter(func(m): return String(m.get("type", "")) != modifier_type)


func tick_modifiers() -> void:
	var remaining: Array = []
	for modifier in modifiers:
		var next_duration: int = int(modifier.get("duration", 0)) - 1
		if next_duration > 0:
			var updated: Dictionary = modifier.duplicate(true)
			updated["duration"] = next_duration
			remaining.append(updated)
	modifiers = remaining


## 语义标签查询（向后兼容旧调用点，内部转发到 ground_tags 或 tile_id 匹配）
func has_tile_tag(tag: String) -> bool:
	match tag:
		Constants.TAG_TILE_CONDUCTIVE:
			return has_ground_tag(Constants.GROUND_TAG_WATER) \
				or has_modifier(Constants.TILE_MOD_SHALLOW_WATER) \
				or has_modifier(Constants.TILE_MOD_POISON_PUDDLE)
		Constants.TAG_TILE_FLAMMABLE:
			return has_ground_tag(Constants.GROUND_TAG_FLAMMABLE)
		Constants.TAG_TILE_ICE:
			return has_ground_tag(Constants.GROUND_TAG_ICE)
		Constants.TAG_TILE_WATER:
			return has_ground_tag(Constants.GROUND_TAG_WATER) \
				or has_modifier(Constants.TILE_MOD_SHALLOW_WATER) \
				or has_modifier(Constants.TILE_MOD_POISON_PUDDLE)
	return false


func clone() -> TileState:
	var tile := TileState.new()
	tile.pos = pos
	tile.tile_id = tile_id
	tile.modifiers = modifiers.duplicate(true)
	tile.edge_mask = edge_mask
	tile.edge_variant = edge_variant
	tile.floor_variant = floor_variant
	tile.ground_tags = ground_tags.duplicate()
	return tile
