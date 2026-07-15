class_name GemTransfer
extends RefCounted


## 宝石位置是一个跨对象不变量：任一时刻只能位于手持、单位槽、地块槽、地面中的一处。
## 调用方描述目标位置，本类同步所有容器引用和 GemState 的所有权镜像。
static func to_hand(state: GameState, gem: GemState, holder_uid: String) -> bool:
	if not _is_registered(state, gem):
		return false
	if not state.held_gem_uid.is_empty() and state.held_gem_uid != gem.uid:
		return false
	_detach_references(state, gem.uid)
	state.held_gem_uid = gem.uid
	gem.mark_held(holder_uid)
	return true


static func to_unit_slot(state: GameState, gem: GemState, unit: UnitState, slot: SlotState) -> bool:
	if not _is_registered(state, gem) or unit == null or slot == null:
		return false
	var index := unit.slots.find(slot)
	if index < 0 or (not slot.gem_uid.is_empty() and slot.gem_uid != gem.uid):
		return false
	_detach_references(state, gem.uid)
	slot.gem_uid = gem.uid
	gem.mark_unit_slotted(unit.uid, index)
	return true


static func to_tile_slot(state: GameState, gem: GemState, tile: TileState, slot: SlotState) -> bool:
	if not _is_registered(state, gem) or tile == null or slot == null:
		return false
	var index := tile.slots.find(slot)
	if index < 0 or (not slot.gem_uid.is_empty() and slot.gem_uid != gem.uid):
		return false
	_detach_references(state, gem.uid)
	slot.gem_uid = gem.uid
	gem.mark_tile_slotted(tile.pos, index)
	return true


static func to_slot_reference(
	state: GameState,
	gem: GemState,
	slot: SlotState,
	unit_owner_uid: String = ""
) -> bool:
	if not unit_owner_uid.is_empty():
		var unit: UnitState = state.units.get(unit_owner_uid, null)
		return to_unit_slot(state, gem, unit, slot)
	for tile: TileState in state.tiles.values():
		if tile.slots.has(slot):
			return to_tile_slot(state, gem, tile, slot)
	return false


static func to_ground(
	state: GameState,
	gem: GemState,
	pos: Vector2i,
	metadata: Dictionary = {}
) -> bool:
	if not _is_registered(state, gem):
		return false
	_detach_references(state, gem.uid)
	gem.mark_ground(pos)
	var drop := metadata.duplicate(true)
	drop["gem_uid"] = gem.uid
	drop["gem_id"] = gem.gem_id
	drop["pos"] = pos
	state.dropped_gems[gem.uid] = drop
	return true


static func detach(state: GameState, gem: GemState) -> bool:
	if not _is_registered(state, gem):
		return false
	_detach_references(state, gem.uid)
	gem.mark_detached()
	return true


static func remove(state: GameState, gem_uid: String) -> bool:
	if state == null or gem_uid.is_empty():
		return false
	var gem: GemState = state.gems.get(gem_uid, null)
	_detach_references(state, gem_uid)
	if gem != null:
		gem.mark_detached()
	state.gems.erase(gem_uid)
	return gem != null


static func reindex_unit(state: GameState, unit: UnitState) -> void:
	if state == null or unit == null:
		return
	for i in range(unit.slots.size()):
		var slot: SlotState = unit.slots[i]
		if slot == null or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null:
			gem.mark_unit_slotted(unit.uid, i)


static func reindex_tile(state: GameState, tile: TileState) -> void:
	if state == null or tile == null:
		return
	for i in range(tile.slots.size()):
		var slot: SlotState = tile.slots[i]
		if slot == null or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null:
			gem.mark_tile_slotted(tile.pos, i)


static func location_count(state: GameState, gem_uid: String) -> int:
	if state == null or gem_uid.is_empty():
		return 0
	var count := 1 if state.held_gem_uid == gem_uid else 0
	if state.dropped_gems.has(gem_uid):
		count += 1
	for unit: UnitState in state.units.values():
		for slot: SlotState in unit.slots:
			if slot != null and slot.gem_uid == gem_uid:
				count += 1
	for tile: TileState in state.tiles.values():
		for slot: SlotState in tile.slots:
			if slot != null and slot.gem_uid == gem_uid:
				count += 1
	return count


static func _is_registered(state: GameState, gem: GemState) -> bool:
	return state != null and gem != null and not gem.uid.is_empty() and state.gems.get(gem.uid, null) == gem


static func _detach_references(state: GameState, gem_uid: String) -> void:
	if state.held_gem_uid == gem_uid:
		state.held_gem_uid = ""
	state.dropped_gems.erase(gem_uid)
	for unit: UnitState in state.units.values():
		for slot: SlotState in unit.slots:
			if slot != null and slot.gem_uid == gem_uid:
				slot.gem_uid = ""
	for tile: TileState in state.tiles.values():
		for slot: SlotState in tile.slots:
			if slot != null and slot.gem_uid == gem_uid:
				slot.gem_uid = ""
