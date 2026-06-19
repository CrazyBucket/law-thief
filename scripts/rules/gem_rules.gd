class_name GemRules
extends RefCounted

const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


static func _effective_extract_range(state: GameState) -> int:
	var registry := _relic_effect_registry()
	var bonus: int = int(registry.query_modifier("extract_range_bonus", state)) if registry != null else 0
	return Constants.EXTRACT_RANGE + bonus


static func _effective_insert_range(state: GameState) -> int:
	var registry := _relic_effect_registry()
	var bonus: int = int(registry.query_modifier("insert_range_bonus", state)) if registry != null else 0
	return Constants.INSERT_RANGE + bonus


static func operation_range_for_action(state: GameState, action: String) -> int:
	match action:
		Constants.ACTION_EXTRACT:
			return _effective_extract_range(state)
		Constants.ACTION_INSERT:
			return _effective_insert_range(state)
	return -1


static func is_unit_in_operation_range(state: GameState, actor: UnitState, target_unit: UnitState, action: String) -> bool:
	if state == null or actor == null or target_unit == null:
		return false
	var max_range := operation_range_for_action(state, action)
	if max_range < 0:
		return false
	return BoardUtils.distance_between_units(actor, target_unit) <= max_range


static func _effective_trigger_range(state: GameState, slot: SlotState) -> int:
	if slot == null or slot.gem_uid.is_empty():
		return Constants.TRIGGER_RANGE
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return Constants.TRIGGER_RANGE
	var profile: String = _data_registry().get_gem_ability_profile(gem, GemEffects.ABILITY_UNIT_RED_ACTIVE)
	match profile:
		"explosion", "poison", "gravity", "fire_gem", "ice", "split":
			return 1
	return Constants.TRIGGER_RANGE


static func can_extract(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if slot.gem_uid.is_empty():
		return _fail("槽位为空")
	if not state.held_gem_uid.is_empty():
		return _fail("手中已有宝石")
	if BoardUtils.distance_between_units(actor, target_unit) > _effective_extract_range(state):
		return _fail("超出范围")
	return _ok()


static func extract(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	var check := can_extract(state, actor, target_unit, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	var was_overload_slot := slot.lock_type == Constants.LOCK_OVERLOAD_SLOT
	var echo_active := OverloadRules.is_active(state, Constants.OVERLOAD_ECHO_EXTRACT)
	var lawless_active := OverloadRules.is_active(state, Constants.OVERLOAD_LAWLESS_ANY_EXTRACT)
	var slot_type := slot.slot_type
	state.held_gem_uid = gem.uid
	gem.owner_uid = actor.uid
	gem.slot_index = -1
	slot.gem_uid = ""
	state.log("%s 从 %s 的 %s 槽拔出 %s" % [actor.uid, target_unit.uid, slot_type, _data_registry().get_gem_display_name(gem)])
	if was_overload_slot:
		_remove_unit_slot(state, target_unit, slot)
	else:
		OverloadRules.leave_extract_echo(state, slot, gem, target_unit.uid, echo_active)
	_behavior_for(target_unit).on_gem_extracted(state, target_unit, slot_type, gem.uid)
	OverloadRules.on_enemy_gem_extracted(state, target_unit, slot_type, gem.uid, lawless_active)
	var registry := _relic_effect_registry()
	if registry != null:
		registry.fire_event("after_extract", state, {
			"unit_uid": actor.uid, "gem_id": gem.gem_id, "slot_type": slot_type
		})
	if was_overload_slot:
		OverloadRules.sync_active_mutations_to_overload_slots(state, false)
	IntentSystem.refresh_all_intents(state)
	return _ok({"gem_uid": gem.uid})


static func can_insert(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if state.held_gem_uid.is_empty():
		return _fail("手中没有宝石")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if BoardUtils.distance_between_units(actor, target_unit) > _effective_insert_range(state):
		return _fail("超出范围")
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem != null:
		var gem_def: Dictionary = _data_registry().get_gem_def(gem.gem_id)
		var gem_slot_type: String = str(gem_def.get("slot_type", ""))
		if not gem_slot_type.is_empty() and not slot.accepts_slot_type(gem_slot_type):
			if not OverloadRules.can_force_insert(state):
				return _fail("宝石颜色与槽位不兼容")
	if not slot.gem_uid.is_empty() and not OverloadRules.can_force_insert(state) and target_unit.uid != actor.uid:
		return _fail("槽位已有宝石")
	return _ok()


static func insert(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	var check := can_insert(state, actor, target_unit, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	var overload_forced := false
	var should_create_overload_slot := OverloadRules.can_force_insert(state) \
		or (not slot.gem_uid.is_empty() and target_unit.uid == actor.uid)
	if should_create_overload_slot:
		overload_forced = true
		slot = _make_overload_slot(slot)
		target_unit.slots.append(slot)
		state.log("%s 强行将 %s 压入 %s 的 %s 槽，过载涌动" % [
			actor.uid,
			_data_registry().get_gem_display_name(gem),
			target_unit.uid,
			slot.slot_type,
		])
	gem.owner_uid = target_unit.uid
	gem.slot_index = target_unit.slots.find(slot)
	slot.gem_uid = gem.uid
	state.held_gem_uid = ""
	state.log("%s 将 %s 嵌入 %s 的 %s 槽" % [actor.uid, _data_registry().get_gem_display_name(gem), target_unit.uid, slot.slot_type])
	_behavior_for(target_unit).on_gem_inserted(state, target_unit, gem.uid)
	var registry := _relic_effect_registry()
	if registry != null:
		registry.fire_event("after_insert", state, {
			"unit_uid": target_unit.uid,
			"gem_id": gem.gem_id,
			"slot_type": slot.slot_type,
			"from_uid": actor.uid,
		})
	IntentSystem.refresh_all_intents(state)
	return _ok({"gem_uid": gem.uid, "swapped_gem_uid": "", "overload_forced": overload_forced})


static func can_trigger(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if state.player_acted:
		return _fail("本回合已行动")
	if slot.slot_type != Constants.SLOT_RED:
		return _fail("仅红槽可主动触发")
	if slot.gem_uid.is_empty():
		return _fail("槽位为空")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if BoardUtils.distance_between_units(actor, target_unit) > _effective_trigger_range(state, slot):
		return _fail("超出范围")
	return _ok()


static func trigger(
	state: GameState,
	actor: UnitState,
	target_unit: UnitState,
	slot: SlotState,
	out_events: Array[Dictionary] = []
) -> Dictionary:
	var check := can_trigger(state, actor, target_unit, slot)
	if not check.get("ok", false):
		return check
	if not GemEffects.trigger_gem(state, target_unit.uid, slot, out_events):
		return _fail("该槽位不支持主动触发")
	IntentSystem.refresh_all_intents(state)
	state.player_acted = true
	return _ok()


# ═══════════════════════════════════════════════════════════════════════════
# 地块槽位操作
# ═══════════════════════════════════════════════════════════════════════════

static func can_extract_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	if not tile.has_slots():
		return _fail("该地块没有槽位")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if slot.gem_uid.is_empty():
		return _fail("槽位为空")
	if not state.held_gem_uid.is_empty():
		return _fail("手中已有宝石")
	if BoardUtils.manhattan(actor.pos, tile.pos) > _effective_extract_range(state):
		return _fail("超出范围")
	return _ok()


static func extract_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	var check := can_extract_tile(state, actor, tile, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	var was_overload_slot := slot.lock_type == Constants.LOCK_OVERLOAD_SLOT
	var echo_active := OverloadRules.is_active(state, Constants.OVERLOAD_ECHO_EXTRACT)
	state.held_gem_uid = gem.uid
	gem.owner_uid = ""
	gem.slot_index = -1
	slot.gem_uid = ""
	state.log("%s 从 %s 地块拔出 %s" % [actor.uid, tile.tile_id, _data_registry().get_gem_display_name(gem)])
	if was_overload_slot:
		_remove_tile_slot(state, tile, slot)
		OverloadRules.sync_active_mutations_to_overload_slots(state, false)
	else:
		OverloadRules.leave_extract_echo(state, slot, gem, "", echo_active)
	return _ok({"gem_uid": gem.uid})


static func can_insert_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	if not tile.has_slots():
		return _fail("该地块没有槽位")
	if state.held_gem_uid.is_empty():
		return _fail("手中没有宝石")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if BoardUtils.manhattan(actor.pos, tile.pos) > _effective_insert_range(state):
		return _fail("超出范围")
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem != null:
		var gem_def: Dictionary = _data_registry().get_gem_def(gem.gem_id)
		var gem_slot_type: String = str(gem_def.get("slot_type", ""))
		if not gem_slot_type.is_empty() and not slot.accepts_slot_type(gem_slot_type):
			if not OverloadRules.can_force_insert(state):
				return _fail("宝石颜色与槽位不兼容")
	if not slot.gem_uid.is_empty() and not OverloadRules.can_force_insert(state):
		return _fail("槽位已有宝石")
	return _ok()


static func insert_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	var check := can_insert_tile(state, actor, tile, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	var overload_forced := false
	if OverloadRules.can_force_insert(state):
		overload_forced = true
		slot = _make_overload_slot(slot)
		tile.slots.append(slot)
		state.log("%s 强行将 %s 压入 %s 地块，过载涌动" % [
			actor.uid,
			_data_registry().get_gem_display_name(gem),
			tile.tile_id,
		])
	gem.owner_uid = ""
	gem.slot_index = tile.slots.find(slot)
	slot.gem_uid = gem.uid
	state.held_gem_uid = ""
	state.log("%s 将 %s 嵌入 %s 地块" % [actor.uid, _data_registry().get_gem_display_name(gem), tile.tile_id])
	GemEffects.on_tile_gem_inserted(state, tile, slot, gem)
	return _ok({"gem_uid": gem.uid, "swapped_gem_uid": "", "overload_forced": overload_forced})


static func can_trigger_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	if not tile.has_slots():
		return _fail("该地块没有槽位")
	if state.player_acted:
		return _fail("本回合已行动")
	if slot.gem_uid.is_empty():
		return _fail("槽位为空")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if BoardUtils.manhattan(actor.pos, tile.pos) > Constants.TRIGGER_RANGE:
		return _fail("超出范围")
	return _ok()


static func trigger_tile(
	state: GameState,
	actor: UnitState,
	tile: TileState,
	slot: SlotState,
	out_events: Array[Dictionary] = []
) -> Dictionary:
	var check := can_trigger_tile(state, actor, tile, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	if not GemEffects.trigger_tile_gem(state, tile, slot, out_events):
		return _fail("该槽位不支持主动触发")
	state.player_acted = true
	return _ok()


static func _make_overload_slot(slot: SlotState) -> SlotState:
	var overflow_slot := slot.clone()
	overflow_slot.gem_uid = ""
	overflow_slot.locked = false
	overflow_slot.lock_type = Constants.LOCK_OVERLOAD_SLOT
	overflow_slot.unlock_until_turn = -1
	return overflow_slot


static func _remove_unit_slot(state: GameState, unit: UnitState, slot: SlotState) -> void:
	var idx := unit.slots.find(slot)
	if idx < 0:
		return
	unit.slots.remove_at(idx)
	_reindex_unit_gems(state, unit)


static func _remove_tile_slot(state: GameState, tile: TileState, slot: SlotState) -> void:
	var idx := tile.slots.find(slot)
	if idx < 0:
		return
	tile.slots.remove_at(idx)
	_reindex_tile_gems(state, tile)


static func _reindex_unit_gems(state: GameState, unit: UnitState) -> void:
	for i in range(unit.slots.size()):
		var slot: SlotState = unit.slots[i]
		if slot == null or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null:
			gem.owner_uid = unit.uid
			gem.slot_index = i


static func _reindex_tile_gems(state: GameState, tile: TileState) -> void:
	for i in range(tile.slots.size()):
		var slot: SlotState = tile.slots[i]
		if slot == null or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null:
			gem.owner_uid = ""
			gem.slot_index = i


static func _behavior_for(unit: UnitState) -> GDScript:
	return BehaviorRegistry.get_behavior(unit.behavior_id)


static func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


static func _fail(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
