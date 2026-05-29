class_name StoneBowGuardRules
extends RefCounted


static func is_deployed(_start_pos: Vector2i, move_path: Array) -> bool:
	return move_path.is_empty()


static func attack_range_for(_start_pos: Vector2i, move_path: Array) -> int:
	var range := Constants.STONE_BOW_ATTACK_RANGE
	if is_deployed(_start_pos, move_path):
		range += Constants.STONE_BOW_DEPLOY_RANGE_BONUS
	return range


static func can_shoot_from_anchor(
	anchor: Vector2i,
	player_pos: Vector2i,
	move_path: Array
) -> bool:
	var dist := BoardUtils.manhattan(anchor, player_pos)
	if dist < Constants.STONE_BOW_KITE_MIN_RANGE:
		return false
	return dist <= attack_range_for(anchor, move_path)


static func is_faulty_blind_shot(unit: UnitState) -> bool:
	return StatusRules.is_lawless(unit)


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StatusRules.apply_lawless(state, unit, gem_uid)


static func on_lawless_recovered(_unit: UnitState) -> void:
	pass


static func bonus_damage(unit: UnitState) -> int:
	if is_faulty_blind_shot(unit):
		return Constants.STONE_BOW_FAULTY_DAMAGE_BONUS
	return 0


static func ranged_damage_preview(state: GameState, unit: UnitState) -> int:
	return CombatRules.attack_damage(state, unit) + bonus_damage(unit)


static func roll_hit(_state: GameState, attacker_uid: String) -> bool:
	var roll := float(_rng_service().roll_int("stone_bow_hit_%s" % attacker_uid, 0, 999)) / 999.0
	return roll >= Constants.STONE_BOW_FAULTY_MISS_CHANCE


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node("RngService")


static func in_range(from_pos: Vector2i, target_pos: Vector2i, start_pos: Vector2i, move_path: Array) -> bool:
	return can_shoot_from_anchor(from_pos, target_pos, move_path)


## 石弓专用风筝 AI：每步决策用当前玩家坐标；已在射程内优先原地架设射击
static func decide(state: GameState, enemy: UnitState, cell_blockers: Dictionary = {}) -> Dictionary:
	var player := state.get_player()
	if player == null or not player.alive:
		return {"move_path": [] as Array[Vector2i], "action": null}

	var player_pos: Vector2i = player.pos
	var turn_start: Vector2i = enemy.pos
	var current_dist: int = BoardUtils.manhattan(turn_start, player_pos)
	var can_shoot_here: bool = can_shoot_from_anchor(turn_start, player_pos, [])

	var reachable: Array[Vector2i] = []
	if StatusRules.can_move(enemy):
		reachable = BoardUtils.reachable_cells(
			state, enemy.pos, enemy.move_points, enemy.uid, {}, cell_blockers
		)
	reachable.append(enemy.pos)

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
		var dist: int = BoardUtils.manhattan(move_pos, player_pos)
		var max_range: int = attack_range_for(turn_start, move_path)
		if dist < Constants.STONE_BOW_KITE_MIN_RANGE or dist > max_range:
			continue
		var candidate := EnemyAI.ActionCandidate.new()
		candidate.type = EnemyAI.ActionType.RANGED_ATTACK
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
		var new_dist: int = BoardUtils.manhattan(move_pos, player_pos)
		if can_shoot_here and new_dist >= Constants.STONE_BOW_KITE_MIN_RANGE:
			continue
		if can_shoot_here and new_dist < current_dist:
			continue
		var candidate := EnemyAI.ActionCandidate.new()
		candidate.type = EnemyAI.ActionType.MOVE
		candidate.move_target = move_pos
		candidate.score = _score_kite_reposition(current_dist, new_dist)
		candidate.description = "风筝走位"
		candidates.append(candidate)

	var wait := EnemyAI.ActionCandidate.new()
	wait.type = EnemyAI.ActionType.WAIT
	wait.move_target = enemy.pos
	wait.score = -5.0
	wait.description = "等待"
	candidates.append(wait)

	if candidates.is_empty():
		return {"move_path": [] as Array[Vector2i], "action": null}

	var best: EnemyAI.ActionCandidate = candidates[0]
	for c in candidates:
		if c.score > best.score:
			best = c

	var result_path: Array[Vector2i] = []
	if best.move_target != enemy.pos and best.type != EnemyAI.ActionType.WAIT:
		result_path = BoardUtils.path_toward(
			state, enemy.pos, best.move_target, enemy.move_points, enemy.uid, {}, cell_blockers
		)
	return {"move_path": result_path, "action": best}


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
	var score: float = float(damage) * 10.0
	if player.hp <= damage:
		score += 150.0
	var move_steps: int = move_path.size()
	score -= float(move_steps) * 0.35
	score -= float(absi(dist - Constants.STONE_BOW_KITE_IDEAL_RANGE)) * 14.0
	if dist < Constants.STONE_BOW_KITE_IDEAL_RANGE:
		score -= float(Constants.STONE_BOW_KITE_IDEAL_RANGE - dist) * 18.0
	if dist == max_range:
		score += 4.0

	if can_shoot_here:
		if move_pos == turn_start:
			score += 120.0
			if is_deployed(turn_start, move_path) and dist >= Constants.STONE_BOW_KITE_IDEAL_RANGE:
				score += 12.0
		else:
			score -= 45.0
			if dist < current_dist:
				score -= 80.0
	elif current_dist <= Constants.STONE_BOW_KITE_MIN_RANGE and dist > current_dist:
		score += float(dist - current_dist) * 32.0
	elif dist > current_dist:
		score -= float(dist - current_dist) * 8.0
	elif not can_shoot_here and dist < current_dist:
		score += float(current_dist - dist) * 6.0

	if is_deployed(turn_start, move_path) and dist >= Constants.STONE_BOW_KITE_IDEAL_RANGE and not can_shoot_here:
		score += 6.0
	return score


static func _score_kite_reposition(current_dist: int, new_dist: int) -> float:
	var score: float = 0.0
	if current_dist <= Constants.STONE_BOW_KITE_MIN_RANGE and new_dist > current_dist:
		score += float(new_dist - current_dist) * 22.0
	score -= float(absi(new_dist - Constants.STONE_BOW_KITE_IDEAL_RANGE)) * 6.0
	if new_dist < Constants.STONE_BOW_KITE_MIN_RANGE:
		score -= 30.0
	return score


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
