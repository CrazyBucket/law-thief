class_name Displacement
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")

enum Direction { AWAY, TOWARD, NORTH, SOUTH, EAST, WEST }


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
	var registry := _relic_effect_registry()
	if registry != null and bool(registry.query_modifier("forced_move_immune", state)):
		return
	_push_directional(state, unit, origin, Direction.AWAY, steps, source_uid, events, collision_damage, skip_gem_hooks, 0)


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
	var registry := _relic_effect_registry()
	if registry != null and bool(registry.query_modifier("forced_move_immune", state)):
		return
	_push_directional(state, unit, anchor, Direction.TOWARD, steps, source_uid, events, collision_damage, skip_gem_hooks, 0)


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
	_push_directional(state, unit, unit.pos, direction, steps, source_uid, events, collision_damage, false, 0)


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
	chain_depth: int = 0
) -> void:
	var start_pos := unit.pos
	var remaining := steps
	var i := 0
	var is_large := unit.footprint_size != Vector2i(1, 1)

	while i < remaining:
		var step_vec := _step_vector(unit.pos, reference_pos, dir)
		if step_vec == Vector2i.ZERO:
			break
		var next := unit.pos + step_vec
		if next == unit.pos:
			break

		if not _footprint_in_bounds(state, unit, next):
			if collision_damage > 0:
				_deal_collision_damage(state, unit, source_uid, collision_damage, "wall_collision", events)
			break

		var entity := _blocking_entity_at_anchor(state, unit, next)
		if entity != null:
			EntityRules.on_unit_collide_entity(state, unit, entity, source_uid, events)
			_land_after_block(state, unit, next, step_vec, source_uid, events, skip_gem_hooks)
			break

		var blocker := _blocking_unit_at_anchor(state, unit, next)
		if blocker != null:
			if chain_depth < Constants.DISPLACEMENT_CHAIN_MAX_DEPTH:
				var chain_events: Array[Dictionary] = []
				var pushed := _push_unit_one_step(
					state, blocker, step_vec, source_uid, chain_events, collision_damage, skip_gem_hooks, chain_depth + 1
				)
				events.append_array(chain_events)
				if pushed:
					blocker = _blocking_unit_at_anchor(state, unit, next)
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

		var moved_tile := state.get_tile(next)
		if moved_tile.has_ground_tag(Constants.GROUND_TAG_ICE):
			remaining += 1

		i += 1

	if unit.pos != start_pos:
		TileRules.on_unit_position_changed(state, unit, start_pos)
		TileRules.on_unit_entered(state, unit, start_pos, {"forced": true, "source_uid": source_uid})
		if not skip_gem_hooks:
			GemEffects.on_forced_displacement(state, unit, events)


static func _push_unit_one_step(
	state: GameState,
	unit: UnitState,
	step_vec: Vector2i,
	source_uid: String,
	events: Array[Dictionary],
	collision_damage: int,
	skip_gem_hooks: bool,
	chain_depth: int
) -> bool:
	if not unit.alive or step_vec == Vector2i.ZERO:
		return false
	var next := unit.pos + step_vec
	if not _footprint_in_bounds(state, unit, next):
		return false
	if _blocking_entity_at_anchor(state, unit, next) != null:
		return false
	if not BoardUtils.can_unit_push_to(state, unit, step_vec):
		var blocker := _blocking_unit_at_anchor(state, unit, next)
		if blocker == null:
			return false
		if chain_depth >= Constants.DISPLACEMENT_CHAIN_MAX_DEPTH:
			return false
		if not _push_unit_one_step(state, blocker, step_vec, source_uid, events, collision_damage, skip_gem_hooks, chain_depth + 1):
			return false
		if not BoardUtils.can_unit_push_to(state, unit, step_vec):
			return false
	var from_pos := unit.pos
	state.move_unit(unit, next)
	TileRules.on_unit_moved_through(state, unit, next)
	state.on_unit_move.emit(unit.uid, from_pos, next)
	events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})
	return true


static func _land_after_block(
	state: GameState,
	unit: UnitState,
	blocked_anchor: Vector2i,
	step_vec: Vector2i,
	source_uid: String,
	events: Array[Dictionary],
	skip_gem_hooks: bool
) -> void:
	var landing := _find_landing_anchor(state, unit, blocked_anchor, step_vec)
	if landing == unit.pos:
		return
	var from_pos := unit.pos
	state.move_unit(unit, landing)
	TileRules.on_unit_moved_through(state, unit, landing)
	TileRules.on_unit_entered(state, unit, from_pos, {"forced": true, "source_uid": source_uid})
	state.on_unit_move.emit(unit.uid, from_pos, landing)
	events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": landing})
	if not skip_gem_hooks:
		GemEffects.on_forced_displacement(state, unit, events)


static func _find_landing_anchor(
	state: GameState,
	unit: UnitState,
	blocked_anchor: Vector2i,
	step_vec: Vector2i
) -> Vector2i:
	var lateral: Array[Vector2i] = [
		Vector2i(-step_vec.y, step_vec.x),
		Vector2i(step_vec.y, -step_vec.x),
	]
	for dist in range(1, Constants.DISPLACEMENT_LANDING_SCAN + 1):
		var along: Vector2i = blocked_anchor + step_vec * (dist - 1)
		if BoardUtils.unit_footprint_passable(state, unit, along, unit.uid):
			return along
		for side: Vector2i in lateral:
			var candidate: Vector2i = along + side
			if BoardUtils.unit_footprint_passable(state, unit, candidate, unit.uid):
				return candidate
	return unit.pos


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


static func _resolve_next_cell(current: Vector2i, reference: Vector2i, dir: Direction) -> Vector2i:
	return current + _step_vector(current, reference, dir)


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
