class_name StatusRules
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")


static func apply_poison(
	state: GameState,
	unit: UnitState,
	stacks: int = 1,
	duration: int = 2,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_POISON, {
		"stacks": stacks,
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_armor(
	state: GameState,
	unit: UnitState,
	value: int,
	duration: int = 1,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_ARMOR, {
		"value": value,
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_shield(state: GameState, unit: UnitState, value: int, duration: int = 1) -> void:
	apply_armor(state, unit, value, duration)


static func apply_rooted(
	state: GameState,
	unit: UnitState,
	duration: int = 2,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_ROOTED, {
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_exposed(state: GameState, unit: UnitState, slot: SlotState, turn_index: int) -> void:
	var saved_lock_type := slot.lock_type if not slot.lock_type.is_empty() else Constants.LOCK_ARMOR
	_apply(state, unit, Constants.STATUS_EXPOSED, {
		"duration": 1,
		"payload": {
			"slot_type": slot.slot_type,
			"lock_type": saved_lock_type,
		},
	})
	slot.locked = false
	slot.lock_type = ""
	slot.unlock_until_turn = turn_index


static func apply_lawless(state: GameState, unit: UnitState, target_gem_uid: String, source_uid: String = "") -> void:
	_apply(state, unit, Constants.STATUS_LAWLESS, {
		"duration": 0,
		"source_uid": source_uid,
		"payload": {"target_gem_uid": target_gem_uid},
	})


static func clear_lawless(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_LAWLESS)


static func is_lawless(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_LAWLESS)


static func get_lawless_gem_uid(unit: UnitState) -> String:
	var status: StatusInstance = unit.get_status(Constants.STATUS_LAWLESS)
	if status == null:
		return ""
	return status.payload.get("target_gem_uid", "")


static func can_move(unit: UnitState) -> bool:
	for status in unit.statuses:
		if _StatusRegistry.blocks_movement(status.status_id):
			return false
	return true


static func get_armor_bonus(unit: UnitState) -> int:
	var armor: StatusInstance = unit.get_status(Constants.STATUS_ARMOR)
	if armor == null:
		return 0
	return maxi(0, armor.value)


static func tick_turn_start(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		_apply_blue_turn_start_effects(state, unit)
		_tick_phase(state, unit, _StatusRegistry.TICK_TURN_START)
		var tile := state.get_tile(unit.pos)
		if tile.has_modifier("poison_fog"):
			CombatRules.apply_damage(state, unit, Constants.POISON_FOG_DAMAGE, unit.uid, "poison_fog")


static func tick_turn_end(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		_tick_phase(state, unit, _StatusRegistry.TICK_TURN_END)
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		tile.tick_modifiers()
	_apply_tile_pillar_auras(state)


static func _apply(state: GameState, unit: UnitState, status_id: String, params: Dictionary) -> void:
	var incoming := StatusInstance.create(
		status_id,
		int(params.get("stacks", 1)),
		int(params.get("duration", 0)),
		params.get("source_uid", ""),
		params.get("payload", {})
	)
	if params.has("value"):
		incoming.value = int(params.get("value", 0))
	_StatusRegistry.apply_to_unit(unit, incoming)
	state.log("%s 获得状态 %s" % [unit.uid, _StatusRegistry.display_name(status_id)])


static func _tick_phase(state: GameState, unit: UnitState, phase: String) -> void:
	var next: Array[StatusInstance] = []
	for status in unit.statuses:
		if _StatusRegistry.tick_phase(status.status_id) != phase:
			next.append(status)
			continue
		_resolve_tick(state, unit, status)
		if status.duration > 0:
			status.duration -= 1
			if status.duration <= 0:
				state.log("%s 的状态 %s 结束" % [unit.uid, _StatusRegistry.display_name(status.status_id)])
				_on_status_expired(unit, status)
				continue
		next.append(status)
	unit.statuses = next


static func _on_status_expired(unit: UnitState, status: StatusInstance) -> void:
	if status.status_id != Constants.STATUS_EXPOSED:
		return
	var slot_type: String = status.payload.get("slot_type", "")
	var lock_type: String = status.payload.get("lock_type", Constants.LOCK_ARMOR)
	if slot_type.is_empty():
		return
	var slot := unit.get_slot(slot_type)
	if slot == null or slot.gem_uid.is_empty():
		return
	slot.locked = true
	slot.lock_type = lock_type
	slot.unlock_until_turn = -1


static func _resolve_tick(state: GameState, unit: UnitState, status: StatusInstance) -> void:
	match status.status_id:
		Constants.STATUS_POISON:
			CombatRules.apply_damage(state, unit, status.stacks, status.source_uid, "poison")


static func _apply_tile_pillar_auras(state: GameState) -> void:
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_PILLAR:
			TileEffects.tick_pillar_aura(state, tile)


static func _apply_blue_turn_start_effects(state: GameState, unit: UnitState) -> void:
	GemEffects.run_unit_hooks(state, unit, Constants.SLOT_BLUE, GemEffects.TIMING_TURN_START, {})
