class_name EnemyAI
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")

## 分值评估系统 (Utility AI)
## 核心思路：遍历所有合法行动 → 模拟执行 → 打分 → 选最高分
## 怪物行动经济：每回合 1 次移动 + 1 次行动（攻击/技能）


# ─── 行动类型 ───────────────────────────────────────────────────────────
enum ActionType {
	MOVE,           # 移动到某格
	ATTACK,         # 近战攻击
	RANGED_ATTACK,  # 远程射击
	SKILL_RED,      # 红槽宝石技能（冲刺爆炸、拉人、毒攻等）
	EXTRACT,        # 拔出宝石
	WAIT,           # 原地等待
}


# ─── 行动候选结构 ─────────────────────────────────────────────────────────
class ActionCandidate:
	var type: int = ActionType.WAIT
	var move_target: Vector2i = Vector2i(-1, -1)  # 移动目标格
	var action_target_uid: String = ""             # 行动目标单位
	var slot_index: int = -1                       # 槽位索引（拔出用）
	var score: float = 0.0
	var description: String = ""


static func make_candidate() -> ActionCandidate:
	return ActionCandidate.new()


# ─── 辅助：从 profile 字典安全取 float ─────────────────────────────────────
static func _w(profile: Dictionary, key: String, fallback: float = 0.0) -> float:
	return float(profile.get(key, fallback))


# ─── 主入口：为一个敌人生成最优行动 ─────────────────────────────────────────
static func decide(state: GameState, enemy: UnitState, cell_blockers: Dictionary = {}) -> Dictionary:
	## 返回 { "move_path": Array[Vector2i], "action": ActionCandidate }
	var profile: Dictionary = AIProfiles.get_profile(enemy.ai_profile_id)
	var path_profile: Dictionary = _build_path_cost_profile(profile)
	var candidates: Array = _generate_all_candidates(state, enemy, profile, cell_blockers)

	if candidates.is_empty():
		return {"move_path": [] as Array[Vector2i], "action": null}

	# 选最高分
	var best: ActionCandidate = candidates[0]
	for c in candidates:
		if c.score > best.score:
			best = c

	# 构建移动路径
	var move_path: Array[Vector2i] = []
	if best.move_target != Vector2i(-1, -1) and best.move_target != enemy.pos:
		move_path = BoardUtils.path_toward(
			state,
			enemy.pos,
			best.move_target,
			enemy.move_points,
			enemy.uid,
			path_profile,
			cell_blockers,
			enemy
		)

	return {"move_path": move_path, "action": best}


static func _is_blocked_destination(
	state: GameState,
	anchor: Vector2i,
	unit: UnitState,
	cell_blockers: Dictionary
) -> bool:
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var key := state.tile_key(cell)
		if cell_blockers.has(key) and str(cell_blockers[key]) != unit.uid:
			return true
	return false


# ─── 生成所有候选行动 ─────────────────────────────────────────────────────
static func _generate_all_candidates(
	state: GameState,
	enemy: UnitState,
	profile: Dictionary,
	cell_blockers: Dictionary = {}
) -> Array:
	var candidates: Array = []
	var path_profile: Dictionary = _build_path_cost_profile(profile)

	# 获取所有可达格子（包括原地）
	var reachable: Array[Vector2i] = []
	if not StatusRules.can_move(enemy):
		reachable = [] as Array[Vector2i]
	else:
		reachable = BoardUtils.reachable_cells(
			state, enemy.pos, enemy.move_points, enemy.uid, path_profile, cell_blockers, enemy
		)
	reachable.append(enemy.pos)  # 原地也是选项

	for move_pos in reachable:
		if _is_blocked_destination(state, move_pos, enemy, cell_blockers):
			continue
		# --- 在每个可达位置评估可执行的行动 ---

		# 1. 近战攻击
		if profile.get("ranged_only", false):
			pass
		else:
			var attack_candidates: Array = _evaluate_attacks_from(state, enemy, move_pos, profile)
			candidates.append_array(attack_candidates)
		if profile.get("can_ranged_attack", false) and not GemEffects.unit_has_red_split(state, enemy):
			var ranged_candidates: Array = _evaluate_ranged_attacks_from(state, enemy, move_pos, profile)
			candidates.append_array(ranged_candidates)

		# 2. 红槽技能（如果有红宝石）
		var skill_candidates: Array = _evaluate_red_skill_from(state, enemy, move_pos, profile)
		candidates.append_array(skill_candidates)

	# 3. 纯移动（不攻击，只靠近目标）
	var move_only: Array = _evaluate_move_only(state, enemy, reachable, profile, cell_blockers)
	candidates.append_array(move_only)

	# 4. 原地等待（兜底）
	var wait := ActionCandidate.new()
	wait.type = ActionType.WAIT
	wait.move_target = enemy.pos
	wait.score = _w(profile, "wait_score", -10.0)
	wait.description = "等待"
	candidates.append(wait)

	return candidates


# ─── 评估近战攻击 ─────────────────────────────────────────────────────────
static func _evaluate_attacks_from(state: GameState, enemy: UnitState, from_pos: Vector2i, profile: Dictionary) -> Array:
	var results: Array = []
	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return results

	# 检查从 from_pos 能否攻击到玩家
	var can_attack := BoardUtils.are_units_adjacent_at(enemy, from_pos, player)
	if not can_attack:
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.ATTACK
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid

	# 打分
	var damage_dealt: int = CombatRules.attack_damage(state, enemy)
	var score: float = float(damage_dealt) * _w(profile, "w_damage", 10.0)

	# 击杀加分
	if player.hp <= damage_dealt:
		score += _w(profile, "w_kill_player", 200.0)

	# 距离惩罚（移动越远扣分越少，鼓励靠近攻击）
	var move_dist: int = BoardUtils.manhattan(enemy.pos, from_pos)
	score -= float(move_dist) * _w(profile, "w_move_cost", 0.5)

	# 自身安全评估：移动后是否踩到危险地块
	score += _evaluate_tile_safety(state, from_pos, profile)

	candidate.score = score
	candidate.description = "移动到%s攻击玩家" % str(from_pos)
	results.append(candidate)
	return results


static func _evaluate_ranged_attacks_from(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	profile: Dictionary
) -> Array:
	var results: Array = []
	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return results
	var max_range: int = GemEffects.red_attack_range(state, enemy, Constants.ATTACK_RANGE)
	var in_range := BoardUtils.can_unit_reach_unit_at(enemy, from_pos, player, max_range)
	var dist: int = BoardUtils.distance_between_unit_at_and_unit(enemy, from_pos, player)
	var from_cell := BoardUtils.projectile_origin_cell_at(enemy, from_pos, player.pos)
	var blocked := BoardUtils.projectile_blocked_before_aim(state, from_cell, player.pos)
	if not in_range or blocked:
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.RANGED_ATTACK
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var damage_dealt: int = CombatRules.attack_damage(state, enemy)
	var score: float = float(damage_dealt) * _w(profile, "w_damage", 10.0)
	if player.hp <= damage_dealt:
		score += _w(profile, "w_kill_player", 200.0)
	var move_dist: int = BoardUtils.manhattan(enemy.pos, from_pos)
	score -= float(move_dist) * _w(profile, "w_move_cost", 0.5)
	score += _evaluate_tile_safety(state, from_pos, profile)
	if profile.get("prefer_distance", false):
		score += float(dist) * _w(profile, "w_keep_distance", 3.0) * 0.3
	candidate.score = score
	var range_label := str(max_range)
	candidate.description = "在%s远程射击(%s格)" % [str(from_pos), range_label]
	results.append(candidate)
	return results


# ─── 评估红槽技能 ─────────────────────────────────────────────────────────
static func _evaluate_red_skill_from(state: GameState, enemy: UnitState, from_pos: Vector2i, profile: Dictionary) -> Array:
	var results: Array = []
	var red_slot: SlotState = enemy.get_slot(Constants.SLOT_RED)
	if red_slot == null or red_slot.gem_uid.is_empty():
		return results

	var gem: GemState = state.gems.get(red_slot.gem_uid, null)
	if gem == null:
		return results

	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return results

	match str(GemEffects.get_enemy_red_intent_meta(gem, CombatRules.attack_damage(state, enemy)).get("type", "wait")):
		"explosion_attack":
			results.append_array(_score_explosion_attack(state, enemy, from_pos, player, profile))
		"charge_explode":
			results.append_array(_score_explosion_skill(state, enemy, from_pos, player, profile))
		"pull":
			results.append_array(_score_pull_skill(state, enemy, from_pos, player, profile))
		"poison_attack":
			results.append_array(_score_poison_skill(state, enemy, from_pos, player, profile))
		"arc_attack":
			results.append_array(_score_arc_skill(state, enemy, from_pos, player, profile))
		"fire_attack":
			results.append_array(_score_fire_skill(state, enemy, from_pos, player, profile))
		"ice_attack":
			results.append_array(_score_ice_skill(state, enemy, from_pos, player, profile))
		"split_attack":
			results.append_array(_score_split_skill(state, enemy, from_pos, player, profile))
		"light_beam":
			results.append_array(_score_light_skill(state, enemy, from_pos, player, profile))
		"counter_attack":
			results.append_array(_score_counter_skill(state, enemy, from_pos, player, profile))
		"echo_attack":
			results.append_array(_score_echo_skill(state, enemy, from_pos, player, profile))
	return results


static func evaluate_red_skill_candidates(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	profile: Dictionary
) -> Array:
	return _evaluate_red_skill_from(state, enemy, from_pos, profile)


# ─── 爆炸宝石：近战十字溅射（与玩家红槽攻击同源，不自爆）────────────────────
static func _score_explosion_attack(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if BoardUtils.manhattan(from_pos, player.pos) != 1:
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var damage: int = CombatConfig.explosion_cross_damage()
	candidate.score = float(damage) * _w(profile, "w_damage", 10.0)
	if player.hp <= damage:
		candidate.score += _w(profile, "w_kill_player", 200.0)
	candidate.score += _evaluate_tile_safety(state, from_pos, profile)
	candidate.description = "爆炸攻击"
	results.append(candidate)
	return results


# ─── 冲刺自爆（遗留 intent，非爆炸宝石默认路径）────────────────────────────
static func _score_explosion_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	var dist_to_player: int = BoardUtils.manhattan(from_pos, player.pos)
	var max_threat_range: int = Constants.CHARGE_EXPLODE_DASH_RANGE + Constants.EXPLOSION_RADIUS
	if dist_to_player > max_threat_range:
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid

	var score: float = 0.0
	if dist_to_player <= Constants.EXPLOSION_RADIUS:
		score += float(Constants.EXPLOSION_DAMAGE) * _w(profile, "w_damage", 10.0) * 2.0
	elif dist_to_player <= max_threat_range:
		score += float(Constants.EXPLOSION_DAMAGE) * _w(profile, "w_damage", 10.0)

	score += _w(profile, "w_self_sacrifice", 0.0)

	# 友军误伤扣分
	for cell in BoardUtils.cells_in_radius(player.pos, Constants.EXPLOSION_RADIUS):
		var unit: UnitState = state.get_unit_at(cell)
		if unit != null and unit.alive:
			if unit.team == Constants.TEAM_ENEMY and unit.uid != enemy.uid:
				score -= _w(profile, "w_friendly_fire", 30.0)

	candidate.score = score
	candidate.description = "冲刺爆炸"
	results.append(candidate)
	return results


# ─── 引力技能评分 ─────────────────────────────────────────────────────────
static func _score_pull_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	var max_range := GemEffects.gravity_pull_range(state, enemy, CombatConfig.enemy_gravity_pull_range())
	var dist: int = BoardUtils.distance_between_unit_at_and_unit(enemy, from_pos, player)
	if dist > max_range:
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid

	var score: float = _w(profile, "w_pull", 15.0) + 8.0
	# 拉到危险地块加分
	var pull_dest: Vector2i = BoardUtils.step_toward(player.pos, from_pos)
	if BoardUtils.spike_entity_at(state, pull_dest) != null:
		score += float(Constants.SPIKE_DAMAGE) * _w(profile, "w_damage", 10.0)
	var pull_tile: TileState = state.get_tile(pull_dest)
	if pull_tile.has_modifier("poison_fog"):
		score += _w(profile, "w_damage", 10.0) * 0.5
	# 引力会附带束缚，距离越远价值越高
	score += float(dist) * 1.2

	candidate.score = score
	candidate.description = "引力拉近(%d格)" % max_range
	results.append(candidate)
	return results


# ─── 毒攻击评分 ───────────────────────────────────────────────────────────
static func _score_poison_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid

	var score: float = float(CombatRules.attack_damage(state, enemy)) * _w(profile, "w_damage", 10.0)
	score += _w(profile, "w_poison", 8.0)  # 附加中毒价值

	candidate.score = score
	candidate.description = "毒攻击"
	results.append(candidate)
	return results


static func _score_arc_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var base := float(CombatRules.attack_damage(state, enemy))
	var score: float = base * _w(profile, "w_damage", 10.0)
	for unit in state.units.values():
		if not unit.alive or unit.team == player.team or unit.uid == player.uid:
			continue
		if BoardUtils.chebyshev(player.pos, unit.pos) <= CombatConfig.arc_chain_range():
			score += base * CombatConfig.arc_chain_damage_ratio() * _w(profile, "w_damage", 10.0) * 0.5
	candidate.score = score
	candidate.description = "电击"
	results.append(candidate)
	return results


static func _score_fire_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var score: float = float(CombatRules.attack_damage(state, enemy)) * _w(profile, "w_damage", 10.0)
	score += _w(profile, "w_status", 6.0)
	candidate.score = score
	candidate.description = "烈焰攻击"
	results.append(candidate)
	return results


static func _score_ice_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var score: float = float(CombatRules.attack_damage(state, enemy)) * _w(profile, "w_damage", 10.0)
	score += _w(profile, "w_status", 6.0)
	candidate.score = score
	candidate.description = "寒冰攻击"
	results.append(candidate)
	return results


static func _score_split_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	var in_range := BoardUtils.are_units_adjacent_at(enemy, from_pos, player)
	if not in_range:
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var base := float(CombatRules.attack_damage(state, enemy)) * CombatConfig.split_attack_damage_ratio()
	var score: float = base * _w(profile, "w_damage", 10.0)
	candidate.score = score
	candidate.description = "分裂攻击"
	results.append(candidate)
	return results


static func _score_light_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	var max_range := Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
	if not BoardUtils.can_unit_attack_cell_at(enemy, state, from_pos, player.pos, max_range):
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var score: float = float(CombatRules.attack_damage(state, enemy)) * 0.5 * _w(profile, "w_damage", 10.0)
	score += _w(profile, "w_status", 6.0)
	candidate.score = score
	candidate.description = "光束"
	results.append(candidate)
	return results


static func _score_counter_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var score: float = float(CombatRules.attack_damage(state, enemy)) * _w(profile, "w_damage", 10.0)
	score += _w(profile, "w_status", 6.0)
	candidate.score = score
	candidate.description = "反击"
	results.append(candidate)
	return results


static func _score_echo_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	var max_range := GemEffects.red_attack_range(state, enemy, Constants.ATTACK_RANGE)
	var in_range := BoardUtils.can_unit_reach_unit_at(enemy, from_pos, player, max_range)
	if not in_range:
		return results
	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid
	var score: float = float(CombatRules.attack_damage(state, enemy)) * _w(profile, "w_damage", 10.0)
	score += _w(profile, "w_status", 6.0)
	candidate.score = score
	candidate.description = "回响"
	results.append(candidate)
	return results


# ─── 评估纯移动（不攻击） ─────────────────────────────────────────────────
static func _evaluate_move_only(
	state: GameState,
	enemy: UnitState,
	reachable: Array[Vector2i],
	profile: Dictionary,
	cell_blockers: Dictionary = {}
) -> Array:
	var results: Array = []
	var player: UnitState = state.get_player()
	if player == null:
		return results

	if profile.get("prefer_distance", false):
		return _evaluate_move_kiting(state, enemy, reachable, profile, cell_blockers)

	var current_dist := BoardUtils.path_distance_to_cell(
		state, enemy.pos, player.pos, enemy.uid, cell_blockers, enemy
	)
	if current_dist < 0:
		return results

	var added_targets: Dictionary = {}
	var path_profile := _build_path_cost_profile(profile)
	var planned_path := BoardUtils.path_toward(
		state,
		enemy.pos,
		player.pos,
		enemy.move_points,
		enemy.uid,
		path_profile,
		cell_blockers,
		enemy
	)
	if not planned_path.is_empty():
		var planned_pos: Vector2i = planned_path[planned_path.size() - 1]
		if planned_pos != enemy.pos and not _is_blocked_destination(state, planned_pos, enemy, cell_blockers):
			var planned_dist := BoardUtils.path_distance_to_cell(
				state, planned_pos, player.pos, enemy.uid, cell_blockers, enemy
			)
			if planned_dist >= 0:
				var candidate := ActionCandidate.new()
				candidate.type = ActionType.MOVE
				candidate.move_target = planned_pos
				var progress := maxf(0.25, float(current_dist - planned_dist))
				var score := progress * _w(profile, "w_approach", 5.0)
				score += _evaluate_tile_safety(state, planned_pos, profile)
				candidate.score = score
				candidate.description = "移动到%s" % str(planned_pos)
				results.append(candidate)
				added_targets[planned_pos] = true

	var best_pos := enemy.pos
	var best_dist := current_dist
	for pos in reachable:
		if pos == enemy.pos:
			continue
		if added_targets.has(pos):
			continue
		if _is_blocked_destination(state, pos, enemy, cell_blockers):
			continue
		var dist := BoardUtils.path_distance_to_cell(
			state, pos, player.pos, enemy.uid, cell_blockers, enemy
		)
		if dist < 0 or dist >= best_dist:
			continue
		best_dist = dist
		best_pos = pos

	if best_pos == enemy.pos:
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.MOVE
	candidate.move_target = best_pos
	var score := float(current_dist - best_dist) * _w(profile, "w_approach", 5.0)
	score += _evaluate_tile_safety(state, best_pos, profile)
	candidate.score = score
	candidate.description = "移动到%s" % str(best_pos)
	results.append(candidate)
	return results


static func _evaluate_move_kiting(
	state: GameState,
	enemy: UnitState,
	reachable: Array[Vector2i],
	profile: Dictionary,
	cell_blockers: Dictionary = {}
) -> Array:
	var results: Array = []
	var player: UnitState = state.get_player()
	if player == null:
		return results
	for pos in reachable:
		if pos == enemy.pos:
			continue
		if _is_blocked_destination(state, pos, enemy, cell_blockers):
			continue
		var candidate := ActionCandidate.new()
		candidate.type = ActionType.MOVE
		candidate.move_target = pos
		var dist_to_player: int = BoardUtils.manhattan(pos, player.pos)
		var current_dist: int = BoardUtils.manhattan(enemy.pos, player.pos)
		var score: float = float(current_dist - dist_to_player) * _w(profile, "w_approach", 5.0)
		score += float(dist_to_player) * _w(profile, "w_keep_distance", 3.0)
		score += _evaluate_tile_safety(state, pos, profile)
		candidate.score = score
		candidate.description = "移动到%s" % str(pos)
		results.append(candidate)
	return results


# ─── 路径权重构建 ───────────────────────────────────────────────────────────
static func _build_path_cost_profile(profile: Dictionary) -> Dictionary:
	return {
		"base_step_cost": _w(profile, "path_base_step_cost", 1.0),
		"spike_damage_weight": _w(profile, "path_spike_damage_weight", _w(profile, "w_self_damage", 8.0) * 0.25),
		"water_cost_bias": _w(profile, "path_water_cost_bias", 0.0),
		"allow_partial_path": profile.get("allow_partial_path", true),
	}


# ─── 地块安全评估 ─────────────────────────────────────────────────────────
static func _evaluate_tile_safety(state: GameState, pos: Vector2i, profile: Dictionary) -> float:
	var score: float = 0.0
	if BoardUtils.spike_entity_at(state, pos) != null:
		score -= float(Constants.SPIKE_DAMAGE) * _w(profile, "w_self_damage", 8.0)
	var tile: TileState = state.get_tile(pos)
	if tile.has_modifier("poison_fog"):
		score -= float(CombatConfig.poison_fog_damage()) * _w(profile, "w_self_damage", 8.0)
	return score


# ─── 最近友军距离 ─────────────────────────────────────────────────────────
static func _nearest_ally_distance(state: GameState, from_pos: Vector2i, ignore_uid: String) -> int:
	var best: int = 999
	for unit in state.units.values():
		if not unit.alive or unit.team != Constants.TEAM_ENEMY or unit.uid == ignore_uid:
			continue
		var dist: int = BoardUtils.manhattan(from_pos, unit.pos)
		if dist < best:
			best = dist
	return best


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
