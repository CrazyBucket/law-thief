class_name CounterfeitRules
extends RefCounted

const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _TURN_FLAG := "relic_counterfeit_used"


static func try_leave_once(
	relic_id: String,
	_effect: Dictionary,
	state: GameState,
	payload: Dictionary
) -> void:
	if state == null or bool(state.relic_battle.turn_flags.get(_TURN_FLAG, false)):
		return
	if str(payload.get("actor_uid", "")) != state.player_uid:
		return
	var target: UnitState = state.units.get(str(payload.get("from_uid", "")), null)
	if target == null or not target.alive or target.team != Constants.TEAM_ENEMY:
		return
	if bool(payload.get("was_overload_slot", false)):
		return
	var slot_index := int(payload.get("slot_index", -1))
	var slot := target.get_slot_by_index(slot_index)
	if slot == null or slot.locked or not slot.gem_uid.is_empty():
		return
	var registry := _data_registry()
	if registry == null:
		return
	var fake_uid := str(registry.next_runtime_uid("counterfeit"))
	var fake: GemState = registry.create_gem_instance(fake_uid, Constants.GEM_COUNTERFEIT)
	state.gems[fake_uid] = fake
	if not _GemTransfer.to_unit_slot(state, fake, target, slot):
		state.gems.erase(fake_uid)
		return
	slot.locked = true
	slot.lock_type = Constants.LOCK_COUNTERFEIT
	slot.unlock_until_turn = state.turn_index
	state.relic_battle.counterfeits[fake_uid] = {
		"owner_uid": target.uid,
		"slot_type": str(payload.get("slot_type", slot.slot_type)),
		"original_gem_uid": str(payload.get("gem_uid", "")),
		"lawless_overload_active": bool(payload.get("lawless_overload_active", false)),
	}
	state.relic_battle.turn_flags[_TURN_FLAG] = true
	state.log("[Relic] %s -> %s 的槽位留下赝品" % [relic_id, target.uid])


static func is_counterfeit_slot(state: GameState, slot: SlotState) -> bool:
	if state == null or slot == null or slot.lock_type != Constants.LOCK_COUNTERFEIT:
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	return gem != null and gem.gem_id == Constants.GEM_COUNTERFEIT


static func break_after_action(state: GameState, unit: UnitState) -> void:
	if state == null or unit == null:
		return
	var fake_uids: Array = state.relic_battle.counterfeits.keys().duplicate()
	var changed := false
	for fake_uid_value in fake_uids:
		var fake_uid := str(fake_uid_value)
		var record: Dictionary = state.relic_battle.counterfeits.get(fake_uid, {})
		if str(record.get("owner_uid", "")) != unit.uid:
			continue
		changed = _remove(state, fake_uid, unit.alive, record) or changed
	if changed:
		IntentSystem.refresh_all_intents(state)


static func remove_for_unit_death(state: GameState, unit: UnitState) -> void:
	if state == null or unit == null:
		return
	var fake_uids: Array = state.relic_battle.counterfeits.keys().duplicate()
	for fake_uid_value in fake_uids:
		var fake_uid := str(fake_uid_value)
		var record: Dictionary = state.relic_battle.counterfeits.get(fake_uid, {})
		if str(record.get("owner_uid", "")) == unit.uid:
			_remove(state, fake_uid, false, record)


static func _remove(
	state: GameState,
	fake_uid: String,
	resolve_extraction: bool,
	record: Dictionary
) -> bool:
	var unit: UnitState = state.units.get(str(record.get("owner_uid", "")), null)
	var fake: GemState = state.gems.get(fake_uid, null)
	var slot := _find_slot(unit, fake_uid)
	var existed := fake != null and slot != null and is_counterfeit_slot(state, slot)
	_GemTransfer.remove(state, fake_uid)
	state.relic_battle.counterfeits.erase(fake_uid)
	if slot != null and slot.lock_type == Constants.LOCK_COUNTERFEIT:
		slot.locked = false
		slot.lock_type = ""
		slot.unlock_until_turn = -1
	if not existed or not resolve_extraction or unit == null or not unit.alive:
		return existed
	var behavior_registry := load("res://scripts/services/behavior_registry.gd") as GDScript
	if behavior_registry != null:
		behavior_registry.get_behavior(unit.behavior_id).on_gem_extracted(
			state,
			unit,
			str(record.get("slot_type", "")),
			str(record.get("original_gem_uid", ""))
		)
	if bool(record.get("lawless_overload_active", false)):
		var overload_rules := load("res://scripts/rules/overload_rules.gd") as GDScript
		if overload_rules != null:
			overload_rules.on_enemy_gem_extracted(
				state,
				unit,
				str(record.get("slot_type", "")),
				str(record.get("original_gem_uid", "")),
				true
			)
	state.log("%s 的赝品破碎" % unit.uid)
	return true


static func _find_slot(unit: UnitState, fake_uid: String) -> SlotState:
	if unit == null:
		return null
	for slot: SlotState in unit.slots:
		if slot != null and slot.gem_uid == fake_uid:
			return slot
	return null


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")
