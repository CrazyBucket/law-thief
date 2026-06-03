class_name OverloadRules
extends RefCounted

const MUTATIONS: Array[String] = [
	Constants.OVERLOAD_LAWLESS_ANY_EXTRACT,
	Constants.OVERLOAD_GEM_OP_DAMAGE,
	Constants.OVERLOAD_ECHO_EXTRACT,
	Constants.OVERLOAD_RANDOM_ENEMY_GEMS,
	Constants.OVERLOAD_SPAWN_ENFORCER,
	Constants.OVERLOAD_AI_CONTROL,
	Constants.OVERLOAD_SPAWN_LAW_BEAST,
]


static func can_force_insert(state: GameState) -> bool:
	return state != null \
		and state.overload_last_action == Constants.ACTION_INSERT \
		and state.overload_last_insert_turn == state.turn_index


static func record_insert(state: GameState, forced: bool = false) -> void:
	if state == null:
		return
	var chained := can_force_insert(state)
	state.overload_last_action = Constants.ACTION_INSERT
	state.overload_last_insert_turn = state.turn_index
	if chained or forced:
		state.overload_pending = true
		state.overload_pending_turn = state.turn_index
		state.log("过载预兆：连续嵌入已触发，结束回合后异变生效；切换/取消嵌入可避免")


static func record_non_insert_action(state: GameState, action: String = "") -> void:
	if state == null:
		return
	if action == Constants.ACTION_INSERT:
		return
	cancel_pending(state)
	state.overload_last_action = action


static func cancel_pending(state: GameState) -> void:
	if state == null:
		return
	if state.overload_pending:
		state.log("过载已取消")
	state.overload_pending = false
	state.overload_pending_turn = 0


static func activate_pending(state: GameState) -> void:
	if state == null or not state.overload_pending:
		return
	var mutation := _pick_next_mutation(state)
	state.overload_pending = false
	state.overload_pending_turn = 0
	if mutation.is_empty():
		state.log("过载涌动，但暂未形成新的异变")
		return
	if mutation not in state.overload_active_mutations:
		state.overload_active_mutations.append(mutation)
	state.log("过载生效：%s" % mutation_label(mutation))
	match mutation:
		Constants.OVERLOAD_RANDOM_ENEMY_GEMS:
			fill_random_enemy_gem(state)
		Constants.OVERLOAD_SPAWN_ENFORCER:
			spawn_special_enemy(state, "unit_overload_enforcer", "执律者")
		Constants.OVERLOAD_SPAWN_LAW_BEAST:
			spawn_law_beast(state)
	IntentSystem.refresh_all_intents(state)


static func is_active(state: GameState, mutation: String) -> bool:
	return state != null and mutation in state.overload_active_mutations


static func on_enemy_gem_extracted(state: GameState, unit: UnitState, _slot_type: String, gem_uid: String) -> void:
	if not is_active(state, Constants.OVERLOAD_LAWLESS_ANY_EXTRACT):
		return
	if unit == null or unit.team != Constants.TEAM_ENEMY:
		return
	StatusRules.apply_lawless(state, unit, gem_uid)


static func leave_extract_echo(state: GameState, slot: SlotState, gem: GemState, owner_uid: String = "") -> void:
	if not is_active(state, Constants.OVERLOAD_ECHO_EXTRACT):
		return
	if slot == null or gem == null or not slot.gem_uid.is_empty():
		return
	var registry: Node = _data_registry()
	if registry == null:
		return
	var echo_uid: String = str(registry.next_runtime_uid("echo_gem"))
	var echo: GemState = registry.create_gem_instance(echo_uid, gem.gem_id, gem.def_overrides)
	echo.owner_uid = owner_uid
	echo.slot_index = -1
	state.gems[echo_uid] = echo
	slot.gem_uid = echo_uid
	state.overload_echo_gems[echo_uid] = state.turn_index + 1
	state.log("过载残响：%s 的回声暂留原槽" % registry.get_gem_display_name(gem))


static func apply_gem_operation_backlash(state: GameState) -> void:
	if not is_active(state, Constants.OVERLOAD_GEM_OP_DAMAGE):
		return
	var player := state.get_player()
	if player == null or not player.alive:
		return
	CombatRules.apply_true_damage(
		state,
		player,
		Constants.OVERLOAD_GEM_OP_DAMAGE_AMOUNT,
		player.uid,
		"overload_gem_operation"
	)


static func tick_turn_start(state: GameState) -> void:
	if state == null:
		return
	_clear_expired_echoes(state)
	if is_active(state, Constants.OVERLOAD_RANDOM_ENEMY_GEMS):
		fill_random_enemy_gem(state)
	if is_active(state, Constants.OVERLOAD_AI_CONTROL):
		_try_ai_control_player(state)
	IntentSystem.refresh_all_intents(state)


static func fill_random_enemy_gem(state: GameState) -> void:
	var candidates: Array[Dictionary] = []
	for unit in state.get_alive_enemies():
		for slot in unit.slots:
			if slot == null or not slot.gem_uid.is_empty() or not slot.is_operable(state.turn_index):
				continue
			candidates.append({"unit": unit, "slot": slot})
	if candidates.is_empty():
		return
	var rng: Node = _rng_service()
	var registry: Node = _data_registry()
	if rng == null or registry == null:
		return
	var picked: Dictionary = rng.pick("overload_fill_enemy_%d" % state.turn_index, candidates)
	var unit: UnitState = picked.get("unit", null)
	var slot: SlotState = picked.get("slot", null)
	if unit == null or slot == null:
		return
	var gem_id: String = str(registry.roll_spawnable_gem_id("overload_fill_gem_%d" % state.turn_index))
	if gem_id.is_empty():
		return
	var gem_uid: String = str(registry.next_runtime_uid("overload_gem"))
	var gem: GemState = registry.create_gem_instance(gem_uid, gem_id, {})
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid
	state.log("过载异变：%s 的 %s 槽被填入 %s" % [
		unit.uid, slot.slot_type, registry.get_gem_display_name(gem)
	])


static func spawn_law_beast(state: GameState) -> void:
	var beast := spawn_special_enemy(state, "unit_law_beast", "律兽")
	if beast == null:
		return
	var player := state.get_player()
	if player == null:
		return
	for slot in player.slots:
		if slot != null and slot.slot_type == Constants.SLOT_RED:
			slot.locked = true
			slot.lock_type = "overload_law_beast_ban"
			slot.unlock_until_turn = -1
	state.log("律兽压制：玩家红槽被封禁")


static func spawn_special_enemy(state: GameState, unit_def_id: String, label: String) -> UnitState:
	if _alive_enemy_def_exists(state, unit_def_id):
		return null
	var registry: Node = _data_registry()
	if registry == null or not registry.has_unit_def(unit_def_id):
		return null
	var cell := _first_free_cell(state)
	if cell == Vector2i(-1, -1):
		return null
	var uid: String = str(registry.next_runtime_uid(unit_def_id))
	var def: Dictionary = registry.get_unit_def(unit_def_id)
	_instantiate_spawn_gems(state, uid, def, registry)
	var unit := UnitState.from_def(uid, unit_def_id, Constants.TEAM_ENEMY, cell, def)
	for i in range(unit.slots.size()):
		var slot: SlotState = unit.slots[i]
		if slot != null and not slot.gem_uid.is_empty() and state.gems.has(slot.gem_uid):
			var gem: GemState = state.gems[slot.gem_uid]
			gem.owner_uid = unit.uid
			gem.slot_index = i
	state.register_unit(unit)
	state.log("过载异变：%s 出现于 %s" % [label, cell])
	return unit


static func ai_control_probability(state: GameState) -> float:
	var chapter := 1
	var run_service: Node = _run_service()
	if run_service != null and run_service.has_method("get_current_chapter"):
		chapter = clampi(int(run_service.get_current_chapter()), 1, 45)
	var gem_count := _player_gem_count(state)
	var percent := 75.0 - float(chapter - 3) - float(gem_count - 9) * 7.0
	return clampf(percent / 100.0, 0.0, 0.95)


static func mutation_label(mutation: String) -> String:
	match mutation:
		Constants.OVERLOAD_LAWLESS_ANY_EXTRACT:
			return "拔走怪物任意宝石都会使其失律"
		Constants.OVERLOAD_GEM_OP_DAMAGE:
			return "宝石操作反噬，玩家扣血"
		Constants.OVERLOAD_ECHO_EXTRACT:
			return "拔走宝石会留下残响一回合"
		Constants.OVERLOAD_RANDOM_ENEMY_GEMS:
			return "场上开始给怪物随机填充宝石"
		Constants.OVERLOAD_SPAWN_ENFORCER:
			return "执律者降临"
		Constants.OVERLOAD_AI_CONTROL:
			return "玩家每回合可能被 AI 接管"
		Constants.OVERLOAD_SPAWN_LAW_BEAST:
			return "BOSS 律兽出现"
	return mutation


static func _pick_next_mutation(state: GameState) -> String:
	var candidates: Array[String] = []
	for mutation in MUTATIONS:
		if mutation not in state.overload_active_mutations:
			candidates.append(mutation)
	if candidates.is_empty():
		candidates = MUTATIONS.duplicate()
	var rng: Node = _rng_service()
	if rng == null:
		return candidates[0] if not candidates.is_empty() else ""
	return str(rng.pick("overload_mutation_%d_%d" % [state.turn_index, state.overload_active_mutations.size()], candidates))


static func _clear_expired_echoes(state: GameState) -> void:
	var expired: Array[String] = []
	for gem_uid in state.overload_echo_gems.keys():
		if state.turn_index > int(state.overload_echo_gems[gem_uid]):
			expired.append(str(gem_uid))
	for gem_uid in expired:
		_remove_echo_gem(state, gem_uid)


static func _remove_echo_gem(state: GameState, gem_uid: String) -> void:
	state.overload_echo_gems.erase(gem_uid)
	for unit in state.units.values():
		for slot in unit.slots:
			if slot != null and slot.gem_uid == gem_uid:
				slot.gem_uid = ""
	for tile in state.tiles.values():
		for slot in tile.slots:
			if slot != null and slot.gem_uid == gem_uid:
				slot.gem_uid = ""
	state.gems.erase(gem_uid)
	state.log("过载残响消散")


static func _try_ai_control_player(state: GameState) -> void:
	if state.battle_temp_flags.get("overload_ai_turn", 0) == state.turn_index:
		return
	state.battle_temp_flags["overload_ai_turn"] = state.turn_index
	var probability := ai_control_probability(state)
	var rng: Node = _rng_service()
	if rng == null or not rng.chance("overload_ai_control_%d" % state.turn_index, probability):
		return
	var player := state.get_player()
	if player == null or not player.alive:
		return
	StatusRegistry.apply_to_unit(player, StatusInstance.create(Constants.STATUS_OVERLOAD_AI_CONTROL, 1, 1))
	state.player_moved = true
	state.player_acted = true
	state.log("过载异变：AI 接管本回合（概率 %.0f%%），玩家行动被消耗" % (probability * 100.0))


static func _player_gem_count(state: GameState) -> int:
	var count := 0
	var player := state.get_player()
	if player != null:
		for slot in player.slots:
			if slot != null and not slot.gem_uid.is_empty():
				count += 1
	if not state.held_gem_uid.is_empty():
		count += 1
	return count


static func _first_free_cell(state: GameState) -> Vector2i:
	for y in range(state.board_size.y):
		for x in range(state.board_size.x):
			var cell := Vector2i(x, y)
			if state.get_unit_at(cell) != null:
				continue
			if BoardUtils.blocking_entity_at(state, cell) != null:
				continue
			return cell
	return Vector2i(-1, -1)


static func _alive_enemy_def_exists(state: GameState, unit_def_id: String) -> bool:
	for unit in state.get_alive_enemies():
		if unit.unit_def_id == unit_def_id:
			return true
	return false


static func _instantiate_spawn_gems(state: GameState, owner_uid: String, def: Dictionary, registry: Node) -> void:
	var slots: Array = def.get("slots", [])
	for slot_entry in slots:
		if not (slot_entry is Dictionary):
			continue
		if not slot_entry.has("gem_id"):
			continue
		var gem_id := str(slot_entry.get("gem_id", ""))
		if gem_id.is_empty():
			continue
		var gem_uid: String = str(registry.next_runtime_uid("gem"))
		var gem: GemState = registry.create_gem_instance(gem_uid, gem_id, slot_entry.get("gem_overrides", {}))
		gem.owner_uid = owner_uid
		state.gems[gem_uid] = gem
		slot_entry["gem_uid"] = gem_uid
		slot_entry.erase("gem_id")
		slot_entry.erase("gem_overrides")


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RngService")


static func _run_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RunService")
