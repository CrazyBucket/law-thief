class_name TileRules
extends RefCounted


static func on_unit_entered(state: GameState, unit: UnitState, from_pos: Vector2i) -> void:
	var tile := state.get_tile(unit.pos)
	if tile.tile_id == Constants.TILE_SPIKE:
		CombatRules.apply_damage(state, unit, Constants.SPIKE_DAMAGE, unit.uid, "spike")
		_unlock_armor_locks(state, unit)
	# 进入毒雾：立刻上一层毒
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
		StatusRules.apply_poison(state, unit, 1, 2)
	# 进入火焰：立刻上一层 burning
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		StatusRules.apply_burning(state, unit, 1)


## 单位经过某格时触发（移动路径中间格）
static func on_unit_moved_through(state: GameState, unit: UnitState, pos: Vector2i) -> void:
	var tile := state.get_tile(pos)
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
		StatusRules.apply_poison(state, unit, 1, 2)
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		StatusRules.apply_burning(state, unit, 1)
	GemEffects.run_unit_hooks(
		state,
		unit,
		Constants.SLOT_BLUE,
		GemEffects.TIMING_MOVED_THROUGH,
		{"pos": pos}
	)


## 单位坐标发生任意变化后调用（含强制位移），处理离开火焰时清零 burning
static func on_unit_position_changed(state: GameState, unit: UnitState, old_pos: Vector2i) -> void:
	if unit.pos == old_pos:
		return
	var new_tile := state.get_tile(unit.pos)
	if not new_tile.has_modifier(Constants.TILE_MOD_FIRE):
		StatusRules.clear_burning(unit)


static func create_poison_fog(state: GameState, pos: Vector2i) -> void:
	if not BoardUtils.in_bounds(state, pos):
		return
	var tile := state.get_tile(pos)
	var add_turns := Constants.POISON_FOG_DURATION
	for i in range(tile.modifiers.size()):
		var existing: Variant = tile.modifiers[i]
		if str(existing.get("type", "")) != Constants.TILE_MOD_POISON_FOG:
			continue
		var merged: Dictionary = existing.duplicate(true)
		merged["duration"] = int(merged.get("duration", 0)) + add_turns
		tile.modifiers[i] = merged
		return
	tile.add_modifier(Constants.TILE_MOD_POISON_FOG, add_turns)


static func create_fire(state: GameState, pos: Vector2i) -> void:
	if not BoardUtils.in_bounds(state, pos):
		return
	var tile := state.get_tile(pos)
	for i in range(tile.modifiers.size()):
		var existing: Variant = tile.modifiers[i]
		if str(existing.get("type", "")) != Constants.TILE_MOD_FIRE:
			continue
		var merged: Dictionary = existing.duplicate(true)
		merged["duration"] = maxi(int(merged.get("duration", 0)), Constants.FIRE_DURATION)
		tile.modifiers[i] = merged
		return
	tile.add_modifier(Constants.TILE_MOD_FIRE, Constants.FIRE_DURATION)
	# 如果此刻有单位站在上面，立刻上火
	var occupant := state.get_unit_at(pos)
	if occupant != null and occupant.alive:
		StatusRules.apply_burning(state, occupant, 1)


static func _unlock_armor_locks(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
			StatusRules.apply_exposed(state, unit, slot, state.turn_index)
