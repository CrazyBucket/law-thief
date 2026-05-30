class_name BattleActionService
extends RefCounted

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
	if state.player_moved:
		return _fail("本回合已移动")
	var player: UnitState = state.get_player()
	if player == null:
		return _fail("玩家不存在")
	if not StatusRules.can_move(player):
		return _fail("被束缚，无法移动")
	var reachable := BoardUtils.reachable_cells(state, player.pos, player.move_points)
	if not target_pos in reachable:
		return _fail("无法移动到该格")
	var path := BoardUtils.astar_path(state, player.pos, target_pos, player.move_points, player.uid, {
		"allow_partial_path": false
	})
	if path.is_empty():
		return _fail("无法规划路径")
	var presentation_state: GameState = state.clone()
	var previous := player.pos
	var move_events: Array[Dictionary] = []
	for step in path:
		var from_pos := player.pos
		player.facing = UnitState.facing_from_step(from_pos, step)
		state.move_unit(player, step)
		TileRules.on_unit_moved_through(state, player, step)
		state.on_unit_move.emit(player.uid, from_pos, step)
		move_events.append({"type": "move_step", "uid": player.uid, "from": from_pos, "to": step})
	TileRules.on_unit_entered(state, player, previous)
	state.player_moved = true
	state.log("玩家移动到 %s" % target_pos)
	IntentSystem.refresh_all_intents(state)
	# 注意：不调用 _emit_changed()，由 UI 层在动画播完后手动刷新
	# 避免动画开始前 queue_redraw 把单位画到终点导致闪烁
	var result := _ok()
	result["move_events"] = move_events
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
	if ctrl.state.player_acted:
		return _fail("本回合已行动")
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
	if state.player_acted:
		return _fail("本回合已行动")
	var player: UnitState = state.get_player()
	if player == null:
		return _fail("玩家不存在")
	if target_pos == player.pos:
		return _fail("不能攻击自己")
	if not BoardUtils.can_unit_attack_cell(player, state, target_pos, Constants.ATTACK_RANGE):
		return _fail("目标超出射程")
	var presentation_state: GameState = state.clone()
	var from_pos := player.pos
	var to_pos := target_pos
	var attack_events: Array[Dictionary] = []
	var atk_result := CombatRules.ranged_attack(
		state, player, target_pos, Constants.ATTACK_RANGE, {"aim_cell": target_pos}
	)
	if not atk_result.get("ok", false):
		return _fail(atk_result.get("reason", "无法攻击"))
	attack_events.append_array(atk_result.get("events", [] as Array[Dictionary]))
	state.player_acted = true
	ctrl._check_battle_end()
	IntentSystem.refresh_all_intents(state)
	ctrl._emit_changed()
	return _ok({
		"from_pos": from_pos,
		"to_pos": to_pos,
		"attack_events": attack_events,
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
	var player: UnitState = ctrl.state.get_player()
	var target: UnitState = ctrl.state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot: SlotState = target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.extract(ctrl.state, player, target, slot)
	if result.get("ok", false):
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
	var player: UnitState = ctrl.state.get_player()
	var target: UnitState = ctrl.state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot: SlotState = target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.insert(ctrl.state, player, target, slot)
	if result.get("ok", false):
		ctrl.anim_gem_flash.emit(target.pos, Color(0.4, 0.9, 1.0))
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
		result["events"] = events
		result["presentation_state"] = presentation_state
		ctrl._check_battle_end()
		ctrl._emit_changed()
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
	var player: UnitState = ctrl.state.get_player()
	var tile: TileState = ctrl.state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot: SlotState = tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.extract_tile(ctrl.state, player, tile, slot)
	if result.get("ok", false):
		ctrl.anim_gem_flash.emit(tile_pos, Color(1.0, 0.85, 0.3))
		ctrl._emit_changed()
	return result


func try_insert_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleActionService: _ctrl is null in try_insert_tile")
		return _fail("内部错误：controller 未初始化")
	if ctrl.state == null:
		return _fail("战斗未开始")
	var player: UnitState = ctrl.state.get_player()
	var tile: TileState = ctrl.state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot: SlotState = tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.insert_tile(ctrl.state, player, tile, slot)
	if result.get("ok", false):
		ctrl.anim_gem_flash.emit(tile_pos, Color(0.4, 0.9, 1.0))
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
		result["events"] = events
		result["presentation_state"] = presentation_state
		ctrl._check_battle_end()
		ctrl._emit_changed()
	return result


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
