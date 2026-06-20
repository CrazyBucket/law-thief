class_name CombatRules
extends RefCounted

const _SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")
const _GemEffects = preload("res://scripts/rules/gem_effects.gd")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")

static var _defer_death_hooks_depth: int = 0
static var _pending_deaths: Array[Dictionary] = []
static var _death_event_sink: Array[Dictionary] = []
static var _death_chain_serial: int = 0
static var _active_death_chain_id: int = 0


static func apply_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> int:
	if not unit.alive or amount <= 0:
		return 0
	if _try_resolve_counter_mark_before_hit(state, unit, source_uid):
		return 0
	var incoming := amount
	if unit.uid == state.player_uid:
		var registry := _relic_effect_registry()
		var absorb: bool = registry != null and bool(registry.query_modifier("first_damage_absorb", state))
		if absorb:
			incoming = 1
			state.battle_temp_flags["painkiller_used"] = true
	var blocked := incoming
	var remaining := StatusRules.absorb_with_shield(state, unit, incoming)
	blocked -= remaining
	if blocked > 0:
		state.log("%s 的护盾抵挡了 %d 点伤害 (%s)" % [unit.uid, blocked, reason])
	if remaining <= 0:
		return 0
	var final_amount := remaining
	if StatusRules.is_vulnerable(unit):
		final_amount = int(final_amount * 1.5)
	final_amount = GemEffects.intercept_damage_for_split(state, unit, source_uid, reason, final_amount)
	_apply_blue_reactive_effects(state, unit, source_uid, reason, final_amount)
	unit.hp -= final_amount
	_record_damage_pair(state, unit.uid, source_uid, final_amount)
	state.log("%s 受到 %d 点伤害 (%s)" % [unit.uid, final_amount, reason])
	state.on_damage_taken.emit(unit.uid, final_amount, reason)
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return final_amount


## 无视护甲的真实伤害（毒/火等 DoT 使用）
static func apply_true_damage(state: GameState, unit: UnitState, amount: int, source_uid: String, reason: String) -> int:
	if not unit.alive or amount <= 0:
		return 0
	if reason == "burning" or reason == "tile_fire":
		_apply_blue_reactive_effects(state, unit, source_uid, reason, amount)
	unit.hp -= amount
	_record_damage_pair(state, unit.uid, source_uid, amount)
	state.log("%s 受到 %d 点真实伤害 (%s)" % [unit.uid, amount, reason])
	state.on_damage_taken.emit(unit.uid, amount, reason)
	if unit.hp <= 0:
		_kill_unit(state, unit, source_uid, reason)
	return amount


static func begin_deferred_death_hooks(event_sink: Array[Dictionary] = []) -> void:
	_defer_death_hooks_depth += 1
	_death_event_sink = event_sink


static func end_deferred_death_hooks(state: GameState) -> void:
	_defer_death_hooks_depth = maxi(0, _defer_death_hooks_depth - 1)
	if _defer_death_hooks_depth > 0:
		return
	for entry in _pending_deaths:
		var unit: UnitState = entry.get("unit", null)
		if unit == null:
			continue
		var chain_id := int(entry.get("death_chain_id", 0))
		var prev_chain_id := _active_death_chain_id
		_active_death_chain_id = chain_id
		_GemEffects.on_unit_death(state, unit, _death_event_sink, {
			"death_chain_id": chain_id,
			"source_uid": entry.get("source_uid", ""),
			"damage": int(entry.get("damage", 0)),
			"reason": entry.get("reason", ""),
		})
		_drop_enemy_gems_to_ground(state, unit)
		_active_death_chain_id = prev_chain_id
	_pending_deaths.clear()
	_death_event_sink = []


static func _kill_unit(state: GameState, unit: UnitState, source_uid: String, reason: String) -> void:
	unit.hp = 0
	state.kill_unit(unit)  # 撤销占格索引并标记 alive = false
	state.log("%s 被击败" % unit.uid)
	state.on_unit_die.emit(unit.uid, source_uid, reason)
	var death_chain_id := _active_death_chain_id
	if death_chain_id <= 0:
		_death_chain_serial += 1
		death_chain_id = _death_chain_serial
	if _defer_death_hooks_depth > 0:
		var last_damage := int(state.battle_temp_flags.get("last_damage_taken:%s" % unit.uid, 0))
		_pending_deaths.append({
			"unit": unit,
			"death_chain_id": death_chain_id,
			"source_uid": source_uid,
			"damage": last_damage,
			"reason": reason,
		})
	else:
		var prev_chain_id := _active_death_chain_id
		_active_death_chain_id = death_chain_id
		var death_events: Array[Dictionary] = []
		if state.has_combat_event_sink():
			death_events = state.get_combat_event_sink()
		_GemEffects.on_unit_death(state, unit, death_events, {
			"death_chain_id": death_chain_id,
			"source_uid": source_uid,
			"damage": int(state.battle_temp_flags.get("last_damage_taken:%s" % unit.uid, 0)),
			"reason": reason,
		})
		_drop_enemy_gems_to_ground(state, unit)
		_active_death_chain_id = prev_chain_id


static func _record_damage_pair(state: GameState, victim_uid: String, source_uid: String, amount: int) -> void:
	if source_uid.is_empty() or amount <= 0:
		return
	state.battle_temp_flags["damaged_by:%s:%s:%d" % [victim_uid, source_uid, state.turn_index]] = true
	state.battle_temp_flags["last_damage_taken:%s" % victim_uid] = amount


static func _try_resolve_counter_mark_before_hit(state: GameState, victim: UnitState, source_uid: String) -> bool:
	if state == null or victim == null or source_uid.is_empty():
		return false
	var source: UnitState = state.units.get(source_uid, null)
	if source == null or not source.alive:
		return false
	var mark: StatusInstance = source.get_status(Constants.STATUS_COUNTER_MARK)
	if mark == null:
		return false
	var watchers: Array = mark.payload.get("watchers", [])
	if watchers.is_empty():
		source.remove_status(Constants.STATUS_COUNTER_MARK)
		return false
	var matched := false
	var matched_level := 1
	var next_watchers: Array = []
	for watcher_data in watchers:
		var watcher: Dictionary = watcher_data
		if str(watcher.get("uid", "")) == victim.uid and not matched:
			matched = true
			matched_level = maxi(1, int(watcher.get("level", 1)))
			continue
		next_watchers.append(watcher)
	if not matched:
		return false
	if next_watchers.is_empty():
		source.remove_status(Constants.STATUS_COUNTER_MARK)
	else:
		mark.payload["watchers"] = next_watchers
	if matched_level >= 2:
		var result := AttackPipeline.execute_aimed(state, victim, source.pos, [AttackPipeline.TAG_RANGED], {
			"damage_reason": "counter_red",
		})
		var sink := state.get_combat_event_sink()
		for event in result.get("events", []):
			if sink != null:
				sink.append(event)
		if matched_level >= 3 and not source.alive:
			_grant_counter_kill_refresh(state, victim)
		return not source.alive
	var tx := CombatTransaction.begin_from_state(state)
	tx.damage_unit(source, attack_damage(state, victim), victim.uid, "counter_red", {"pos": source.pos})
	if matched_level >= 3 and not source.alive:
		_grant_counter_kill_refresh(state, victim)
	return not source.alive


static func _grant_counter_kill_refresh(state: GameState, unit: UnitState) -> void:
	if state == null or unit == null or not unit.alive:
		return
	StatusRules.grant_extra_attack(state, unit, 1, unit.uid)


static func _drop_enemy_gems_to_ground(state: GameState, unit: UnitState) -> void:
	if state == null or unit == null or unit.team != Constants.TEAM_ENEMY:
		return
	var registry := _data_registry()
	for unit_slot in unit.slots:
		if unit_slot == null or unit_slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(unit_slot.gem_uid, null)
		if gem == null:
			unit_slot.gem_uid = ""
			continue
		gem.owner_uid = ""
		gem.slot_index = -1
		state.dropped_gems[gem.uid] = {
			"gem_uid": gem.uid,
			"gem_id": gem.gem_id,
			"pos": unit.pos,
			"source_unit_uid": unit.uid,
			"source_slot_type": unit_slot.slot_type,
		}
		unit_slot.gem_uid = ""
		var gem_name := gem.gem_id
		if registry != null:
			gem_name = registry.get_gem_display_name(gem)
		state.log("%s 掉落在 %s" % [
			gem_name,
			unit.pos,
		])


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")


## 近战攻击（pipeline 版本）：返回 {ok, reason, events}
static func melee_attack(
	state: GameState,
	attacker: UnitState,
	target: UnitState,
	charge_bonus: int = 0
) -> Dictionary:
	if not attacker.alive or not target.alive:
		return {"ok": false, "reason": "目标无效", "events": []}
	var payload: Dictionary = {}
	if charge_bonus > 0:
		payload["charge_bonus"] = charge_bonus
	return AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE], payload)


## 远程射击：唯一入口是瞄准格；格上单位在 pipeline 内解析为 target（可为 null）
static func ranged_attack(
	state: GameState,
	attacker: UnitState,
	aim_cell: Vector2i,
	max_range: int = Constants.ATTACK_RANGE,
	payload: Dictionary = {}
) -> Dictionary:
	if not attacker.alive:
		return {"ok": false, "reason": "攻击者无效", "events": []}
	return AttackPipeline.execute_aimed(
		state,
		attacker,
		aim_cell,
		[AttackPipeline.TAG_RANGED],
		payload,
		max_range
	)


## AI / 意图等仍持有目标单位引用时的薄封装
static func ranged_attack_unit(
	state: GameState,
	attacker: UnitState,
	target: UnitState,
	max_range: int = Constants.ATTACK_RANGE,
	payload: Dictionary = {}
) -> Dictionary:
	if not attacker.alive or not target.alive:
		return {"ok": false, "reason": "目标无效", "events": []}
	if BoardUtils.distance_between_units(attacker, target) > max_range:
		return {"ok": false, "reason": "目标超出射程", "events": []}
	var aim_cell: Vector2i = target.pos
	var raw: Variant = payload.get("aim_cell", null)
	if raw is Vector2i:
		aim_cell = raw
	return ranged_attack(state, attacker, aim_cell, max_range, payload)


## 分裂红槽近战：相邻格瞄准，走 split_shot 两翼，不发射弹道
static func split_melee_attack(state: GameState, attacker: UnitState, target: UnitState) -> Dictionary:
	if not attacker.alive or not target.alive:
		return {"ok": false, "reason": "目标无效", "events": []}
	if not BoardUtils.are_units_adjacent(attacker, target):
		return {"ok": false, "reason": "目标不在近战范围", "events": []}
	var aim_cell: Vector2i = _SplitShotRules.aim_pos_for_target(attacker.pos, target)
	return AttackPipeline.execute_aimed(
		state,
		attacker,
		aim_cell,
		[AttackPipeline.TAG_MELEE, AttackPipeline.TAG_SPLIT_SHOT],
		{"aim_cell": aim_cell},
		Constants.SPLIT_ATTACK_RANGE
	)


static func attack_damage(state: GameState, attacker: UnitState) -> int:
	var base := attacker.base_attack + GemEffects.get_attack_bonus(state, attacker)
	var registry := _relic_effect_registry()
	var mult: float = 1.0
	var bonus: int = 0
	if registry != null:
		mult = float(registry.query_modifier("attack_damage_mult", state))
		bonus = int(registry.query_modifier("attack_damage_bonus", state))
	var result := int(float(base) * mult) + bonus
	if StatusRules.is_weak(attacker):
		result = int(float(result) * 0.75)
	return maxi(0, result)


static func current_shield(_state: GameState, unit: UnitState) -> int:
	return StatusRules.get_shield(unit)


static func current_armor(state: GameState, unit: UnitState) -> int:
	return current_shield(state, unit)


static func _apply_blue_reactive_effects(state: GameState, owner: UnitState, source_uid: String, reason: String, damage: int = 0) -> void:
	var ctx := {"source_uid": source_uid, "reason": reason, "damage": damage}
	if state.has_combat_event_sink():
		ctx["events"] = state.get_combat_event_sink()
	GemEffects.run_unit_hooks(
		state,
		owner,
		Constants.SLOT_BLUE,
		GemEffects.TIMING_OWNER_DAMAGED,
		ctx
	)
