class_name CombatRules
extends RefCounted


static func apply_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> int:
	if not unit.alive or amount <= 0:
		return 0
	var total_armor := current_armor(state, unit)
	var final_amount := maxi(0, amount - total_armor)
	if final_amount <= 0:
		state.log("%s 的护甲吸收了 %d 点伤害 (%s)" % [unit.uid, amount, reason])
		return 0
	_apply_blue_reactive_effects(state, unit, source_uid, reason)
	unit.hp -= final_amount
	state.log("%s 受到 %d 点伤害 (%s)" % [unit.uid, final_amount, reason])
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return final_amount


static func _kill_unit(state: GameState, unit: UnitState, source_uid: String, reason: String) -> void:
	unit.alive = false
	unit.hp = 0
	state.log("%s 被击败" % unit.uid)
	GemEffects.on_unit_death(state, unit)


static func attack(state: GameState, attacker: UnitState, target: UnitState) -> int:
	if not attacker.alive or not target.alive:
		return 0
	if BoardUtils.manhattan(attacker.pos, target.pos) != 1:
		return 0
	return apply_damage(state, target, attack_damage(state, attacker), attacker.uid, "attack")


static func attack_damage(state: GameState, attacker: UnitState) -> int:
	return maxi(0, attacker.base_attack + GemEffects.get_attack_bonus(state, attacker))


static func current_armor(state: GameState, unit: UnitState) -> int:
	var armor := maxi(unit.armor, 0) + GemEffects.get_armor_bonus(state, unit)
	armor += StatusRules.get_armor_bonus(unit)
	return maxi(0, armor)


static func _apply_blue_reactive_effects(state: GameState, owner: UnitState, source_uid: String, reason: String) -> void:
	GemEffects.run_unit_hooks(
		state,
		owner,
		Constants.SLOT_BLUE,
		GemEffects.TIMING_OWNER_DAMAGED,
		{"source_uid": source_uid, "reason": reason}
	)
