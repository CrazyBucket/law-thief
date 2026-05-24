class_name StatusRules
extends RefCounted


static func apply_poison(state: GameState, unit: UnitState, stacks: int = 1, duration: int = 2) -> void:
	unit.add_status(StatusInstance.create("poison", stacks, duration))


static func apply_shield(state: GameState, unit: UnitState, value: int, duration: int = 1) -> void:
	var status := StatusInstance.create("shield", 1, duration)
	status.value = value
	unit.add_status(status)


static func apply_exposed(state: GameState, unit: UnitState, slot: SlotState, turn_index: int) -> void:
	slot.locked = false
	slot.lock_type = ""
	slot.unlock_until_turn = turn_index
	unit.add_status(StatusInstance.create("exposed", 1, 1))


static func apply_lawless(state: GameState, unit: UnitState, target_gem_uid: String) -> void:
	unit.lawless = true
	unit.lawless_target_gem_uid = target_gem_uid
	unit.add_status(StatusInstance.create("lawless", 1, 99))


static func tick_turn_start(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		var poison: StatusInstance = unit.get_status("poison")
		if poison != null:
			CombatRules.apply_damage(state, unit, poison.stacks, unit.uid, "poison")
			poison.duration -= 1
			if poison.duration <= 0:
				unit.remove_status("poison")
		var tile := state.get_tile(unit.pos)
		if tile.has_modifier("poison_fog"):
			CombatRules.apply_damage(state, unit, Constants.POISON_FOG_DAMAGE, unit.uid, "poison_fog")


static func tick_turn_end(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		var shield: StatusInstance = unit.get_status("shield")
		if shield != null:
			shield.duration -= 1
			if shield.duration <= 0:
				unit.remove_status("shield")
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		tile.tick_modifiers()
