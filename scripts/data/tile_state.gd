class_name TileState
extends RefCounted

var pos: Vector2i = Vector2i.ZERO
var tile_id: String = "tile_floor"
var modifiers: Array = []
var edge_mask: int = 0
var edge_variant: String = ""
var floor_variant: int = 0
var slots: Array = []  # Array[SlotState] — 地块槽位（祭坛/机关柱等特殊地块才有）


static func create(pos: Vector2i, tile_id: String = "tile_floor") -> TileState:
	var tile := TileState.new()
	tile.pos = pos
	tile.tile_id = tile_id
	return tile


## 创建带槽位的特殊地块
static func create_with_slots(pos: Vector2i, tile_id: String, slot_defs: Array) -> TileState:
	var tile := TileState.new()
	tile.pos = pos
	tile.tile_id = tile_id
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


func add_modifier(modifier_type: String, duration: int, payload: Dictionary = {}) -> void:
	modifiers.append({
		"type": modifier_type,
		"duration": duration,
		"payload": payload,
	})


func tick_modifiers() -> void:
	var remaining: Array = []
	for modifier in modifiers:
		var next_duration: int = int(modifier.get("duration", 0)) - 1
		if next_duration > 0:
			var updated: Dictionary = modifier.duplicate(true)
			updated["duration"] = next_duration
			remaining.append(updated)
	modifiers = remaining
