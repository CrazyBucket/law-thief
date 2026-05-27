class_name BattleController
extends RefCounted

const _StatusUi = preload("res://scripts/ui/status_ui.gd")

signal state_changed
signal battle_ended(result: String)
signal anim_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i)
signal anim_damage(grid: Vector2i, damage: int, is_crit: bool)
signal anim_gem_flash(grid: Vector2i, gem_color: Color)

var state: GameState = null
var selected_action: String = ""
var selected_unit_uid: String = ""


func start_encounter(encounter_id: String, seed_value: int = 0) -> void:
	state = _data_registry().create_battle_state(encounter_id, seed_value)
	selected_action = ""
	selected_unit_uid = state.player_uid if state != null else ""
	state.on_battle_start.emit()
	_emit_changed()


func select_action(action: String) -> void:
	selected_action = action
	_emit_changed()


func try_move(target_pos: Vector2i) -> Dictionary:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return _fail("不是玩家回合")
	if state.player_moved:
		return _fail("本回合已移动")
	var player := state.get_player()
	if player == null:
		return _fail("玩家不存在")
	if not StatusRules.can_move(player):
		return _fail("被束缚，无法移动")
	var reachable := BoardUtils.reachable_cells(state, player.pos, player.move_points)
	if not target_pos in reachable:
		return _fail("无法移动到该格")

	# 计算 A* 路径并逐格移动
	var path := BoardUtils.astar_path(state, player.pos, target_pos, player.move_points, player.uid, {
		"allow_partial_path": false
	})
	if path.is_empty():
		return _fail("无法规划路径")

	var previous := player.pos
	var move_events: Array[Dictionary] = []
	for step in path:
		var from_pos := player.pos
		player.pos = step
		TileRules.on_unit_moved_through(state, player, step)
		state.on_unit_move.emit(player.uid, from_pos, step)
		move_events.append({"type": "move_step", "uid": player.uid, "from": from_pos, "to": step})
	TileRules.on_unit_entered(state, player, previous)
	state.player_moved = true
	state.log("玩家移动到 %s" % target_pos)
	# 注意：不调用 _emit_changed()，由 UI 层在动画播完后手动刷新
	# 避免动画开始前 queue_redraw 把单位画到终点导致闪烁
	var result := _ok()
	result["move_events"] = move_events
	return result


func try_attack(target_uid: String) -> Dictionary:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return _fail("不是玩家回合")
	if state.player_acted:
		return _fail("本回合已行动")
	var player := state.get_player()
	var target: UnitState = state.units.get(target_uid, null)
	if target == null or not target.alive:
		return _fail("目标无效")
	var from_pos := player.pos
	var to_pos := target.pos
	var atk_result := CombatRules.ranged_attack(state, player, target)
	if not atk_result.get("ok", false):
		return _fail(atk_result.get("reason", "无法攻击"))
	state.player_acted = true
	_check_battle_end()
	IntentSystem.refresh_all_intents(state)
	_emit_changed()
	return _ok({
		"from_pos": from_pos,
		"to_pos": to_pos,
		"attack_events": atk_result.get("events", []),
	})


func try_skill(target_pos: Vector2i) -> Dictionary:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return _fail("不是玩家回合")
	if state.player_acted:
		return _fail("本回合已行动")
	var player := state.get_player()
	if player == null:
		return _fail("玩家不存在")
	var red_slot := player.get_slot(Constants.SLOT_RED)
	if red_slot == null or red_slot.gem_uid.is_empty():
		return _fail("红槽没有宝石")
	if not GemEffects.can_use_skill_at(state, player, target_pos):
		return _fail("无法对该位置使用技能")
	var events := GemEffects.player_use_skill(state, player, target_pos)
	state.player_acted = true
	_check_battle_end()
	IntentSystem.refresh_all_intents(state)
	_emit_changed()
	return _ok({"events": events})


func try_extract(target_uid: String, slot_index: int) -> Dictionary:
	var player := state.get_player()
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot := target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.extract(state, player, target, slot)
	if result.get("ok", false):
		anim_gem_flash.emit(target.pos, Color(1.0, 0.85, 0.3))
		_check_battle_end()
		_emit_changed()
	return result


func try_insert(target_uid: String, slot_index: int) -> Dictionary:
	var player := state.get_player()
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot := target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.insert(state, player, target, slot)
	if result.get("ok", false):
		anim_gem_flash.emit(target.pos, Color(0.4, 0.9, 1.0))
		_check_battle_end()
		_emit_changed()
	return result


func try_trigger(target_uid: String, slot_index: int) -> Dictionary:
	var player := state.get_player()
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return _fail("目标无效")
	var slot := target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.trigger(state, player, target, slot)
	if result.get("ok", false):
		_check_battle_end()
		_emit_changed()
	return result


# ═══════════════════════════════════════════════════════════════════════════
# 地块槽位操作
# ═══════════════════════════════════════════════════════════════════════════

func try_extract_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var player := state.get_player()
	var tile := state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot := tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.extract_tile(state, player, tile, slot)
	if result.get("ok", false):
		anim_gem_flash.emit(tile_pos, Color(1.0, 0.85, 0.3))
		_emit_changed()
	return result


func try_insert_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var player := state.get_player()
	var tile := state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot := tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.insert_tile(state, player, tile, slot)
	if result.get("ok", false):
		anim_gem_flash.emit(tile_pos, Color(0.4, 0.9, 1.0))
		_check_battle_end()
		_emit_changed()
	return result


func try_trigger_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	var player := state.get_player()
	var tile := state.get_tile(tile_pos)
	if tile == null or not tile.has_slots():
		return _fail("该地块没有槽位")
	var slot := tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	var result := GemRules.trigger_tile(state, player, tile, slot)
	if result.get("ok", false):
		_check_battle_end()
		_emit_changed()
	return result


func check_tile_slot_action(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	if state == null:
		return _fail("战斗未开始")
	var player := state.get_player()
	var tile := state.get_tile(tile_pos)
	if player == null or tile == null or not tile.has_slots():
		return _fail("目标无效")
	var slot := tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	match selected_action:
		Constants.ACTION_EXTRACT:
			return GemRules.can_extract_tile(state, player, tile, slot)
		Constants.ACTION_INSERT:
			return GemRules.can_insert_tile(state, player, tile, slot)
		Constants.ACTION_TRIGGER:
			return GemRules.can_trigger_tile(state, player, tile, slot)
	return _fail("当前操作不支持地块槽位")


## 开始敌方回合（只切换 phase，不执行逻辑）
func begin_enemy_phase() -> void:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return
	state.on_turn_end.emit(state.turn_index)
	state.phase = Constants.PHASE_ENEMY
	_emit_changed()


## 执行单个敌人的意图，返回动画事件列表
## 由 battle_scene 逐个调用，每次调用之间 await 动画完成
func execute_single_enemy(enemy: UnitState) -> Array[Dictionary]:
	if not enemy.alive:
		return [] as Array[Dictionary]
	if enemy.has_status(Constants.STATUS_PARALYZED):
		enemy.remove_status(Constants.STATUS_PARALYZED)
		state.log("%s 因麻痹跳过回合" % enemy.uid)
		_emit_changed()
		return [] as Array[Dictionary]
	var events := IntentSystem.execute_intent(state, enemy)
	_check_battle_end()
	_emit_changed()
	return events


## 结束敌方回合，进入下一个玩家回合
func finish_enemy_phase() -> void:
	StatusRules.tick_turn_end(state)
	if state.phase == Constants.PHASE_ENDED:
		return
	state.turn_index += 1
	StatusRules.tick_turn_start(state)
	state.phase = Constants.PHASE_PLAYER
	state.player_moved = false
	state.player_acted = false
	IntentSystem.refresh_all_intents(state)
	state.log("敌方回合结束")
	state.on_turn_start.emit(state.turn_index)
	_check_battle_end()
	_emit_changed()


## 获取排序后的存活敌人列表（sluggish 单位垫底，按原速度顺序）
func get_sorted_enemies() -> Array:
	if state == null:
		return []
	var enemies := state.get_alive_enemies()
	enemies.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		var a_slug: bool = a.has_status(Constants.STATUS_SLUGGISH)
		var b_slug: bool = b.has_status(Constants.STATUS_SLUGGISH)
		if a_slug != b_slug:
			return not a_slug
		if a.speed == b.speed:
			return a.uid < b.uid
		return a.speed > b.speed
	)
	return enemies


func get_held_gem() -> GemState:
	if state == null or state.held_gem_uid.is_empty():
		return null
	return state.gems.get(state.held_gem_uid, null)


func can_use_action(action: String) -> bool:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return false
	match action:
		Constants.ACTION_MOVE:
			return not state.player_moved
		Constants.ACTION_ATTACK, Constants.ACTION_TRIGGER:
			return not state.player_acted
		Constants.ACTION_SKILL:
			if state.player_acted:
				return false
			var player := state.get_player()
			if player == null:
				return false
			var red_slot := player.get_slot(Constants.SLOT_RED)
			return red_slot != null and not red_slot.gem_uid.is_empty()
		Constants.ACTION_EXTRACT:
			return state.held_gem_uid.is_empty()
		Constants.ACTION_INSERT:
			return not state.held_gem_uid.is_empty()
		Constants.ACTION_END_TURN:
			return true
	return false


func check_slot_action(target_uid: String, slot_index: int) -> Dictionary:
	if state == null:
		return _fail("战斗未开始")
	var player := state.get_player()
	var target: UnitState = state.units.get(target_uid, null)
	if player == null or target == null:
		return _fail("目标无效")
	var slot := target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	match selected_action:
		Constants.ACTION_EXTRACT:
			return GemRules.can_extract(state, player, target, slot)
		Constants.ACTION_INSERT:
			return GemRules.can_insert(state, player, target, slot)
		Constants.ACTION_TRIGGER:
			return GemRules.can_trigger(state, player, target, slot)
	return _fail("当前操作不支持槽位")


func get_highlights() -> Dictionary:
	var result := {
		"reachable": [],
		"targets": [],
		"paths": [],
		"danger": [],
		"effect_preview": [],
	}
	if state == null:
		return result
	var player := state.get_player()
	if player == null:
		return result
	if selected_action == Constants.ACTION_MOVE and not state.player_moved and StatusRules.can_move(player):
		result["reachable"] = BoardUtils.reachable_cells(state, player.pos, player.move_points)
	elif selected_action == Constants.ACTION_ATTACK and not state.player_acted:
		result["targets"] = _adjacent_enemy_cells(player.pos)
		result["effect_preview"] = _attack_effect_preview(player.pos)
	elif selected_action == Constants.ACTION_SKILL and can_use_action(Constants.ACTION_SKILL):
		result["targets"] = _skill_target_cells(player)
	elif selected_action == Constants.ACTION_TRIGGER and not state.player_acted:
		result["targets"] = _gem_target_cells(player)
	elif selected_action == Constants.ACTION_EXTRACT and can_use_action(Constants.ACTION_EXTRACT):
		result["targets"] = _gem_target_cells(player)
	elif selected_action == Constants.ACTION_INSERT and can_use_action(Constants.ACTION_INSERT):
		result["targets"] = _gem_target_cells(player)
	for enemy in state.get_alive_enemies():
		if enemy.intent == null:
			continue
		result["paths"] = result["paths"] + enemy.intent.path
		if enemy.intent.type in ["charge_explode", "shock"]:
			result["danger"] = result["danger"] + enemy.intent.affected_cells
	return result


func get_cell_preview(cell: Vector2i) -> Dictionary:
	if state == null:
		return {}
	var player := state.get_player()
	if player == null:
		return {}
	var unit := state.get_unit_at(cell)
	var tile := state.get_tile(cell)
	var lines: Array[String] = ["%s %s" % [_data_registry().get_tile_display_name(tile.tile_id), cell]]
	match tile.tile_id:
		Constants.TILE_SPIKE:
			lines.append("尖刺地块：进入受到 %d 伤害" % Constants.SPIKE_DAMAGE)
		Constants.TILE_WATER:
			lines.append("水洼：导电连锁区域")
		Constants.TILE_ALTAR:
			lines.append("祭坛：嵌入宝石触发全场效果")
		Constants.TILE_PILLAR:
			lines.append("机关柱：嵌入宝石产生持续光环")
	if tile.has_modifier("poison_fog"):
		lines.append("毒雾：回合开始受到 %d 伤害" % Constants.POISON_FOG_DAMAGE)
	# 显示地块槽位信息
	if tile.has_slots():
		for i in range(tile.slots.size()):
			var tslot: SlotState = tile.slots[i]
			lines.append(_slot_preview_line_tile(tile, tslot, i))
	if unit != null:
		lines.append("%s HP %d/%d" % [_data_registry().get_unit_display_name(unit.unit_def_id), unit.hp, unit.max_hp])
		for status_line in _StatusUi.preview_lines(unit):
			lines.append(status_line)
		if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
			lines.append("意图: %s" % unit.intent.preview_text)
		for i in range(unit.slots.size()):
			var slot: SlotState = unit.slots[i]
			lines.append(_slot_preview_line(unit, slot, i))
	match selected_action:
		Constants.ACTION_MOVE:
			if not state.player_moved and StatusRules.can_move(player) and cell in BoardUtils.reachable_cells(state, player.pos, player.move_points):
				lines.append("→ 点击移动")
		Constants.ACTION_ATTACK:
			if unit != null and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(player.pos, cell) <= Constants.ATTACK_RANGE:
				lines.append("→ 点击射击（%d 伤害）" % CombatRules.attack_damage(state, player))
				lines.append_array(_death_gem_preview_lines(unit))
		Constants.ACTION_EXTRACT:
			if unit != null and can_use_action(Constants.ACTION_EXTRACT):
				var valid := _valid_slot_indices(unit, Constants.ACTION_EXTRACT)
				if not valid.is_empty():
					lines.append("→ 可拔出: %s（免费）" % ", ".join(valid))
			elif tile.has_slots() and can_use_action(Constants.ACTION_EXTRACT):
				var tile_valid := _valid_tile_slot_indices(tile, Constants.ACTION_EXTRACT)
				if not tile_valid.is_empty():
					lines.append("→ 可从地块拔出: %s（免费）" % ", ".join(tile_valid))
		Constants.ACTION_INSERT:
			if unit != null and can_use_action(Constants.ACTION_INSERT):
				var insert_valid := _valid_slot_indices(unit, Constants.ACTION_INSERT)
				if not insert_valid.is_empty():
					lines.append("→ 可嵌入: %s（免费）" % ", ".join(insert_valid))
			elif tile.has_slots() and can_use_action(Constants.ACTION_INSERT):
				var tile_insert_valid := _valid_tile_slot_indices(tile, Constants.ACTION_INSERT)
				if not tile_insert_valid.is_empty():
					lines.append("→ 可嵌入地块: %s（免费）" % ", ".join(tile_insert_valid))
		Constants.ACTION_TRIGGER:
			if unit != null and not state.player_acted:
				var trigger_valid := _valid_slot_indices(unit, Constants.ACTION_TRIGGER)
				if not trigger_valid.is_empty():
					lines.append("→ 可触发: %s（消耗行动）" % ", ".join(trigger_valid))
			elif tile.has_slots() and not state.player_acted:
				var tile_trigger_valid := _valid_tile_slot_indices(tile, Constants.ACTION_TRIGGER)
				if not tile_trigger_valid.is_empty():
					lines.append("→ 可触发地块: %s（消耗行动）" % ", ".join(tile_trigger_valid))
	return {"title": lines[0] if not lines.is_empty() else "", "body": "\n".join(lines)}


func get_action_hint() -> String:
	match selected_action:
		Constants.ACTION_MOVE:
			if state != null:
				var player := state.get_player()
				if player != null and not StatusRules.can_move(player):
					return "移动：你被束缚，暂时无法移动"
			return "移动：点击蓝色高亮格（每回合 1 次）"
		Constants.ACTION_ATTACK:
			return "射击：点击 %d 格内敌人（消耗行动）" % Constants.ATTACK_RANGE
		Constants.ACTION_SKILL:
			var player := state.get_player()
			if player != null:
				var red_slot := player.get_slot(Constants.SLOT_RED)
				if red_slot != null and not red_slot.gem_uid.is_empty():
					var gem: GemState = state.gems.get(red_slot.gem_uid, null)
					if gem != null:
						return "技能：%s（消耗行动）" % _data_registry().get_gem_effect_description(gem, Constants.SLOT_RED, "player_skill")
			return "技能：红槽为空"
		Constants.ACTION_EXTRACT:
			return "拔出：点击目标 → 选槽位（免费）"
		Constants.ACTION_INSERT:
			return "嵌入：点击目标 → 选空槽（免费）"
		Constants.ACTION_TRIGGER:
			return "触发：点击目标 → 选槽位（消耗行动）"
	return "请选择操作"


func get_tutorial_hint() -> String:
	if state == null or state.encounter_id != "tutorial_001" or state.phase != Constants.PHASE_PLAYER:
		return ""
	if state.phase == Constants.PHASE_ENDED:
		return ""
	var held := get_held_gem()
	if held == null and not state.player_acted:
		return "① 拔出：点击自爆工兵 → 选红槽偷走爆炸（免费）"
	if held != null and not state.player_acted:
		var player := state.get_player()
		var guard_near := false
		for unit in state.get_alive_enemies():
			if unit.has_tag(Constants.TAG_UNIT_TRAINING) and BoardUtils.manhattan(player.pos, unit.pos) <= Constants.INSERT_RANGE:
				guard_near = true
				break
		if guard_near:
			return "② 嵌入：点击守卫 → 选黑槽塞入爆炸（免费）\n③ 攻击：点击守卫补刀 → 触发死亡爆炸"
		else:
			return "② 移动靠近守卫 → 嵌入黑槽 → 攻击补刀"
	if held == null and state.player_acted:
		return "行动已用，点「结束回合」"
	return "目标：偷爆炸 → 塞死亡槽 → 补刀引爆"


func _skill_target_cells(player: UnitState) -> Array:
	var cells: Array = []
	var red_slot := player.get_slot(Constants.SLOT_RED)
	if red_slot == null or red_slot.gem_uid.is_empty():
		return cells
	var gem: GemState = state.gems.get(red_slot.gem_uid, null)
	if gem == null:
		return cells
	# 自我施放技能只高亮自己
	if _data_registry().get_player_skill_target_mode(gem) == "self":
		cells.append(player.pos)
		return cells
	# 其他技能高亮范围内所有有效格子
	for x in range(Constants.BOARD_SIZE.x):
		for y in range(Constants.BOARD_SIZE.y):
			var pos := Vector2i(x, y)
			if GemEffects.can_use_skill_at(state, player, pos):
				cells.append(pos)
	return cells


func _adjacent_enemy_cells(from_pos: Vector2i) -> Array:
	var cells: Array = []
	for unit in state.units.values():
		if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(from_pos, unit.pos) <= Constants.ATTACK_RANGE:
			cells.append(unit.pos)
	return cells


func _gem_target_cells(player: UnitState) -> Array:
	var cells: Array = []
	# 单位目标
	for unit in state.units.values():
		if not unit.alive:
			continue
		if BoardUtils.manhattan(player.pos, unit.pos) > Constants.EXTRACT_RANGE:
			continue
		if not _valid_slot_indices(unit, selected_action).is_empty():
			cells.append(unit.pos)
	# 地块目标（祭坛、机关柱等有槽位的地块）
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		if not tile.has_slots():
			continue
		if BoardUtils.manhattan(player.pos, tile.pos) > Constants.EXTRACT_RANGE:
			continue
		if not _valid_tile_slot_indices(tile, selected_action).is_empty():
			if not tile.pos in cells:  # 避免与单位位置重复
				cells.append(tile.pos)
	return cells


func _valid_tile_slot_indices(tile: TileState, action: String) -> Array[String]:
	var labels: Array[String] = []
	for i in range(tile.slots.size()):
		var check := check_tile_slot_action(tile.pos, i)
		if check.get("ok", false):
			var slot: SlotState = tile.slots[i]
			labels.append(_slot_short_label(slot))
	return labels


func _valid_slot_indices(unit: UnitState, action: String) -> Array[String]:
	var labels: Array[String] = []
	for i in range(unit.slots.size()):
		var check := check_slot_action(unit.uid, i)
		if check.get("ok", false):
			var slot: SlotState = unit.slots[i]
			labels.append(_slot_short_label(slot))
	return labels


func _slot_short_label(slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "红"
		Constants.SLOT_BLUE:
			return "蓝"
		Constants.SLOT_BLACK:
			return "黑"
	return "?"


func _slot_preview_line(unit: UnitState, slot: SlotState, index: int) -> String:
	var label := _slot_short_label(slot)
	if slot.locked:
		return "%s槽: 锁定" % label
	if slot.gem_uid.is_empty():
		return "%s槽: 空" % label
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return "%s槽: ?" % label
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	var effect := GemEffects.get_slot_effect_description(gem, slot.slot_type, _unit_slot_context(unit, slot))
	if effect.is_empty():
		return "%s槽: ◆%s" % [label, gem_name]
	return "%s槽: ◆%s — %s" % [label, gem_name, effect]


func _slot_preview_line_tile(tile: TileState, slot: SlotState, index: int) -> String:
	var label := _slot_short_label(slot)
	if slot.locked:
		return "地块%s槽: 锁定" % label
	if slot.gem_uid.is_empty():
		return "地块%s槽: 空" % label
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return "地块%s槽: ?" % label
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	var effect := GemEffects.get_slot_effect_description(gem, slot.slot_type, _tile_slot_context(tile))
	if effect.is_empty():
		return "地块%s槽: ◆%s" % [label, gem_name]
	return "地块%s槽: ◆%s — %s" % [label, gem_name, effect]


func _unit_slot_context(unit: UnitState, slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "enemy_active" if unit.team == Constants.TEAM_ENEMY else "player_trigger"
		Constants.SLOT_BLUE:
			return "unit_blue"
	return ""


func _tile_slot_context(tile: TileState) -> String:
	if tile.tile_id == Constants.TILE_ALTAR:
		return "altar"
	if tile.tile_id == Constants.TILE_PILLAR:
		return "pillar"
	return ""


func _attack_effect_preview(player_pos: Vector2i) -> Array:
	var cells: Array = []
	for unit in state.units.values():
		if not unit.alive or unit.team != Constants.TEAM_ENEMY:
			continue
		if BoardUtils.manhattan(player_pos, unit.pos) > Constants.ATTACK_RANGE:
			continue
		if unit.hp > 1:
			continue
		for slot in unit.slots:
			if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null:
				continue
			cells.append_array(_death_gem_preview_cells(unit.pos, gem))
	return cells


func _death_gem_preview_lines(unit: UnitState) -> Array[String]:
	var lines: Array[String] = []
	if unit.hp > 1:
		return lines
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var effect := GemEffects.get_slot_effect_description(gem, Constants.SLOT_BLACK, "")
		if not effect.is_empty():
			lines.append("预判: %s" % effect)
	return lines


func _death_gem_preview_cells(origin: Vector2i, gem_ref: Variant) -> Array:
	var cells: Array = []
	match _data_registry().get_gem_ability_profile(gem_ref, "black_death"):
		"explosion":
			for cell in BoardUtils.cells_in_radius(origin, Constants.EXPLOSION_RADIUS):
				if BoardUtils.in_bounds(state, cell):
					cells.append(cell)
	return cells


func _check_battle_end() -> void:
	var player := state.get_player()
	if player == null or not player.alive:
		state.phase = Constants.PHASE_ENDED
		state.result = "lose"
		state.log("战斗失败")
		state.on_battle_end.emit("lose")
		battle_ended.emit("lose")
		return
	if state.get_alive_enemies().is_empty():
		state.phase = Constants.PHASE_ENDED
		state.result = "win"
		state.log("战斗胜利")
		state.on_battle_end.emit("win")
		battle_ended.emit("win")


func _emit_changed() -> void:
	state_changed.emit()


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func run_editor_command(raw_command: String) -> Dictionary:
	if state == null:
		return _fail("battle has not started")
	var tokens := _editor_tokens(raw_command)
	if tokens.is_empty():
		return _fail("enter a command")
	var cmd := _normalize_editor_command(tokens[0])
	match cmd:
		"help":
			return _ok({
				"message": "Editor CLI help",
				"lines": _editor_help_lines(),
			})
		"list":
			return _run_editor_list_command(tokens)
		"spawn":
			return _run_editor_spawn_command(tokens, 1)
		"spawn_many":
			return _run_editor_spawn_many_command(tokens, 1)
		"remove":
			return _run_editor_remove_command(tokens, 1)
		"move":
			return _run_editor_move_command(tokens, 1)
		"set":
			return _run_editor_set_command(tokens, 1)
		"export":
			return _run_editor_export_command(tokens, 1)
		_:
			return _fail("unknown command: %s (use /help for usage)" % tokens[0])


func _run_editor_spawn_command(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing object id")
	var object_id := str(tokens[start_index])
	var object_kind := _editor_object_kind_from_id(object_id)
	if object_kind.is_empty():
		return _fail("unknown object id: %s" % object_id)
	var arg_parse := _editor_parse_cli_args(tokens, start_index + 1)
	if not arg_parse.get("ok", false):
		return arg_parse
	var positionals: Array = arg_parse.get("positionals", [])
	var options: Dictionary = arg_parse.get("options", {})
	if positionals.is_empty():
		return _fail("missing position")
	if positionals.size() > 1:
		return _fail("spawn accepts exactly one position")
	match object_kind:
		"unit":
			var option_check := _editor_validate_option_keys(options, ["team"])
			if not option_check.get("ok", false):
				return option_check
			var unit_tokens: Array = [object_id, str(positionals[0])]
			if options.has("team"):
				unit_tokens.append(str(options["team"]))
			return _run_editor_spawn_unit(unit_tokens, 0)
		"gem":
			var gem_option_check := _editor_validate_option_keys(options, ["slot", "target"])
			if not gem_option_check.get("ok", false):
				return gem_option_check
			var gem_tokens: Array = [object_id, str(positionals[0])]
			if options.has("slot"):
				gem_tokens.append(str(options["slot"]))
			if options.has("target"):
				gem_tokens.append(str(options["target"]))
			return _run_editor_spawn_gem(gem_tokens, 0)
		"tile":
			var tile_option_check := _editor_validate_option_keys(options, [])
			if not tile_option_check.get("ok", false):
				return tile_option_check
			return _run_editor_set_tile([str(positionals[0]), object_id], 0)
	return _fail("unsupported object id: %s" % object_id)


func _run_editor_spawn_many_command(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing unit id")
	var unit_def_id := str(tokens[start_index])
	if not _data_registry().has_unit_def(unit_def_id):
		return _fail("spawn-many only supports unit ids: %s" % unit_def_id)
	var arg_parse := _editor_parse_cli_args(tokens, start_index + 1)
	if not arg_parse.get("ok", false):
		return arg_parse
	var positionals: Array = arg_parse.get("positionals", [])
	var options: Dictionary = arg_parse.get("options", {})
	if positionals.is_empty():
		return _fail("missing batch positions")
	var option_check := _editor_validate_option_keys(options, ["team"])
	if not option_check.get("ok", false):
		return option_check
	var batch_tokens: Array = [unit_def_id]
	if options.has("team"):
		batch_tokens.append(str(options["team"]))
	for pos_token in positionals:
		batch_tokens.append(str(pos_token))
	return _run_editor_batch_spawn_unit(batch_tokens, 0)


func _run_editor_remove_command(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing remove target type")
	var noun := _normalize_editor_noun(tokens[start_index])
	match noun:
		"unit":
			return _run_editor_delete_unit(tokens, start_index + 1)
		"gem":
			var arg_parse := _editor_parse_cli_args(tokens, start_index + 1)
			if not arg_parse.get("ok", false):
				return arg_parse
			var positionals: Array = arg_parse.get("positionals", [])
			var options: Dictionary = arg_parse.get("options", {})
			if positionals.is_empty():
				return _fail("missing position")
			if positionals.size() > 1:
				return _fail("remove gem accepts exactly one position")
			var option_check := _editor_validate_option_keys(options, ["slot", "target"])
			if not option_check.get("ok", false):
				return option_check
			var gem_tokens: Array = [str(positionals[0])]
			if options.has("slot"):
				gem_tokens.append(str(options["slot"]))
			if options.has("target"):
				gem_tokens.append(str(options["target"]))
			return _run_editor_delete_gem(gem_tokens, 0)
		_:
			return _fail("remove only supports unit or gem")


func _run_editor_move_command(tokens: Array, start_index: int) -> Dictionary:
	var move_start := start_index
	if tokens.size() > start_index:
		var noun := _normalize_editor_noun(tokens[start_index])
		if noun == "unit":
			move_start += 1
		elif not noun.is_empty():
			return _fail("move only supports units")
	return _run_editor_move_unit(tokens, move_start)


func _run_editor_set_command(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing set target type")
	var noun := _normalize_editor_noun(tokens[start_index])
	match noun:
		"tile":
			return _run_editor_set_tile(tokens, start_index + 1)
		"stat":
			return _run_editor_set_unit_stat(tokens, start_index + 1)
		"player_spawn":
			return _run_editor_set_player_spawn(tokens, start_index + 1)
		_:
			return _fail("set only supports tile, stat, or spawn")


func _run_editor_export_command(tokens: Array, start_index: int) -> Dictionary:
	var export_start := start_index
	if tokens.size() > start_index and _normalize_editor_noun(tokens[start_index]) == "encounter":
		export_start += 1
	return _run_editor_export_encounter(tokens, export_start)


func _run_editor_list_command(tokens: Array, start_index: int = 1) -> Dictionary:
	if tokens.size() <= start_index:
		return _ok({
			"message": "Available catalogs: units, gems, tiles",
			"lines": ["list units", "list gems", "list tiles"],
		})
	var category := _normalize_editor_noun(tokens[start_index])
	var lines: Array[String] = []
	match category:
		"unit":
			lines.append("(string def_id)")
			for unit_def_id in _data_registry().get_unit_def_ids():
				lines.append("  %s  %s" % [unit_def_id, _data_registry().get_unit_display_name(unit_def_id)])
			return _ok({"message": "Unit definition ids (strings)", "lines": lines})
		"gem":
			lines.append("(string def_id)")
			for gem_id in _data_registry().get_gem_ids():
				lines.append("  %s  %s" % [gem_id, _data_registry().get_gem_display_name(gem_id)])
			return _ok({"message": "Gem definition ids (strings)", "lines": lines})
		"tile":
			lines.append("(string def_id)")
			for tile_id in _data_registry().get_tile_ids():
				lines.append("  %s  %s" % [tile_id, _data_registry().get_tile_display_name(tile_id)])
			return _ok({"message": "Tile definition ids (strings)", "lines": lines})
	return _fail("list only supports units, gems, or tiles")


func _run_editor_spawn_unit(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing unit id")
	var unit_def_id := str(tokens[start_index])
	if not _data_registry().has_unit_def(unit_def_id):
		return _fail("unknown unit id: %s" % unit_def_id)
	var pos_parse := _editor_parse_pos(tokens, start_index + 1)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(state, pos):
		return _fail("position out of bounds: %s" % pos)
	if state.get_unit_at(pos) != null:
		return _fail("a live unit already exists at %s" % pos)
	var team := Constants.TEAM_ENEMY
	var next_index: int = int(pos_parse.get("next", start_index + 1))
	if tokens.size() > next_index:
		team = _normalize_editor_team(tokens[next_index])
		if team.is_empty():
			return _fail("unknown team: %s" % tokens[next_index])
	var unit_uid: String = _data_registry().next_runtime_uid("runtime_unit")
	var unit := UnitState.from_def(unit_uid, unit_def_id, team, pos, _data_registry().get_unit_def(unit_def_id))
	state.units[unit_uid] = unit
	return _finalize_editor_mutation("spawned %s at %s for team %s" % [unit_def_id, pos, team], false, {"unit_uid": unit_uid})


func _run_editor_delete_unit(tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	var unit := state.get_unit_at(pos)
	if unit == null:
		return _fail("no live unit at %s" % pos)
	if unit.uid == state.player_uid:
		return _fail("cannot remove the player; use `set spawn` instead")
	_clear_unit_gems(unit)
	state.units.erase(unit.uid)
	if selected_unit_uid == unit.uid:
		selected_unit_uid = state.player_uid
	return _finalize_editor_mutation("removed unit %s at %s" % [unit.unit_def_id, pos])


func _run_editor_move_unit(tokens: Array, start_index: int) -> Dictionary:
	var from_parse := _editor_parse_pos(tokens, start_index)
	if not from_parse.get("ok", false):
		return from_parse
	var next_index: int = int(from_parse.get("next", start_index))
	var to_parse := _editor_parse_pos(tokens, next_index)
	if not to_parse.get("ok", false):
		return to_parse
	var from_pos: Vector2i = from_parse.get("pos", Vector2i.ZERO)
	var to_pos: Vector2i = to_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(state, to_pos):
		return _fail("destination out of bounds: %s" % to_pos)
	var unit := state.get_unit_at(from_pos)
	if unit == null:
		return _fail("no live unit at source position %s" % from_pos)
	if from_pos == to_pos:
		return _ok({"message": "unit is already at the destination"})
	var occupant := state.get_unit_at(to_pos)
	if occupant != null and occupant.uid != unit.uid:
		return _fail("destination is occupied: %s" % to_pos)
	unit.pos = to_pos
	var move_message := "moved %s from %s to %s" % [unit.unit_def_id, from_pos, to_pos]
	if unit.uid == state.player_uid:
		move_message = "moved player spawn to %s" % to_pos
	return _finalize_editor_mutation(move_message)


func _run_editor_batch_spawn_unit(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing unit id")
	var unit_def_id := str(tokens[start_index])
	if not _data_registry().has_unit_def(unit_def_id):
		return _fail("unknown unit id: %s" % unit_def_id)
	var next_index := start_index + 1
	var team := Constants.TEAM_ENEMY
	if tokens.size() > next_index:
		var maybe_team := _normalize_editor_team(tokens[next_index])
		if not maybe_team.is_empty():
			team = maybe_team
			next_index += 1
	var positions_parse := _editor_parse_batch_positions(tokens, next_index)
	if not positions_parse.get("ok", false):
		return positions_parse
	var positions: Array[Vector2i] = positions_parse.get("positions", [] as Array[Vector2i])
	var seen: Dictionary = {}
	for pos in positions:
		if not BoardUtils.in_bounds(state, pos):
			return _fail("position out of bounds: %s" % pos)
		if state.get_unit_at(pos) != null:
			return _fail("a live unit already exists at %s" % pos)
		var pos_key := state.tile_key(pos)
		if seen.has(pos_key):
			return _fail("duplicate position in batch: %s" % pos)
		seen[pos_key] = true
	var created_uids: Array[String] = []
	for pos in positions:
		var unit_uid: String = _data_registry().next_runtime_uid("runtime_unit")
		var unit := UnitState.from_def(unit_uid, unit_def_id, team, pos, _data_registry().get_unit_def(unit_def_id))
		state.units[unit_uid] = unit
		created_uids.append(unit_uid)
	return _finalize_editor_mutation("spawned %d instances of %s for team %s" % [created_uids.size(), unit_def_id, team], false, {"unit_uids": created_uids})


func _run_editor_set_tile(tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var next_index: int = int(pos_parse.get("next", start_index))
	if tokens.size() <= next_index:
		return _fail("missing tile id")
	var tile_id := str(tokens[next_index])
	if not _data_registry().has_tile_id(tile_id):
		return _fail("unknown tile id: %s" % tile_id)
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(state, pos):
		return _fail("position out of bounds: %s" % pos)
	var existing: TileState = state.get_tile(pos)
	_clear_tile_gems(existing)
	var slot_defs := _default_tile_slot_defs(tile_id)
	var tile := TileState.create(pos, tile_id) if slot_defs.is_empty() else TileState.create_with_slots(pos, tile_id, slot_defs)
	state.tiles[state.tile_key(pos)] = tile
	return _finalize_editor_mutation("set tile at %s to %s" % [pos, tile_id], true)


func _run_editor_spawn_gem(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing gem id")
	var gem_id := str(tokens[start_index])
	if not _data_registry().has_gem_def(gem_id):
		return _fail("unknown gem id: %s" % gem_id)
	var pos_parse := _editor_parse_pos(tokens, start_index + 1)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(state, pos):
		return _fail("position out of bounds: %s" % pos)
	var next_index: int = int(pos_parse.get("next", start_index + 1))
	var preferred_slot := ""
	if tokens.size() > next_index:
		var maybe_slot := _normalize_editor_slot_type(tokens[next_index])
		if not maybe_slot.is_empty():
			preferred_slot = maybe_slot
			next_index += 1
	var target_kind := ""
	if tokens.size() > next_index:
		target_kind = _normalize_editor_target_kind(tokens[next_index])
		if target_kind.is_empty():
			return _fail("unknown gem target: %s" % tokens[next_index])
	var unit: UnitState = state.get_unit_at(pos)
	var tile: TileState = state.get_tile(pos)
	if target_kind.is_empty():
		target_kind = "unit" if unit != null else "tile"
	var slot_index := -1
	var slot: SlotState = null
	var target_label := ""
	if target_kind == "unit":
		if unit == null:
			return _fail("no unit at %s" % pos)
		slot_index = _find_editor_slot_index(unit.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no available slot on unit at %s" % pos)
		slot = unit.get_slot_by_index(slot_index)
		target_label = "unit %s slot %s" % [unit.unit_def_id, _editor_slot_label(slot)]
	else:
		if tile == null or not tile.has_slots():
			return _fail("no slotted tile at %s" % pos)
		slot_index = _find_editor_slot_index(tile.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no available slot on tile at %s" % pos)
		slot = tile.get_slot_by_index(slot_index)
		target_label = "tile %s slot %s" % [tile.tile_id, _editor_slot_label(slot)]
	_clear_slot_gem(slot)
	var gem_uid: String = _data_registry().next_runtime_uid("runtime_gem")
	var gem: GemState = _data_registry().create_gem_instance(gem_uid, gem_id)
	if target_kind == "unit" and unit != null:
		gem.owner_uid = unit.uid
		gem.slot_index = slot_index
	else:
		gem.owner_uid = ""
		gem.slot_index = -1
	state.gems[gem.uid] = gem
	slot.gem_uid = gem.uid
	return _finalize_editor_mutation("spawned %s in %s" % [gem_id, target_label], false, {"gem_uid": gem.uid})


func _run_editor_set_unit_stat(tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var next_index: int = int(pos_parse.get("next", start_index))
	if tokens.size() <= next_index + 1:
		return _fail("missing stat field or value")
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	var unit := state.get_unit_at(pos)
	if unit == null:
		return _fail("no live unit at %s" % pos)
	var field := _normalize_editor_stat_field(tokens[next_index])
	if field.is_empty():
		return _fail("unsupported stat field: %s" % tokens[next_index])
	var raw_value := str(tokens[next_index + 1])
	match field:
		"hp":
			if not raw_value.is_valid_int():
				return _fail("hp must be an integer")
			unit.hp = maxi(0, int(raw_value))
			if unit.hp > unit.max_hp:
				unit.max_hp = unit.hp
			unit.alive = unit.hp > 0
		"max_hp":
			if not raw_value.is_valid_int():
				return _fail("max_hp must be an integer")
			unit.max_hp = maxi(1, int(raw_value))
			if unit.hp > unit.max_hp:
				unit.hp = unit.max_hp
			if unit.alive and unit.hp <= 0:
				unit.hp = unit.max_hp
		"move_points":
			if not raw_value.is_valid_int():
				return _fail("move_points must be an integer")
			unit.move_points = maxi(0, int(raw_value))
		"speed":
			if not raw_value.is_valid_int():
				return _fail("speed must be an integer")
			unit.speed = maxi(0, int(raw_value))
		"base_attack":
			if not raw_value.is_valid_int():
				return _fail("base_attack must be an integer")
			unit.base_attack = int(raw_value)
		"armor":
			if not raw_value.is_valid_int():
				return _fail("armor must be an integer")
			unit.armor = maxi(0, int(raw_value))
		"alive":
			var alive_parse := _editor_parse_bool(raw_value)
			if not alive_parse.get("ok", false):
				return _fail("alive only supports true or false")
			unit.alive = alive_parse.get("value", false)
			if unit.alive and unit.hp <= 0:
				unit.hp = maxi(1, unit.max_hp)
			elif not unit.alive:
				unit.hp = 0
	return _finalize_editor_mutation("set %s.%s = %s" % [unit.unit_def_id, field, raw_value])


func _run_editor_set_player_spawn(tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(state, pos):
		return _fail("position out of bounds: %s" % pos)
	var player := state.get_player()
	if player == null:
		return _fail("player does not exist")
	var occupant := state.get_unit_at(pos)
	if occupant != null and occupant.uid != player.uid:
		return _fail("destination is occupied: %s" % pos)
	player.pos = pos
	return _finalize_editor_mutation("set player spawn to %s" % pos)


func _run_editor_delete_gem(tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(state, pos):
		return _fail("position out of bounds: %s" % pos)
	var next_index: int = int(pos_parse.get("next", start_index))
	var preferred_slot := ""
	if tokens.size() > next_index:
		var maybe_slot := _normalize_editor_slot_type(tokens[next_index])
		if not maybe_slot.is_empty():
			preferred_slot = maybe_slot
			next_index += 1
	var target_kind := ""
	if tokens.size() > next_index:
		target_kind = _normalize_editor_target_kind(tokens[next_index])
		if target_kind.is_empty():
			return _fail("unknown gem target: %s" % tokens[next_index])
	var unit: UnitState = state.get_unit_at(pos)
	var tile: TileState = state.get_tile(pos)
	var slot_index := -1
	var slot: SlotState = null
	var target_label := ""
	if target_kind == "unit" or (target_kind.is_empty() and unit != null and _find_editor_filled_slot_index(unit.slots, preferred_slot) >= 0):
		if unit == null:
			return _fail("no unit at %s" % pos)
		slot_index = _find_editor_filled_slot_index(unit.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no gem found on unit at %s" % pos)
		slot = unit.get_slot_by_index(slot_index)
		target_label = "unit %s slot %s" % [unit.unit_def_id, _editor_slot_label(slot)]
	else:
		if tile == null or not tile.has_slots():
			return _fail("no slotted tile at %s" % pos)
		slot_index = _find_editor_filled_slot_index(tile.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no gem found on tile at %s" % pos)
		slot = tile.get_slot_by_index(slot_index)
		target_label = "tile %s slot %s" % [tile.tile_id, _editor_slot_label(slot)]
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	var gem_id := gem.gem_id if gem != null else "unknown_gem"
	_clear_slot_gem(slot)
	return _finalize_editor_mutation("removed %s from %s" % [gem_id, target_label])


func _run_editor_export_encounter(tokens: Array, start_index: int) -> Dictionary:
	var encounter_id := "editor_export_%s" % state.encounter_id
	if tokens.size() > start_index:
		encounter_id = str(tokens[start_index])
	var encounter := _build_editor_export_encounter()
	return _ok({
		"message": "exported encounter %s" % encounter_id,
		"lines": _format_editor_export_encounter(encounter_id, encounter),
		"encounter": encounter,
	})


func _finalize_editor_mutation(message: String, rebuild_tiles: bool = false, payload: Dictionary = {}) -> Dictionary:
	state.log("[Editor CLI] %s" % message)
	if rebuild_tiles:
		_refresh_runtime_tile_visuals()
	if state.phase == Constants.PHASE_ENDED:
		var player := state.get_player()
		if player != null and player.alive and not state.get_alive_enemies().is_empty():
			state.phase = Constants.PHASE_PLAYER
			state.result = ""
			state.player_moved = false
			state.player_acted = false
	IntentSystem.refresh_all_intents(state)
	_check_battle_end()
	payload["message"] = message
	_emit_changed()
	return _ok(payload)


func _refresh_runtime_tile_visuals() -> void:
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_FLOOR:
			tile.floor_variant = absi(hash(str(state.run_seed, ":", tile.pos.x, ":", tile.pos.y))) % 3
		else:
			tile.floor_variant = 0
	BoardMapGenerator._compute_edge_masks(state)


func _build_editor_export_encounter() -> Dictionary:
	var player := state.get_player()
	var enemies: Array[Dictionary] = []
	var tiles: Array[Dictionary] = []
	for unit in state.units.values():
		if unit.uid == state.player_uid or not unit.alive or unit.team != Constants.TEAM_ENEMY:
			continue
		var enemy_entry := {
			"def_id": unit.unit_def_id,
			"pos": unit.pos,
		}
		var slot_defs := _collect_editor_slot_entries(unit.slots)
		if not slot_defs.is_empty():
			enemy_entry["slots"] = slot_defs
		enemies.append(enemy_entry)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_editor_positions(a.get("pos", Vector2i.ZERO), b.get("pos", Vector2i.ZERO))
	)
	for tile in state.tiles.values():
		if tile.tile_id == Constants.TILE_FLOOR and not tile.has_slots():
			continue
		var tile_entry := {
			"pos": tile.pos,
			"tile_id": tile.tile_id,
		}
		var tile_slots := _collect_editor_slot_entries(tile.slots)
		if not tile_slots.is_empty():
			tile_entry["slots"] = tile_slots
		tiles.append(tile_entry)
	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_editor_positions(a.get("pos", Vector2i.ZERO), b.get("pos", Vector2i.ZERO))
	)
	return {
		"player_spawn": player.pos if player != null else Vector2i.ZERO,
		"floor_seed": state.run_seed,
		"enemies": enemies,
		"tiles": tiles,
	}


func _format_editor_export_encounter(encounter_id: String, encounter: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("\"%s\": {" % encounter_id)
	lines.append("\t\"player_spawn\": %s," % _format_editor_vector2i(encounter.get("player_spawn", Vector2i.ZERO)))
	lines.append("\t\"floor_seed\": %d," % int(encounter.get("floor_seed", state.run_seed)))
	lines.append("\t\"enemies\": [")
	var enemies: Array = encounter.get("enemies", [])
	for i in range(enemies.size()):
		lines.append("\t\t%s%s" % [_format_editor_export_enemy_line(enemies[i]), "," if i < enemies.size() - 1 else ""])
	lines.append("\t],")
	lines.append("\t\"tiles\": [")
	var tiles: Array = encounter.get("tiles", [])
	for i in range(tiles.size()):
		lines.append("\t\t%s%s" % [_format_editor_export_tile_line(tiles[i]), "," if i < tiles.size() - 1 else ""])
	lines.append("\t]")
	lines.append("},")
	return lines


func _format_editor_export_enemy_line(enemy: Dictionary) -> String:
	var parts: Array[String] = [
		"\"def_id\": \"%s\"" % str(enemy.get("def_id", "")),
		"\"pos\": %s" % _format_editor_vector2i(enemy.get("pos", Vector2i.ZERO)),
	]
	var slots: Array = enemy.get("slots", [])
	if not slots.is_empty():
		parts.append("\"slots\": %s" % _format_editor_slot_entries_inline(slots))
	return "{%s}" % ", ".join(parts)


func _format_editor_export_tile_line(tile_entry: Dictionary) -> String:
	var parts: Array[String] = [
		"\"pos\": %s" % _format_editor_vector2i(tile_entry.get("pos", Vector2i.ZERO)),
		"\"tile_id\": \"%s\"" % str(tile_entry.get("tile_id", Constants.TILE_FLOOR)),
	]
	var slots: Array = tile_entry.get("slots", [])
	if not slots.is_empty():
		parts.append("\"slots\": %s" % _format_editor_slot_entries_inline(slots))
	return "{%s}" % ", ".join(parts)


func _format_editor_slot_entries_inline(slot_entries: Array) -> String:
	var parts: Array[String] = []
	for entry in slot_entries:
		var fields: Array[String] = ["\"slot_type\": \"%s\"" % str(entry.get("slot_type", ""))]
		if entry.has("gem_id"):
			fields.append("\"gem_id\": \"%s\"" % str(entry.get("gem_id", "")))
		if entry.has("gem_overrides"):
			fields.append("\"gem_overrides\": %s" % var_to_str(entry.get("gem_overrides", {})))
		if bool(entry.get("locked", false)):
			fields.append("\"locked\": true")
		if entry.has("lock_type") and not str(entry.get("lock_type", "")).is_empty():
			fields.append("\"lock_type\": \"%s\"" % str(entry.get("lock_type", "")))
		parts.append("{%s}" % ", ".join(fields))
	return "[%s]" % ", ".join(parts)


func _format_editor_vector2i(value: Variant) -> String:
	var pos: Vector2i = value
	return "Vector2i(%d, %d)" % [pos.x, pos.y]


func _compare_editor_positions(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


func _collect_editor_slot_entries(slots: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot in slots:
		var slot_entry := {
			"slot_type": slot.slot_type,
		}
		if bool(slot.locked):
			slot_entry["locked"] = true
		if not str(slot.lock_type).is_empty():
			slot_entry["lock_type"] = slot.lock_type
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				slot_entry["gem_id"] = gem.gem_id
				if not gem.def_overrides.is_empty():
					slot_entry["gem_overrides"] = gem.def_overrides.duplicate(true)
		if slot_entry.size() > 1:
			entries.append(slot_entry)
	return entries


func _clear_tile_gems(tile: TileState) -> void:
	if tile == null:
		return
	for slot in tile.slots:
		_clear_slot_gem(slot)


func _clear_unit_gems(unit: UnitState) -> void:
	if unit == null:
		return
	for slot in unit.slots:
		_clear_slot_gem(slot)


func _clear_slot_gem(slot: SlotState) -> void:
	if slot == null or slot.gem_uid.is_empty():
		return
	if state.held_gem_uid == slot.gem_uid:
		state.held_gem_uid = ""
	state.gems.erase(slot.gem_uid)
	slot.gem_uid = ""


func _default_tile_slot_defs(tile_id: String) -> Array:
	match tile_id:
		Constants.TILE_ALTAR:
			return [{"slot_type": Constants.SLOT_RED}]
		Constants.TILE_PILLAR:
			return [{"slot_type": Constants.SLOT_BLUE}]
		_:
			return []


func _editor_slot_label(slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "red"
		Constants.SLOT_BLUE:
			return "blue"
		Constants.SLOT_BLACK:
			return "black"
	return "unknown"


func _find_editor_slot_index(slots: Array, preferred_slot_type: String = "") -> int:
	var fallback := -1
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not preferred_slot_type.is_empty() and slot.slot_type != preferred_slot_type:
			continue
		if slot.gem_uid.is_empty():
			return i
		if fallback < 0:
			fallback = i
	return fallback


func _find_editor_filled_slot_index(slots: Array, preferred_slot_type: String = "") -> int:
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not preferred_slot_type.is_empty() and slot.slot_type != preferred_slot_type:
			continue
		if not slot.gem_uid.is_empty():
			return i
	return -1


func _editor_parse_batch_positions(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing batch positions; use x,y x,y ...")
	var positions: Array[Vector2i] = []
	for i in range(start_index, tokens.size()):
		var pos_parse := _editor_parse_single_pos_token(str(tokens[i]))
		if not pos_parse.get("ok", false):
			return _fail("batch positions must use x,y format: %s" % tokens[i])
		positions.append(pos_parse.get("pos", Vector2i.ZERO))
	return _ok({"positions": positions})


func _editor_parse_cli_args(tokens: Array, start_index: int) -> Dictionary:
	var positionals: Array[String] = []
	var options := {}
	var index := start_index
	while index < tokens.size():
		var token := str(tokens[index])
		if token.begins_with("--"):
			var option_key := token.trim_prefix("--").replace("-", "_")
			if option_key.is_empty():
				return _fail("invalid option: %s" % token)
			if index + 1 >= tokens.size():
				return _fail("missing option value for %s" % token)
			options[option_key] = str(tokens[index + 1])
			index += 2
			continue
		positionals.append(token)
		index += 1
	return _ok({
		"positionals": positionals,
		"options": options,
	})


func _editor_validate_option_keys(options: Dictionary, allowed_keys: Array[String]) -> Dictionary:
	for key in options.keys():
		var option_key := str(key)
		if not allowed_keys.has(option_key):
			return _fail("unsupported option: --%s" % option_key.replace("_", "-"))
	return _ok()


func _editor_object_kind_from_id(object_id: String) -> String:
	if _data_registry().has_unit_def(object_id):
		return "unit"
	if _data_registry().has_gem_def(object_id):
		return "gem"
	if _data_registry().has_tile_id(object_id):
		return "tile"
	return ""


func _editor_parse_single_pos_token(token: String) -> Dictionary:
	if not token.contains(","):
		return _fail("position format must be x,y")
	var parts := token.split(",", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return _fail("position format must be x,y")
	return _ok({"pos": Vector2i(int(parts[0]), int(parts[1]))})


func _editor_parse_pos(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing position")
	var first := str(tokens[start_index])
	if first.contains(","):
		var parts := first.split(",", false)
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return _fail("position format must be x,y or x y")
		return _ok({
			"pos": Vector2i(int(parts[0]), int(parts[1])),
			"next": start_index + 1,
		})
	if tokens.size() <= start_index + 1:
		return _fail("position format must be x,y or x y")
	var second := str(tokens[start_index + 1])
	if not first.is_valid_int() or not second.is_valid_int():
		return _fail("position coordinates must be integers")
	return _ok({
		"pos": Vector2i(int(first), int(second)),
		"next": start_index + 2,
	})


func _editor_parse_bool(raw_value: String) -> Dictionary:
	var lowered := raw_value.to_lower()
	if lowered in ["true", "1", "yes", "on"]:
		return _ok({"value": true})
	if lowered in ["false", "0", "no", "off"]:
		return _ok({"value": false})
	return _fail("invalid bool")


func _editor_tokens(raw_command: String) -> Array[String]:
	var normalized := raw_command.strip_edges()
	normalized = normalized.replace("\t", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	var tokens: Array[String] = []
	for token in normalized.split(" ", false):
		var value := String(token).strip_edges()
		if value.begins_with("/"):
			value = value.substr(1)
		if value.is_empty():
			continue
		if _is_editor_filler_token(value):
			continue
		tokens.append(value)
	return tokens


func _is_editor_filler_token(token: String) -> bool:
	return token.to_lower() in ["at", "to", "into", "on"]


func _normalize_editor_command(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"help", "?":
			return "help"
		"list", "ls":
			return "list"
		"spawn", "create":
			return "spawn"
		"spawn_many", "spawn-many":
			return "spawn_many"
		"set":
			return "set"
		"remove", "delete":
			return "remove"
		"move":
			return "move"
		"export", "save":
			return "export"
	return lowered


func _normalize_editor_noun(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"unit", "units", "monster", "monsters", "enemy", "enemies":
			return "unit"
		"gem", "gems":
			return "gem"
		"tile", "tiles", "cell", "cells":
			return "tile"
		"stat", "stats", "attr", "attribute":
			return "stat"
		"player_spawn", "spawn", "spawn_point":
			return "player_spawn"
		"encounter", "level", "map":
			return "encounter"
	return ""


func _normalize_editor_slot_type(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"red", "r":
			return Constants.SLOT_RED
		"blue", "b":
			return Constants.SLOT_BLUE
		"black", "k":
			return Constants.SLOT_BLACK
	return ""


func _normalize_editor_target_kind(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"unit", "monster", "enemy":
			return "unit"
		"tile", "cell":
			return "tile"
	return ""


func _normalize_editor_team(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"enemy", "monster":
			return Constants.TEAM_ENEMY
		"player", "ally":
			return Constants.TEAM_PLAYER
	return ""


func _normalize_editor_stat_field(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"hp":
			return "hp"
		"max_hp", "maxhp":
			return "max_hp"
		"move_points", "move":
			return "move_points"
		"speed", "spd":
			return "speed"
		"base_attack", "attack", "atk":
			return "base_attack"
		"armor", "def":
			return "armor"
		"alive":
			return "alive"
	return ""


func _editor_help_lines() -> Array[String]:
	return [
		"Editor CLI (F9)",
		"Commands start with /. Bare names like help still work.",
		"IDs are string resource keys (unit_bomber, gem_poison, tile_water), not numeric.",
		"Runtime unit_uid / gem_uid are also strings; list only shows definition ids.",
		"",
		"Catalogs:",
		"  /list units                Show spawnable unit ids",
		"  /list gems                 Show spawnable gem ids",
		"  /list tiles                Show placeable tile ids",
		"",
		"Commands:",
		"  /spawn <object_id> <pos> [--team enemy|player]",
		"    - object_id can be a unit id, gem id, or tile id",
		"    - units spawn on the board; gems auto-detect unit/tile unless overridden",
		"    - example: /spawn unit_bomber 2,4 --team enemy",
		"    - example: /spawn gem_poison 2,4 --slot red --target tile",
		"    - example: /spawn tile_altar 4,4",
		"  /spawn-many <unit_id> <pos> <pos> ... [--team enemy|player]",
		"    - example: /spawn-many unit_grunt 0,0 1,0 2,0 --team enemy",
		"  /move [unit] <from_pos> <to_pos>",
		"    - example: /move 2,4 3,4",
		"  /remove unit <pos>",
		"    - example: /remove unit 3,4",
		"  /remove gem <pos> [--slot red|blue|black] [--target unit|tile]",
		"    - example: /remove gem 2,4 --slot red --target unit",
		"  /set tile <pos> <tile_id>",
		"    - example: /set tile 4,4 tile_water",
		"  /set stat <pos> <field> <value>",
		"    - supported fields: hp, max_hp, move_points, speed, base_attack, armor, alive",
		"    - example: /set stat 2,4 hp 12",
		"  /set spawn <pos>",
		"    - example: /set spawn 1,6",
		"  /export [encounter] [encounter_id]",
		"    - example: /export encounter custom_level_001",
	]


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
