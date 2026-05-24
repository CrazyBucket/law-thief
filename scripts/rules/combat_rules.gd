class_name CombatRules
extends RefCounted


static func apply_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> void:
	if not unit.alive:
		return
	var final_amount := amount
	if unit.has_status("shield"):
		var shield := unit.get_status("shield")
		var absorbed := mini(final_amount, shield.value)
		shield.value -= absorbed
		final_amount -= absorbed
		if shield.value <= 0:
			unit.remove_status("shield")
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and gem.gem_id == Constants.GEM_HEAVY_ARMOR and slot.slot_type == Constants.SLOT_BLUE:
			final_amount = maxi(0, final_amount - 1)
	if final_amount <= 0:
		return
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
	apply_damage(state, target, attacker.base_attack, attacker.uid, "attack")
	return true
