class_name BoardUtils
extends RefCounted


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


static func is_passable(state: GameState, pos: Vector2i, ignore_uid: String = "") -> bool:
	if not in_bounds(state, pos):
		return false
	var unit := state.get_unit_at(pos)
	if unit != null and unit.uid != ignore_uid:
		return false
	return true


## 获取地块移动代价（用于 A* 和 reachable_cells）
## 普通地板=1，陷阱=3（优先绕开），不可通行=INF
static func tile_move_cost(state: GameState, pos: Vector2i) -> float:
	var tile: TileState = state.get_tile(pos)
	match tile.tile_id:
		Constants.TILE_SPIKE:
			return 3.0
		_:
			pass
	if tile.has_modifier("poison_fog"):
		return 3.0
	return 1.0


## A* 寻路：从 from_pos 到 to_pos，最多消耗 max_steps 步移动力
## 返回路径（不含起点），如果无法到达则返回在 max_steps 内最接近目标的路径
## avoid_occupied: 是否绕开有单位的格子（默认 true）
static func astar_path(state: GameState, from_pos: Vector2i, to_pos: Vector2i, max_steps: int, ignore_uid: String = "", avoid_occupied: bool = true) -> Array[Vector2i]:
	if from_pos == to_pos:
		return [] as Array[Vector2i]

	# A* open set: {pos: {g_cost, parent, f_cost}}
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
			# 可通行性检查：目标格允许站（即使有单位也可以作为终点寻路目标）
			if avoid_occupied and neighbor != to_pos:
				if not is_passable(state, neighbor, ignore_uid):
					continue
			elif not avoid_occupied:
				if not in_bounds(state, neighbor):
					continue
			else:
				# neighbor == to_pos 时，允许寻路到目标（即使有单位占据）
				if not in_bounds(state, neighbor):
					continue

			var step_cost: float = tile_move_cost(state, neighbor)
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
## 返回从 from_pos 朝 to_pos 移动的路径，最多 max_steps 步
static func path_toward(state: GameState, from_pos: Vector2i, to_pos: Vector2i, max_steps: int, ignore_uid: String = "") -> Array[Vector2i]:
	return astar_path(state, from_pos, to_pos, max_steps, ignore_uid, true)


## BFS 可达格子（考虑地块代价）
static func reachable_cells(state: GameState, start: Vector2i, move_points: int, ignore_uid: String = "") -> Array[Vector2i]:
	var visited: Dictionary = {start: 0.0}
	var queue: Array = [start]
	var result: Array[Vector2i] = []
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var dist: float = visited[current]
		if dist > 0.0:
			result.append(current)
		if dist >= float(move_points):
			continue
		for neighbor in neighbors4(current):
			if not in_bounds(state, neighbor):
				continue
			if not is_passable(state, neighbor, ignore_uid):
				continue
			var cost: float = tile_move_cost(state, neighbor)
			var new_dist: float = dist + cost
			if new_dist > float(move_points):
				continue
			if visited.has(neighbor) and float(visited[neighbor]) <= new_dist:
				continue
			visited[neighbor] = new_dist
			queue.append(neighbor)
	return result


## 旧接口保留兼容：贪心单步（仅内部使用）
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
