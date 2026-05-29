class_name CombatRules
extends RefCounted

const _AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")


static func apply_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> int:
	if not unit.alive or amount <= 0:
		return 0
	# 止痛药：本场战斗首次受伤降为 1
	if unit.uid == state.player_uid:
		var absorb: bool = RelicEffectRegistry.query_modifier("first_damage_absorb", state)
		if absorb:
			amount = 1
			state.battle_temp_flags["painkiller_used"] = true
	var total_armor := current_armor(state, unit)
	var final_amount := maxi(0, amount - total_armor)
	if final_amount <= 0:
		state.log("%s 的护甲吸收了 %d 点伤害 (%s)" % [unit.uid, amount, reason])
		return 0
	if StatusRules.is_vulnerable(unit):
		final_amount = int(final_amount * 1.5)
	# 分裂宝石蓝槽：拦截伤害，将一部分转移给周围随机单位
	final_amount = GemEffects.intercept_damage_for_split(state, unit, source_uid, reason, final_amount)
	_apply_blue_reactive_effects(state, unit, source_uid, reason, final_amount)
	unit.hp -= final_amount
	state.log("%s 受到 %d 点伤害 (%s)" % [unit.uid, final_amount, reason])
	state.on_damage_taken.emit(unit.uid, final_amount, reason)
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return final_amount


## 无视护甲的真实伤害（毒/火等 DoT 使用）
static func apply_true_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> int:
	if not unit.alive or amount <= 0:
		return 0
	unit.hp -= amount
	state.log("%s 受到 %d 点真实伤害 (%s)" % [unit.uid, amount, reason])
	state.on_damage_taken.emit(unit.uid, amount, reason)
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return amount


static func _kill_unit(state: GameState, unit: UnitState, source_uid: String, reason: String) -> void:
	unit.hp = 0
	state.kill_unit(unit)  # 撤销占格索引并标记 alive = false
	state.log("%s 被击败" % unit.uid)
	state.on_unit_die.emit(unit.uid, source_uid, reason)
	GemEffects.on_unit_death(state, unit)


## 近战攻击（pipeline 版本）：返回 {ok, reason, events}
static func melee_attack(
	state: GameState,
	attacker: UnitState,
	target: UnitState,
	charge_bonus: int = 0
) -> Dictionary:
	if not attacker.alive or not target.alive:
		return {"ok": false, "reason": "目标无效", "events": []}
	var payload: Dictionary = {}
	if charge_bonus > 0:
		payload["charge_bonus"] = charge_bonus
	return _AttackPipeline.execute(state, attacker, target, [_AttackPipeline.TAG_MELEE], payload)


## 远程攻击（pipeline 版本）：返回 {ok, reason, events}
static func ranged_attack(
	state: GameState,
	attacker: UnitState,
	target: UnitState,
	max_range: int = Constants.ATTACK_RANGE,
	payload: Dictionary = {}
) -> Dictionary:
	if not attacker.alive or not target.alive:
		return {"ok": false, "reason": "目标无效", "events": []}
	if BoardUtils.distance_between_units(attacker, target) > max_range:
		return {"ok": false, "reason": "目标超出射程", "events": []}
	return _AttackPipeline.execute(state, attacker, target, [_AttackPipeline.TAG_RANGED], payload)


static func attack_damage(state: GameState, attacker: UnitState) -> int:
	var base := attacker.base_attack + GemEffects.get_attack_bonus(state, attacker)
	var mult: float = RelicEffectRegistry.query_modifier("attack_damage_mult", state)
	return maxi(0, int(float(base) * mult))


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
