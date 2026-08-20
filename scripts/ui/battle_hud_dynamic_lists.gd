class_name BattleHudDynamicLists
extends RefCounted


static func inspect_slot_signature(state: GameState, unit: UnitState) -> String:
	var parts: Array[String] = [unit.uid, str(state.turn_index), unit.behavior_id]
	for raw_slot in unit.slots:
		var slot: SlotState = raw_slot
		if slot == null:
			parts.append("null")
			continue
		parts.append("%s:%s:%s:%s:%s:%d:%s:%s" % [
			slot.slot_type,
			slot.dual_type,
			slot.gem_uid,
			str(slot.locked),
			slot.lock_type,
			slot.unlock_until_turn,
			str(slot.overload_slot),
			str(slot.overload_mutation_deferred),
		])
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null:
			parts.append("%s:%s" % [gem.gem_id, JSON.stringify(gem.def_overrides)])
	return "|".join(parts)


static func timeline_signature(state: GameState, uids: Array[String], active_uid: String, focus_uid: String) -> String:
	var parts: Array[String] = [active_uid, focus_uid]
	for uid in uids:
		var unit: UnitState = state.units.get(uid, null)
		if unit != null:
			parts.append("%s:%s:%s:%d" % [uid, unit.unit_def_id, unit.team, unit.speed])
	return "|".join(parts)


static func clear(container: Container) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
