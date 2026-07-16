class_name StatusRules
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")
const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _StatusActionRules = preload("res://scripts/rules/status_action_rules.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const StatusConfig = preload("res://scripts/core/status_config.gd")


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RngService")


static func apply_poison(
	state: GameState,
	unit: UnitState,
	stacks: int = -1,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_stacks := stacks if stacks >= 0 else _default_stacks("poison")
	var resolved_duration := duration if duration >= 0 else _default_duration("poison")
	_apply(state, unit, Constants.STATUS_POISON, {
		"stacks": resolved_stacks,
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


static func apply_burning(
	state: GameState,
	unit: UnitState,
	stacks: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_stacks := stacks if stacks >= 0 else _default_stacks("burning")
	_apply(state, unit, Constants.STATUS_BURNING, {
		"stacks": resolved_stacks,
		"duration": _default_duration("burning"),
		"source_uid": source_uid,
	})


static func apply_armor(
	state: GameState,
	unit: UnitState,
	value: int,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else _default_duration("armor")
	apply_shield(state, unit, value, resolved_duration, source_uid)


static func apply_shield(
	state: GameState,
	unit: UnitState,
	value: int,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	if value <= 0:
		return
	var resolved_duration := duration if duration >= 0 else _default_duration("shield")
	_apply(state, unit, Constants.STATUS_ARMOR, {
		"value": value,
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


## 护盾优先抵挡伤害；抵挡后按实际消耗扣减，归零则移除
static func absorb_with_shield(state: GameState, unit: UnitState, amount: int) -> int:
	if amount <= 0:
		return 0
	var shield: StatusInstance = unit.get_status(Constants.STATUS_ARMOR)
	if shield == null or shield.value <= 0:
		return amount
	var blocked := mini(amount, shield.value)
	shield.value -= blocked
	if shield.value <= 0:
		unit.remove_status(Constants.STATUS_ARMOR)
	return amount - blocked


static func apply_rooted(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else _default_duration("rooted")
	_apply(state, unit, Constants.STATUS_ROOTED, {
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


static func apply_exposed(state: GameState, unit: UnitState, slot: SlotState, turn_index: int) -> void:
	var saved_lock_type := slot.lock_type if not slot.lock_type.is_empty() else Constants.LOCK_ARMOR
	_apply(state, unit, Constants.STATUS_EXPOSED, {
		"duration": _default_duration("exposed"),
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
		"duration": _default_duration("lawless"),
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
		"duration": _default_duration("bomb_rat_plunder"),
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


static func apply_law_worm_incubating(state: GameState, unit: UnitState, ready_turn: int) -> void:
	_apply(state, unit, Constants.STATUS_LAW_WORM_INCUBATING, {
		"payload": {"ready_turn": ready_turn},
	})


static func law_worm_ready_turn(unit: UnitState) -> int:
	var status: StatusInstance = unit.get_status(Constants.STATUS_LAW_WORM_INCUBATING)
	return int(status.payload.get("ready_turn", -1)) if status != null else -1


static func set_broodmother_next_split(state: GameState, unit: UnitState, next_split: bool) -> void:
	_apply(state, unit, Constants.STATUS_BROODMOTHER_CYCLE, {
		"payload": {"next_split": next_split},
	})


static func broodmother_next_split(unit: UnitState) -> bool:
	var status: StatusInstance = unit.get_status(Constants.STATUS_BROODMOTHER_CYCLE)
	return bool(status.payload.get("next_split", true)) if status != null else true


static func sync_broodmother_crisis(state: GameState, unit: UnitState, active: bool) -> void:
	if active:
		if not unit.has_status(Constants.STATUS_BROODMOTHER_CRISIS):
			_apply(state, unit, Constants.STATUS_BROODMOTHER_CRISIS, {})
	else:
		unit.remove_status(Constants.STATUS_BROODMOTHER_CRISIS)


static func can_move(unit: UnitState) -> bool:
	return _StatusActionRules.can_move(unit)


static func move_block_reason(unit: UnitState) -> String:
	for status in unit.statuses:
		if not _StatusRegistry.blocks_movement(status.status_id):
			continue
		match status.status_id:
			Constants.STATUS_PARALYZED:
				return "被麻痹，无法移动"
			Constants.STATUS_ROOTED:
				return "被束缚，无法移动"
	return ""


static func can_attack(unit: UnitState) -> bool:
	return _StatusActionRules.can_attack(unit)


static func attack_block_reason(unit: UnitState) -> String:
	if unit != null and unit.has_status(Constants.STATUS_DISARMED):
		var text := TranslationServer.translate("status.disarmed.block")
		return "被缴械，无法攻击" if text == "status.disarmed.block" else text
	return ""


static func action_block_reason(unit: UnitState) -> String:
	if unit != null and unit.has_status(Constants.STATUS_PARALYZED):
		var text := TranslationServer.translate("status.paralyzed.block")
		return "被麻痹，无法行动" if text == "status.paralyzed.block" else text
	return ""


static func get_armor_bonus(unit: UnitState) -> int:
	return get_shield(unit)


static func get_shield(unit: UnitState) -> int:
	var shield: StatusInstance = unit.get_status(Constants.STATUS_ARMOR)
	if shield == null:
		return 0
	return maxi(0, shield.value)


static func apply_paralyzed(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	if unit.has_status(Constants.STATUS_PARALYZED):
		return
	var resolved_duration := duration if duration >= 0 else _default_duration("paralyzed")
	_apply(state, unit, Constants.STATUS_PARALYZED, {
		"duration": maxi(1, resolved_duration),
		"source_uid": source_uid,
	})


static func apply_slowed(
	state: GameState,
	unit: UnitState,
	stacks: int = -1,
	source_uid: String = "",
	min_move_points: int = -1
) -> void:
	var resolved_stacks := stacks if stacks >= 0 else _default_stacks("slowed")
	var default_min := _config_int("slowed", "min_move_points")
	var resolved_min := min_move_points if min_move_points >= 0 else default_min
	var existing: StatusInstance = unit.get_status(Constants.STATUS_SLOWED)
	var merged_min := resolved_min
	if existing != null:
		merged_min = mini(int(existing.payload.get("min_move_points", default_min)), resolved_min)
	_apply(state, unit, Constants.STATUS_SLOWED, {
		"stacks": resolved_stacks,
		"duration": _default_duration("slowed"),
		"source_uid": source_uid,
		"payload": {"min_move_points": resolved_min},
	})
	var applied: StatusInstance = unit.get_status(Constants.STATUS_SLOWED)
	if applied != null:
		applied.payload["min_move_points"] = merged_min


static func apply_wet(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else _default_duration("wet")
	_apply(state, unit, Constants.STATUS_WET, {
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


static func apply_sluggish(
	state: GameState,
	unit: UnitState,
	source_uid: String = ""
) -> void:
	_apply(state, unit, Constants.STATUS_SLUGGISH, {
		"duration": _default_duration("sluggish"),
		"source_uid": source_uid,
	})


static func apply_vulnerable(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else _default_duration("vulnerable")
	_apply(state, unit, Constants.STATUS_VULNERABLE, {
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


static func apply_disarmed(
	state: GameState,
	unit: UnitState,
	stacks: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_stacks := stacks if stacks >= 0 else _default_stacks("disarmed")
	if resolved_stacks <= 0:
		return
	_apply(state, unit, Constants.STATUS_DISARMED, {
		"stacks": resolved_stacks,
		"source_uid": source_uid,
	})


static func consume_disarm(unit: UnitState) -> bool:
	if unit == null:
		return false
	var status: StatusInstance = unit.get_status(Constants.STATUS_DISARMED)
	if status == null:
		return false
	status.stacks -= 1
	if status.stacks <= 0:
		unit.remove_status(Constants.STATUS_DISARMED)
	return true


static func is_vulnerable(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_VULNERABLE)


static func apply_weak(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else _default_duration("weak")
	_apply(state, unit, Constants.STATUS_WEAK, {
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


static func is_weak(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_WEAK)


static func apply_light_exposed(
	state: GameState,
	unit: UnitState,
	stacks: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_stacks := stacks if stacks >= 0 else _default_stacks("light_exposed")
	_apply(state, unit, Constants.STATUS_LIGHT_EXPOSED, {
		"stacks": resolved_stacks,
		"duration": _default_duration("light_exposed"),
		"source_uid": source_uid,
	})


static func apply_blinded(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else _default_duration("blinded")
	_apply(state, unit, Constants.STATUS_BLINDED, {
		"duration": resolved_duration,
		"source_uid": source_uid,
	})


static func apply_counter_mark(
	state: GameState,
	unit: UnitState,
	watcher_uid: String,
	effect_def: Dictionary = {},
	source_uid: String = ""
) -> void:
	if watcher_uid.is_empty():
		return
	var resolved_duration := maxi(1, int(effect_def["mark_duration"]))
	var incoming_watcher := {
		"uid": watcher_uid,
		"retaliation_with_tags": bool(effect_def.get("retaliation_with_tags", false)),
		"grant_extra_attack_on_kill": bool(effect_def.get("grant_extra_attack_on_kill", false)),
	}
	var existing: StatusInstance = unit.get_status(Constants.STATUS_COUNTER_MARK)
	if existing == null:
		_apply(state, unit, Constants.STATUS_COUNTER_MARK, {
			"duration": resolved_duration,
			"source_uid": source_uid,
			"payload": {
				"watchers": [incoming_watcher],
			},
		})
		return
	var watchers: Array = existing.payload.get("watchers", [])
	var replaced := false
	for i in range(watchers.size()):
		var watcher: Dictionary = watchers[i]
		if str(watcher.get("uid", "")) != watcher_uid:
			continue
		var legacy_level := int(watcher.get("level", 1))
		watchers[i] = {
			"uid": watcher_uid,
			"retaliation_with_tags": bool(watcher.get("retaliation_with_tags", legacy_level >= 2)) \
				or bool(incoming_watcher.get("retaliation_with_tags", false)),
			"grant_extra_attack_on_kill": bool(watcher.get("grant_extra_attack_on_kill", legacy_level >= 3)) \
				or bool(incoming_watcher.get("grant_extra_attack_on_kill", false)),
		}
		replaced = true
		break
	if not replaced:
		watchers.append(incoming_watcher)
	existing.duration = maxi(existing.duration, resolved_duration)
	existing.source_uid = source_uid
	existing.payload["watchers"] = watchers
	state.log("%s 获得状态 %s" % [unit.uid, _StatusRegistry.display_name(Constants.STATUS_COUNTER_MARK)])


static func grant_extra_attack(state: GameState, unit: UnitState, amount: int = -1, source_uid: String = "") -> void:
	var resolved_amount := amount if amount >= 0 else _default_stacks("extra_attack")
	if resolved_amount <= 0:
		return
	_apply(state, unit, Constants.STATUS_EXTRA_ATTACK, {
		"stacks": resolved_amount,
		"source_uid": source_uid,
	})


static func grant_extra_move(state: GameState, unit: UnitState, amount: int = -1, source_uid: String = "") -> void:
	var resolved_amount := amount if amount >= 0 else _default_stacks("extra_move")
	if resolved_amount <= 0:
		return
	_apply(state, unit, Constants.STATUS_EXTRA_MOVE, {
		"stacks": resolved_amount,
		"source_uid": source_uid,
	})


static func has_extra_attack(unit: UnitState) -> bool:
	return _StatusActionRules.has_extra_attack(unit)


static func has_extra_move(unit: UnitState) -> bool:
	return _StatusActionRules.has_extra_move(unit)


static func consume_extra_attack(unit: UnitState) -> bool:
	return _StatusActionRules.consume_extra_attack(unit)


static func consume_extra_move(unit: UnitState) -> bool:
	return _StatusActionRules.consume_extra_move(unit)


static func clear_extra_action_statuses(unit: UnitState) -> void:
	_StatusActionRules.clear_extra_actions(unit)


## 返回缓速扣减后的实际移动力；特定来源可在状态载荷中降低下限。
static func effective_move_points(unit: UnitState, base: int) -> int:
	return _StatusActionRules.effective_move_points(unit, base, _config_int("slowed", "min_move_points"))


static func can_act(unit: UnitState) -> bool:
	return _StatusActionRules.can_act(unit)


static func is_wet(unit: UnitState) -> bool:
	return unit.has_status(Constants.STATUS_WET)


## 清空单位的 burning 层数（离开火焰地块时调用）
static func clear_burning(unit: UnitState) -> void:
	unit.remove_status(Constants.STATUS_BURNING)


static func tick_turn_start(state: GameState) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		tick_unit_turn_start(state, unit)


## Turn-bound statuses belong to their carrier's action window.
static func tick_unit_turn_start(state: GameState, unit: UnitState) -> void:
	if state == null or unit == null or not unit.alive:
		return
	_apply_blue_turn_start_effects(state, unit)
	_tick_phase(state, unit, _StatusRegistry.TICK_TURN_START)


## Resolve one carrier's completed action window. Ground stay is applied before
## damage-over-time so ending a turn in a hazard has an immediate cost.
static func tick_unit_turn_end(
	state: GameState,
	unit: UnitState,
	events: Array[Dictionary] = []
) -> void:
	if state == null or unit == null or not unit.alive:
		return
	_tick_tile_stay(state, unit)
	_pretick_overlay_status_modifiers(state, unit)
	_tick_phase(state, unit, _StatusRegistry.TICK_TURN_END, events)


## Board-wide effects advance once after every unit has completed its own turn.
static func tick_round_end_environment(
	state: GameState,
	events: Array[Dictionary] = []
) -> void:
	if state == null:
		return
	_ContactResolver.resolve_adjacent(state)
	EntityRules.tick_barrels_in_fire(state, events)
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		tile.tick_modifiers()
	TileRules.spread_fire(state)
	_tick_grass_growth(state)
	_apply_tile_pillar_auras(state)


## 分阶段 turn_end，严格执行以下顺序：
## 1. 地块停留结算：overlay 对停留单位施加状态（毒雾上毒、火焰上火、毒水洼上毒）
## 2. 接触结算：相邻接触 (CONTACT_ADJACENT)
## 3. 状态预处理：地块修正 status 参数（burning 在火焰中翻倍）
## 4. 状态 Tick：统一扣毒/火伤害，层数 -1
## 5. 油桶着火检测
## 6. 地块 modifier 倒计时
## 7. 火焰蔓延 + 草地生长
## 8. Pillar 光环
static func tick_turn_end(state: GameState, events: Array[Dictionary] = []) -> void:
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
		_tick_phase(state, unit, _StatusRegistry.TICK_TURN_END, events)

	# 阶段 6：油桶着火检测
	EntityRules.tick_barrels_in_fire(state, events)

	# 阶段 7：地块 modifier 倒计时
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		tile.tick_modifiers()

	# 阶段 8：火焰蔓延 + 草地随机生长
	TileRules.spread_fire(state)
	_tick_grass_growth(state)

	# 阶段 9：Pillar 光环
	_apply_tile_pillar_auras(state)


## 地块停留效果（通过 TileRules 的进入效果表统一分发）
static func _tick_tile_stay(state: GameState, unit: UnitState) -> void:
	TileRules.sync_standing_ground_effects(state, unit)
	TileRules.apply_enter_effects_for_occupied_cells(state, unit)


## overlay 对 status 参数的预处理表
## key: [status_id, modifier_type]  value: Callable(status) → void
static var _OVERLAY_STATUS_PRETICK: Array = [
	# 处于火焰中：burning 层数 ×2
	[Constants.STATUS_BURNING, Constants.TILE_MOD_FIRE,
		func(status: StatusInstance, state: GameState, unit: UnitState) -> void:
			status.stacks = status.stacks * _config_int("burning", "firelike_stack_mult")
			state.log("%s 处于火焰中，burning 层数翻倍为 %d" % [unit.uid, status.stacks])],
	[Constants.STATUS_BURNING, Constants.TILE_MOD_TOXIC_SMOKE,
		func(status: StatusInstance, state: GameState, unit: UnitState) -> void:
			status.stacks = status.stacks * _config_int("burning", "firelike_stack_mult")
			state.log("%s 处于毒烟中，burning 层数翻倍为 %d" % [unit.uid, status.stacks])],
]


## 通用 overlay-status 预处理：遍历表格，无需针对每种状态单独写函数
static func _pretick_overlay_status_modifiers(state: GameState, unit: UnitState) -> void:
	var applied: Dictionary = {}
	for entry in _OVERLAY_STATUS_PRETICK:
		var status_id: String = entry[0]
		var modifier_type: String = entry[1]
		var callback: Callable = entry[2]
		var effect_key := "%s:%s" % [status_id, modifier_type]
		if status_id == Constants.STATUS_BURNING \
		and modifier_type in [Constants.TILE_MOD_FIRE, Constants.TILE_MOD_TOXIC_SMOKE]:
			effect_key = "burning_firelike"
		if applied.has(effect_key):
			continue
		if not TileRules.unit_occupies_modifier(state, unit, modifier_type):
			continue
		var status: StatusInstance = unit.get_status(status_id)
		if status == null:
			continue
		callback.call(status, state, unit)
		applied[effect_key] = true


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
	_CombatTransaction.begin_from_state(state).apply_status(unit, incoming, {"emit_event": false, "reason": "status_rules_apply"})
	state.log("%s 获得状态 %s" % [unit.uid, _StatusRegistry.display_name(status_id)])


static func _tick_phase(
	state: GameState,
	unit: UnitState,
	phase: String,
	events: Array[Dictionary] = []
) -> void:
	var next: Array[StatusInstance] = []
	for status in unit.statuses:
		if _StatusRegistry.tick_phase(status.status_id) != phase:
			next.append(status)
			continue
		_resolve_tick(state, unit, status, events)
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


static func _resolve_tick(
	state: GameState,
	unit: UnitState,
	status: StatusInstance,
	events: Array[Dictionary] = []
) -> void:
	match status.status_id:
		Constants.STATUS_POISON:
			var poison_dmg := status.stacks * CombatConfig.poison_fog_damage()
			_apply_tick_damage(state, unit, poison_dmg, status.source_uid, "poison", events)
		Constants.STATUS_BURNING:
			_apply_tick_damage(state, unit, status.stacks, status.source_uid, "burning", events)


static func _apply_tick_damage(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	events: Array[Dictionary] = []
) -> void:
	var tx := _CombatTransaction.begin(state, events)
	tx.true_damage_unit(unit, amount, source_uid, reason)
	tx.finish("StatusRules.%s_tick" % reason)


## 草地随机生长为草丛
static func _tick_grass_growth(state: GameState) -> void:
	var rng := _rng_service()
	if rng == null:
		return
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_GRASS and bool(rng.chance("tile_grass_grow_%s" % str(tile.pos), CombatConfig.grass_grow_chance())):
			tile.tile_id = Constants.TILE_BUSH
			tile._init_ground_tags()
			state.log("草地 %s 长成草丛" % [tile.pos])


static func _apply_tile_pillar_auras(state: GameState) -> void:
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_PILLAR and tile.has_tile_tag(Constants.TAG_TILE_INTERACTIVE):
			TileEffects.tick_pillar_aura(state, tile)


static func _apply_blue_turn_start_effects(state: GameState, unit: UnitState) -> void:
	GemEffects.run_unit_hooks(state, unit, Constants.SLOT_BLUE, GemEffects.TIMING_TURN_START, {})


static func _default_stacks(entry_id: String) -> int:
	return StatusConfig.default_stacks(entry_id)


static func _default_duration(entry_id: String) -> int:
	return StatusConfig.default_duration(entry_id)


static func _config_int(entry_id: String, field_id: String) -> int:
	return StatusConfig.int_value(entry_id, field_id)
