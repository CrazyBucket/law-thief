class_name Displacement
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")

# ─── 强制位移组件 ─────────────────────────────────────────────────────────────
#
# 所有"强制移动"行为的统一入口。
# 设计为可独立调用的静态方法，任何系统（宝石、爆炸、技能）均可挂载。
#
# 核心理念：
#   - 提供方向枚举（Away / Toward / Cardinal）
#   - 每种 knockback 方式都可单独调用，也可通过 apply() 统一入口
#   - 附带碰撞检测：撞墙或撞单位时结算碰撞伤害（可选）
#   - 全程返回 move_step 事件列表，由上层收集

# 位移方向枚举
enum Direction { AWAY, TOWARD, NORTH, SOUTH, EAST, WEST }


## 将 unit 从 origin 方向击退 steps 格（推离 origin）
## skip_gem_hooks: 传 true 时不触发位移后宝石钩子（防止爆炸链式递归）
static func knockback(
	state: GameState,
	unit: UnitState,
	origin: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = Constants.KNOCKBACK_COLLISION_DAMAGE,
	skip_gem_hooks: bool = false
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(state, unit, origin, Direction.AWAY, steps, source_uid, events, collision_damage, skip_gem_hooks)


## 将 unit 向 anchor 方向拉近 steps 格
static func pull_toward(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = Constants.KNOCKBACK_COLLISION_DAMAGE,
	skip_gem_hooks: bool = false
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(state, unit, anchor, Direction.TOWARD, steps, source_uid, events, collision_damage, skip_gem_hooks)


## 将 unit 向指定方向推 steps 格（用于机关/陷阱等固定方向）
static func push_cardinal(
	state: GameState,
	unit: UnitState,
	direction: Direction,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = Constants.KNOCKBACK_COLLISION_DAMAGE
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(state, unit, unit.pos, direction, steps, source_uid, events, collision_damage)


## 统一位移执行核心
static func _push_directional(
	state: GameState,
	unit: UnitState,
	reference_pos: Vector2i,
	dir: Direction,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int,
	skip_gem_hooks: bool = false
) -> void:
	var start_pos := unit.pos
	var remaining := steps
	var i := 0
	var is_large := unit.footprint_size != Vector2i(1, 1)

	while i < remaining:
		var step_vec := _step_vector(unit.pos, reference_pos, dir)
		var next := unit.pos + step_vec
		if next == unit.pos:
			break

		# 边界检查（多格单位检查整个 footprint 是否越界）
		var next_in_bounds := true
		if is_large:
			for dx in range(unit.footprint_size.x):
				for dy in range(unit.footprint_size.y):
					if not BoardUtils.in_bounds(state, next + Vector2i(dx, dy)):
						next_in_bounds = false
						break
		else:
			next_in_bounds = BoardUtils.in_bounds(state, next)

		if not next_in_bounds:
			if collision_damage > 0:
				_deal_collision_damage(state, unit, source_uid, collision_damage, "wall_collision", events)
			break

		# 实体碰撞（只对锚点格检测，大单位也触发同类逻辑）
		var entity := state.get_entity_at(next)
		if entity != null and entity.alive and entity.blocks_movement():
			EntityRules.on_unit_collide_entity(state, unit, entity, source_uid, events)
			break

		# 碰撞检测：多格单位检查整个 footprint，找第一个阻挡者
		var blocker: UnitState = null
		if is_large:
			for cell in _footprint_at(unit, next):
				var b := state.get_unit_at(cell)
				if b != null and b.uid != unit.uid:
					blocker = b
					break
		else:
			blocker = state.get_unit_at(next)

		if blocker != null:
			if collision_damage > 0:
				_deal_collision_damage(state, unit, source_uid, collision_damage, "knockback_collision", events)
				_deal_collision_damage(state, blocker, unit.uid, collision_damage, "knockback_collision", events)
			_ContactResolver.on_collision(state, unit, blocker)
			break

		var from_pos := unit.pos
		unit.facing = UnitState.facing_from_step(from_pos, next)
		state.move_unit(unit, next)
		TileRules.on_unit_moved_through(state, unit, next)
		state.on_unit_move.emit(unit.uid, from_pos, next)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})

		# 冰面：额外 +1 格滑行（remaining 扩大，不消耗本格步数）
		var moved_tile := state.get_tile(next)
		if moved_tile.has_ground_tag(Constants.GROUND_TAG_ICE):
			remaining += 1

		i += 1

	if unit.pos != start_pos:
		TileRules.on_unit_position_changed(state, unit, start_pos)
		TileRules.on_unit_entered(state, unit, start_pos)
		if not skip_gem_hooks:
			GemEffects.on_forced_displacement(state, unit, events)


## 返回该方向的单步向量（不含当前位置，供 +step_vec 使用）
static func _step_vector(current: Vector2i, reference: Vector2i, dir: Direction) -> Vector2i:
	match dir:
		Direction.AWAY:
			return _away_step(current, reference)
		Direction.TOWARD:
			return _toward_step(current, reference)
		Direction.NORTH:
			return Vector2i(0, -1)
		Direction.SOUTH:
			return Vector2i(0, 1)
		Direction.EAST:
			return Vector2i(1, 0)
		Direction.WEST:
			return Vector2i(-1, 0)
	return Vector2i.ZERO


## 旧接口保留兼容（避免外部调用断层）
static func _resolve_next_cell(current: Vector2i, reference: Vector2i, dir: Direction) -> Vector2i:
	return current + _step_vector(current, reference, dir)


## 返回 unit footprint 移到 anchor_pos 时覆盖的所有格子
static func _footprint_at(unit: UnitState, anchor_pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(unit.footprint_size.x):
		for dy in range(unit.footprint_size.y):
			cells.append(anchor_pos + Vector2i(dx, dy))
	return cells


## 推离方向步长（优先主轴分量）
static func _away_step(from: Vector2i, origin: Vector2i) -> Vector2i:
	var delta := from - origin
	if delta == Vector2i.ZERO:
		return Vector2i(1, 0)  # 同位时随机给个方向
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## 拉近方向步长
static func _toward_step(from: Vector2i, anchor: Vector2i) -> Vector2i:
	var delta := anchor - from
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## 碰撞结算（伤害 + 事件）
static func _deal_collision_damage(
	state: GameState,
	unit: UnitState,
	source_uid: String,
	amount: int,
	reason: String,
	events: Array[Dictionary]
) -> void:
	if not unit.alive or amount <= 0:
		return
	var dealt := CombatRules.apply_damage(state, unit, amount, source_uid, reason)
	if dealt > 0:
		events.append({"type": "damage", "pos": unit.pos, "damage": dealt, "is_crit": false})
