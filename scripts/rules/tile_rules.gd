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
	if _unit_has_blue_poison(state, unit):
		tile.add_modifier("poison_fog", Constants.POISON_FOG_DURATION)


static func create_poison_fog(state: GameState, pos: Vector2i) -> void:
	if not BoardUtils.in_bounds(state, pos):
		return
	var tile := state.get_tile(pos)
	tile.add_modifier("poison_fog", Constants.POISON_FOG_DURATION)


static func _unit_has_blue_poison(state: GameState, unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and gem.gem_id == Constants.GEM_POISON:
			return true
	return false


static func _unlock_armor_locks(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
			StatusRules.apply_exposed(state, unit, slot, state.turn_index)
