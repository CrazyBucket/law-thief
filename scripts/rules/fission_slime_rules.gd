class_name FissionSlimeRules
extends RefCounted

const EnemyBehavior = preload("res://scripts/rules/behaviors/enemy_behavior.gd")
const _AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")


static func split_stat_ratio(_unit: UnitState) -> float:
	return Constants.FISSION_SLIME_SPLIT_STAT_RATIO


static func should_trigger_split_blue(_unit: UnitState, reason: String) -> bool:
	return is_single_target_damage_reason(reason)


static func is_single_target_damage_reason(reason: String) -> bool:
	return EnemyBehavior.is_single_target_damage_reason(reason)


static func compute_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var player := state.get_player()
	if player == null or not player.alive:
		return IntentState.wait(unit.uid)

	var reachable: Array[Vector2i] = []
	if StatusRules.can_move(unit):
		reachable = BoardUtils.reachable_cells(
			state, unit.pos, unit.move_points, unit.uid, {}, cell_blockers, unit
		)
	reachable.append(unit.pos)

	var best_anchor: Vector2i = unit.pos
	var best_path: Array[Vector2i] = []
	var best_cost := 999
	for anchor in reachable:
		if not _anchor_passable_for_plan(state, unit, anchor, cell_blockers):
			continue
		if not _can_slam_at_anchor(state, unit, anchor, player):
			continue
		var path: Array[Vector2i] = []
		if anchor != unit.pos:
			path = BoardUtils.path_toward(
				state, unit.pos, anchor, unit.move_points, unit.uid, {}, cell_blockers, unit
			)
			if path.is_empty() or path[path.size() - 1] != anchor:
				continue
		var cost := path.size()
		if cost < best_cost:
			best_cost = cost
			best_anchor = anchor
			best_path = path

	if best_cost < 999:
		var intent := IntentState.new()
		intent.type = "slam_attack"
		intent.source_uid = unit.uid
		intent.target_uid = player.uid
		intent.path = best_path
		intent.target_pos = best_anchor
		intent.damage = CombatRules.attack_damage(state, unit)
		intent.preview_text = "砸击 (%d)" % intent.damage
		return intent

	var approach := _find_best_approach(state, unit, player, reachable, cell_blockers)
	if approach.is_empty():
		return IntentState.wait(unit.uid)
	var move_intent := IntentState.new()
	move_intent.type = "move"
	move_intent.source_uid = unit.uid
	move_intent.target_uid = player.uid
	move_intent.path = approach.get("path", [] as Array[Vector2i])
	move_intent.target_pos = approach.get("target_pos", unit.pos)
	move_intent.preview_text = "逼近"
	return move_intent


static func execute_slam(
	state: GameState,
	unit: UnitState,
	intent: IntentState
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return events
	if not _can_slam_at_anchor(state, unit, unit.pos, target):
		return events
	var payload := {"damage_reason": Constants.DAMAGE_REASON_SLAM}
	var result := _AttackPipeline.execute(
		state, unit, target, [_AttackPipeline.TAG_MELEE], payload
	)
	if not result.get("ok", false):
		return events
	events.append_array(result.get("events", [] as Array[Dictionary]))
	if target.alive:
		var origin := _knockback_origin_toward(unit, target.pos)
		Displacement.knockback(
			state,
			target,
			origin,
			Constants.FISSION_SLIME_SLAM_PUSH_STEPS,
			unit.uid,
			events
		)
	return events


static func _can_slam_at_anchor(state: GameState, unit: UnitState, anchor: Vector2i, target: UnitState) -> bool:
	var saved := unit.pos
	unit.pos = anchor
	var ok := BoardUtils.are_units_adjacent(unit, target)
	unit.pos = saved
	return ok


static func _anchor_passable_for_plan(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	cell_blockers: Dictionary
) -> bool:
	if not BoardUtils.unit_footprint_passable(state, unit, anchor, unit.uid, cell_blockers):
		return false
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var key := state.tile_key(cell)
		if cell_blockers.has(key) and str(cell_blockers[key]) != unit.uid:
			return false
	return true


static func _find_best_approach(
	state: GameState,
	unit: UnitState,
	player: UnitState,
	reachable: Array[Vector2i],
	cell_blockers: Dictionary
) -> Dictionary:
	var current_dist := BoardUtils.path_distance_to_cell(
		state, unit.pos, player.pos, unit.uid, cell_blockers, unit
	)
	if current_dist < 0:
		return {}
	var best_path: Array[Vector2i] = []
	var best_dist := current_dist
	var best_anchor := unit.pos

	for anchor in reachable:
		if not _anchor_passable_for_plan(state, unit, anchor, cell_blockers):
			continue
		var dist := BoardUtils.path_distance_to_cell(
			state, anchor, player.pos, unit.uid, cell_blockers, unit
		)
		if dist < 0 or dist >= best_dist:
			continue
		var path: Array[Vector2i] = []
		if anchor != unit.pos:
			path = BoardUtils.path_toward(
				state, unit.pos, anchor, unit.move_points, unit.uid, {}, cell_blockers, unit
			)
			if path.is_empty() or path[path.size() - 1] != anchor:
				continue
		if dist < best_dist or (dist == best_dist and path.size() < best_path.size()):
			best_dist = dist
			best_anchor = anchor
			best_path = path

	if best_dist >= current_dist:
		return {}
	var target_pos := unit.pos
	if not best_path.is_empty():
		target_pos = best_path[best_path.size() - 1]
	return {"path": best_path, "target_pos": target_pos}


static func _knockback_origin_toward(unit: UnitState, target_pos: Vector2i) -> Vector2i:
	var best := unit.pos
	var best_dist := 9999
	for cell in unit.occupied_cells():
		var dist := BoardUtils.manhattan(cell, target_pos)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best
