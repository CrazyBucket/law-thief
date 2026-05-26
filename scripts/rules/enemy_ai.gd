class_name EnemyAI
extends RefCounted
## 分值评估系统 (Utility AI)
## 核心思路：遍历所有合法行动 → 模拟执行 → 打分 → 选最高分
## 怪物行动经济：每回合 1 次移动 + 1 次行动（攻击/技能）


# ─── 行动类型 ───────────────────────────────────────────────────────────
enum ActionType {
	MOVE,           # 移动到某格
	ATTACK,         # 近战攻击
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


# ─── 辅助：从 profile 字典安全取 float ─────────────────────────────────────
static func _w(profile: Dictionary, key: String, fallback: float = 0.0) -> float:
	return float(profile.get(key, fallback))


# ─── 主入口：为一个敌人生成最优行动 ─────────────────────────────────────────
static func decide(state: GameState, enemy: UnitState) -> Dictionary:
	## 返回 { "move_path": Array[Vector2i], "action": ActionCandidate }
	var profile: Dictionary = AIProfiles.get_profile(enemy.ai_profile_id)
	var path_profile: Dictionary = _build_path_cost_profile(profile)
	var candidates: Array = _generate_all_candidates(state, enemy, profile)

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
		move_path = BoardUtils.path_toward(state, enemy.pos, best.move_target, enemy.move_points, enemy.uid, path_profile)

	return {"move_path": move_path, "action": best}


# ─── 生成所有候选行动 ─────────────────────────────────────────────────────
static func _generate_all_candidates(state: GameState, enemy: UnitState, profile: Dictionary) -> Array:
	var candidates: Array = []
	var path_profile: Dictionary = _build_path_cost_profile(profile)

	# 获取所有可达格子（包括原地）
	var reachable: Array[Vector2i] = []
	if not StatusRules.can_move(enemy):
		reachable = [] as Array[Vector2i]
	else:
		reachable = BoardUtils.reachable_cells(state, enemy.pos, enemy.move_points, enemy.uid, path_profile)
	reachable.append(enemy.pos)  # 原地也是选项

	for move_pos in reachable:
		# --- 在每个可达位置评估可执行的行动 ---

		# 1. 近战攻击
		var attack_candidates: Array = _evaluate_attacks_from(state, enemy, move_pos, profile)
		candidates.append_array(attack_candidates)

		# 2. 红槽技能（如果有红宝石）
		var skill_candidates: Array = _evaluate_red_skill_from(state, enemy, move_pos, profile)
		candidates.append_array(skill_candidates)

		# 3. 拔出宝石（偷窃型怪物）
		if profile.get("can_extract", false):
			var extract_candidates: Array = _evaluate_extract_from(state, enemy, move_pos, profile)
			candidates.append_array(extract_candidates)

	# 4. 纯移动（不攻击，只靠近目标）
	var move_only: Array = _evaluate_move_only(state, enemy, reachable, profile)
	candidates.append_array(move_only)

	# 5. 原地等待（兜底）
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

	# 检查从 from_pos 能否攻击到玩家（曼哈顿距离 1）
	if BoardUtils.manhattan(from_pos, player.pos) != 1:
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
		"charge_explode":
			results.append_array(_score_explosion_skill(state, enemy, from_pos, player, profile))
		"pull":
			results.append_array(_score_pull_skill(state, enemy, from_pos, player, profile))
		"poison_attack":
			results.append_array(_score_poison_skill(state, enemy, from_pos, player, profile))
	return results


# ─── 爆炸技能评分 ─────────────────────────────────────────────────────────
static func _score_explosion_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	# 自爆工兵：冲刺 2 格后爆炸，需要靠近玩家
	var dist_to_player: int = BoardUtils.manhattan(from_pos, player.pos)
	# 冲刺距离 2，爆炸半径 1，所以距离 <= 3 就有可能炸到
	if dist_to_player > 3:
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid

	var score: float = 0.0
	# 能炸到玩家的概率越高分越高
	if dist_to_player <= 1:
		score += float(Constants.EXPLOSION_DAMAGE) * _w(profile, "w_damage", 10.0) * 2.0  # 必炸
	elif dist_to_player <= 3:
		score += float(Constants.EXPLOSION_DAMAGE) * _w(profile, "w_damage", 10.0)

	# 自爆兵不在乎自己死
	score += _w(profile, "w_self_sacrifice", 0.0)

	# 如果能同时炸到多个目标加分
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
	var dist: int = BoardUtils.manhattan(from_pos, player.pos)
	if dist > 4:  # 引力范围
		return results

	var candidate := ActionCandidate.new()
	candidate.type = ActionType.SKILL_RED
	candidate.move_target = from_pos
	candidate.action_target_uid = player.uid

	var score: float = _w(profile, "w_pull", 15.0) + 8.0
	# 拉到危险地块加分
	var pull_dest: Vector2i = BoardUtils.step_toward(player.pos, from_pos)
	var tile: TileState = state.get_tile(pull_dest)
	if tile.tile_id == Constants.TILE_SPIKE:
		score += float(Constants.SPIKE_DAMAGE) * _w(profile, "w_damage", 10.0)
	if tile.has_modifier("poison_fog"):
		score += _w(profile, "w_damage", 10.0) * 0.5
	# 引力会附带束缚，距离越远价值越高
	score += float(dist) * 1.2

	candidate.score = score
	candidate.description = "引力拉近"
	results.append(candidate)
	return results


# ─── 毒攻击评分 ───────────────────────────────────────────────────────────
static func _score_poison_skill(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary) -> Array:
	var results: Array = []
	if BoardUtils.manhattan(from_pos, player.pos) != 1:
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


# ─── 评估拔出宝石 ─────────────────────────────────────────────────────────
static func _evaluate_extract_from(state: GameState, enemy: UnitState, from_pos: Vector2i, profile: Dictionary) -> Array:
	var results: Array = []
	# 遍历范围内所有单位的槽位
	for unit in state.units.values():
		if not unit.alive or unit.uid == enemy.uid:
			continue
		if BoardUtils.manhattan(from_pos, unit.pos) > Constants.EXTRACT_RANGE:
			continue
		for i in range(unit.slots.size()):
			var slot: SlotState = unit.slots[i]
			if slot.gem_uid.is_empty() or slot.locked:
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null:
				continue

			var candidate := ActionCandidate.new()
			candidate.type = ActionType.EXTRACT
			candidate.move_target = from_pos
			candidate.action_target_uid = unit.uid
			candidate.slot_index = i

			var score: float = _w(profile, "w_extract_base", 20.0)
			# 偷玩家的宝石更有价值
			if unit.team == Constants.TEAM_PLAYER:
				score += _w(profile, "w_steal_player", 30.0)
			# 偷红槽宝石（核心能力）价值最高
			if slot.slot_type == Constants.SLOT_RED:
				score += _w(profile, "w_steal_red", 25.0)

			candidate.score = score
			candidate.description = "拔出%s的%s宝石" % [unit.uid, _data_registry().get_gem_display_name(gem)]
			results.append(candidate)

	return results


# ─── 评估纯移动（不攻击） ─────────────────────────────────────────────────
static func _evaluate_move_only(state: GameState, enemy: UnitState, reachable: Array[Vector2i], profile: Dictionary) -> Array:
	var results: Array = []
	var player: UnitState = state.get_player()
	if player == null:
		return results

	# 选择最优移动目标
	for pos in reachable:
		if pos == enemy.pos:
			continue  # 原地不算移动

		var candidate := ActionCandidate.new()
		candidate.type = ActionType.MOVE
		candidate.move_target = pos

		var score: float = 0.0
		var dist_to_player: int = BoardUtils.manhattan(pos, player.pos)
		var current_dist: int = BoardUtils.manhattan(enemy.pos, player.pos)

		# 靠近玩家加分（进攻型）
		var approach_value: float = float(current_dist - dist_to_player) * _w(profile, "w_approach", 5.0)
		score += approach_value

		# 远离玩家加分（猥琐型，如引力眼）
		if profile.get("prefer_distance", false):
			score += float(dist_to_player) * _w(profile, "w_keep_distance", 3.0)

		# 地块安全
		score += _evaluate_tile_safety(state, pos, profile)

		# 守卫型：靠近友军加分
		if profile.get("guard_ally", false):
			var nearest_ally_dist: int = _nearest_ally_distance(state, pos, enemy.uid)
			score += float(3 - nearest_ally_dist) * _w(profile, "w_guard_proximity", 4.0)

		candidate.score = score
		candidate.description = "移动到%s" % str(pos)
		results.append(candidate)

	return results


# ─── 路径权重构建 ───────────────────────────────────────────────────────────
static func _build_path_cost_profile(profile: Dictionary) -> Dictionary:
	return {
		"base_step_cost": _w(profile, "path_base_step_cost", 1.0),
		"spike_damage_weight": _w(profile, "path_spike_damage_weight", _w(profile, "w_self_damage", 8.0) * 0.25),
		"poison_damage_weight": _w(profile, "path_poison_damage_weight", _w(profile, "w_self_damage", 8.0) * 0.25),
		"water_cost_bias": _w(profile, "path_water_cost_bias", 0.0),
		"allow_partial_path": profile.get("allow_partial_path", true),
	}


# ─── 地块安全评估 ─────────────────────────────────────────────────────────
static func _evaluate_tile_safety(state: GameState, pos: Vector2i, profile: Dictionary) -> float:
	var score: float = 0.0
	var tile: TileState = state.get_tile(pos)
	if tile.tile_id == Constants.TILE_SPIKE:
		score -= float(Constants.SPIKE_DAMAGE) * _w(profile, "w_self_damage", 8.0)
	if tile.has_modifier("poison_fog"):
		score -= float(Constants.POISON_FOG_DAMAGE) * _w(profile, "w_self_damage", 8.0)
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
