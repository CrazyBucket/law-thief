class_name FuseRules
extends RefCounted


static func try_defer_first_overload(
	relic_id: String,
	_effect: Dictionary,
	state: GameState,
	payload: Dictionary
) -> bool:
	if state == null or state.phase == Constants.PHASE_ENDED:
		return false
	if state.relic_battle.fuse_triggered:
		return false
	var unit: UnitState = state.units.get(str(payload.get("unit_uid", "")), null)
	if unit == null or not unit.alive:
		return false
	var slot := unit.get_slot_by_index(int(payload.get("slot_index", -1)))
	if slot == null or not slot.is_overload_slot() or slot.gem_uid.is_empty():
		return false
	if slot.gem_uid != str(payload.get("gem_uid", "")):
		return false
	slot.overload_mutation_deferred = true
	state.relic_battle.fuse_triggered = true
	state.log("[Relic] %s -> 首次过载异变延迟至战后" % relic_id)
	return true


static func deferred_mutation_count(state: GameState) -> int:
	return 1 if has_deferred_mutation(state) else 0


static func has_deferred_mutation(state: GameState) -> bool:
	if state == null:
		return false
	for unit in state.units.values():
		if unit == null or not unit.alive:
			continue
		for slot in unit.slots:
			if _is_valid_deferred_slot(slot):
				return true
	return false


static func materialize_after_win(
	relic_id: String,
	_effect: Dictionary,
	state: GameState,
	_payload: Dictionary
) -> String:
	if state == null:
		return ""
	var had_valid_deferred := has_deferred_mutation(state)
	_clear_deferred_markers(state)
	if not had_valid_deferred:
		return ""
	var before_count := state.overload_active_mutations.size()
	var overload_rules: GDScript = load("res://scripts/rules/overload_rules.gd")
	overload_rules.sync_active_mutations_to_overload_slots(state, true)
	if state.overload_active_mutations.size() <= before_count:
		return ""
	var mutation := str(state.overload_active_mutations.back())
	state.log("[Relic] %s -> 战后生成异变：%s" % [
		relic_id, overload_rules.mutation_label(mutation)
	])
	return mutation


static func _clear_deferred_markers(state: GameState) -> void:
	for unit in state.units.values():
		if unit == null:
			continue
		for slot in unit.slots:
			if slot != null:
				slot.overload_mutation_deferred = false


static func _is_valid_deferred_slot(slot: SlotState) -> bool:
	return slot != null \
		and slot.overload_mutation_deferred \
		and slot.is_overload_slot() \
		and not slot.gem_uid.is_empty()
