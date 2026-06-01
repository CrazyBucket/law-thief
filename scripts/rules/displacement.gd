class_name Displacement
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


static func _is_forced_move_immune(state: GameState, unit: UnitState) -> bool:
	if unit.uid != state.player_uid:
		return false
	var registry := _relic_effect_registry()
	if registry == null:
		return false
	return bool(registry.query_modifier("forced_move_immune", state))

enum Direction { AWAY, TOWARD, NORTH, SOUTH, EAST, WEST }


static func knockback(
	state: GameState,
	unit: UnitState,
	origin: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = -1,
	skip_gem_hooks: bool = false
) -> void:
	if not unit.alive or steps <= 0:
		return
	if _is_forced_move_immune(state, unit):
		return
	_push_directional(state, unit, origin, Direction.AWAY, steps, source_uid, events, collision_damage, skip_gem_hooks)


static func pull_toward(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = -1,
	skip_gem_hooks: bool = false,
	skip_contact_hooks: bool = false
) -> void:
	if not unit.alive or steps <= 0:
		return
	if _is_forced_move_immune(state, unit):
		return
	_push_directional(state, unit, anchor, Direction.TOWARD, steps, source_uid, events, collision_damage, skip_gem_hooks, skip_contact_hooks)


## 冲刺：向目标位置冲刺指定步数，碰到阻挡时停在上一格，不触发碰撞伤
static func dash_toward(
	state: GameState,
	unit: UnitState,
	target_pos: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = 0,
	skip_gem_hooks: bool = false
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(state, unit, target_pos, Direction.TOWARD, steps, source_uid, events, collision_damage, skip_gem_hooks, true)


static func push_cardinal(
	state: GameState,
	unit: UnitState,
	direction: Direction,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = -1
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(state, unit, unit.pos, direction, steps, source_uid, events, collision_damage, false)


## 强制位移核心：按方向逐格推进，立即截停（不链推、不侧滑）
## collision_damage == -1 表示由实际位移格数自动计算（max(1, steps)）
## collision_damage == 0 表示无碰撞伤（冲刺）
static func _push_directional(
	state: GameState,
	unit: UnitState,
	reference_pos: Vector2i,
	dir: Direction,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int,
	skip_gem_hooks: bool = false,
	skip_contact_hooks: bool = false
) -> void:
	var start_pos := unit.pos
	var remaining := steps
	var i := 0

	while i < remaining:
		var step_vec := _step_vector(unit.pos, reference_pos, dir)
		if step_vec == Vector2i.ZERO:
			break
		var next := unit.pos + step_vec
		if next == unit.pos:
			break

		# ─── 越界撞墙 ───────────────────────────────────────────────────────
		if not _footprint_in_bounds(state, unit, next):
			var dmg := _resolve_collision_damage(collision_damage, i)
			if dmg > 0:
				_deal_unit_collision_damage(state, unit, source_uid, dmg, "wall_collision", events)
			break

		# ─── 撞静态实体（立即截停，按 max_hp 分单/双伤）───────────────────
		var entity := _blocking_entity_at_anchor(state, unit, next)
		if entity != null:
			var dmg := _resolve_collision_damage(collision_damage, i)
			EntityRules.on_unit_collide_entity(state, unit, entity, source_uid, events, dmg)
			break

		# ─── 撞可位移单位（立即截停，A/B 同伤，不链推）─────────────────────
		var blocker := _blocking_unit_at_anchor(state, unit, next)
		if blocker != null:
			var dmg := _resolve_collision_damage(collision_damage, i)
			if dmg > 0:
				_deal_unit_collision_damage(state, unit, source_uid, dmg, "unit_collision", events)
				_deal_unit_collision_damage(state, blocker, unit.uid, dmg, "unit_collision", events)
			if not skip_contact_hooks:
				_ContactResolver.on_collision(state, unit, blocker)
			break

		# ─── 正常移动一格 ───────────────────────────────────────────────────
		var from_pos := unit.pos
		unit.facing = UnitState.facing_from_step(from_pos, next)
		state.move_unit(unit, next)
		TileRules.on_unit_moved_through(state, unit, next)
		state.on_unit_move.emit(unit.uid, from_pos, next)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})

		var moved_tile := state.get_tile(next)
		var _ice_registry := _relic_effect_registry()
		var _ice_immune: bool = _ice_registry != null and bool(_ice_registry.query_modifier("tile_effect_immune", state))
		if not _ice_immune and moved_tile.has_ground_tag(Constants.GROUND_TAG_ICE):
			remaining += 1

		i += 1

	# ─── 位移结束后统一结算 ──────────────────────────────────────────────────
	if unit.pos != start_pos:
		TileRules.on_unit_position_changed(state, unit, start_pos)
		TileRules.on_unit_entered(state, unit, start_pos, {"forced": true, "source_uid": source_uid, "skip_overlay": true})
		state.on_forced_displacement.emit(unit.uid, start_pos, unit.pos, source_uid)
		if not skip_gem_hooks:
			GemEffects.on_forced_displacement(state, unit, events)


## 星状震飞落位：将 unit 从当前位置强制迁移到最近的合法空格（践踏 / 空间挤压共用）
## 先通过 find_star_relocation_cell 找合法格，找到则正常落位并结算地形
## 找不到则触发挤压惩罚伤害，然后留在原地（最终保底）
static func star_relocate(
	state: GameState,
	unit: UnitState,
	origin: Vector2i,
	source_uid: String,
	events: Array[Dictionary],
	skill_damage: int = 0
) -> void:
	if not unit.alive:
		return
	# 先施加技能本身的伤害（践踏伤害 + 1 点碰撞保底）
	if skill_damage > 0:
		_deal_unit_collision_damage(state, unit, source_uid, skill_damage, "trample", events)

	var result := BoardUtils.find_star_relocation_cell(state, origin, unit.uid)
	if result.get("found", false):
		var landing: Vector2i = result.get("pos", origin)
		var from_pos := unit.pos
		state.move_unit(unit, landing)
		state.on_unit_move.emit(unit.uid, from_pos, landing)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": landing})
		TileRules.on_unit_position_changed(state, unit, from_pos)
		# 落地后结算目标格地形（地刺、火焰、毒雾等）
		TileRules.on_unit_entered(state, unit, from_pos, {"forced": true, "source_uid": source_uid})
		state.on_forced_displacement.emit(unit.uid, from_pos, landing, source_uid)
		GemEffects.on_forced_displacement(state, unit, events)
	else:
		# 全堵死：空间挤压惩罚（按最大扫描半径距离伤害）
		var squeeze_dmg := 2
		_deal_unit_collision_damage(state, unit, source_uid, squeeze_dmg, "space_squeeze", events)
		state.log("%s 被挤压，无法逃离！" % unit.uid)


## 计算碰撞伤害：-1 表示按实际步数自动算，0 表示无伤，>0 表示固定值
static func _resolve_collision_damage(collision_damage: int, actual_steps: int) -> int:
	if collision_damage == 0:
		return 0
	if collision_damage < 0:
		return maxi(1, actual_steps)
	return collision_damage


static func _deal_unit_collision_damage(
	state: GameState,
	unit: UnitState,
	source_uid: String,
	amount: int,
	reason: String,
	events: Array[Dictionary]
) -> void:
	if not unit.alive or amount <= 0:
		return
	var registry := _relic_effect_registry()
	var final_amount := amount
	if registry != null:
		var mult: float = float(registry.query_modifier("collision_damage_mult", state))
		final_amount = maxi(1, int(float(amount) * mult))
	var dealt := CombatRules.apply_damage(state, unit, final_amount, source_uid, reason)
	if dealt > 0:
		events.append({"type": "damage", "pos": unit.pos, "damage": dealt, "is_crit": false})


static func _blocking_entity_at_anchor(state: GameState, unit: UnitState, anchor: Vector2i) -> EntityState:
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.blocks_movement():
			return entity
	return null


static func _blocking_unit_at_anchor(state: GameState, unit: UnitState, anchor: Vector2i) -> UnitState:
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var blocker := state.get_unit_at(cell)
		if blocker != null and blocker.uid != unit.uid:
			return blocker
	return null


static func _footprint_in_bounds(state: GameState, unit: UnitState, anchor: Vector2i) -> bool:
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		if not BoardUtils.in_bounds(state, cell):
			return false
	return true


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


static func _away_step(from: Vector2i, origin: Vector2i) -> Vector2i:
	var delta := from - origin
	if delta == Vector2i.ZERO:
		return Vector2i(1, 0)
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


static func _toward_step(from: Vector2i, anchor: Vector2i) -> Vector2i:
	var delta := anchor - from
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))
