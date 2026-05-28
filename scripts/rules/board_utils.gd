class_name BoardUtils
extends RefCounted

const _MIN_STEP_COST: float = 0.05
const _DEFAULT_PATH_COST_PROFILE := {
	"base_step_cost": 1.0,
	"spike_damage_weight": 0.4,
	"poison_damage_weight": 0.35,
	"water_cost_bias": 0.0,
	"allow_partial_path": true,
}


static func in_bounds(state: GameState, pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < state.board_size.x and pos.y < state.board_size.y


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


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
	var tile: TileState = state.get_tile(pos)
	match tile.tile_id:
		Constants.TILE_SPIKE:
			cost += float(Constants.SPIKE_DAMAGE) * float(profile.get("spike_damage_weight", 2.0))
		_:
			pass
	# 水洼（含毒水洼）：移动消耗 +1
	if tile.has_ground_tag(Constants.GROUND_TAG_WATER) or tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE):
		cost += 1.0 + float(profile.get("water_cost_bias", 0.0))
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
		cost += float(Constants.POISON_FOG_DAMAGE) * float(profile.get("poison_damage_weight", 2.0))
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


## path_toward: 使用 A* 寻路（替代旧的贪心直线算法）
## 用于敌人 AI 移动——目标可能被占据（如玩家位置），寻路到最近可达点
## moving_unit 不为 null 时传递给 astar_path 做 footprint 通道宽度校验
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
	# 如果目标被占据，寻路到目标的邻接格中最近的那个
	if not is_passable(state, to_pos, ignore_uid, cell_blockers):
		var best_neighbor: Vector2i = from_pos
		var best_dist: int = manhattan(from_pos, to_pos)
		for adj in neighbors4(to_pos):
			if not in_bounds(state, adj):
				continue
			if not is_passable(state, adj, ignore_uid, cell_blockers) and adj != from_pos:
				continue
			var d: int = manhattan(from_pos, adj)
			if d < best_dist:
				best_dist = d
				best_neighbor = adj
		if best_neighbor == from_pos:
			return [] as Array[Vector2i]
		return astar_path(state, from_pos, best_neighbor, max_steps, ignore_uid, cost_profile, cell_blockers, moving_unit)
	return astar_path(state, from_pos, to_pos, max_steps, ignore_uid, cost_profile, cell_blockers, moving_unit)


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


## 计算两个单位之间的最短曼哈顿距离（坑3：多格受击距离语义）
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


## 检查 unit 的整个 footprint 向 direction 平移一步后是否合法（用于推拉校验）
static func can_unit_push_to(
	state: GameState,
	unit: UnitState,
	direction: Vector2i,
	cell_blockers: Dictionary = {}
) -> bool:
	var new_anchor := unit.pos + direction
	return unit_footprint_passable(state, unit, new_anchor, unit.uid, cell_blockers)


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
