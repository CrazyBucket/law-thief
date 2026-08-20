class_name GemTransfer
extends RefCounted


## 宝石位置是一个跨对象不变量：任一时刻只能位于手持、钩挂、单位槽、地面或脱离状态中的一处。
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


static func to_hooked(state: GameState, gem: GemState, holder_uid: String) -> bool:
	if not _is_registered(state, gem):
		return false
	if not state.relic_battle.hooked_gem_uid.is_empty() \
		and state.relic_battle.hooked_gem_uid != gem.uid:
		return false
	_detach_references(state, gem.uid)
	state.relic_battle.hooked_gem_uid = gem.uid
	gem.mark_hooked(holder_uid)
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


static func to_slot_reference(
	state: GameState,
	gem: GemState,
	slot: SlotState,
	unit_owner_uid: String = ""
) -> bool:
	if not unit_owner_uid.is_empty():
		var unit: UnitState = state.units.get(unit_owner_uid, null)
		return to_unit_slot(state, gem, unit, slot)
	return false


## Atomically exchanges two occupied unit slots without passing either gem
## through hand, ground, extraction, or insertion semantics.
static func swap_unit_slots(
	state: GameState,
	first_unit: UnitState,
	first_index: int,
	second_unit: UnitState,
	second_index: int
) -> bool:
	if state == null or first_unit == null or second_unit == null:
		return false
	if state.units.get(first_unit.uid, null) != first_unit \
		or state.units.get(second_unit.uid, null) != second_unit:
		return false
	if first_unit.uid == second_unit.uid and first_index == second_index:
		return false
	var first_slot := first_unit.get_slot_by_index(first_index)
	var second_slot := second_unit.get_slot_by_index(second_index)
	if first_slot == null or second_slot == null:
		return false
	var first_uid := str(first_slot.gem_uid)
	var second_uid := str(second_slot.gem_uid)
	if first_uid.is_empty() or second_uid.is_empty() or first_uid == second_uid:
		return false
	var first_gem: GemState = state.gems.get(first_uid, null)
	var second_gem: GemState = state.gems.get(second_uid, null)
	if not _is_registered(state, first_gem) or not _is_registered(state, second_gem):
		return false
	first_slot.gem_uid = second_uid
	second_slot.gem_uid = first_uid
	first_gem.mark_unit_slotted(second_unit.uid, second_index)
	second_gem.mark_unit_slotted(first_unit.uid, first_index)
	return true


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
	# 过载残响是临时宝石；任何销毁路径都必须同步清掉生命周期索引。
	state.overload_echo_gems.erase(gem_uid)
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


static func location_count(state: GameState, gem_uid: String) -> int:
	if state == null or gem_uid.is_empty():
		return 0
	var count := 1 if state.held_gem_uid == gem_uid else 0
	if state.relic_battle.hooked_gem_uid == gem_uid:
		count += 1
	if state.dropped_gems.has(gem_uid):
		count += 1
	for unit: UnitState in state.units.values():
		for slot: SlotState in unit.slots:
			if slot != null and slot.gem_uid == gem_uid:
				count += 1
	return count


static func _is_registered(state: GameState, gem: GemState) -> bool:
	return state != null and gem != null and not gem.uid.is_empty() and state.gems.get(gem.uid, null) == gem


static func _detach_references(state: GameState, gem_uid: String) -> void:
	if state.held_gem_uid == gem_uid:
		state.held_gem_uid = ""
	if state.relic_battle.hooked_gem_uid == gem_uid:
		state.relic_battle.clear_hooked_gem()
	state.dropped_gems.erase(gem_uid)
	for unit: UnitState in state.units.values():
		for slot: SlotState in unit.slots:
			if slot != null and slot.gem_uid == gem_uid:
				slot.gem_uid = ""
