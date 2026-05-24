class_name CombatRules
extends RefCounted


static func apply_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> void:
	if not unit.alive:
		return
	var final_amount := amount
	var total_armor := current_armor(state, unit)
	final_amount = maxi(0, final_amount - total_armor)
	if final_amount <= 0:
		return
	_apply_blue_reactive_effects(state, unit, source_uid, reason)
	unit.hp -= final_amount
	state.log("%s 受到 %d 点伤害 (%s)" % [unit.uid, final_amount, reason])
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)


static func _kill_unit(state: GameState, unit: UnitState, source_uid: String, reason: String) -> void:
	unit.alive = false
	unit.hp = 0
	state.log("%s 被击败" % unit.uid)
	GemEffects.on_unit_death(state, unit)


static func attack(state: GameState, attacker: UnitState, target: UnitState) -> bool:
	if not attacker.alive or not target.alive:
		return false
	if BoardUtils.manhattan(attacker.pos, target.pos) != 1:
		return false
	apply_damage(state, target, attack_damage(state, attacker), attacker.uid, "attack")
	return true


static func attack_damage(state: GameState, attacker: UnitState) -> int:
	var bonus := 0
	for slot in attacker.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		if gem.gem_id == Constants.GEM_FRAGILE:
			bonus += 1
	return maxi(0, attacker.base_attack + bonus)


static func current_armor(state: GameState, unit: UnitState) -> int:
	var armor := maxi(unit.armor, 0)
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match gem.gem_id:
			Constants.GEM_HEAVY_ARMOR:
				armor += 2
			Constants.GEM_CONDUCTIVE:
				var tile := state.get_tile(unit.pos)
				if tile.tile_id == Constants.TILE_WATER:
					armor += 1
	var armor_status: StatusInstance = unit.get_status("armor")
	if armor_status != null:
		armor += maxi(0, armor_status.value)
	return maxi(0, armor)


static func _apply_blue_reactive_effects(state: GameState, owner: UnitState, source_uid: String, reason: String) -> void:
	if reason == "blue_conductive_rebound" or source_uid.is_empty():
		return
	var source: UnitState = state.units.get(source_uid, null)
	if source == null or not source.alive:
		return
	for slot in owner.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match gem.gem_id:
			Constants.GEM_POISON:
				if BoardUtils.manhattan(owner.pos, source.pos) <= 1:
					StatusRules.apply_poison(state, source, 1, 2)
			Constants.GEM_CONDUCTIVE:
				var owner_tile := state.get_tile(owner.pos)
				if owner_tile.tile_id == Constants.TILE_WATER and BoardUtils.manhattan(owner.pos, source.pos) <= 2:
					apply_damage(state, source, 1, owner.uid, "blue_conductive_rebound")
