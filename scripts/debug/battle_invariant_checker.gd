class_name BattleInvariantChecker
extends RefCounted

## 系统级不变量校验器
## 校验规则只在调试/测试路径中被主动调用，不污染正常游戏逻辑。


## 单次完整校验，返回所有违规条目。
## 空列表代表通过。
static func check_all(state: GameState) -> Array[String]:
	var violations: Array[String] = []
	_check_dead_units_not_occupying(state, violations)
	_check_no_cell_collision(state, violations)
	_check_occupancy_index_consistency(state, violations)
	_check_all_units_in_bounds(state, violations)
	_check_footprint_not_partially_out_of_bounds(state, violations)
	return violations


## 校验通过时断言，失败时 push_error 并返回 false。
## 用于测试脚本的 assert 替代，不中断执行。
static func assert_valid(state: GameState, context: String = "") -> bool:
	var violations := check_all(state)
	if violations.is_empty():
		return true
	var prefix := "[InvariantChecker]" if context.is_empty() else "[InvariantChecker:%s]" % context
	for v in violations:
		push_error("%s %s" % [prefix, v])
	return false


# ─── 具体校验规则 ──────────────────────────────────────────────────────────────

## 死亡单位不得继续占格
static func _check_dead_units_not_occupying(state: GameState, out: Array[String]) -> void:
	for uid in state.units:
		var unit: UnitState = state.units[uid]
		if unit.alive:
			continue
		for cell in unit.occupied_cells():
			var key := state.tile_key(cell)
			var occupant = state._cell_occupancy.get(key, null)
			if occupant != null and occupant.uid == unit.uid:
				out.append(
					"dead unit '%s' (%s) still occupies cell %s via _cell_occupancy" \
					% [uid, unit.unit_def_id, cell]
				)


## 同一格子不能同时被多个存活单位占用
static func _check_no_cell_collision(state: GameState, out: Array[String]) -> void:
	# 遍历所有存活单位的 occupied_cells，记录格子→单位映射
	var seen: Dictionary = {}
	for uid in state.units:
		var unit: UnitState = state.units[uid]
		if not unit.alive:
			continue
		for cell in unit.occupied_cells():
			var key := state.tile_key(cell)
			if seen.has(key):
				var other: UnitState = seen[key]
				out.append(
					"cell %s occupied by both '%s' (%s) and '%s' (%s)" \
					% [cell, uid, unit.unit_def_id, other.uid, other.unit_def_id]
				)
			else:
				seen[key] = unit


## 占格索引（_cell_occupancy）必须与单位的真实 occupied_cells 保持双向一致
static func _check_occupancy_index_consistency(state: GameState, out: Array[String]) -> void:
	# 正向：存活单位的每个 occupied_cells 都要出现在索引里
	for uid in state.units:
		var unit: UnitState = state.units[uid]
		if not unit.alive:
			continue
		for cell in unit.occupied_cells():
			var key := state.tile_key(cell)
			var indexed = state._cell_occupancy.get(key, null)
			if indexed == null:
				out.append(
					"unit '%s' (%s) occupies %s but _cell_occupancy has no entry for that cell" \
					% [uid, unit.unit_def_id, cell]
				)
			elif indexed.uid != uid:
				out.append(
					"_cell_occupancy[%s] points to '%s' but unit '%s' (%s) also claims that cell" \
					% [key, indexed.uid, uid, unit.unit_def_id]
				)

	# 反向：索引里的每个条目，单位必须存活且真的覆盖那个格子
	for key in state._cell_occupancy:
		var indexed_unit: UnitState = state._cell_occupancy[key]
		if indexed_unit == null:
			out.append("_cell_occupancy[%s] contains null" % key)
			continue
		var stored: UnitState = state.units.get(indexed_unit.uid, null)
		if stored == null:
			out.append(
				"_cell_occupancy[%s] references uid '%s' which is not in state.units" \
				% [key, indexed_unit.uid]
			)
			continue
		if not stored.alive:
			out.append(
				"_cell_occupancy[%s] references dead unit '%s' (%s)" \
				% [key, stored.uid, stored.unit_def_id]
			)
			continue
		var parts: PackedStringArray = key.split(",", false)
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			if not cell in stored.occupied_cells():
				out.append(
					"_cell_occupancy[%s] references unit '%s' but that unit does not occupy %s" \
					% [key, stored.uid, cell]
				)


## 所有存活单位的锚点 pos 必须在棋盘边界内
static func _check_all_units_in_bounds(state: GameState, out: Array[String]) -> void:
	for uid in state.units:
		var unit: UnitState = state.units[uid]
		if not unit.alive:
			continue
		if not BoardUtils.in_bounds(state, unit.pos):
			out.append(
				"unit '%s' (%s) pos %s is out of bounds (board %s)" \
				% [uid, unit.unit_def_id, unit.pos, state.board_size]
			)


## 多格单位 footprint 不允许部分格子越界
static func _check_footprint_not_partially_out_of_bounds(state: GameState, out: Array[String]) -> void:
	for uid in state.units:
		var unit: UnitState = state.units[uid]
		if not unit.alive:
			continue
		if unit.footprint_size == Vector2i(1, 1):
			continue
		for cell in unit.occupied_cells():
			if not BoardUtils.in_bounds(state, cell):
				out.append(
					"multi-cell unit '%s' (%s) footprint cell %s is out of bounds" \
					% [uid, unit.unit_def_id, cell]
				)
