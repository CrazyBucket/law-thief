class_name ContactResolve
extends RefCounted

const FootprintRules = preload("res://scripts/rules/footprint_rules.gd")

## 接触时机定义
const TIMING_COLLISION   := "collision"    # 碰撞（强制位移撞单位）
const TIMING_ADJACENT    := "adjacent"     # 回合结束相邻
const TIMING_ATTACK      := "attack"       # 攻击/被攻击


## 碰撞接触：强制位移撞到另一个单位时调用
## mover 是被位移的单位，blocker 是被撞到的单位
static func on_collision(state: GameState, mover: UnitState, blocker: UnitState) -> void:
	_dispatch(state, mover, blocker, TIMING_COLLISION)
	_dispatch(state, blocker, mover, TIMING_COLLISION)


## 攻击接触：攻击/被攻击时调用
static func on_attack_contact(state: GameState, attacker: UnitState, defender: UnitState) -> void:
	_dispatch(state, attacker, defender, TIMING_ATTACK)
	_dispatch(state, defender, attacker, TIMING_ATTACK)


## 回合结束相邻结算：遍历所有存活单位，检查敌方相邻
static func resolve_adjacent(state: GameState) -> void:
	var units := state.units.values()
	var processed: Dictionary = {}
	for unit in units:
		if not unit.alive:
			continue
		for other in FootprintRules.adjacent_units(state, unit):
			var pair_key := _pair_key(unit.uid, other.uid)
			if processed.has(pair_key):
				continue
			processed[pair_key] = true
			_dispatch(state, unit, other, TIMING_ADJACENT)
			_dispatch(state, other, unit, TIMING_ADJACENT)


## 核心分发：carrier 持有的蓝槽宝石对 other 触发接触效果
static func _dispatch(state: GameState, carrier: UnitState, other: UnitState, timing: String) -> void:
	GemEffects.run_unit_hooks(state, carrier, Constants.SLOT_BLUE, GemEffects.TIMING_ON_CONTACT, {
		"target": other,
		"contact_timing": timing,
	})


static func _pair_key(uid_a: String, uid_b: String) -> String:
	if uid_a < uid_b:
		return uid_a + "|" + uid_b
	return uid_b + "|" + uid_a
