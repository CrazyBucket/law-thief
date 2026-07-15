class_name EnemyAI
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const IntentPreviewRules = preload("res://scripts/rules/intent_preview_rules.gd")
const ActionCandidate = preload("res://scripts/rules/ai_action_candidate.gd")
const AiCandidateSelector = preload("res://scripts/rules/ai_candidate_selector.gd")
const AiSkillCandidateFactory = preload("res://scripts/rules/ai_skill_candidate_factory.gd")
const AiRedSkillScorer = preload("res://scripts/rules/ai_red_skill_scorer.gd")

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


static func make_candidate() -> ActionCandidate:
	return ActionCandidate.new()


# ─── 辅助：从已校验并合成的 profile 字典取值 ──────────────────────────────────
static func _w(profile: Dictionary, key: String) -> float:
	if profile.has(key):
		return float(profile[key])
	push_error("EnemyAI: required profile value missing: %s" % key)
	return 0.0


static func _t(profile: Dictionary, key: String) -> float:
	if profile.has(key):
		return float(profile[key])
	return float(AIProfiles.get_tuning_value(key))


# ─── 主入口：为一个敌人生成最优行动 ─────────────────────────────────────────
static func decide(state: GameState, enemy: UnitState, cell_blockers: Dictionary = {}) -> Dictionary:
	## 返回 { "move_path": Array[Vector2i], "action": ActionCandidate }
	var profile: Dictionary = AIProfiles.get_profile(enemy.ai_profile_id)
	var path_profile: Dictionary = _build_path_cost_profile(profile)
	var candidates: Array = _generate_all_candidates(state, enemy, profile, cell_blockers)

	if candidates.is_empty():
		return {"move_path": [] as Array[Vector2i], "action": null}

	# 选最高分
	var best: ActionCandidate = AiCandidateSelector.select_highest_scoring(candidates)

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
		if bool(profile["ranged_only"]):
			pass
		else:
			var attack_candidates: Array = _evaluate_attacks_from(state, enemy, move_pos, profile)
			candidates.append_array(attack_candidates)
		if bool(profile["can_ranged_attack"]) and not GemEffects.unit_has_red_split(state, enemy):
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
	wait.score = _w(profile, "wait_score")
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
	var damage_dealt := _previewed_red_damage_to(state, enemy, from_pos, player)
	var score: float = float(damage_dealt) * _w(profile, "w_damage")

	# 击杀加分
	if player.hp <= damage_dealt:
		score += _w(profile, "w_kill_player")

	# 距离惩罚（移动越远扣分越少，鼓励靠近攻击）
	var move_dist: int = BoardUtils.manhattan(enemy.pos, from_pos)
	score -= float(move_dist) * _w(profile, "w_move_cost")

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
	var max_range: int = GemEffects.red_attack_range(state, enemy, CombatConfig.attack_range())
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
	var damage_dealt := _previewed_red_damage_to(state, enemy, from_pos, player)
	var score: float = float(damage_dealt) * _w(profile, "w_damage")
	if player.hp <= damage_dealt:
		score += _w(profile, "w_kill_player")
	var move_dist: int = BoardUtils.manhattan(enemy.pos, from_pos)
	score -= float(move_dist) * _w(profile, "w_move_cost")
	score += _evaluate_tile_safety(state, from_pos, profile)
	if bool(profile["prefer_distance"]):
		score += float(dist) * _w(profile, "w_keep_distance") * _t(profile, "ranged_keep_distance_scale")
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
			results.append_array(AiRedSkillScorer.explosion_attack(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"charge_explode":
			results.append_array(AiRedSkillScorer.charge_explode(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"pull":
			results.append_array(AiRedSkillScorer.pull(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"poison_attack":
			results.append_array(AiRedSkillScorer.poison(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"arc_attack":
			results.append_array(AiRedSkillScorer.arc(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"fire_attack":
			results.append_array(AiRedSkillScorer.status_attack(state, enemy, from_pos, player, profile, ActionType.SKILL_RED, "烈焰攻击"))
		"ice_attack":
			results.append_array(AiRedSkillScorer.status_attack(state, enemy, from_pos, player, profile, ActionType.SKILL_RED, "寒冰攻击"))
		"split_attack":
			results.append_array(AiRedSkillScorer.split(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"light_beam":
			results.append_array(AiRedSkillScorer.light(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
		"counter_attack":
			results.append_array(AiRedSkillScorer.status_attack(state, enemy, from_pos, player, profile, ActionType.SKILL_RED, "反击"))
		"echo_attack":
			results.append_array(AiRedSkillScorer.echo(state, enemy, from_pos, player, profile, ActionType.SKILL_RED))
	return results


static func evaluate_red_skill_candidates(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	profile: Dictionary
) -> Array:
	return _evaluate_red_skill_from(state, enemy, from_pos, profile)


# ─── 爆炸宝石：近战十字溅射（与玩家红槽攻击同源，不自爆）────────────────────
# ─── 冲刺自爆（遗留 intent，非爆炸宝石默认路径）────────────────────────────
# ─── 引力技能评分 ─────────────────────────────────────────────────────────
# ─── 毒攻击评分 ───────────────────────────────────────────────────────────
static func _previewed_red_damage_to(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	target: UnitState
) -> int:
	return AiRedSkillScorer.previewed_red_damage_to(state, enemy, from_pos, target)


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

	if bool(profile["prefer_distance"]):
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
				var progress := maxf(_t(profile, "approach_progress_floor"), float(current_dist - planned_dist))
				var score := progress * _w(profile, "w_approach")
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
	var score := float(current_dist - best_dist) * _w(profile, "w_approach")
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
		var score: float = float(current_dist - dist_to_player) * _w(profile, "w_approach")
		score += float(dist_to_player) * _w(profile, "w_keep_distance")
		score += _evaluate_tile_safety(state, pos, profile)
		candidate.score = score
		candidate.description = "移动到%s" % str(pos)
		results.append(candidate)
	return results


# ─── 路径权重构建 ───────────────────────────────────────────────────────────
static func _build_path_cost_profile(profile: Dictionary) -> Dictionary:
	return {
		"base_step_cost": _w(profile, "path_base_step_cost"),
		"spike_damage_weight": _w(profile, "path_spike_damage_weight"),
		"water_cost_bias": _w(profile, "path_water_cost_bias"),
		"allow_partial_path": bool(profile["allow_partial_path"]),
	}


# ─── 地块安全评估 ─────────────────────────────────────────────────────────
static func _evaluate_tile_safety(state: GameState, pos: Vector2i, profile: Dictionary) -> float:
	var score: float = 0.0
	if BoardUtils.spike_entity_at(state, pos) != null:
		score -= float(CombatConfig.spike_damage()) * _w(profile, "w_self_damage")
	var tile: TileState = state.get_tile(pos)
	if tile.has_modifier("poison_fog"):
		score -= float(CombatConfig.poison_fog_damage()) * _w(profile, "w_self_damage")
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
