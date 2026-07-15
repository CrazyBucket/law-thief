class_name OverloadRules
extends RefCounted

const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _UnitSpawnService = preload("res://scripts/rules/unit_spawn_service.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")

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
	sync_active_mutations_to_overload_slots(state, false)
	var mutation := _pick_next_mutation(state)
	state.overload_pending = false
	state.overload_pending_turn = 0
	if mutation.is_empty():
		state.log("过载涌动，但暂未形成新的异变")
		return
	if mutation not in state.overload_active_mutations:
		state.overload_active_mutations.append(mutation)
	sync_active_mutations_to_overload_slots(state, true)
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
	if state == null:
		return false
	sync_active_mutations_to_overload_slots(state, false)
	return mutation in state.overload_active_mutations


static func overload_gem_count(state: GameState) -> int:
	if state == null:
		return 0
	var count := 0
	for unit in state.units.values():
		if unit == null or not unit.alive:
			continue
		count += _count_overload_slot_gems(unit.slots)
	for tile in state.tiles.values():
		if tile == null:
			continue
		count += _count_overload_slot_gems(tile.slots)
	return count


static func sync_active_mutations_to_overload_slots(state: GameState, allow_growth: bool = true) -> void:
	if state == null:
		return
	var target_count := overload_gem_count(state)
	while state.overload_active_mutations.size() > target_count:
		state.overload_active_mutations.pop_back()
	if not allow_growth:
		return
	while state.overload_active_mutations.size() < target_count:
		var mutation := _pick_next_mutation(state)
		if mutation.is_empty():
			return
		state.overload_active_mutations.append(mutation)


static func on_enemy_gem_extracted(state: GameState, unit: UnitState, _slot_type: String, gem_uid: String, force_active: bool = false) -> void:
	if not force_active and not is_active(state, Constants.OVERLOAD_LAWLESS_ANY_EXTRACT):
		return
	if unit == null or unit.team != Constants.TEAM_ENEMY:
		return
	StatusRules.apply_lawless(state, unit, gem_uid)


static func leave_extract_echo(state: GameState, slot: SlotState, gem: GemState, owner_uid: String = "", force_active: bool = false) -> void:
	if not force_active and not is_active(state, Constants.OVERLOAD_ECHO_EXTRACT):
		return
	if slot == null or gem == null or not slot.gem_uid.is_empty():
		return
	# 残响只复制真实宝石一次；残响本身不能继续产出残响，避免单回合无限拔取。
	if state.overload_echo_gems.has(gem.uid):
		return
	var registry: Node = _data_registry()
	if registry == null:
		return
	var echo_uid: String = str(registry.next_runtime_uid("echo_gem"))
	var echo: GemState = registry.create_gem_instance(echo_uid, gem.gem_id, gem.def_overrides)
	state.gems[echo_uid] = echo
	if not _GemTransfer.to_slot_reference(state, echo, slot, owner_uid):
		state.gems.erase(echo_uid)
		return
	state.overload_echo_gems[echo_uid] = state.turn_index + 1
	state.log("过载残响：%s 的回声暂留原槽" % registry.get_gem_display_name(gem))


static func apply_gem_operation_backlash(state: GameState, out_events: Array[Dictionary] = []) -> void:
	if not is_active(state, Constants.OVERLOAD_GEM_OP_DAMAGE):
		return
	var player := state.get_player()
	if player == null or not player.alive:
		return
	var damage := mini(CombatConfig.overload_gem_op_damage_amount(), maxi(player.hp - 1, 0))
	if damage <= 0:
		return
	var tx := _CombatTransaction.begin(state, out_events)
	tx.true_damage_unit(player, damage, player.uid, "overload_gem_operation")
	tx.finish("OverloadRules.apply_gem_operation_backlash")


static func tick_turn_start(state: GameState) -> Dictionary:
	if state == null:
		return {"events": [] as Array[Dictionary], "action": ""}
	var result := {"events": [] as Array[Dictionary], "action": ""}
	sync_active_mutations_to_overload_slots(state, true)
	_clear_expired_echoes(state)
	if is_active(state, Constants.OVERLOAD_RANDOM_ENEMY_GEMS):
		fill_random_enemy_gem(state)
	if is_active(state, Constants.OVERLOAD_AI_CONTROL):
		result = _try_ai_control_player(state)
	IntentSystem.refresh_all_intents(state)
	return result


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
	state.gems[gem_uid] = gem
	if not _GemTransfer.to_unit_slot(state, gem, unit, slot):
		state.gems.erase(gem_uid)
		return
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
	var spawn_result := _UnitSpawnService.register_spawn(state, unit, [], {
		"root_spawn": true,
		"emit_event": false,
		"event_kind": "none",
		"refresh_intent": false,
		"reason": "overload_reinforcement",
	})
	if not bool(spawn_result.get("ok", false)):
		return null
	_GemTransfer.reindex_unit(state, unit)
	state.log("过载异变：%s 出现于 %s" % [label, cell])
	return unit


static func ai_control_probability(state: GameState) -> float:
	var chapter := 1
	var run_service: Node = _run_service()
	if run_service != null and run_service.has_method("get_current_chapter"):
		chapter = clampi(
			int(run_service.get_current_chapter()),
			CombatConfig.overload_ai_control_min_chapter(),
			CombatConfig.overload_ai_control_max_chapter()
		)
	var gem_count := _player_gem_count(state)
	var percent := CombatConfig.overload_ai_control_base_percent()
	percent -= float(chapter - CombatConfig.overload_ai_control_chapter_baseline()) * CombatConfig.overload_ai_control_chapter_penalty()
	percent -= float(gem_count - CombatConfig.overload_ai_control_gem_baseline()) * CombatConfig.overload_ai_control_gem_penalty()
	return clampf(
		percent / 100.0,
		CombatConfig.overload_ai_control_min_probability(),
		CombatConfig.overload_ai_control_max_probability()
	)


static func blocks_player_manual_actions(state: GameState) -> bool:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return false
	var player := state.get_player()
	return player != null and player.alive and player.has_status(Constants.STATUS_OVERLOAD_AI_CONTROL)


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


static func panel_detail_lines(state: GameState) -> Array[String]:
	if state == null:
		return []
	sync_active_mutations_to_overload_slots(state, false)
	var active_count := overload_gem_count(state)
	if active_count <= 0 and not state.overload_pending:
		return []
	var lines: Array[String] = []
	var total_layers := active_count + (1 if state.overload_pending else 0)
	lines.append("过载 %d 层" % total_layers)
	for mutation in state.overload_active_mutations:
		lines.append("· %s" % mutation_label(mutation))
	if state.overload_pending:
		var pending_mutation := _pick_next_mutation(state)
		if not pending_mutation.is_empty():
			lines.append("· 待生效：%s" % mutation_label(pending_mutation))
	if is_active(state, Constants.OVERLOAD_AI_CONTROL):
		lines.append("AI 接管几率 %d%%" % int(roundf(ai_control_probability(state) * 100.0)))
	return lines


static func _pick_next_mutation(state: GameState) -> String:
	if state == null:
		return ""
	for mutation in MUTATIONS:
		if mutation not in state.overload_active_mutations:
			return mutation
	return ""


static func _count_overload_slot_gems(slots: Array) -> int:
	var count := 0
	for slot in slots:
		if slot == null:
			continue
		if slot.lock_type == Constants.LOCK_OVERLOAD_SLOT and not slot.gem_uid.is_empty():
			count += 1
	return count


static func _clear_expired_echoes(state: GameState) -> void:
	var expired: Array[String] = []
	for gem_uid in state.overload_echo_gems.keys():
		if state.turn_index > int(state.overload_echo_gems[gem_uid]):
			expired.append(str(gem_uid))
	for gem_uid in expired:
		_remove_echo_gem(state, gem_uid)


static func _remove_echo_gem(state: GameState, gem_uid: String) -> void:
	state.overload_echo_gems.erase(gem_uid)
	_GemTransfer.remove(state, gem_uid)
	state.log("过载残响消散")


static func _try_ai_control_player(state: GameState) -> Dictionary:
	var out_events: Array[Dictionary] = []
	if state.battle_temp_flags.get("overload_ai_turn", 0) == state.turn_index:
		return {"events": out_events, "action": ""}
	state.battle_temp_flags["overload_ai_turn"] = state.turn_index
	var probability := ai_control_probability(state)
	var rng: Node = _rng_service()
	if rng == null or not rng.chance("overload_ai_control_%d" % state.turn_index, probability):
		return {"events": out_events, "action": ""}
	var player := state.get_player()
	if player == null or not player.alive:
		return {"events": out_events, "action": ""}
	StatusRegistry.apply_to_unit(player, StatusInstance.create(Constants.STATUS_OVERLOAD_AI_CONTROL, 1, 1))
	var result := _execute_player_ai_control(state, player, out_events)
	if result.is_empty():
		state.log("过载异变：AI 接管本回合（概率 %.0f%%），但没有可执行行动" % (probability * 100.0))
	else:
		state.log("过载异变：AI 接管本回合（概率 %.0f%%），自动%s" % [
			probability * 100.0,
			result,
		])
	return {"events": out_events, "action": result}


static func _execute_player_ai_control(state: GameState, player: UnitState, out_events: Array[Dictionary]) -> String:
	var actions: Array[String] = []
	if not state.held_gem_uid.is_empty():
		var insert_result := _try_player_ai_insert(state, player, out_events)
		if not insert_result.is_empty():
			actions.append(insert_result)
	if state.held_gem_uid.is_empty():
		var extract_result := _try_player_ai_extract(state, player, out_events)
		if not extract_result.is_empty():
			actions.append(extract_result)
	if player.alive and not state.player_moved and StatusRules.can_move(player):
		var moved := _move_player_toward_nearest_enemy(state, player, out_events)
		if moved:
			state.player_moved = true
			actions.append("移动")
	if player.alive and not state.player_acted:
		var attack_target := _nearest_attackable_enemy(state, player)
		if attack_target != null:
			var max_range := GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
			var attack_result := CombatRules.ranged_attack(
				state,
				player,
				attack_target.pos,
				max_range,
				{"aim_cell": attack_target.pos}
			)
			if attack_result.get("ok", false):
				out_events.append_array(attack_result.get("events", [] as Array[Dictionary]))
				state.player_acted = true
				var registry := _data_registry()
				var target_name := attack_target.unit_def_id
				if registry != null:
					target_name = registry.get_unit_display_name(attack_target.unit_def_id)
				actions.append("攻击 %s" % target_name)
	return "、".join(actions)


static func _try_player_ai_insert(state: GameState, player: UnitState, out_events: Array[Dictionary]) -> String:
	for unit in _sorted_units_by_distance(state, player):
		for slot in unit.slots:
			if slot == null or not slot.gem_uid.is_empty():
				continue
			var check := GemRules.can_insert(state, player, unit, slot)
			if not check.get("ok", false):
				continue
			var held_gem: GemState = state.gems.get(state.held_gem_uid, null)
			var result := GemRules.insert(state, player, unit, slot)
			if not result.get("ok", false):
				continue
			record_insert(state, bool(result.get("overload_forced", false)))
			out_events.append(_EventBuilder.gem_flash(unit.pos, {
				"color": _data_registry().get_gem_color(held_gem) if held_gem != null else Color.WHITE,
			}))
			apply_gem_operation_backlash(state, out_events)
			return "嵌入 %s" % _unit_label(unit)
	return ""


static func _try_player_ai_extract(state: GameState, player: UnitState, out_events: Array[Dictionary]) -> String:
	for unit in _sorted_units_by_distance(state, player):
		for slot in unit.slots:
			if slot == null or slot.gem_uid.is_empty():
				continue
			var check := GemRules.can_extract(state, player, unit, slot)
			if not check.get("ok", false):
				continue
			var result := GemRules.extract(state, player, unit, slot)
			if not result.get("ok", false):
				continue
			record_non_insert_action(state, Constants.ACTION_EXTRACT)
			out_events.append(_EventBuilder.gem_flash(unit.pos, {"color": Color(1.0, 0.85, 0.3)}))
			apply_gem_operation_backlash(state, out_events)
			return "拔取 %s" % _unit_label(unit)
	return ""


static func _nearest_attackable_enemy(state: GameState, player: UnitState) -> UnitState:
	var max_range := GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
	var best: UnitState = null
	var best_dist := 999999
	for enemy in state.get_alive_enemies():
		if enemy == null or not enemy.alive:
			continue
		if not BoardUtils.can_unit_attack_cell(player, state, enemy.pos, max_range):
			continue
		var dist := BoardUtils.distance_between_units(player, enemy)
		if best == null or dist < best_dist:
			best = enemy
			best_dist = dist
	return best


static func _sorted_units_by_distance(state: GameState, player: UnitState) -> Array:
	var units: Array = []
	for unit in state.units.values():
		if unit != null and unit.alive:
			units.append(unit)
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		var da := BoardUtils.distance_between_units(player, a)
		var db := BoardUtils.distance_between_units(player, b)
		if da == db:
			return a.uid < b.uid
		return da < db
	)
	return units


static func _unit_label(unit: UnitState) -> String:
	var registry := _data_registry()
	if registry != null:
		return registry.get_unit_display_name(unit.unit_def_id)
	return unit.unit_def_id


static func _move_player_toward_nearest_enemy(state: GameState, player: UnitState, out_events: Array[Dictionary]) -> bool:
	var target := _nearest_enemy(state, player)
	if target == null:
		return false
	var move_budget := StatusRules.effective_move_points(player, player.move_points)
	if move_budget <= 0:
		return false
	var path := BoardUtils.astar_path(state, player.pos, target.pos, move_budget, player.uid, {}, {}, player)
	if path.is_empty():
		return false
	var previous := player.pos
	var tx := _CombatTransaction.begin(state, out_events).bind_event_sink()
	for step in path:
		if not BoardUtils.unit_footprint_passable(state, player, step, player.uid):
			break
		tx.move_unit(player, step, {"reason": "overload_ai_control"})
		TileRules.on_unit_moved_through(state, player, step)
		if not player.alive:
			break
	if player.alive:
		TileRules.finish_voluntary_move(state, player, previous)
	tx.finish("OverloadRules._move_player_toward_nearest_enemy")
	return player.pos != previous


static func _nearest_enemy(state: GameState, player: UnitState) -> UnitState:
	var best: UnitState = null
	var best_dist := 999999
	for enemy in state.get_alive_enemies():
		if enemy == null or not enemy.alive:
			continue
		var dist := BoardUtils.distance_between_units(player, enemy)
		if best == null or dist < best_dist:
			best = enemy
			best_dist = dist
	return best


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
		gem.mark_detached()
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
