class_name BattleActionService
extends RefCounted

const EventValidator = preload("res://scripts/debug/event_validator.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")

var _ctrl: BattleController


func setup(controller: BattleController) -> void:
	_ctrl = controller


func _c() -> BattleController:
	return _ctrl


# ═══════════════════════════════════════════════════════════════════════════
# 玩家移动
# ═══════════════════════════════════════════════════════════════════════════

func try_move(target_pos: Vector2i) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_move")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		push_error("BattleActionService: state is null in try_move")
		return _fail("战斗未开始")
	if ctrl.state.phase != Constants.PHASE_PLAYER:
		push_warning("BattleActionService: try_move rejected — phase is '%s'" % ctrl.state.phase)
		return _fail("不是玩家回合")
	var state: GameState = ctrl.state
	var unlimited := ctrl.editor_unlimited_actions_enabled()
	if not unlimited and OverloadRules.blocks_player_manual_actions(state):
		return _fail("AI 已接管本回合")
	var player: UnitState = state.get_player()
	if player == null:
		return _fail("玩家不存在")
	var consume_bonus_move := false
	if not unlimited and state.player_moved:
		if not StatusRules.has_extra_move(player):
			return _fail("本回合已移动")
		consume_bonus_move = true
	if not unlimited and not StatusRules.can_move(player):
		var block_reason := StatusRules.move_block_reason(player)
		return _fail(block_reason if not block_reason.is_empty() else "无法移动")
	var move_budget := ctrl.player_move_budget(player)
	var reachable := BoardUtils.reachable_cells(state, player.pos, move_budget)
	if not target_pos in reachable:
		return _fail("无法移动到该格")
	var path := BoardUtils.astar_path(state, player.pos, target_pos, move_budget, player.uid, {
		"allow_partial_path": false
	})
	if path.is_empty():
		return _fail("无法规划路径")
	var presentation_state: GameState = state.clone()
	var previous := player.pos
	var move_events: Array[Dictionary] = []
	var tx := _CombatTransaction.begin(state, move_events).bind_event_sink()
	for step in path:
		tx.move_unit(player, step, {"reason": "player_move"})
		TileRules.on_unit_moved_through(state, player, step)
		if not player.alive:
			break
	if player.alive:
		TileRules.finish_voluntary_move(state, player, previous)
	# 旧式压力阀临时移动力：移动一次后重置剩余临时点数
	if state.battle_temp_flags.has("pressure_valve_temp_move"):
		var temp_move: int = int(state.battle_temp_flags["pressure_valve_temp_move"])
		state.battle_temp_flags.erase("pressure_valve_temp_move")
		player.move_points = maxi(0, player.move_points - temp_move)
	if not unlimited:
		if consume_bonus_move:
			StatusRules.consume_extra_move(player)
		state.player_moved = true
		OverloadRules.record_non_insert_action(state, Constants.ACTION_MOVE)
	state.log("玩家移动到 %s" % target_pos)
	ctrl._check_battle_end()
	if state.phase != Constants.PHASE_ENDED:
		IntentSystem.refresh_all_intents(state)
	# 注意：不调用 _emit_changed()，由 UI 层在动画播完后手动刷新
	# 避免动画开始前 queue_redraw 把单位画到终点导致闪烁
	var result := _ok()
	result["move_events"] = _validated_events(tx.finish("BattleActionService.try_move"), "BattleActionService.try_move")
	result["presentation_state"] = presentation_state
	return result


# ═══════════════════════════════════════════════════════════════════════════
# 攻击
# ═══════════════════════════════════════════════════════════════════════════

func try_attack(target_uid: String) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_attack")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if ctrl.state.phase != Constants.PHASE_PLAYER:
		return _fail("不是玩家回合")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var target: UnitState = ctrl.state.units.get(target_uid, null)
	if target == null or not target.alive:
		return _fail("目标无效")
	return try_attack_cell(target.pos)


func try_attack_cell(target_pos: Vector2i) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_attack_cell")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null or ctrl.state.phase != Constants.PHASE_PLAYER:
		return _fail("不是玩家回合")
	var state: GameState = ctrl.state
	var unlimited := ctrl.editor_unlimited_actions_enabled()
	if not unlimited and OverloadRules.blocks_player_manual_actions(state):
		return _fail("AI 已接管本回合")
	var player: UnitState = state.get_player()
	if player == null:
		return _fail("玩家不存在")
	var consume_bonus_attack := false
	if not unlimited and state.player_acted:
		if not StatusRules.has_extra_attack(player):
			return _fail("本回合已行动")
		consume_bonus_attack = true
	if target_pos == player.pos:
		return _fail("不能攻击自己")
	if GemEffects.unit_has_red_light(state, player) and not GemEffects.is_valid_light_aim(player, target_pos):
		return _fail("光束只能朝八个方向发射")
	var max_range := GemEffects.red_attack_range(state, player, Constants.ATTACK_RANGE)
	if not BoardUtils.can_unit_attack_cell(player, state, target_pos, max_range):
		return _fail("目标超出射程")
	var presentation_state: GameState = state.clone()
	var from_pos := player.pos
	var to_pos := target_pos
	var attack_events: Array[Dictionary] = []
	var atk_result := CombatRules.ranged_attack(
		state, player, target_pos, max_range, {"aim_cell": target_pos}
	)
	if not atk_result.get("ok", false):
		return _fail(atk_result.get("reason", "无法攻击"))
	attack_events.append_array(atk_result.get("events", [] as Array[Dictionary]))
	if not unlimited:
		if consume_bonus_attack:
			StatusRules.consume_extra_attack(player)
		state.player_acted = true
		OverloadRules.record_non_insert_action(state, Constants.ACTION_ATTACK)
	ctrl._check_battle_end()
	IntentSystem.refresh_all_intents(state)
	return _ok({
		"from_pos": from_pos,
		"to_pos": to_pos,
		"attack_events": _validated_events(attack_events, "BattleActionService.try_attack_cell"),
		"presentation_state": presentation_state,
	})


# ═══════════════════════════════════════════════════════════════════════════
# 单位槽位操作
# ═══════════════════════════════════════════════════════════════════════════

func try_extract(target_uid: String, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_extract")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var player: UnitState = ctrl.state.get_player()
	var target: UnitState = ctrl.state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot: SlotState = target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.extract(ctrl.state, player, target, slot)
	if result.get("ok", false):
		OverloadRules.record_non_insert_action(ctrl.state, Constants.ACTION_EXTRACT)
		OverloadRules.apply_gem_operation_backlash(ctrl.state)
		ctrl.anim_gem_flash.emit(target.pos, Color(1.0, 0.85, 0.3))
		ctrl._check_battle_end()
		ctrl._emit_changed()
	return result


func try_insert(target_uid: String, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_insert")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var player: UnitState = ctrl.state.get_player()
	var target: UnitState = ctrl.state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot: SlotState = target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.insert(ctrl.state, player, target, slot)
	if result.get("ok", false):
		OverloadRules.record_insert(ctrl.state, bool(result.get("overload_forced", false)))
		OverloadRules.apply_gem_operation_backlash(ctrl.state)
		ctrl._check_battle_end()
		ctrl._emit_changed()
	return result


func try_trigger(target_uid: String, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_trigger")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var player: UnitState = ctrl.state.get_player()
	var target: UnitState = ctrl.state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot: SlotState = target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var presentation_state: GameState = ctrl.state.clone()
	var events: Array[Dictionary] = []
	var result := GemRules.trigger(ctrl.state, player, target, slot, events)
	if result.get("ok", false):
		OverloadRules.record_non_insert_action(ctrl.state, Constants.ACTION_TRIGGER)
		OverloadRules.apply_gem_operation_backlash(ctrl.state)
		result["events"] = _validated_events(events, "BattleActionService.try_trigger")
		result["presentation_state"] = presentation_state
		ctrl._check_battle_end()
	return result


# ═══════════════════════════════════════════════════════════════════════════
# 地块槽位操作
# ═══════════════════════════════════════════════════════════════════════════

func try_extract_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_extract_tile")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var player: UnitState = ctrl.state.get_player()
	var tile: TileState = ctrl.state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot: SlotState = tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.extract_tile(ctrl.state, player, tile, slot)
	if result.get("ok", false):
		OverloadRules.record_non_insert_action(ctrl.state, Constants.ACTION_EXTRACT)
		OverloadRules.apply_gem_operation_backlash(ctrl.state)
		ctrl.anim_gem_flash.emit(tile_pos, Color(1.0, 0.85, 0.3))
		ctrl._check_battle_end()
		ctrl._emit_changed()
	return result


func try_insert_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_insert_tile")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var player: UnitState = ctrl.state.get_player()
	var tile: TileState = ctrl.state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot: SlotState = tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.insert_tile(ctrl.state, player, tile, slot)
	if result.get("ok", false):
		OverloadRules.record_insert(ctrl.state, bool(result.get("overload_forced", false)))
		OverloadRules.apply_gem_operation_backlash(ctrl.state)
		ctrl._check_battle_end()
		ctrl._emit_changed()
	return result


func try_trigger_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_trigger_tile")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	if not ctrl.editor_unlimited_actions_enabled() and OverloadRules.blocks_player_manual_actions(ctrl.state):
		return _fail("AI 已接管本回合")
	var player: UnitState = ctrl.state.get_player()
	var tile: TileState = ctrl.state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot: SlotState = tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var presentation_state: GameState = ctrl.state.clone()
	var events: Array[Dictionary] = []
	var result := GemRules.trigger_tile(ctrl.state, player, tile, slot, events)
	if result.get("ok", false):
		OverloadRules.record_non_insert_action(ctrl.state, Constants.ACTION_TRIGGER)
		OverloadRules.apply_gem_operation_backlash(ctrl.state)
		result["events"] = _validated_events(events, "BattleActionService.try_trigger_tile")
		result["presentation_state"] = presentation_state
		ctrl._check_battle_end()
	return result


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _validated_events(events: Array[Dictionary], context: String) -> Array[Dictionary]:
	if OS.is_debug_build():
		EventValidator.assert_valid(events, context)
	return events
