class_name TileRules
extends RefCounted


static func on_unit_entered(state: GameState, unit: UnitState, from_pos: Vector2i) -> void:
	var tile := state.get_tile(unit.pos)
	if tile.tile_id == Constants.TILE_SPIKE:
		CombatRules.apply_damage(state, unit, Constants.SPIKE_DAMAGE, unit.uid, "spike")
		_unlock_armor_locks(state, unit)


static func on_unit_moved_through(state: GameState, unit: UnitState, pos: Vector2i) -> void:
	var tile := state.get_tile(pos)
	if tile.has_modifier("poison_fog"):
		StatusRules.apply_poison(state, unit, 1, 2)
	GemEffects.run_unit_hooks(
		state,
		unit,
		Constants.SLOT_BLUE,
		GemEffects.TIMING_MOVED_THROUGH,
		{"pos": pos}
	)


static func create_poison_fog(state: GameState, pos: Vector2i) -> void:
	if not BoardUtils.in_bounds(state, pos):
		return
	var tile := state.get_tile(pos)
	var add_turns := Constants.POISON_FOG_DURATION
	for i in range(tile.modifiers.size()):
		var existing: Variant = tile.modifiers[i]
		if str(existing.get("type", "")) != "poison_fog":
			continue
		var merged: Dictionary = existing.duplicate(true)
		merged["duration"] = int(merged.get("duration", 0)) + add_turns
		tile.modifiers[i] = merged
		return
	tile.add_modifier("poison_fog", add_turns)


static func _unlock_armor_locks(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
			StatusRules.apply_exposed(state, unit, slot, state.turn_index)
