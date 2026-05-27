class_name TileRules
extends RefCounted

# ─── Overlay 进入效果表 ────────────────────────────────────────────────────────
# 每条记录：{ modifier → Callable(state, unit) }
# 新增一种 overlay 的进入效果只需在此表加一行，不改其他任何函数
static var _ENTER_EFFECTS: Dictionary = {
	Constants.TILE_MOD_POISON_FOG: func(state: GameState, unit: UnitState) -> void:
		StatusRules.apply_poison(state, unit, 1, 0),
	Constants.TILE_MOD_FIRE: func(state: GameState, unit: UnitState) -> void:
		StatusRules.apply_burning(state, unit, 1),
	Constants.TILE_MOD_POISON_PUDDLE: func(state: GameState, unit: UnitState) -> void:
		StatusRules.apply_poison(state, unit, 1, 0),
}

# ─── 覆盖层共存反应表 ──────────────────────────────────────────────────────────
# 每条记录：{ [new_mod, existing_mod] → Callable(state, tile) }
# 返回值约定：true = 阻止 new_mod 实际写入（已被反应消耗）
static var _OVERLAY_REACTIONS: Dictionary = {
	# 水 + 火 → 火熄灭，地块恢复正常
	[Constants.TILE_MOD_FIRE, Constants.TILE_MOD_POISON_FOG]: func(state: GameState, tile: TileState) -> bool:
		tile.remove_modifier(Constants.TILE_MOD_POISON_FOG)
		state.log("爆炸/烈火消散了位于 %s 的毒雾" % [tile.pos])
		return false,   # fire 本身仍然写入
}


## 单位当前所在格的地形常驻效果（水域→潮湿）；出生、停留、进入时均需同步
static func sync_standing_ground_effects(state: GameState, unit: UnitState) -> void:
	if not unit.alive:
		return
	var tile := state.get_tile(unit.pos)
	if tile.has_ground_tag(Constants.GROUND_TAG_WATER):
		StatusRules.apply_wet(state, unit, 2)


static func sync_all_units_standing_ground(state: GameState) -> void:
	for unit in state.units.values():
		sync_standing_ground_effects(state, unit)


## 单位主动移动进入格子时
static func on_unit_entered(state: GameState, unit: UnitState, from_pos: Vector2i) -> void:
	var tile := state.get_tile(unit.pos)

	# 地面固有危险（地刺 tile）
	if tile.has_tile_tag(Constants.TAG_TILE_HAZARD):
		CombatRules.apply_damage(state, unit, Constants.SPIKE_DAMAGE, unit.uid, "spike")
		_unlock_armor_locks(state, unit)

	sync_standing_ground_effects(state, unit)

	# 实体进入检测（地刺 entity）
	EntityRules.on_unit_entered(state, unit)

	# Overlay 进入效果（数据驱动）
	_apply_enter_effects(state, unit, tile)


## 单位经过某格时触发（移动路径中间格）
static func on_unit_moved_through(state: GameState, unit: UnitState, pos: Vector2i) -> void:
	var tile := state.get_tile(pos)

	sync_standing_ground_effects(state, unit)
	_apply_enter_effects(state, unit, tile)

	GemEffects.run_unit_hooks(
		state,
		unit,
		Constants.SLOT_BLUE,
		GemEffects.TIMING_MOVED_THROUGH,
		{"pos": pos}
	)


## 单位坐标发生任意变化后调用（含强制位移）
static func on_unit_position_changed(state: GameState, unit: UnitState, old_pos: Vector2i) -> void:
	if unit.pos == old_pos:
		return
	var new_tile := state.get_tile(unit.pos)
	if not new_tile.has_modifier(Constants.TILE_MOD_FIRE):
		StatusRules.clear_burning(unit)


# ─── Overlay 创建 ──────────────────────────────────────────────────────────────

static func create_poison_fog(state: GameState, pos: Vector2i) -> void:
	if not BoardUtils.in_bounds(state, pos):
		return
	var tile := state.get_tile(pos)
	# 水洼中无法形成毒雾，但可变成毒水洼（如已有水洼则转化）
	if tile.has_ground_tag(Constants.GROUND_TAG_WATER):
		_convert_water_to_poison_puddle(state, tile)
		return
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
	_apply_enter_effects_to_occupant(state, pos, tile)


static func create_fire(state: GameState, pos: Vector2i) -> void:
	if not BoardUtils.in_bounds(state, pos):
		return
	var tile := state.get_tile(pos)

	# 火 + 水洼 → 熄灭（直接 return，不创建火）
	if tile.has_ground_tag(Constants.GROUND_TAG_WATER):
		state.log("火焰在水洼 %s 中熄灭" % [pos])
		return

	# 触发共存反应（fire 叠加时检查是否与毒雾反应）
	_run_overlay_reactions(state, tile, Constants.TILE_MOD_FIRE)

	# 更新或新建 fire modifier
	for i in range(tile.modifiers.size()):
		var existing: Variant = tile.modifiers[i]
		if str(existing.get("type", "")) != Constants.TILE_MOD_FIRE:
			continue
		var merged: Dictionary = existing.duplicate(true)
		merged["duration"] = maxi(int(merged.get("duration", 0)), Constants.FIRE_DURATION)
		tile.modifiers[i] = merged
		return
	tile.add_modifier(Constants.TILE_MOD_FIRE, Constants.FIRE_DURATION)

	# 点燃可燃地面（草地/草丛）：将 tile_id 更换为普通地板，火焰附在上面
	if tile.has_ground_tag(Constants.GROUND_TAG_FLAMMABLE):
		state.log("%s 的 %s 被点燃" % [pos, tile.tile_id])
		tile.tile_id = Constants.TILE_FLOOR
		tile._init_ground_tags()

	# 如果此刻有单位站在上面，立刻上火
	var occupant := state.get_unit_at(pos)
	if occupant != null and occupant.alive:
		StatusRules.apply_burning(state, occupant, 1)

	# 如果此刻有油桶站在上面，触发爆炸
	var barrel := state.get_entity_at(pos)
	if barrel != null and barrel.alive and barrel.entity_id == Constants.ENTITY_BARREL:
		var ev: Array[Dictionary] = []
		EntityRules.damage_barrel(state, barrel, barrel.hp, "", ev)


## 火焰蔓延：[着火] 的地块引燃相邻可燃格（每回合 50% 概率）
static func spread_fire(state: GameState) -> void:
	var fire_positions: Array[Vector2i] = []
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		if tile.has_modifier(Constants.TILE_MOD_FIRE):
			fire_positions.append(tile.pos)
	for pos in fire_positions:
		for neighbor in BoardUtils.neighbors4(pos):
			if not BoardUtils.in_bounds(state, neighbor):
				continue
			var ntile := state.get_tile(neighbor)
			if ntile.has_modifier(Constants.TILE_MOD_FIRE):
				continue
			if ntile.has_ground_tag(Constants.GROUND_TAG_FLAMMABLE):
				if randf() < Constants.FIRE_SPREAD_CHANCE:
					create_fire(state, neighbor)

	# [着火] 的单位路过可燃格也会点燃（已在 on_unit_moved_through 的 burning 触发中隐含，
	# 此处补充：burning 单位当前所在格若可燃则立即点燃）
	for unit in state.units.values():
		if not unit.alive:
			continue
		if not unit.has_status(Constants.STATUS_BURNING):
			continue
		var utile := state.get_tile(unit.pos)
		if utile.has_ground_tag(Constants.GROUND_TAG_FLAMMABLE) and not utile.has_modifier(Constants.TILE_MOD_FIRE):
			create_fire(state, unit.pos)


# ─── 内部工具 ──────────────────────────────────────────────────────────────────

static func _apply_enter_effects(state: GameState, unit: UnitState, tile: TileState) -> void:
	for modifier_type in _ENTER_EFFECTS.keys():
		if tile.has_modifier(modifier_type):
			_ENTER_EFFECTS[modifier_type].call(state, unit)


static func _apply_enter_effects_to_occupant(state: GameState, pos: Vector2i, tile: TileState) -> void:
	var occupant := state.get_unit_at(pos)
	if occupant == null or not occupant.alive:
		return
	_apply_enter_effects(state, occupant, tile)


static func _run_overlay_reactions(state: GameState, tile: TileState, incoming_type: String) -> void:
	for key in _OVERLAY_REACTIONS.keys():
		if key[0] == incoming_type and tile.has_modifier(key[1]):
			_OVERLAY_REACTIONS[key].call(state, tile)


static func _convert_water_to_poison_puddle(state: GameState, tile: TileState) -> void:
	state.log("水洼 %s 被毒雾污染，变为毒水洼" % [tile.pos])
	tile.add_modifier(Constants.TILE_MOD_POISON_PUDDLE, Constants.POISON_FOG_DURATION)
	_apply_enter_effects_to_occupant(state, tile.pos, tile)


static func _unlock_armor_locks(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
			StatusRules.apply_exposed(state, unit, slot, state.turn_index)
