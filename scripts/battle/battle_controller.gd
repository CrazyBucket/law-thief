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
	if CombatRules.attack(state, player, target) <= 0:
		return _fail("无法攻击")
	anim_damage.emit(target.pos, CombatRules.attack_damage(state, player), false)
	state.player_acted = true
	_check_battle_end()
	IntentSystem.refresh_all_intents(state)
	_emit_changed()
	return _ok()


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
	state.phase = Constants.PHASE_ENEMY
	_emit_changed()


## 执行单个敌人的意图，返回动画事件列表
## 由 battle_scene 逐个调用，每次调用之间 await 动画完成
func execute_single_enemy(enemy: UnitState) -> Array[Dictionary]:
	if not enemy.alive:
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
	_check_battle_end()
	_emit_changed()


## 获取排序后的存活敌人列表
func get_sorted_enemies() -> Array:
	if state == null:
		return []
	var enemies := state.get_alive_enemies()
	enemies.sort_custom(func(a: UnitState, b: UnitState) -> bool:
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
			if unit != null and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(player.pos, cell) == 1:
				lines.append("→ 点击攻击（%d 伤害）" % CombatRules.attack_damage(state, player))
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
			return "攻击：点击邻格敌人（消耗行动）"
		Constants.ACTION_SKILL:
			var player := state.get_player()
			if player != null:
				var red_slot := player.get_slot(Constants.SLOT_RED)
				if red_slot != null and not red_slot.gem_uid.is_empty():
					var gem: GemState = state.gems.get(red_slot.gem_uid, null)
					if gem != null:
						return "技能：%s（消耗行动）" % GemEffects.get_skill_description(gem.gem_id)
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
			if unit.unit_def_id == "unit_training_guard" and BoardUtils.manhattan(player.pos, unit.pos) <= Constants.INSERT_RANGE:
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
	# 重甲是自我施放，高亮自己
	if gem.gem_id == Constants.GEM_HEAVY_ARMOR:
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
		if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(from_pos, unit.pos) == 1:
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
	var gem_name: String = _data_registry().get_gem_display_name(gem.gem_id)
	var effect := GemEffects.get_slot_effect_description(gem.gem_id, slot.slot_type, _unit_slot_context(unit, slot))
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
	var gem_name: String = _data_registry().get_gem_display_name(gem.gem_id)
	var effect := GemEffects.get_slot_effect_description(gem.gem_id, slot.slot_type, _tile_slot_context(tile))
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
		if BoardUtils.manhattan(player_pos, unit.pos) != 1:
			continue
		if unit.hp > 1:
			continue
		for slot in unit.slots:
			if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null:
				continue
			if gem.gem_id == Constants.GEM_EXPLOSION:
				for cell in BoardUtils.cells_in_radius(unit.pos, Constants.EXPLOSION_RADIUS):
					if BoardUtils.in_bounds(state, cell):
						cells.append(cell)
			elif gem.gem_id == Constants.GEM_FRAGILE:
				for neighbor in BoardUtils.neighbors4(unit.pos):
					if BoardUtils.in_bounds(state, neighbor):
						cells.append(neighbor)
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
		var effect := GemEffects.get_slot_effect_description(gem.gem_id, Constants.SLOT_BLACK, "")
		if not effect.is_empty():
			lines.append("预判: %s" % effect)
	return lines


func _check_battle_end() -> void:
	var player := state.get_player()
	if player == null or not player.alive:
		state.phase = Constants.PHASE_ENDED
		state.result = "lose"
		state.log("战斗失败")
		battle_ended.emit("lose")
		return
	if state.get_alive_enemies().is_empty():
		state.phase = Constants.PHASE_ENDED
		state.result = "win"
		state.log("战斗胜利")
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


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
