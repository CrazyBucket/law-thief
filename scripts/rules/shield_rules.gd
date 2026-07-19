class_name ShieldRules
extends RefCounted


static func damage(state: GameState, unit: UnitState, amount: int) -> int:
	if unit == null or amount <= 0:
		return 0
	var removed := mini(amount, StatusRules.get_shield(unit))
	if removed <= 0:
		return 0
	StatusRules.absorb_with_shield(state, unit, removed)
	return removed
