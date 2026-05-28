class_name GemRules
extends RefCounted

const BombRatRules = preload("res://scripts/rules/bomb_rat_rules.gd")
const PatrolGuardRules = preload("res://scripts/rules/patrol_guard_rules.gd")
const StoneBowGuardRules = preload("res://scripts/rules/stone_bow_guard_rules.gd")


static func can_extract(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if slot.gem_uid.is_empty():
		return _fail("槽位为空")
	if not state.held_gem_uid.is_empty():
		return _fail("手中已有宝石")
	if BoardUtils.distance_between_units(actor, target_unit) > Constants.EXTRACT_RANGE:
		return _fail("超出范围")
	return _ok()


static func extract(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	var check := can_extract(state, actor, target_unit, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	state.held_gem_uid = gem.uid
	gem.owner_uid = actor.uid
	gem.slot_index = -1
	slot.gem_uid = ""
	state.log("%s 从 %s 的 %s 槽拔出 %s" % [actor.uid, target_unit.uid, slot.slot_type, _data_registry().get_gem_display_name(gem)])
	if slot.slot_type == Constants.SLOT_RED and target_unit.team == Constants.TEAM_ENEMY:
		if PatrolGuardRules.is_patrol_guard(target_unit):
			PatrolGuardRules.on_red_gem_stolen(state, target_unit, gem.uid)
		elif StoneBowGuardRules.is_stone_bow_guard(target_unit):
			StoneBowGuardRules.on_red_gem_stolen(state, target_unit, gem.uid)
		else:
			StatusRules.apply_lawless(state, target_unit, gem.uid)
	if BombRatRules.is_bomb_rat(target_unit):
		BombRatRules.sync_plunder_state(state, target_unit)
	IntentSystem.refresh_all_intents(state)
	return _ok({"gem_uid": gem.uid})


static func can_insert(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if state.held_gem_uid.is_empty():
		return _fail("手中没有宝石")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if not slot.is_empty():
		return _fail("槽位已被占用")
	if BoardUtils.distance_between_units(actor, target_unit) > Constants.INSERT_RANGE:
		return _fail("超出范围")
	return _ok()


static func insert(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	var check := can_insert(state, actor, target_unit, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	gem.owner_uid = target_unit.uid
	gem.slot_index = target_unit.slots.find(slot)
	slot.gem_uid = gem.uid
	state.held_gem_uid = ""
	state.log("%s 将 %s 嵌入 %s 的 %s 槽" % [actor.uid, _data_registry().get_gem_display_name(gem), target_unit.uid, slot.slot_type])
	if StatusRules.is_lawless(target_unit) and StatusRules.get_lawless_gem_uid(target_unit) == gem.uid:
		if PatrolGuardRules.is_patrol_guard(target_unit):
			PatrolGuardRules.on_lawless_recovered(target_unit)
		elif StoneBowGuardRules.is_stone_bow_guard(target_unit):
			StoneBowGuardRules.on_lawless_recovered(target_unit)
		StatusRules.clear_lawless(target_unit)
	IntentSystem.refresh_all_intents(state)
	return _ok()


static func can_trigger(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if state.player_acted:
		return _fail("本回合已行动")
	if slot.slot_type != Constants.SLOT_RED:
		return _fail("仅红槽可主动触发")
	if slot.gem_uid.is_empty():
		return _fail("槽位为空")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if BoardUtils.distance_between_units(actor, target_unit) > Constants.TRIGGER_RANGE:
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
	if BoardUtils.manhattan(actor.pos, tile.pos) > Constants.EXTRACT_RANGE:
		return _fail("超出范围")
	return _ok()


static func extract_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	var check := can_extract_tile(state, actor, tile, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	state.held_gem_uid = gem.uid
	gem.owner_uid = ""
	gem.slot_index = -1
	slot.gem_uid = ""
	state.log("%s 从 %s 地块拔出 %s" % [actor.uid, tile.tile_id, _data_registry().get_gem_display_name(gem)])
	return _ok({"gem_uid": gem.uid})


static func can_insert_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	if not tile.has_slots():
		return _fail("该地块没有槽位")
	if state.held_gem_uid.is_empty():
		return _fail("手中没有宝石")
	if not slot.is_operable(state.turn_index):
		return _fail("槽位被锁定")
	if not slot.is_empty():
		return _fail("槽位已被占用")
	if BoardUtils.manhattan(actor.pos, tile.pos) > Constants.INSERT_RANGE:
		return _fail("超出范围")
	return _ok()


static func insert_tile(state: GameState, actor: UnitState, tile: TileState, slot: SlotState) -> Dictionary:
	var check := can_insert_tile(state, actor, tile, slot)
	if not check.get("ok", false):
		return check
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	gem.owner_uid = ""
	gem.slot_index = tile.slots.find(slot)
	slot.gem_uid = gem.uid
	state.held_gem_uid = ""
	state.log("%s 将 %s 嵌入 %s 地块" % [actor.uid, _data_registry().get_gem_display_name(gem), tile.tile_id])
	GemEffects.on_tile_gem_inserted(state, tile, slot, gem)
	return _ok()


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
