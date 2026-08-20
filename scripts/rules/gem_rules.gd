class_name GemRules
extends RefCounted

const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _OldMageBehavior = preload("res://scripts/rules/behaviors/behavior_old_mage.gd")
const _CounterfeitRules = preload("res://scripts/rules/counterfeit_rules.gd")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


static func _effective_extract_range(state: GameState) -> int:
	var registry := _relic_effect_registry()
	var bonus: int = int(registry.query_modifier("extract_range_bonus", state)) if registry != null else 0
	return CombatConfig.extract_range() + bonus


static func _effective_insert_range(state: GameState) -> int:
	var registry := _relic_effect_registry()
	var bonus: int = int(registry.query_modifier("insert_range_bonus", state)) if registry != null else 0
	return CombatConfig.insert_range() + bonus


static func operation_range_for_action(state: GameState, action: String) -> int:
	match action:
		Constants.ACTION_EXTRACT:
			return _effective_extract_range(state)
		Constants.ACTION_INSERT, Constants.ACTION_INSERT_HOOKED:
			return _effective_insert_range(state)
	return -1


static func is_unit_in_operation_range(state: GameState, actor: UnitState, target_unit: UnitState, action: String) -> bool:
	if state == null or actor == null or target_unit == null:
		return false
	var max_range := operation_range_for_action(state, action)
	if max_range < 0:
		return false
	return BoardUtils.distance_between_units(actor, target_unit) <= max_range


static func can_extract_dropped(state: GameState, actor: UnitState, gem_uid: String) -> Dictionary:
	if state == null or actor == null:
		return _fail("目标无效")
	if not state.held_gem_uid.is_empty():
		return _fail("手中已有宝石")
	var drop: Variant = state.dropped_gems.get(gem_uid, null)
	if not drop is Dictionary or not state.gems.has(gem_uid):
		return _fail("地面宝石不存在")
	var pos: Vector2i = (drop as Dictionary).get("pos", Vector2i(-1, -1))
	if BoardUtils.manhattan(actor.pos, pos) > _effective_extract_range(state):
		return _fail("超出范围")
	return _ok()


static func extract_dropped(state: GameState, actor: UnitState, gem_uid: String) -> Dictionary:
	var check := can_extract_dropped(state, actor, gem_uid)
	if not check.get("ok", false):
		return check
	var drop: Dictionary = state.dropped_gems.get(gem_uid, {})
	var gem: GemState = state.gems.get(gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	if not _GemTransfer.to_hand(state, gem, actor.uid):
		return _fail("无法持有宝石")
	state.battle_temp_flags["held_gem_source_uid"] = str(drop.get("source_unit_uid", ""))
	state.log("%s 从地面拔取 %s" % [actor.uid, _data_registry().get_gem_display_name(gem)])
	IntentSystem.refresh_all_intents(state)
	return _ok({"gem_uid": gem_uid, "pos": drop.get("pos", actor.pos)})


static func _effective_trigger_range(state: GameState, slot: SlotState) -> int:
	if slot == null or slot.gem_uid.is_empty():
		return CombatConfig.trigger_range()
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return CombatConfig.trigger_range()
	var profile: String = _data_registry().get_gem_ability_profile(gem, GemEffects.ABILITY_UNIT_RED_ACTIVE)
	match profile:
		"explosion", "poison", "gravity", "fire_gem", "ice", "split":
			return 1
	return CombatConfig.trigger_range()


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
	var was_overload_slot := slot.is_overload_slot()
	var was_overload_echo := state.overload_echo_gems.has(gem.uid)
	var echo_active := OverloadRules.is_active(state, Constants.OVERLOAD_ECHO_EXTRACT)
	var lawless_active := OverloadRules.is_active(state, Constants.OVERLOAD_LAWLESS_ANY_EXTRACT)
	var slot_type := slot.slot_type
	var extracted_from_uid := target_unit.uid
	if not _GemTransfer.to_hand(state, gem, actor.uid):
		return _fail("无法持有宝石")
	state.battle_temp_flags["held_gem_source_uid"] = extracted_from_uid
	state.log("%s 从 %s 的 %s 槽拔出 %s" % [actor.uid, target_unit.uid, slot_type, _data_registry().get_gem_display_name(gem)])
	if was_overload_slot:
		_remove_unit_slot(state, target_unit, slot)
	var registry := _relic_effect_registry()
	if registry != null:
		registry.fire_event("before_extract_behavior", state, {
			"actor_uid": actor.uid,
			"from_uid": extracted_from_uid,
			"gem_uid": gem.uid,
			"gem_id": gem.gem_id,
			"slot_type": slot_type,
			"slot_index": target_unit.slots.find(slot),
			"was_overload_slot": was_overload_slot,
			"was_overload_echo": was_overload_echo,
			"lawless_overload_active": lawless_active,
		})
	# 赝品和拔取残响都会占用原槽。赝品先结算；只有槽位仍为空时，
	# 残响才可生成，避免两个临时占位物互相吞掉触发或留下悬空记录。
	if not was_overload_slot:
		OverloadRules.leave_extract_echo(state, slot, gem, target_unit.uid, echo_active)
	var extraction_deferred := _CounterfeitRules.is_counterfeit_slot(state, slot)
	if not extraction_deferred:
		_behavior_for(target_unit).on_gem_extracted(state, target_unit, slot_type, gem.uid)
		OverloadRules.on_enemy_gem_extracted(state, target_unit, slot_type, gem.uid, lawless_active)
	if registry != null:
		registry.fire_event("after_extract", state, {
			"unit_uid": actor.uid,
			"gem_id": gem.gem_id,
			"slot_type": slot_type,
			"from_uid": extracted_from_uid,
		})
	if was_overload_slot:
		OverloadRules.sync_active_mutations_to_overload_slots(state, false)
	IntentSystem.refresh_all_intents(state)
	return _ok({"gem_uid": gem.uid})


static func can_insert(state: GameState, actor: UnitState, target_unit: UnitState, slot: SlotState) -> Dictionary:
	if state.held_gem_uid.is_empty():
		return _fail("手中没有宝石")
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	return can_insert_gem(state, actor, target_unit, slot, gem)


static func can_insert_gem(
	state: GameState,
	actor: UnitState,
	target_unit: UnitState,
	slot: SlotState,
	gem: GemState
) -> Dictionary:
	if gem == null:
		return _fail("宝石不存在")
	if target_unit == null or not target_unit.alive:
		return _fail("目标无效")
	if BoardUtils.distance_between_units(actor, target_unit) > _effective_insert_range(state):
		return _fail("超出范围")
	# 分裂锁只禁用原槽效果与普通操作；过载会新建同色槽，不改写被锁槽。
	if not slot.is_operable(state.turn_index):
		if slot.is_split_disabled() and gem != null:
			return _ok({"requires_overload": true})
		return _fail("槽位被锁定")
	if _OldMageBehavior.accepts_decoy_insert(state, target_unit, slot, gem):
		return _ok({"requires_overload": false, "old_mage_decoy": true})
	if gem != null:
		var gem_def: Dictionary = _data_registry().get_gem_def(gem.gem_id)
		var gem_slot_type: String = str(gem_def.get("slot_type", ""))
		if not gem_slot_type.is_empty() and not slot.accepts_slot_type(gem_slot_type):
			return _ok({"requires_overload": true})
	return _ok({"requires_overload": not slot.gem_uid.is_empty()})


static func insert(
	state: GameState,
	actor: UnitState,
	target_unit: UnitState,
	slot: SlotState,
	force_overload: bool = false
) -> Dictionary:
	var gem: GemState = state.gems.get(state.held_gem_uid, null)
	if gem == null:
		return _fail("宝石不存在")
	var source_uid := str(state.battle_temp_flags.get("held_gem_source_uid", ""))
	var result := insert_gem(state, actor, target_unit, slot, gem, source_uid, force_overload)
	if result.get("ok", false) and not bool(result.get("overload_armed", false)):
		state.battle_temp_flags.erase("held_gem_source_uid")
	return result


static func insert_gem(
	state: GameState,
	actor: UnitState,
	target_unit: UnitState,
	slot: SlotState,
	gem: GemState,
	source_uid: String = "",
	force_overload: bool = false
) -> Dictionary:
	var check := can_insert_gem(state, actor, target_unit, slot, gem)
	if not check.get("ok", false):
		return check
	var requires_overload := bool(check.get("requires_overload", false))
	if requires_overload and not force_overload and not OverloadRules.can_force_insert(state):
		state.log("过载预兆：再次嵌入可强行压入当前槽位")
		return _ok({
			"gem_uid": gem.uid,
			"inserted": false,
			"overload_armed": true,
			"overload_forced": false,
		})
	var overload_forced := false
	var should_create_overload_slot := force_overload or OverloadRules.can_force_insert(state)
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
	if not _GemTransfer.to_unit_slot(state, gem, target_unit, slot):
		return _fail("无法嵌入宝石")
	state.log("%s 将 %s 嵌入 %s 的 %s 槽" % [actor.uid, _data_registry().get_gem_display_name(gem), target_unit.uid, slot.slot_type])
	_behavior_for(target_unit).on_gem_inserted(state, target_unit, gem.uid)
	var registry := _relic_effect_registry()
	if registry != null:
		if overload_forced:
			registry.fire_event("overload_slot_created", state, {
				"unit_uid": target_unit.uid,
				"slot_index": target_unit.slots.find(slot),
				"gem_uid": gem.uid,
				"gem_id": gem.gem_id,
				"slot_type": slot.slot_type,
			})
		registry.fire_event("after_insert", state, {
			"unit_uid": target_unit.uid,
			"gem_id": gem.gem_id,
			"slot_type": slot.slot_type,
			"from_uid": source_uid,
			"actor_uid": actor.uid,
		})
	IntentSystem.refresh_all_intents(state)
	return _ok({
		"gem_uid": gem.uid,
		"swapped_gem_uid": "",
		"overload_forced": overload_forced,
		"mutation_deferred": slot.overload_mutation_deferred,
		"old_mage_decoy": bool(check.get("old_mage_decoy", false)),
	})


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
# ═══════════════════════════════════════════════════════════════════════════

static func _make_overload_slot(slot: SlotState) -> SlotState:
	var overflow_slot := slot.clone()
	overflow_slot.gem_uid = ""
	overflow_slot.locked = false
	overflow_slot.lock_type = Constants.LOCK_OVERLOAD_SLOT
	overflow_slot.unlock_until_turn = -1
	overflow_slot.overload_slot = true
	overflow_slot.overload_mutation_deferred = false
	return overflow_slot


static func _remove_unit_slot(state: GameState, unit: UnitState, slot: SlotState) -> void:
	var idx := unit.slots.find(slot)
	if idx < 0:
		return
	unit.slots.remove_at(idx)
	_reindex_unit_gems(state, unit)


static func _reindex_unit_gems(state: GameState, unit: UnitState) -> void:
	_GemTransfer.reindex_unit(state, unit)


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
