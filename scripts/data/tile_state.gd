class_name TileState
extends RefCounted

var pos: Vector2i = Vector2i.ZERO
var tile_id: String = "tile_floor"
var modifiers: Array = []
var edge_mask: int = 0
var edge_variant: String = ""
var floor_variant: int = 0
var slots: Array = []  # Array[SlotState] — 地块槽位（机关柱等特殊地块才有）

## 地面固有属性标签（由 tile_id 决定，运行时不可变）
## 使用字符串集合而非枚举，支持一块地同时具有多个属性
var ground_tags: Array[String] = []


static func create(pos: Vector2i, tile_id: String = "tile_floor") -> TileState:
	var tile := TileState.new()
	tile.pos = pos
	tile.tile_id = tile_id
	tile._init_ground_tags()
	return tile


## 创建带槽位的特殊地块
static func create_with_slots(pos: Vector2i, tile_id: String, slot_defs: Array) -> TileState:
	var tile := TileState.new()
	tile.pos = pos
	tile.tile_id = tile_id
	tile._init_ground_tags()
	for slot_data in slot_defs:
		tile.slots.append(
			SlotState.create(
				slot_data.get("slot_type", Constants.SLOT_RED),
				slot_data.get("gem_uid", ""),
				slot_data.get("locked", false),
				slot_data.get("lock_type", "")
			)
		)
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


func has_slots() -> bool:
	return not slots.is_empty()


func get_slot_by_index(index: int) -> SlotState:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


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
			return has_ground_tag(Constants.GROUND_TAG_WATER)
		Constants.TAG_TILE_INTERACTIVE:
			return tile_id == Constants.TILE_PILLAR
		Constants.TAG_TILE_FLAMMABLE:
			return has_ground_tag(Constants.GROUND_TAG_FLAMMABLE)
		Constants.TAG_TILE_ICE:
			return has_ground_tag(Constants.GROUND_TAG_ICE)
		Constants.TAG_TILE_WATER:
			return has_ground_tag(Constants.GROUND_TAG_WATER)
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
	for slot in slots:
		tile.slots.append(slot.clone() if slot != null else null)
	return tile
