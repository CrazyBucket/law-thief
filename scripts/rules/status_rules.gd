class_name StatusRules
extends RefCounted


static func apply_poison(state: GameState, unit: UnitState, stacks: int = 1, duration: int = 2) -> void:
	unit.add_status(StatusInstance.create("poison", stacks, duration))


static func apply_armor(state: GameState, unit: UnitState, value: int, duration: int = 1) -> void:
	var status := StatusInstance.create("armor", 1, duration)
	status.value = value
	unit.add_status(status)


static func apply_shield(state: GameState, unit: UnitState, value: int, duration: int = 1) -> void:
	# 兼容旧接口：统一转换成护甲值
	apply_armor(state, unit, value, duration)


static func apply_rooted(state: GameState, unit: UnitState, duration: int = 2) -> void:
	unit.add_status(StatusInstance.create("rooted", 1, duration))


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
		_apply_blue_turn_start_effects(state, unit)
		var poison: StatusInstance = unit.get_status("poison")
		if poison != null:
			CombatRules.apply_damage(state, unit, poison.stacks, unit.uid, "poison")
			poison.duration -= 1
			if poison.duration <= 0:
				unit.remove_status("poison")
		var rooted: StatusInstance = unit.get_status("rooted")
		if rooted != null:
			rooted.duration -= 1
			if rooted.duration <= 0:
				unit.remove_status("rooted")
		var tile := state.get_tile(unit.pos)
		if tile.has_modifier("poison_fog"):
			CombatRules.apply_damage(state, unit, Constants.POISON_FOG_DAMAGE, unit.uid, "poison_fog")


static func tick_turn_end(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		var armor: StatusInstance = unit.get_status("armor")
		if armor != null:
			armor.duration -= 1
			if armor.duration <= 0:
				unit.remove_status("armor")
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		tile.tick_modifiers()


static func _apply_blue_turn_start_effects(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match gem.gem_id:
			Constants.GEM_GRAVITY:
				var nearest := _nearest_opponent(state, unit)
				if nearest != null and BoardUtils.manhattan(unit.pos, nearest.pos) <= 3:
					var next := BoardUtils.step_toward(nearest.pos, unit.pos)
					if next != nearest.pos and BoardUtils.is_passable(state, next, nearest.uid):
						var from_pos := nearest.pos
						nearest.pos = next
						TileRules.on_unit_moved_through(state, nearest, next)
						TileRules.on_unit_entered(state, nearest, from_pos)
						apply_rooted(state, nearest, 2)
			Constants.GEM_EXPLOSION:
				for cell in BoardUtils.neighbors4(unit.pos):
					var target := state.get_unit_at(cell)
					if target != null and target.alive and target.team != unit.team:
						CombatRules.apply_damage(state, target, 1, unit.uid, "blue_explosion_aura")
						break


static func _nearest_opponent(state: GameState, unit: UnitState) -> UnitState:
	var best: UnitState = null
	var best_dist := 999
	for other in state.units.values():
		if not other.alive or other.team == unit.team:
			continue
		var dist := BoardUtils.manhattan(unit.pos, other.pos)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best
