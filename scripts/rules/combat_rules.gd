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
	_apply_blue_reactive_effects(state, unit, source_uid, reason, final_amount)
	unit.hp -= final_amount
	state.log("%s 受到 %d 点伤害 (%s)" % [unit.uid, final_amount, reason])
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return final_amount


## 无视护甲的真实伤害（毒/火等 DoT 使用）
static func apply_true_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> int:
	if not unit.alive or amount <= 0:
		return 0
	unit.hp -= amount
	state.log("%s 受到 %d 点真实伤害 (%s)" % [unit.uid, amount, reason])
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return amount


static func _kill_unit(state: GameState, unit: UnitState, source_uid: String, reason: String) -> void:
	unit.alive = false
	unit.hp = 0
	state.log("%s 被击败" % unit.uid)
	GemEffects.on_unit_death(state, unit)


## 近战攻击（保留，供 AI 和需要严格 manhattan==1 检查的场景使用）
static func attack(state: GameState, attacker: UnitState, target: UnitState) -> int:
	if not attacker.alive or not target.alive:
		return 0
	if BoardUtils.manhattan(attacker.pos, target.pos) != 1:
		return 0
	return apply_damage(state, target, attack_damage(state, attacker), attacker.uid, "attack")


## 远程攻击（pipeline 版本）：返回 {ok, reason, events}
static func ranged_attack(state: GameState, attacker: UnitState, target: UnitState) -> Dictionary:
	if not attacker.alive or not target.alive:
		return {"ok": false, "reason": "目标无效", "events": []}
	if BoardUtils.manhattan(attacker.pos, target.pos) > Constants.ATTACK_RANGE:
		return {"ok": false, "reason": "目标超出射程", "events": []}
	return AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_RANGED])


static func attack_damage(state: GameState, attacker: UnitState) -> int:
	return maxi(0, attacker.base_attack + GemEffects.get_attack_bonus(state, attacker))


static func current_armor(state: GameState, unit: UnitState) -> int:
	var armor := maxi(unit.armor, 0) + GemEffects.get_armor_bonus(state, unit)
	armor += StatusRules.get_armor_bonus(unit)
	return maxi(0, armor)


static func _apply_blue_reactive_effects(state: GameState, owner: UnitState, source_uid: String, reason: String, damage: int = 0) -> void:
	GemEffects.run_unit_hooks(
		state,
		owner,
		Constants.SLOT_BLUE,
		GemEffects.TIMING_OWNER_DAMAGED,
		{"source_uid": source_uid, "reason": reason, "damage": damage}
	)
