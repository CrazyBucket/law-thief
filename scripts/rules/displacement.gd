class_name Displacement
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")


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
	skip_gem_hooks: bool = false,
	damage_context: Dictionary = {}
) -> void:
	if not unit.alive or steps <= 0:
		return
	if _is_forced_move_immune(state, unit):
		return
	_push_directional(
		state, unit, origin, Direction.AWAY, steps, source_uid, events,
		collision_damage, skip_gem_hooks, false, damage_context
	)


static func pull_toward(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = -1,
	skip_gem_hooks: bool = false,
	skip_contact_hooks: bool = false,
	damage_context: Dictionary = {}
) -> void:
	if not unit.alive or steps <= 0:
		return
	if _is_forced_move_immune(state, unit):
		return
	_push_directional(
		state, unit, anchor, Direction.TOWARD, steps, source_uid, events,
		collision_damage, skip_gem_hooks, skip_contact_hooks, damage_context
	)


## 冲刺：向目标位置冲刺指定步数，碰到阻挡时停在上一格，不触发碰撞伤
static func dash_toward(
	state: GameState,
	unit: UnitState,
	target_pos: Vector2i,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = 0,
	skip_gem_hooks: bool = false,
	damage_context: Dictionary = {}
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(
		state, unit, target_pos, Direction.TOWARD, steps, source_uid, events,
		collision_damage, skip_gem_hooks, true, damage_context
	)


static func push_cardinal(
	state: GameState,
	unit: UnitState,
	direction: Direction,
	steps: int,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int = -1,
	damage_context: Dictionary = {}
) -> void:
	if not unit.alive or steps <= 0:
		return
	_push_directional(
		state, unit, unit.pos, direction, steps, source_uid, events,
		collision_damage, false, false, damage_context
	)


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
	skip_contact_hooks: bool = false,
	damage_context: Dictionary = {}
) -> void:
	var start_pos := unit.pos
	var remaining := steps
	var i := 0
	var tx := _CombatTransaction.begin(state, events).bind_event_sink()

	while i < remaining:
		var step_vec := _step_vector(unit, reference_pos, dir)
		if step_vec == Vector2i.ZERO:
			break
		var next := unit.pos + step_vec
		if next == unit.pos:
			break

		# ─── 越界撞墙 ───────────────────────────────────────────────────────
		if not _footprint_in_bounds(state, unit, next):
			_append_collision_motion(events, unit, next, source_uid, "wall_collision", "boundary")
			var dmg := _resolve_collision_damage(collision_damage, i)
			if dmg > 0:
				_deal_unit_collision_damage(
					state, unit, source_uid, dmg, "wall_collision", events, damage_context
				)
			break

		# ─── 撞静态实体（立即截停，按 max_hp 分单/双伤）───────────────────
		var blocking_entities := _blocking_entities_at_anchor(state, unit, next)
		if not blocking_entities.is_empty():
			var dmg := _resolve_collision_damage(collision_damage, i)
			for entity in blocking_entities:
				_append_collision_motion(
					events, unit, next, source_uid, "entity_collision", "entity", entity.uid, entity.entity_id
				)
			if dmg > 0:
				_deal_unit_collision_damage(
					state, unit, source_uid, dmg, "entity_collision", events, damage_context
				)
				for entity in blocking_entities:
					if entity.max_hp > 0:
						EntityRules.damage_entity(state, entity, dmg, source_uid, events)
			break

		# ─── 撞可位移单位（立即截停，A/B 同伤，不链推）─────────────────────
		var blocking_units := _blocking_units_at_anchor(state, unit, next)
		if not blocking_units.is_empty():
			for blocker in blocking_units:
				_append_collision_motion(
					events, unit, next, source_uid, "unit_collision", "unit", blocker.uid
				)
			var dmg := _resolve_collision_damage(collision_damage, i)
			if dmg > 0:
				_deal_unit_collision_damage(
					state, unit, source_uid, dmg, "unit_collision", events, damage_context
				)
				for blocker in blocking_units:
					_deal_unit_collision_damage(
						state, blocker, unit.uid, dmg, "unit_collision", events, damage_context
					)
			if not skip_contact_hooks:
				for blocker in blocking_units:
					_ContactResolver.on_collision(state, unit, blocker)
			break

		# ─── 正常移动一格 ───────────────────────────────────────────────────
		var from_pos := unit.pos
		tx.move_unit(unit, next, {"emit_signal": false, "emit_event": false})
		TileRules.on_unit_moved_through(state, unit, next, {
			"forced": true,
			"source_uid": source_uid,
			"damage_context": damage_context,
		})
		state.on_unit_move.emit(unit.uid, from_pos, next)
		events.append(_EventBuilder.move_step(unit.uid, from_pos, next, {
			"forced": true,
			"source_uid": source_uid,
			"reason": "forced_displacement",
		}))

		var _ice_registry := _relic_effect_registry()
		var _ice_immune: bool = _ice_registry != null and bool(_ice_registry.query_modifier("tile_effect_immune", state))
		if not _ice_immune and _footprint_has_ground_tag(state, unit, Constants.GROUND_TAG_ICE):
			remaining += 1

		i += 1

	# ─── 位移结束后统一结算 ──────────────────────────────────────────────────
	if unit.pos != start_pos:
		TileRules.on_unit_position_changed(state, unit, start_pos, {"forced": true})
		TileRules.on_unit_entered(state, unit, start_pos, {
			"forced": true,
			"source_uid": source_uid,
			"damage_context": damage_context,
		})
		state.on_forced_displacement.emit(unit.uid, start_pos, unit.pos, source_uid)
		if not skip_gem_hooks:
			GemEffects.on_forced_displacement(state, unit, events)
	tx.finish("Displacement._push_directional")


static func _append_collision_motion(
	events: Array[Dictionary],
	unit: UnitState,
	contact_pos: Vector2i,
	source_uid: String,
	reason: String,
	blocker_kind: String,
	blocker_uid: String = "",
	entity_id: String = ""
) -> void:
	events.append(_EventBuilder.displacement_impact(unit.uid, unit.pos, contact_pos, {
		"source_uid": source_uid,
		"reason": reason,
		"blocker_kind": blocker_kind,
		"blocker_uid": blocker_uid,
		"entity_id": entity_id,
	}))


## 星状震飞落位：将 unit 从当前位置强制迁移到最近的合法空格（践踏 / 空间挤压共用）
## 先通过 find_star_relocation_cell 找合法格，找到则正常落位并结算地形
## 找不到则触发挤压惩罚伤害，然后留在原地（最终保底）
static func star_relocate(
	state: GameState,
	unit: UnitState,
	origin: Vector2i,
	source_uid: String,
	events: Array[Dictionary],
	opts: Dictionary = {}
) -> void:
	if not unit.alive:
		return
	var initial_damage := int(opts.get("initial_damage", 0))
	var damage_context: Dictionary = opts.get("damage_context", {})
	var tx := _CombatTransaction.begin(state, events).bind_event_sink()
	# 先施加调用方已组合的技能与碰撞伤害。
	if initial_damage > 0:
		_deal_unit_collision_damage(
			state, unit, source_uid, initial_damage, "trample", events, damage_context
		)

	var result := BoardUtils.find_star_relocation_cell(state, origin, unit.uid)
	if result.get("found", false):
		var landing: Vector2i = result.get("pos", origin)
		var from_pos := unit.pos
		tx.move_unit(unit, landing, {"emit_signal": false, "emit_event": false})
		# 践踏允许目标短暂与多格单位重叠；离开后需恢复被覆盖的占格索引。
		state.rebuild_occupancy()
		state.on_unit_move.emit(unit.uid, from_pos, landing)
		events.append(_EventBuilder.move_step(unit.uid, from_pos, landing, {
			"forced": true,
			"source_uid": source_uid,
			"reason": "star_relocate",
		}))
		TileRules.on_unit_position_changed(state, unit, from_pos, {"forced": true})
		# 落地后结算目标格地形（地刺、火焰、毒雾等）
		TileRules.on_unit_entered(state, unit, from_pos, {
			"forced": true,
			"source_uid": source_uid,
			"damage_context": damage_context,
		})
		state.on_forced_displacement.emit(unit.uid, from_pos, landing, source_uid)
		GemEffects.on_forced_displacement(state, unit, events)
	else:
		# 全堵死：空间挤压惩罚（按最大扫描半径距离伤害）
		var squeeze_dmg := int(result.get("max_dist", 0)) \
			* CombatConfig.star_relocation_squeeze_damage_per_tile()
		_deal_unit_collision_damage(
			state, unit, source_uid, squeeze_dmg, "space_squeeze", events, damage_context
		)
		state.rebuild_occupancy()
		state.log("%s 被挤压，无法逃离！" % unit.uid)
	tx.finish("Displacement.star_relocate")


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
	events: Array[Dictionary],
	damage_context: Dictionary = {}
) -> void:
	if not unit.alive or amount <= 0:
		return
	var registry := _relic_effect_registry()
	var final_amount := amount
	if registry != null:
		var mult: float = float(registry.query_modifier("collision_damage_mult", state))
		final_amount = maxi(1, int(float(amount) * mult))
	var tx := _CombatTransaction.begin(state, events)
	tx.damage_unit(unit, final_amount, source_uid, reason, {"damage_context": damage_context})


static func _blocking_entities_at_anchor(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i
) -> Array[EntityState]:
	var result: Array[EntityState] = []
	var seen: Dictionary = {}
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.blocks_movement() and not seen.has(entity.uid):
			seen[entity.uid] = true
			result.append(entity)
	return result


static func _blocking_units_at_anchor(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i
) -> Array[UnitState]:
	var result: Array[UnitState] = []
	var seen: Dictionary = {}
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		var blocker := state.get_unit_at(cell)
		if blocker != null and blocker.uid != unit.uid and not seen.has(blocker.uid):
			seen[blocker.uid] = true
			result.append(blocker)
	return result


static func _footprint_has_ground_tag(state: GameState, unit: UnitState, tag: String) -> bool:
	for cell in unit.occupied_cells():
		var tile := state.get_tile(cell)
		if tile != null and tile.has_ground_tag(tag):
			return true
	return false


static func _footprint_in_bounds(state: GameState, unit: UnitState, anchor: Vector2i) -> bool:
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, anchor):
		if not BoardUtils.in_bounds(state, cell):
			return false
	return true


static func _step_vector(unit: UnitState, reference: Vector2i, dir: Direction) -> Vector2i:
	var current_center_twice := unit.pos * 2 + unit.footprint_size - Vector2i.ONE
	var reference_twice := reference * 2
	match dir:
		Direction.AWAY:
			return _away_step(current_center_twice, reference_twice)
		Direction.TOWARD:
			return _toward_step(current_center_twice, reference_twice)
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
