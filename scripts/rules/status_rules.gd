class_name StatusRules
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")
const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")


static func apply_poison(
	state: GameState,
	unit: UnitState,
	stacks: int = 1,
	duration: int = 2,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_POISON, {
		"stacks": stacks,
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_burning(
	state: GameState,
	unit: UnitState,
	stacks: int = 1,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_BURNING, {
		"stacks": stacks,
		"duration": 0,
		"source_uid": source_uid,
	})


static func apply_armor(
	state: GameState,
	unit: UnitState,
	value: int,
	duration: int = 1,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_ARMOR, {
		"value": value,
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_shield(state: GameState, unit: UnitState, value: int, duration: int = 1) -> void:
	apply_armor(state, unit, value, duration)


static func apply_rooted(
	state: GameState,
	unit: UnitState,
	duration: int = 2,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_ROOTED, {
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_exposed(state: GameState, unit: UnitState, slot: SlotState, turn_index: int) -> void:
	var saved_lock_type := slot.lock_type if not slot.lock_type.is_empty() else Constants.LOCK_ARMOR
	_apply(state, unit, Constants.STATUS_EXPOSED, {
		"duration": 1,
		"payload": {
			"slot_type": slot.slot_type,
			"lock_type": saved_lock_type,
		},
	})
	slot.locked = false
	slot.lock_type = ""
	slot.unlock_until_turn = turn_index


static func apply_lawless(state: GameState, unit: UnitState, target_gem_uid: String, source_uid: String = "") -> void:
	_apply(state, unit, Constants.STATUS_LAWLESS, {
		"duration": 0,
		"source_uid": source_uid,
		"payload": {"target_gem_uid": target_gem_uid},
	})


static func clear_lawless(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_LAWLESS)


static func is_lawless(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_LAWLESS)


static func get_lawless_gem_uid(unit: UnitState) -> String:
	var status: StatusInstance = unit.get_status(Constants.STATUS_LAWLESS)
	if status == null:
		return ""
	return status.payload.get("target_gem_uid", "")


static func apply_bomb_rat_plunder(state: GameState, unit: UnitState, phase: int) -> void:
	_apply(state, unit, Constants.STATUS_BOMB_RAT_PLUNDER, {
		"duration": 0,
		"payload": {"phase": phase},
	})


static func clear_bomb_rat_plunder(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_BOMB_RAT_PLUNDER)


static func get_bomb_rat_plunder_phase(unit: UnitState) -> int:
	var status: StatusInstance = unit.get_status(Constants.STATUS_BOMB_RAT_PLUNDER)
	if status == null:
		return -1
	return int(status.payload.get("phase", -1))


static func set_bomb_rat_plunder_phase(unit: UnitState, phase: int) -> void:
	var status: StatusInstance = unit.get_status(Constants.STATUS_BOMB_RAT_PLUNDER)
	if status == null:
		return
	status.payload["phase"] = phase


static func can_move(unit: UnitState) -> bool:
	for status in unit.statuses:
		if _StatusRegistry.blocks_movement(status.status_id):
			return false
	return true


static func get_armor_bonus(unit: UnitState) -> int:
	var armor: StatusInstance = unit.get_status(Constants.STATUS_ARMOR)
	if armor == null:
		return 0
	return maxi(0, armor.value)


static func apply_paralyzed(
	state: GameState,
	unit: UnitState,
	_duration: int = 1,
	source_uid: String = ""
) -> void:
	if unit.has_status(Constants.STATUS_PARALYZED):
		return
	_apply(state, unit, Constants.STATUS_PARALYZED, {
		"duration": 0,
		"source_uid": source_uid,
	})


static func apply_slowed(
	state: GameState,
	unit: UnitState,
	stacks: int = 1,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_SLOWED, {
		"stacks": stacks,
		"duration": 0,
		"source_uid": source_uid,
	})


static func apply_wet(
	state: GameState,
	unit: UnitState,
	duration: int = 2,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_WET, {
		"duration": duration,
		"source_uid": source_uid,
	})


static func apply_sluggish(
	state: GameState,
	unit: UnitState,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_SLUGGISH, {
		"duration": 1,
		"source_uid": source_uid,
	})


static func apply_vulnerable(
	state: GameState,
	unit: UnitState,
	duration: int = 1,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_VULNERABLE, {
		"duration": duration,
		"source_uid": source_uid,
	})


static func is_vulnerable(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_VULNERABLE)


## 返回缓速扣减后的实际移动力（最低1）
static func effective_move_points(unit: UnitState, base: int) -> int:
	var slow: StatusInstance = unit.get_status(Constants.STATUS_SLOWED)
	if slow == null:
		return base
	return maxi(1, base - slow.stacks)


static func can_act(unit: UnitState) -> bool:
	for status in unit.statuses:
		if _StatusRegistry.blocks_action(status.status_id):
			return false
	return true


static func is_wet(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_WET)


## 清空单位的 burning 层数（离开火焰地块时调用）
static func clear_burning(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_BURNING)


static func tick_turn_start(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		_apply_blue_turn_start_effects(state, unit)
		_tick_phase(state, unit, _StatusRegistry.TICK_TURN_START)


## 分阶段 turn_end，严格执行以下顺序：
## 1. 地块停留结算：overlay 对停留单位施加状态（毒雾上毒、火焰上火、毒水洼上毒）
## 2. 接触结算：相邻接触 (CONTACT_ADJACENT)
## 3. 状态预处理：地块修正 status 参数（burning 在火焰中翻倍）
## 4. 状态 Tick：统一扣毒/火伤害，层数 -1
## 5. 油桶着火检测
## 6. 地块 modifier 倒计时
## 7. 火焰蔓延 + 草地生长
## 8. Pillar 光环
static func tick_turn_end(state: GameState) -> void:
	# 阶段 1：地块停留结算
	for unit in state.units.values():
		if not unit.alive:
			continue
		_tick_tile_stay(state, unit)

	# 阶段 2：接触结算（相邻）
	_ContactResolver.resolve_adjacent(state)

	# 阶段 3：状态预处理（由 overlay 修正 status 参数）
	for unit in state.units.values():
		if not unit.alive:
			continue
		_pretick_overlay_status_modifiers(state, unit)

	# 阶段 4：状态 Tick（poison/burning/armor 等）
	for unit in state.units.values():
		if not unit.alive:
			continue
		_tick_phase(state, unit, _StatusRegistry.TICK_TURN_END)

	# 阶段 5：油桶着火检测
	EntityRules.tick_barrels_in_fire(state)

	# 阶段 6：地块 modifier 倒计时
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		tile.tick_modifiers()

	# 阶段 7：火焰蔓延 + 草地随机生长
	TileRules.spread_fire(state)
	_tick_grass_growth(state)

	# 阶段 8：Pillar 光环
	_apply_tile_pillar_auras(state)


## 地块停留效果（通过 TileRules 的进入效果表统一分发）
static func _tick_tile_stay(state: GameState, unit: UnitState) -> void:
	TileRules.sync_standing_ground_effects(state, unit)
	var tile := state.get_tile(unit.pos)
	TileRules._apply_enter_effects(state, unit, tile)


## overlay 对 status 参数的预处理表
## key: [status_id, modifier_type]  value: Callable(status) → void
static var _OVERLAY_STATUS_PRETICK: Array = [
	# 处于火焰中：burning 层数 ×2
	[Constants.STATUS_BURNING, Constants.TILE_MOD_FIRE,
		func(status: StatusInstance, state: GameState, unit: UnitState) -> void:
			status.stacks = status.stacks * 2
			state.log("%s 处于火焰中，burning 层数翻倍为 %d" % [unit.uid, status.stacks])],
]


## 通用 overlay-status 预处理：遍历表格，无需针对每种状态单独写函数
static func _pretick_overlay_status_modifiers(state: GameState, unit: UnitState) -> void:
	var tile := state.get_tile(unit.pos)
	for entry in _OVERLAY_STATUS_PRETICK:
		var status_id: String = entry[0]
		var modifier_type: String = entry[1]
		var callback: Callable = entry[2]
		if not tile.has_modifier(modifier_type):
			continue
		var status: StatusInstance = unit.get_status(status_id)
		if status == null:
			continue
		callback.call(status, state, unit)


static func _apply(state: GameState, unit: UnitState, status_id: String, params: Dictionary) -> void:
	var incoming := StatusInstance.create(
		status_id,
		int(params.get("stacks", 1)),
		int(params.get("duration", 0)),
		params.get("source_uid", ""),
		params.get("payload", {})
	)
	if params.has("value"):
		incoming.value = int(params.get("value", 0))
	_StatusRegistry.apply_to_unit(unit, incoming)
	state.log("%s 获得状态 %s" % [unit.uid, _StatusRegistry.display_name(status_id)])


static func _tick_phase(state: GameState, unit: UnitState, phase: String) -> void:
	var next: Array[StatusInstance] = []
	for status in unit.statuses:
		if _StatusRegistry.tick_phase(status.status_id) != phase:
			next.append(status)
			continue
		_resolve_tick(state, unit, status)
		if status.duration > 0:
			status.duration -= 1
			if status.duration <= 0:
				state.log("%s 的状态 %s 结束" % [unit.uid, _StatusRegistry.display_name(status.status_id)])
				_on_status_expired(unit, status)
				continue
		# 层数类状态（poison/burning）：tick 后层数 -1，归零则移除
		elif _is_stack_dot(status.status_id):
			status.stacks -= 1
			if status.stacks <= 0:
				state.log("%s 的 %s 归零" % [unit.uid, _StatusRegistry.display_name(status.status_id)])
				continue
		next.append(status)
	unit.statuses = next


static func _is_stack_dot(status_id: String) -> bool:
	match status_id:
		Constants.STATUS_POISON, Constants.STATUS_BURNING, Constants.STATUS_SLOWED:
			return true
	return false


static func _on_status_expired(unit: UnitState, status: StatusInstance) -> void:
	if status.status_id != Constants.STATUS_EXPOSED:
		return
	var slot_type: String = status.payload.get("slot_type", "")
	var lock_type: String = status.payload.get("lock_type", Constants.LOCK_ARMOR)
	if slot_type.is_empty():
		return
	var slot := unit.get_slot(slot_type)
	if slot == null or slot.gem_uid.is_empty():
		return
	slot.locked = true
	slot.lock_type = lock_type
	slot.unlock_until_turn = -1


static func _resolve_tick(state: GameState, unit: UnitState, status: StatusInstance) -> void:
	match status.status_id:
		Constants.STATUS_POISON:
			var poison_dmg := status.stacks * Constants.POISON_FOG_DAMAGE
			CombatRules.apply_true_damage(state, unit, poison_dmg, status.source_uid, "poison")
		Constants.STATUS_BURNING:
			CombatRules.apply_true_damage(state, unit, status.stacks, status.source_uid, "burning")


## 草地随机生长为草丛
static func _tick_grass_growth(state: GameState) -> void:
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_GRASS and RngService.chance("tile_grass_grow_%s" % str(tile.pos), Constants.GRASS_GROW_CHANCE):
			tile.tile_id = Constants.TILE_BUSH
			tile._init_ground_tags()
			state.log("草地 %s 长成草丛" % [tile.pos])


static func _apply_tile_pillar_auras(state: GameState) -> void:
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_PILLAR and tile.has_tile_tag(Constants.TAG_TILE_INTERACTIVE):
			TileEffects.tick_pillar_aura(state, tile)


static func _apply_blue_turn_start_effects(state: GameState, unit: UnitState) -> void:
	GemEffects.run_unit_hooks(state, unit, Constants.SLOT_BLUE, GemEffects.TIMING_TURN_START, {})
