class_name BoardUtils
extends RefCounted

const _MIN_STEP_COST: float = 1.0
const _FULL_PATH_BUDGET_FACTOR: float = 8.0
const _DEFAULT_PATH_COST_PROFILE := {
	"base_step_cost": 1.0,
	"spike_damage_weight": 0.4,
	"water_cost_bias": 0.0,
	"allow_partial_path": true,
}


static func in_bounds(state: GameState, pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < state.board_size.x and pos.y < state.board_size.y


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func spike_entity_at(state: GameState, pos: Vector2i) -> EntityState:
	var entity := state.get_entity_at(pos)
	if entity != null and entity.alive and entity.entity_id == Constants.ENTITY_SPIKE:
		return entity
	return null


static func blocking_entity_at(state: GameState, pos: Vector2i) -> EntityState:
	var entity := state.get_entity_at(pos)
	if entity != null and entity.alive and entity.blocks_movement():
		return entity
	return null


static func neighbors4(pos: Vector2i) -> Array[Vector2i]:
	return [
		pos + Vector2i(1, 0),
		pos + Vector2i(-1, 0),
		pos + Vector2i(0, 1),
		pos + Vector2i(0, -1),
	]


static func cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) <= radius:
				cells.append(center + Vector2i(dx, dy))
	return cells


## 从 origin 出发四连通泛洪，返回相连水域格（含毒水洼等带 ground:water 的地块）
static func water_cluster(state: GameState, origin: Vector2i) -> Array[Vector2i]:
	if not in_bounds(state, origin):
		return []
	var start := state.get_tile(origin)
	if start == null or not start.has_tile_tag(Constants.TAG_TILE_WATER):
		return []
	var result: Array[Vector2i] = []
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		var tile := state.get_tile(current)
		if tile == null or not tile.has_tile_tag(Constants.TAG_TILE_WATER):
			continue
		result.append(current)
		for neighbor in neighbors4(current):
			if not visited.has(neighbor) and in_bounds(state, neighbor):
				queue.append(neighbor)
	return result


## 水域导电范围：水域格 + 与任一格水域正交相邻的格子
static func water_conduction_zone(cluster: Array[Vector2i]) -> Dictionary:
	var zone: Dictionary = {}
	for cell in cluster:
		zone[cell] = true
		for neighbor in neighbors4(cell):
			zone[neighbor] = true
	return zone


static func is_passable(
	state: GameState,
	pos: Vector2i,
	ignore_uid: String = "",
	cell_blockers: Dictionary = {}
) -> bool:
	if not in_bounds(state, pos):
		return false
	var key := state.tile_key(pos)
	if cell_blockers.has(key):
		var blocker_uid: String = str(cell_blockers[key])
		if not blocker_uid.is_empty() and blocker_uid != ignore_uid:
			return false
	var unit := state.get_unit_at(pos)
	if unit != null and unit.uid != ignore_uid:
		return false
	var entity := state.get_entity_at(pos)
	if entity != null and entity.alive and entity.blocks_movement():
		return false
	return true


## 生成寻路权重配置（可通过 overrides 覆盖）
static func path_cost_profile(overrides: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = _DEFAULT_PATH_COST_PROFILE.duplicate(true)
	for key in overrides.keys():
		profile[key] = overrides[key]
	return profile


## 获取地块移动代价（用于 A* 和 reachable_cells）
## 保留旧接口，兼容历史调用
static func tile_move_cost(state: GameState, pos: Vector2i) -> float:
	return _step_cost_with_profile(state, pos, _DEFAULT_PATH_COST_PROFILE)


static func _step_cost_with_profile(state: GameState, pos: Vector2i, profile: Dictionary) -> float:
	var base_step: float = float(profile.get("base_step_cost", 1.0))
	var cost: float = base_step
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")
	var tile_immune: bool = registry != null and bool(registry.query_modifier("tile_effect_immune", state))
	var spike := spike_entity_at(state, pos)
	if spike != null:
		cost += float(Constants.SPIKE_DAMAGE) * float(profile.get("spike_damage_weight", 2.0))
	var tile: TileState = state.get_tile(pos)
	# 水洼（含毒水洼）：移动消耗 +1；夜鹭翅膀免疫
	if not tile_immune and (tile.has_ground_tag(Constants.GROUND_TAG_WATER) or tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE)):
		var water_cost := 1.0 + float(profile.get("water_cost_bias", 0.0))
		if registry != null:
			var reduce: int = int(registry.query_modifier("overlay_move_cost_reduction", state, {"overlay_type": "water"}))
			water_cost = maxf(0.0, water_cost - float(reduce))
		cost += water_cost
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG) \
	or tile.has_modifier(Constants.TILE_MOD_FIRE) \
	or tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		if registry != null:
			var overlay_type := "poison_fog"
			if tile.has_modifier(Constants.TILE_MOD_FIRE):
				overlay_type = "fire"
			var reduce: int = int(registry.query_modifier("overlay_move_cost_reduction", state, {"overlay_type": overlay_type}))
			cost = maxf(base_step, cost - float(reduce))
	return maxf(cost, _MIN_STEP_COST)


## A* 寻路：从 from_pos 到 to_pos，最多消耗 max_steps 步移动力
## 返回路径（不含起点），如果无法到达则返回在 max_steps 内最接近目标的路径
## moving_unit 不为 null 时启用多格 footprint 通道宽度校验（坑1）
static func astar_path(
	state: GameState,
	from_pos: Vector2i,
	to_pos: Vector2i,
	max_steps: int,
	ignore_uid: String = "",
	cost_profile: Dictionary = {},
	cell_blockers: Dictionary = {},
	moving_unit: UnitState = null
) -> Array[Vector2i]:
	if from_pos == to_pos:
		return [] as Array[Vector2i]
	var profile := path_cost_profile(cost_profile)
	var allow_partial: bool = bool(profile.get("allow_partial_path", true))
	var use_footprint: bool = moving_unit != null and moving_unit.footprint_size != Vector2i(1, 1)

	var open_set: Array[Vector2i] = [from_pos]
	var g_costs: Dictionary = {from_pos: 0.0}
	var f_costs: Dictionary = {from_pos: float(manhattan(from_pos, to_pos))}
	var parents: Dictionary = {}  # pos → parent pos
	var closed_set: Dictionary = {}

	# 记录在 max_steps 内可达的、离目标最近的节点
	var best_pos: Vector2i = from_pos
	var best_dist: int = manhattan(from_pos, to_pos)

	while not open_set.is_empty():
		# 找 f_cost 最小的节点
		var current: Vector2i = open_set[0]
		var current_f: float = f_costs[current]
		for i in range(1, open_set.size()):
			var f: float = f_costs[open_set[i]]
			if f < current_f:
				current = open_set[i]
				current_f = f
		open_set.erase(current)
		closed_set[current] = true

		# 到达目标
		if current == to_pos:
			best_pos = to_pos
			break

		var current_g: float = g_costs[current]

		for neighbor in neighbors4(current):
			if closed_set.has(neighbor):
				continue
			if not in_bounds(state, neighbor):
				continue
			# 多格单位：整体 footprint 都必须可通行（坑1 通道宽度）
			if use_footprint:
				if not unit_footprint_passable(state, moving_unit, neighbor, ignore_uid, cell_blockers):
					continue
			else:
				if not is_passable(state, neighbor, ignore_uid, cell_blockers):
					continue

			var step_cost: float = _step_cost_with_profile(state, neighbor, profile)
			var tentative_g: float = current_g + step_cost

			# 超过移动力上限则跳过
			if tentative_g > float(max_steps):
				continue

			if not g_costs.has(neighbor) or tentative_g < float(g_costs[neighbor]):
				g_costs[neighbor] = tentative_g
				parents[neighbor] = current
				var h: float = float(manhattan(neighbor, to_pos))
				f_costs[neighbor] = tentative_g + h
				if not open_set.has(neighbor):
					open_set.append(neighbor)

				# 更新最佳可达点
				var dist_to_target: int = manhattan(neighbor, to_pos)
				if dist_to_target < best_dist:
					best_dist = dist_to_target
					best_pos = neighbor

	# 不允许近似路径时，目标没到达则失败
	if not allow_partial and best_pos != to_pos:
		return [] as Array[Vector2i]

	# 回溯路径
	if best_pos == from_pos:
		return [] as Array[Vector2i]

	var path: Array[Vector2i] = []
	var trace: Vector2i = best_pos
	while trace != from_pos:
		path.append(trace)
		if not parents.has(trace):
			break
		trace = parents[trace]
	path.reverse()
	return path


## path_toward: 使用完整路径规划后再截断到本回合可走步数
## 这样在需要先横移/绕路时，也不会因为本回合没缩短曼哈顿距离而原地发呆
static func path_toward(
	state: GameState,
	from_pos: Vector2i,
	to_pos: Vector2i,
	max_steps: int,
	ignore_uid: String = "",
	cost_profile: Dictionary = {},
	cell_blockers: Dictionary = {},
	moving_unit: UnitState = null
) -> Array[Vector2i]:
	if from_pos == to_pos or max_steps <= 0:
		return [] as Array[Vector2i]
	var profile := path_cost_profile(cost_profile)
	var path_result := _best_full_path_toward(
		state, from_pos, to_pos, ignore_uid, profile, cell_blockers, moving_unit
	)
	if bool(path_result.get("ok", false)):
		var full_path: Array[Vector2i] = path_result.get("path", [] as Array[Vector2i])
		return _trim_path_to_budget(state, full_path, max_steps, profile)
	if not bool(profile.get("allow_partial_path", true)):
		return [] as Array[Vector2i]
	return astar_path(state, from_pos, to_pos, max_steps, ignore_uid, profile, cell_blockers, moving_unit)


static func _best_full_path_toward(
	state: GameState,
	from_pos: Vector2i,
	to_pos: Vector2i,
	ignore_uid: String,
	profile: Dictionary,
	cell_blockers: Dictionary,
	moving_unit: UnitState
) -> Dictionary:
	var use_footprint := moving_unit != null and moving_unit.footprint_size != Vector2i(1, 1)
	var goal_ok := is_passable(state, to_pos, ignore_uid, cell_blockers)
	if use_footprint:
		goal_ok = goal_ok and unit_footprint_passable(state, moving_unit, to_pos, ignore_uid, cell_blockers)
	var goals: Array[Vector2i] = []
	if goal_ok:
		goals.append(to_pos)
	else:
		goals = _path_goal_candidates(state, to_pos, ignore_uid, cell_blockers, moving_unit)
	if goals.is_empty():
		return {"ok": false, "path": [] as Array[Vector2i]}

	var full_profile := profile.duplicate(true)
	full_profile["allow_partial_path"] = false
	var full_budget := _full_path_budget(state, full_profile)
	var found := false
	var best_path: Array[Vector2i] = []
	var best_cost: float = 0.0
	var best_goal_dist := 0

	for goal in goals:
		var path := astar_path(
			state, from_pos, goal, full_budget, ignore_uid, full_profile, cell_blockers, moving_unit
		)
		if goal != from_pos and (path.is_empty() or path[path.size() - 1] != goal):
			continue
		var cost := _path_cost(state, path, full_profile)
		var goal_dist := manhattan(goal, to_pos)
		if not found \
		or cost < best_cost \
		or (is_equal_approx(cost, best_cost) and goal_dist < best_goal_dist) \
		or (is_equal_approx(cost, best_cost) and goal_dist == best_goal_dist and path.size() < best_path.size()):
			found = true
			best_path = path
			best_cost = cost
			best_goal_dist = goal_dist

	return {
		"ok": found,
		"path": best_path,
	}


static func _full_path_budget(state: GameState, profile: Dictionary) -> int:
	var cells := maxi(1, state.board_size.x * state.board_size.y)
	var base_cost := maxf(1.0, float(profile.get("base_step_cost", 1.0)))
	return int(ceili(float(cells) * base_cost * _FULL_PATH_BUDGET_FACTOR))


static func _path_cost(state: GameState, path: Array[Vector2i], profile: Dictionary) -> float:
	var total := 0.0
	for step in path:
		total += _step_cost_with_profile(state, step, profile)
	return total


static func _trim_path_to_budget(
	state: GameState,
	path: Array[Vector2i],
	max_steps: int,
	profile: Dictionary
) -> Array[Vector2i]:
	var trimmed: Array[Vector2i] = []
	var spent := 0.0
	for step in path:
		var step_cost := _step_cost_with_profile(state, step, profile)
		if spent + step_cost > float(max_steps):
			break
		spent += step_cost
		trimmed.append(step)
	return trimmed


static func _path_goal_candidates(
	state: GameState,
	to_pos: Vector2i,
	ignore_uid: String,
	cell_blockers: Dictionary,
	moving_unit: UnitState
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var use_footprint := moving_unit != null and moving_unit.footprint_size != Vector2i(1, 1)
	if use_footprint:
		var fp := moving_unit.footprint_size
		var search_radius := fp.x + fp.y + 3
		for ax in range(to_pos.x - search_radius, to_pos.x + search_radius + 1):
			for ay in range(to_pos.y - search_radius, to_pos.y + search_radius + 1):
				var anchor := Vector2i(ax, ay)
				if not in_bounds(state, anchor):
					continue
				if not unit_footprint_passable(state, moving_unit, anchor, ignore_uid, cell_blockers):
					continue
				if not _footprint_adjacent_to_cell(moving_unit, anchor, to_pos):
					continue
				if not candidates.has(anchor):
					candidates.append(anchor)
		return candidates

	for adj in neighbors4(to_pos):
		if not in_bounds(state, adj):
			continue
		if not is_passable(state, adj, ignore_uid, cell_blockers):
			continue
		if not candidates.has(adj):
			candidates.append(adj)
	return candidates


static func _footprint_adjacent_to_cell(unit: UnitState, anchor: Vector2i, cell: Vector2i) -> bool:
	for fc in footprint_cells_at(unit.footprint_size, anchor):
		if manhattan(fc, cell) <= 1:
			return true
	return false


## Dijkstra BFS 可达格子（考虑地块代价）
## moving_unit 不为 null 时对多格单位校验 footprint 全通行（坑1）
static func reachable_cells(
	state: GameState,
	start: Vector2i,
	move_points: int,
	ignore_uid: String = "",
	cost_profile: Dictionary = {},
	cell_blockers: Dictionary = {},
	moving_unit: UnitState = null
) -> Array[Vector2i]:
	var profile := path_cost_profile(cost_profile)
	var use_footprint: bool = moving_unit != null and moving_unit.footprint_size != Vector2i(1, 1)
	var visited: Dictionary = {start: 0.0}
	var queue: Array[Vector2i] = [start]
	var result: Array[Vector2i] = []
	while not queue.is_empty():
		# 简易优先队列：找最小 cost 的节点
		var min_idx: int = 0
		var min_cost: float = visited[queue[0]]
		for i in range(1, queue.size()):
			var c: float = visited[queue[i]]
			if c < min_cost:
				min_cost = c
				min_idx = i
		var current: Vector2i = queue[min_idx]
		queue.remove_at(min_idx)
		var dist: float = visited[current]
		if current != start:
			result.append(current)
		if dist >= float(move_points):
			continue
		for neighbor in neighbors4(current):
			if not in_bounds(state, neighbor):
				continue
			# 多格单位：整体 footprint 通道宽度校验
			if use_footprint:
				if not unit_footprint_passable(state, moving_unit, neighbor, ignore_uid, cell_blockers):
					continue
			else:
				if not is_passable(state, neighbor, ignore_uid, cell_blockers):
					continue
			var cost: float = _step_cost_with_profile(state, neighbor, profile)
			var new_dist: float = dist + cost
			if new_dist > float(move_points):
				continue
			if visited.has(neighbor) and float(visited[neighbor]) <= new_dist:
				continue
			visited[neighbor] = new_dist
			queue.append(neighbor)
	return result


## ─── 多格单位（footprint）专用工具 ──────────────────────────────────────────

## 检查 unit 的整个 footprint 从 anchor_pos 出发是否全部可通行
## anchor_pos 为目标锚点（左上角），ignore_uid 为该单位自身（排除自占）
static func unit_footprint_passable(
	state: GameState,
	unit: UnitState,
	anchor_pos: Vector2i,
	ignore_uid: String = "",
	cell_blockers: Dictionary = {}
) -> bool:
	for dx in range(unit.footprint_size.x):
		for dy in range(unit.footprint_size.y):
			if not is_passable(state, anchor_pos + Vector2i(dx, dy), ignore_uid, cell_blockers):
				return false
	return true


static func are_units_adjacent(unit_a: UnitState, unit_b: UnitState) -> bool:
	return distance_between_units(unit_a, unit_b) == 1


static func footprint_cells_at(footprint: Vector2i, anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(footprint.x):
		for dy in range(footprint.y):
			cells.append(anchor + Vector2i(dx, dy))
	return cells


static func footprint_cells_for_unit_at(unit: UnitState, anchor: Vector2i) -> Array[Vector2i]:
	if unit == null:
		return [] as Array[Vector2i]
	return footprint_cells_at(unit.footprint_size, anchor)


## 计算两个单位之间的最短曼哈顿距离（多格单位取占格间最小值）
static func distance_between_units(unit_a: UnitState, unit_b: UnitState) -> int:
	if unit_a.footprint_size == Vector2i(1, 1) and unit_b.footprint_size == Vector2i(1, 1):
		return manhattan(unit_a.pos, unit_b.pos)
	var min_dist: int = 999999
	for ca in unit_a.occupied_cells():
		for cb in unit_b.occupied_cells():
			var d := manhattan(ca, cb)
			if d < min_dist:
				min_dist = d
	return min_dist


static func distance_between_unit_at_and_unit(unit_a: UnitState, anchor_a: Vector2i, unit_b: UnitState) -> int:
	if unit_a == null or unit_b == null:
		return 999999
	if unit_a.footprint_size == Vector2i(1, 1) and unit_b.footprint_size == Vector2i(1, 1):
		return manhattan(anchor_a, unit_b.pos)
	var min_dist: int = 999999
	for ca in footprint_cells_for_unit_at(unit_a, anchor_a):
		for cb in unit_b.occupied_cells():
			var d := manhattan(ca, cb)
			if d < min_dist:
				min_dist = d
	return min_dist


static func distance_between_unit_at_and_cell(unit: UnitState, anchor: Vector2i, cell: Vector2i) -> int:
	if unit == null:
		return 999999
	if unit.footprint_size == Vector2i(1, 1):
		return manhattan(anchor, cell)
	var min_dist: int = 999999
	for occupied in footprint_cells_for_unit_at(unit, anchor):
		var d := manhattan(occupied, cell)
		if d < min_dist:
			min_dist = d
	return min_dist


static func are_units_adjacent_at(unit_a: UnitState, anchor_a: Vector2i, unit_b: UnitState) -> bool:
	return distance_between_unit_at_and_unit(unit_a, anchor_a, unit_b) == 1


## 占格间最短切比雪夫距离（分裂宝石「周围 N 格」等范围判定）
static func chebyshev_between_units(unit_a: UnitState, unit_b: UnitState) -> int:
	if unit_a.footprint_size == Vector2i(1, 1) and unit_b.footprint_size == Vector2i(1, 1):
		return chebyshev(unit_a.pos, unit_b.pos)
	var min_dist: int = 999999
	for ca in unit_a.occupied_cells():
		for cb in unit_b.occupied_cells():
			var d := chebyshev(ca, cb)
			if d < min_dist:
				min_dist = d
	return min_dist


static func is_within_surround(unit: UnitState, other: UnitState, radius: int) -> bool:
	return chebyshev_between_units(unit, other) <= radius


static func is_within_manhattan_range_of_cell(from_pos: Vector2i, cell: Vector2i, max_range: int) -> bool:
	return manhattan(from_pos, cell) <= max_range


static func can_unit_reach_unit(attacker: UnitState, target: UnitState, max_range: int) -> bool:
	return distance_between_units(attacker, target) <= max_range


static func can_unit_reach_unit_at(attacker: UnitState, anchor: Vector2i, target: UnitState, max_range: int) -> bool:
	return distance_between_unit_at_and_unit(attacker, anchor, target) <= max_range


static func can_unit_attack_cell(attacker: UnitState, state: GameState, cell: Vector2i, max_range: int) -> bool:
	var target := state.get_unit_at(cell)
	if target != null and target.alive and target.uid != attacker.uid:
		return can_unit_reach_unit(attacker, target, max_range)
	return is_within_manhattan_range_of_cell(attacker.pos, cell, max_range)


static func can_unit_attack_cell_at(
	attacker: UnitState,
	state: GameState,
	anchor: Vector2i,
	cell: Vector2i,
	max_range: int
) -> bool:
	var target := state.get_unit_at(cell)
	if target != null and target.alive and target.uid != attacker.uid:
		return can_unit_reach_unit_at(attacker, anchor, target, max_range)
	return distance_between_unit_at_and_cell(attacker, anchor, cell) <= max_range


## 检查 unit 的整个 footprint 向 direction 平移一步后是否合法（用于推拉校验）
static func can_unit_push_to(
	state: GameState,
	unit: UnitState,
	direction: Vector2i,
	cell_blockers: Dictionary = {}
) -> bool:
	var new_anchor := unit.pos + direction
	return unit_footprint_passable(state, unit, new_anchor, unit.uid, cell_blockers)


## 星状外扩落点搜索：以 origin 为震中，按距离 1→2 逐圈扫描合法空格
## 距离 1：先四正交（上/下/左/右），再四对角
## 距离 2：外圈 12 格（按环形顺序）
## ignore_uid：被腾挪单位自身，排除自占
## 返回第一个合法空格；若全堵死返回 origin
static func find_star_relocation_cell(
	state: GameState,
	origin: Vector2i,
	ignore_uid: String = ""
) -> Dictionary:
	const _RING1: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	for offset in _RING1:
		var candidate := origin + offset
		if not in_bounds(state, candidate):
			continue
		if is_passable(state, candidate, ignore_uid):
			return {"found": true, "pos": candidate, "dist": 1}
	const _RING2: Array[Vector2i] = [
		Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2),
		Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
		Vector2i(1, 2), Vector2i(0, 2), Vector2i(-1, 2), Vector2i(-2, 2),
		Vector2i(-2, 1), Vector2i(-2, 0), Vector2i(-2, -1), Vector2i(-2, -2),
		Vector2i(-1, -2),
	]
	for offset in _RING2:
		var candidate := origin + offset
		if not in_bounds(state, candidate):
			continue
		if is_passable(state, candidate, ignore_uid):
			return {"found": true, "pos": candidate, "dist": 2}
	return {"found": false, "pos": origin, "dist": 0}


## 旧接口保留兼容：贪心单步（仅 pull 技能等内部使用）
static func step_toward(from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	var delta := to_pos - from_pos
	if delta == Vector2i.ZERO:
		return from_pos
	var step := Vector2i(signi(delta.x), signi(delta.y))
	if absi(delta.x) > absi(delta.y):
		step = Vector2i(signi(delta.x), 0)
	elif absi(delta.y) > absi(delta.x):
		step = Vector2i(0, signi(delta.y))
	return from_pos + step


static func cells_toward(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if from_pos == to_pos:
		return cells
	var current := from_pos
	while current != to_pos:
		current = step_toward(current, to_pos)
		cells.append(current)
	return cells


## Bresenham 直线光栅化：返回从 from_pos 到 to_pos 之间所有格子（不含起点，含终点）
## 用于射线/LOS 检测，避免贪心步进在非正交方向走错路径
static func los_cells_between(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if from_pos == to_pos:
		return cells
	var dx := absi(to_pos.x - from_pos.x)
	var dy := absi(to_pos.y - from_pos.y)
	var sx := signi(to_pos.x - from_pos.x)
	var sy := signi(to_pos.y - from_pos.y)
	var x := from_pos.x
	var y := from_pos.y
	var err := dx - dy
	while true:
		if x == to_pos.x and y == to_pos.y:
			cells.append(Vector2i(x, y))
			break
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		cells.append(Vector2i(x, y))
	return cells


static func projectile_origin_cell(attacker: UnitState, target_pos: Vector2i) -> Vector2i:
	if attacker == null:
		return target_pos
	return projectile_origin_cell_at(attacker, attacker.pos, target_pos)


static func projectile_origin_cell_at(attacker: UnitState, anchor: Vector2i, target_pos: Vector2i) -> Vector2i:
	if attacker == null:
		return target_pos
	if attacker.footprint_size == Vector2i(1, 1):
		return anchor
	var best := anchor
	var best_dist := 999999
	for cell in footprint_cells_for_unit_at(attacker, anchor):
		var dist := chebyshev(cell, target_pos)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


static func resolve_projectile_impact(state: GameState, from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	for cell in los_cells_between(from_pos, to_pos):
		if cell == to_pos:
			break
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.blocks_projectile():
			return cell
	return to_pos


static func projectile_blocked_before_aim(
	state: GameState,
	from_pos: Vector2i,
	aim_cell: Vector2i
) -> bool:
	return resolve_projectile_impact(state, from_pos, aim_cell) != aim_cell


## 到目标格的最短寻路步数；若已在可攻击位则返回 0，不可达时返回 -1
static func path_distance_to_cell(
	state: GameState,
	from_pos: Vector2i,
	to_pos: Vector2i,
	ignore_uid: String = "",
	cell_blockers: Dictionary = {},
	moving_unit: UnitState = null
) -> int:
	if from_pos == to_pos:
		return 0
	var path_result := _best_full_path_toward(
		state,
		from_pos,
		to_pos,
		ignore_uid,
		path_cost_profile(),
		cell_blockers,
		moving_unit
	)
	if not bool(path_result.get("ok", false)):
		return -1
	var path: Array[Vector2i] = path_result.get("path", [] as Array[Vector2i])
	return path.size()
