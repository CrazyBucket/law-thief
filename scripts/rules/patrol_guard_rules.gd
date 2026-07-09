class_name PatrolGuardRules
extends RefCounted


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")


static func _balance_int(unit_def_id: String, key: String, fallback: int) -> int:
	var registry := _data_registry()
	if registry == null:
		return fallback
	return int(registry.get_unit_balance_value(unit_def_id, key, fallback))


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StatusRules.apply_lawless(state, unit, gem_uid)
	StatusRules.apply_vulnerable(state, unit, 0)


static func on_lawless_recovered(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_VULNERABLE)


static func rampage_move_points(unit: UnitState) -> int:
	return unit.move_points + _balance_int(unit.unit_def_id, "rampage_move_bonus", Constants.PATROL_GUARD_RAMPAGE_MOVE_BONUS)


static func charge_bonus(state: GameState, unit: UnitState, move_start_pos: Vector2i, path: Array) -> int:
	if unit.has_status(Constants.STATUS_SLOWED):
		return 0
	var steps := _path_steps(path)
	var charge_min_steps := _balance_int(unit.unit_def_id, "charge_min_steps", Constants.PATROL_GUARD_CHARGE_MIN_STEPS)
	if steps.size() < charge_min_steps:
		return 0
	var charge_cells := _final_charge_cells(move_start_pos, steps, charge_min_steps)
	if charge_cells.is_empty():
		return 0
	if _charge_move_cost_sum(state, charge_cells) > charge_min_steps:
		return 0
	return _balance_int(unit.unit_def_id, "charge_bonus", Constants.PATROL_GUARD_CHARGE_BONUS)


static func melee_damage_preview(
	state: GameState,
	unit: UnitState,
	move_start_pos: Vector2i,
	path: Array,
	target_pos: Vector2i
) -> int:
	return CombatRules.attack_damage(state, unit) + charge_bonus(state, unit, move_start_pos, path)


static func _path_steps(path: Array) -> Array[Vector2i]:
	var steps: Array[Vector2i] = []
	for step in path:
		if step is Vector2i:
			steps.append(step)
	return steps


static func _final_charge_cells(from_pos: Vector2i, steps: Array[Vector2i], charge_min_steps: int) -> Array[Vector2i]:
	var full_path: Array[Vector2i] = [from_pos]
	full_path.append_array(steps)
	if full_path.size() < 3:
		return []

	var last_idx := full_path.size() - 1
	var last_dir := full_path[last_idx] - full_path[last_idx - 1]
	if last_dir.x != 0 and last_dir.y != 0:
		return []

	var straight_steps := 1
	for i in range(last_idx - 1, 0, -1):
		var current_dir := full_path[i] - full_path[i - 1]
		if current_dir == last_dir:
			straight_steps += 1
		else:
			break

	if straight_steps < charge_min_steps:
		return []

	var result: Array[Vector2i] = []
	var start_idx := steps.size() - charge_min_steps
	for i in range(start_idx, steps.size()):
		result.append(steps[i])
	return result


static func _charge_move_cost_sum(state: GameState, cells: Array[Vector2i]) -> int:
	var total := 0
	for cell in cells:
		total += ceili(BoardUtils.tile_move_cost(state, cell))
	return total
