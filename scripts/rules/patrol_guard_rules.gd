class_name PatrolGuardRules
extends RefCounted


static func is_patrol_guard(unit: UnitState) -> bool:
	return unit.has_tag(Constants.TAG_UNIT_PATROL_GUARD)


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StatusRules.apply_lawless(state, unit, gem_uid)
	StatusRules.apply_vulnerable(state, unit, 0)


static func on_lawless_recovered(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_VULNERABLE)


static func rampage_move_points(unit: UnitState) -> int:
	return unit.move_points + Constants.PATROL_GUARD_RAMPAGE_MOVE_BONUS


static func charge_bonus_from_path(from_pos: Vector2i, path: Array) -> int:
	if straight_orthogonal_steps(from_pos, path) >= Constants.PATROL_GUARD_CHARGE_MIN_STEPS:
		return Constants.PATROL_GUARD_CHARGE_BONUS
	return 0


static func melee_damage_preview(state: GameState, unit: UnitState, from_pos: Vector2i, path: Array) -> int:
	return CombatRules.attack_damage(state, unit) + charge_bonus_from_path(from_pos, path)


static func straight_orthogonal_steps(from_pos: Vector2i, path: Array) -> int:
	if path.is_empty():
		return 0
	var prev: Vector2i = from_pos
	var axis: Vector2i = Vector2i.ZERO
	var count: int = 0
	for step in path:
		if not step is Vector2i:
			continue
		var delta: Vector2i = step - prev
		if absi(delta.x) + absi(delta.y) != 1:
			return count
		if axis == Vector2i.ZERO:
			axis = delta
		elif delta != axis:
			return count
		count += 1
		prev = step
	return count
