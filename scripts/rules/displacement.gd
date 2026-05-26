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

	for _i in range(steps):
		var next := _resolve_next_cell(unit.pos, reference_pos, dir)
		if next == unit.pos:
			break  # 无法继续移动（同位）

		if not BoardUtils.in_bounds(state, next):
			# 撞边界：结算碰撞伤害后停止
			if collision_damage > 0:
				_deal_collision_damage(state, unit, source_uid, collision_damage, "wall_collision", events)
			break

		var blocker: UnitState = state.get_unit_at(next)
		if blocker != null:
			# 撞单位：双方碰撞伤害 + 接触钩子
			if collision_damage > 0:
				_deal_collision_damage(state, unit, source_uid, collision_damage, "knockback_collision", events)
				_deal_collision_damage(state, blocker, unit.uid, collision_damage, "knockback_collision", events)
			_ContactResolver.on_collision(state, unit, blocker)
			break

		var from_pos := unit.pos
		unit.pos = next
		TileRules.on_unit_moved_through(state, unit, next)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})

	if unit.pos != start_pos:
		# 统一坐标变化入口：离开火焰时清零 burning
		TileRules.on_unit_position_changed(state, unit, start_pos)
		TileRules.on_unit_entered(state, unit, start_pos)
		if not skip_gem_hooks:
			GemEffects.on_forced_displacement(state, unit, events)


## 计算下一格坐标
static func _resolve_next_cell(current: Vector2i, reference: Vector2i, dir: Direction) -> Vector2i:
	match dir:
		Direction.AWAY:
			# 推离 reference：delta 方向取反
			return current + _away_step(current, reference)
		Direction.TOWARD:
			# 拉向 reference
			return current + _toward_step(current, reference)
		Direction.NORTH:
			return current + Vector2i(0, -1)
		Direction.SOUTH:
			return current + Vector2i(0, 1)
		Direction.EAST:
			return current + Vector2i(1, 0)
		Direction.WEST:
			return current + Vector2i(-1, 0)
	return current


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
