class_name StoneBowGuardRules
extends RefCounted

const _EnemyAI := preload("res://scripts/rules/enemy_ai.gd")
const AIProfiles = preload("res://scripts/rules/ai_profiles.gd")


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")


static func _balance_int(unit_def_id: String, key: String) -> int:
	var registry := _data_registry()
	if registry == null:
		push_error("StoneBowGuardRules: DataRegistry unavailable")
		return 0
	var value: Variant = registry.get_unit_balance_value(unit_def_id, key, null)
	if value == null:
		push_error("StoneBowGuardRules: required balance missing: %s.%s" % [unit_def_id, key])
		return 0
	return int(value)


static func _balance_float(unit_def_id: String, key: String) -> float:
	var registry := _data_registry()
	if registry == null:
		push_error("StoneBowGuardRules: DataRegistry unavailable")
		return 0.0
	var value: Variant = registry.get_unit_balance_value(unit_def_id, key, null)
	if value == null:
		push_error("StoneBowGuardRules: required balance missing: %s.%s" % [unit_def_id, key])
		return 0.0
	return float(value)


static func _score_float(unit_def_id: String, key: String) -> float:
	return _balance_float(unit_def_id, key)


static func is_deployed(_start_pos: Vector2i, move_path: Array) -> bool:
	return move_path.is_empty()


static func attack_range_for(_start_pos: Vector2i, move_path: Array) -> int:
	var range := _balance_int("unit_stone_bow_guard", "attack_range")
	if is_deployed(_start_pos, move_path):
		range += _balance_int("unit_stone_bow_guard", "deploy_range_bonus")
	return range


static func can_shoot_from_anchor(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	target: UnitState,
	move_path: Array
) -> bool:
	if state == null or unit == null or target == null or not target.alive:
		return false
	var dist := BoardUtils.distance_between_unit_at_and_unit(unit, anchor, target)
	var kite_min_range := _balance_int(unit.unit_def_id, "kite_min_range")
	if dist < kite_min_range:
		return false
	var max_range := attack_range_for(anchor, move_path)
	if dist > max_range:
		return false
	var from_cell := BoardUtils.projectile_origin_cell_at(unit, anchor, target.pos)
	return not BoardUtils.projectile_blocked_before_aim(state, from_cell, target.pos)


static func is_faulty_blind_shot(unit: UnitState) -> bool:
	return StatusRules.is_lawless(unit)


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StatusRules.apply_lawless(state, unit, gem_uid)


static func on_lawless_recovered(_unit: UnitState) -> void:
	pass


static func bonus_damage(unit: UnitState) -> int:
	if is_faulty_blind_shot(unit):
		return _balance_int(unit.unit_def_id, "faulty_damage_bonus")
	return 0


static func ranged_damage_preview(state: GameState, unit: UnitState) -> int:
	var base_damage := CombatRules.attack_damage(state, unit) + bonus_damage(unit)
	return GemEffects.primary_attack_damage_preview(state, unit, base_damage)


static func roll_hit(_state: GameState, attacker_uid: String) -> bool:
	var roll := float(_rng_service().roll_int("stone_bow_hit_%s" % attacker_uid, 0, 999)) / 999.0
	return roll >= _balance_float("unit_stone_bow_guard", "faulty_miss_chance")


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node("RngService")


static func in_range(state: GameState, unit: UnitState, from_pos: Vector2i, target: UnitState, move_path: Array) -> bool:
	return can_shoot_from_anchor(state, unit, from_pos, target, move_path)


## 石弓专用风筝 AI：每步决策用当前玩家坐标；已在射程内优先原地架设射击
static func decide(state: GameState, enemy: UnitState, cell_blockers: Dictionary = {}) -> Dictionary:
	var player := state.get_player()
	if player == null or not player.alive:
		return {"move_path": [] as Array[Vector2i], "action": null}

	var profile: Dictionary = AIProfiles.get_profile(enemy.ai_profile_id)
	var player_pos: Vector2i = player.pos
	var turn_start: Vector2i = enemy.pos
	var current_dist: int = BoardUtils.distance_between_units(enemy, player)
	var can_shoot_here: bool = can_shoot_from_anchor(state, enemy, turn_start, player, [])

	var reachable: Array[Vector2i] = []
	if StatusRules.can_move(enemy):
		reachable = BoardUtils.reachable_cells(
			state, enemy.pos, enemy.move_points, enemy.uid, {}, cell_blockers
		)
	reachable.append(enemy.pos)

	var red_skill_candidates: Array = []
	for move_pos in reachable:
		if _anchor_blocked(state, enemy, move_pos, cell_blockers):
			continue
		if move_pos != enemy.pos:
			var move_path := BoardUtils.path_toward(
				state, enemy.pos, move_pos, enemy.move_points, enemy.uid, {}, cell_blockers
			)
			if move_path.is_empty() or move_path[move_path.size() - 1] != move_pos:
				continue
		red_skill_candidates.append_array(
			_EnemyAI.evaluate_red_skill_candidates(state, enemy, move_pos, profile)
		)
	if not red_skill_candidates.is_empty():
		return _build_decision_from_best_candidate(state, enemy, red_skill_candidates, cell_blockers)

	var max_shoot_range: int = attack_range_for(turn_start, [])
	var candidates: Array = []
	for move_pos in reachable:
		if _anchor_blocked(state, enemy, move_pos, cell_blockers):
			continue
		var move_path: Array[Vector2i] = []
		if move_pos != enemy.pos:
			move_path = BoardUtils.path_toward(
				state, enemy.pos, move_pos, enemy.move_points, enemy.uid, {}, cell_blockers
			)
			if move_path.is_empty():
				continue
		var dist: int = BoardUtils.distance_between_unit_at_and_unit(enemy, move_pos, player)
		var max_range: int = attack_range_for(turn_start, move_path)
		var kite_min_range := _balance_int(enemy.unit_def_id, "kite_min_range")
		if dist < kite_min_range or dist > max_range:
			continue
		if not in_range(state, enemy, move_pos, player, move_path):
			continue
		var candidate := _EnemyAI.make_candidate()
		candidate.type = _EnemyAI.ActionType.RANGED_ATTACK
		candidate.move_target = move_pos
		candidate.action_target_uid = player.uid
		candidate.score = _score_ranged_position(
			state,
			enemy,
			turn_start,
			move_pos,
			move_path,
			dist,
			max_range,
			current_dist,
			can_shoot_here,
			player
		)
		var label := "架设" if is_deployed(turn_start, move_path) else "移动"
		candidate.description = "%s后射击(%d格)" % [label, dist]
		candidates.append(candidate)

	for move_pos in reachable:
		if move_pos == turn_start:
			continue
		if _anchor_blocked(state, enemy, move_pos, cell_blockers):
			continue
		var new_dist: int = BoardUtils.distance_between_unit_at_and_unit(enemy, move_pos, player)
		var kite_min_range := _balance_int(enemy.unit_def_id, "kite_min_range")
		if can_shoot_here and new_dist >= kite_min_range:
			continue
		if can_shoot_here and new_dist < current_dist:
			continue
		var candidate := _EnemyAI.make_candidate()
		candidate.type = _EnemyAI.ActionType.MOVE
		candidate.move_target = move_pos
		if current_dist > max_shoot_range:
			candidate.score = _score_approach_out_of_range(enemy.unit_def_id, current_dist, new_dist, move_pos, enemy.pos)
		else:
			candidate.score = _score_kite_reposition(enemy.unit_def_id, current_dist, new_dist)
		if not can_shoot_here:
			candidate.score += _score_reposition_for_line(
				state, enemy, turn_start, move_pos, player, reachable, cell_blockers
			)
		candidate.description = "风筝走位" if current_dist <= max_shoot_range else "逼近射程"
		candidates.append(candidate)

	var wait := _EnemyAI.make_candidate()
	wait.type = _EnemyAI.ActionType.WAIT
	wait.move_target = enemy.pos
	wait.score = _score_float(enemy.unit_def_id, "wait_score")
	wait.description = "等待"
	candidates.append(wait)

	if candidates.is_empty():
		return {"move_path": [] as Array[Vector2i], "action": null}

	return _build_decision_from_best_candidate(state, enemy, candidates, cell_blockers)


static func _score_ranged_position(
	state: GameState,
	enemy: UnitState,
	turn_start: Vector2i,
	move_pos: Vector2i,
	move_path: Array[Vector2i],
	dist: int,
	max_range: int,
	current_dist: int,
	can_shoot_here: bool,
	player: UnitState
) -> float:
	var damage: int = ranged_damage_preview(state, enemy)
	var unit_def_id := enemy.unit_def_id
	var kite_ideal_range := _balance_int(enemy.unit_def_id, "kite_ideal_range")
	var kite_min_range := _balance_int(enemy.unit_def_id, "kite_min_range")
	var score: float = float(damage) * _score_float(unit_def_id, "ranged_damage_score_mult")
	if player.hp <= damage:
		score += _score_float(unit_def_id, "kill_bonus")
	var move_steps: int = move_path.size()
	score -= float(move_steps) * _score_float(unit_def_id, "move_step_cost")
	score -= float(absi(dist - kite_ideal_range)) * _score_float(unit_def_id, "ideal_range_penalty")
	if dist < kite_ideal_range:
		score -= float(kite_ideal_range - dist) * _score_float(unit_def_id, "too_close_extra_penalty")
	if dist == max_range:
		score += _score_float(unit_def_id, "max_range_bonus")

	if can_shoot_here:
		if move_pos == turn_start:
			score += _score_float(unit_def_id, "hold_position_bonus")
			if is_deployed(turn_start, move_path) and dist >= kite_ideal_range:
				score += _score_float(unit_def_id, "deploy_hold_bonus")
		else:
			score -= _score_float(unit_def_id, "move_when_shooting_penalty")
			if dist < current_dist:
				score -= _score_float(unit_def_id, "closer_when_shooting_penalty")
	elif current_dist <= kite_min_range and dist > current_dist:
		score += float(dist - current_dist) * _score_float(unit_def_id, "emergency_retreat_bonus_per_tile")
	elif dist > current_dist:
		score -= float(dist - current_dist) * _score_float(unit_def_id, "extra_distance_penalty_per_tile")
	elif not can_shoot_here and dist < current_dist:
		score += float(current_dist - dist) * _score_float(unit_def_id, "closer_to_gain_shot_bonus_per_tile")

	if is_deployed(turn_start, move_path) and dist >= kite_ideal_range and not can_shoot_here:
		score += _score_float(unit_def_id, "setup_deploy_bonus")
	return score


static func _score_approach_out_of_range(
	unit_def_id: String,
	current_dist: int,
	new_dist: int,
	move_pos: Vector2i,
	turn_start: Vector2i
) -> float:
	var kite_min_range := _balance_int(unit_def_id, "kite_min_range")
	var kite_ideal_range := _balance_int(unit_def_id, "kite_ideal_range")
	var score: float = float(current_dist - new_dist) * _score_float(unit_def_id, "approach_progress_score")
	score -= float(BoardUtils.manhattan(turn_start, move_pos)) * _score_float(unit_def_id, "approach_distance_cost")
	if new_dist < kite_min_range:
		score -= _score_float(unit_def_id, "approach_too_close_penalty")
	elif new_dist <= kite_ideal_range:
		score += _score_float(unit_def_id, "approach_ideal_band_bonus")
	return score


static func _score_kite_reposition(unit_def_id: String, current_dist: int, new_dist: int) -> float:
	var kite_min_range := _balance_int(unit_def_id, "kite_min_range")
	var kite_ideal_range := _balance_int(unit_def_id, "kite_ideal_range")
	var score: float = 0.0
	if current_dist <= kite_min_range and new_dist > current_dist:
		score += float(new_dist - current_dist) * _score_float(unit_def_id, "retreat_bonus_per_tile")
	score -= float(absi(new_dist - kite_ideal_range)) * _score_float(unit_def_id, "retreat_ideal_range_penalty")
	if new_dist < kite_min_range:
		score -= _score_float(unit_def_id, "retreat_too_close_penalty")
	return score


static func _score_reposition_for_line(
	state: GameState,
	enemy: UnitState,
	turn_start: Vector2i,
	move_pos: Vector2i,
	player: UnitState,
	reachable: Array[Vector2i],
	cell_blockers: Dictionary
) -> float:
	var unit_def_id := enemy.unit_def_id
	var best_current := _nearest_open_shot_path_distance(state, enemy, turn_start, player, reachable, cell_blockers)
	var best_next := _nearest_open_shot_path_distance(state, enemy, move_pos, player, reachable, cell_blockers)
	if best_next < 0:
		return _score_float(unit_def_id, "line_unreachable_penalty")
	if best_current < 0:
		return _score_float(unit_def_id, "line_setup_bonus") - float(BoardUtils.manhattan(turn_start, move_pos)) * _score_float(unit_def_id, "line_setup_distance_cost")
	if best_next < best_current:
		return float(best_current - best_next) * _score_float(unit_def_id, "line_progress_bonus_per_step")
	return _score_float(unit_def_id, "line_no_progress_penalty")


static func _nearest_open_shot_path_distance(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	player: UnitState,
	reachable: Array[Vector2i],
	cell_blockers: Dictionary
) -> int:
	var best := 999999
	for anchor in _open_shot_anchors(state, enemy, player, cell_blockers):
		var dist := 0
		if anchor != from_pos:
			var path := BoardUtils.path_toward(state, from_pos, anchor, state.board_size.x * state.board_size.y, enemy.uid, {}, cell_blockers)
			if path.is_empty() or path[path.size() - 1] != anchor:
				continue
			dist = path.size()
		if dist < best:
			best = dist
	if best == 999999:
		return -1
	return best


static func _open_shot_anchors(
	state: GameState,
	enemy: UnitState,
	player: UnitState,
	cell_blockers: Dictionary
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var max_range := attack_range_for(enemy.pos, [])
	for x in range(state.board_size.x):
		for y in range(state.board_size.y):
			var anchor := Vector2i(x, y)
			if _anchor_blocked(state, enemy, anchor, cell_blockers):
				continue
			var dist := BoardUtils.distance_between_unit_at_and_unit(enemy, anchor, player)
			var from_cell := BoardUtils.projectile_origin_cell_at(enemy, anchor, player.pos)
			var blocked := BoardUtils.projectile_blocked_before_aim(state, from_cell, player.pos)
			var kite_min_range := _balance_int(enemy.unit_def_id, "kite_min_range")
			if dist < kite_min_range or dist > max_range or blocked:
				continue
			anchors.append(anchor)
	return anchors


static func _anchor_blocked(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	cell_blockers: Dictionary
) -> bool:
	if not BoardUtils.unit_footprint_passable(state, unit, anchor, unit.uid, cell_blockers):
		return true
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var key := state.tile_key(cell)
		if cell_blockers.has(key) and str(cell_blockers[key]) != unit.uid:
			return true
	return false


static func _build_decision_from_best_candidate(
	state: GameState,
	enemy: UnitState,
	candidates: Array,
	cell_blockers: Dictionary
) -> Dictionary:
	if candidates.is_empty():
		return {"move_path": [] as Array[Vector2i], "action": null}
	var best = candidates[0]
	var best_move_dist := BoardUtils.manhattan(enemy.pos, best.move_target)
	for c in candidates:
		var move_dist := BoardUtils.manhattan(enemy.pos, c.move_target)
		if c.score > best.score or (is_equal_approx(c.score, best.score) and move_dist < best_move_dist):
			best = c
			best_move_dist = move_dist
	var result_path: Array[Vector2i] = []
	if best.move_target != enemy.pos and best.type != _EnemyAI.ActionType.WAIT:
		result_path = BoardUtils.path_toward(
			state, enemy.pos, best.move_target, enemy.move_points, enemy.uid, {}, cell_blockers
		)
	return {"move_path": result_path, "action": best}
