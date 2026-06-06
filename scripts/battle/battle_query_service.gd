class_name BattleQueryService
extends RefCounted

const _StatusUi = preload("res://scripts/ui/status_ui.gd")
const GemEffects = preload("res://scripts/rules/gem_effects.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const _SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")

var _ctrl: BattleController


func setup(controller: BattleController) -> void:
	_ctrl = controller


func _c() -> BattleController:
	return _ctrl


# ═══════════════════════════════════════════════════════════════════════════
# 高亮 & 预览
# ═══════════════════════════════════════════════════════════════════════════

func get_highlights(hover_cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var result := {
		"reachable": [],
		"targets": [],
		"attack_range": [],
		"paths": [],
		"danger": [],
		"effect_preview": [],
	}
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleQueryService: _ctrl is null in get_highlights")
		return result
	if ctrl.state == null:
		return result
	var state: GameState = ctrl.state
	var player: UnitState = state.get_player()
	if player == null:
		return result
	var action: String = ctrl.selected_action
	if action == Constants.ACTION_MOVE and not state.player_moved and StatusRules.can_move(player):
		result["reachable"] = BoardUtils.reachable_cells(state, player.pos, player.move_points)
	elif action == Constants.ACTION_ATTACK and not state.player_acted:
		result["attack_range"] = _attack_target_cells(state, player)
		if hover_cell.x >= 0 and BoardUtils.in_bounds(state, hover_cell):
			result["effect_preview"] = _attack_hit_preview_cells(state, player, hover_cell)
		else:
			result["effect_preview"] = _attack_effect_preview(state, player)
	elif action == Constants.ACTION_EXTRACT and ctrl.can_use_action(Constants.ACTION_EXTRACT):
		result["targets"] = _gem_target_cells(ctrl, state, player)
	elif action == Constants.ACTION_INSERT and ctrl.can_use_action(Constants.ACTION_INSERT):
		result["targets"] = _gem_target_cells(ctrl, state, player)
	var selected_uid: String = ctrl.selected_unit_uid
	if not selected_uid.is_empty():
		var selected_unit: UnitState = state.units.get(selected_uid, null)
		if selected_unit != null and selected_unit.alive and selected_unit.intent != null:
			result["paths"] = selected_unit.intent.path.duplicate()
			if not selected_unit.intent.affected_cells.is_empty():
				result["danger"] = selected_unit.intent.affected_cells.duplicate()
	return result


func get_cell_preview(cell: Vector2i) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleQueryService: _ctrl is null in get_cell_preview")
		return {}
	if ctrl.state == null:
		return {}
	var state: GameState = ctrl.state
	var player: UnitState = state.get_player()
	if player == null:
		push_error("BattleQueryService: get_player() returned null in get_cell_preview")
		return {}
	var unit: UnitState = state.get_unit_at(cell)
	var tile: TileState = state.get_tile(cell)
	var lines: Array[String] = ["%s %s" % [_data_registry().get_tile_display_name(tile.tile_id), cell]]
	var spike := BoardUtils.spike_entity_at(state, cell)
	if spike != null:
		lines.append("地刺：步入 %d 伤害；被强制位移踩入附加易伤并受到 %d 伤害" % [
			Constants.SPIKE_DAMAGE, Constants.SPIKE_COLLISION_DAMAGE
		])
	var blocking := BoardUtils.blocking_entity_at(state, cell)
	if blocking != null and blocking.is_indestructible():
		lines.append("静物：不可通行，攻击无效")
	match tile.tile_id:
		Constants.TILE_WATER:
			lines.append("水洼：导电连锁区域")
		Constants.TILE_PILLAR:
			lines.append("机关柱：嵌入宝石产生持续光环")
	if tile.has_modifier("poison_fog"):
		lines.append("毒雾：进入叠 1 层毒；回合结束仍在其内再叠 1 层（每层 %d 伤害）" % Constants.POISON_FOG_DAMAGE)
	if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		lines.append("毒烟：同时视为火焰与毒雾，持续 1 回合")
	if tile.has_slots():
		for i in range(tile.slots.size()):
			var tslot: SlotState = tile.slots[i]
			lines.append(_slot_preview_line_tile(state, tile, tslot))
	if unit != null:
		lines.append("%s HP %d/%d" % [_data_registry().get_unit_display_name(unit.unit_def_id), unit.hp, unit.max_hp])
		for status_line in _StatusUi.preview_lines(unit):
			lines.append(status_line)
		if unit.intent != null and unit.team == Constants.TEAM_ENEMY and ctrl.selected_unit_uid == unit.uid:
			lines.append("意图: %s" % unit.intent.preview_text)
		for i in range(unit.slots.size()):
			var slot: SlotState = unit.slots[i]
			lines.append(_slot_preview_line(state, unit, slot))
	match ctrl.selected_action:
		Constants.ACTION_MOVE:
			if not state.player_moved and StatusRules.can_move(player) and cell in BoardUtils.reachable_cells(state, player.pos, player.move_points):
				lines.append("→ 点击移动")
		Constants.ACTION_ATTACK:
			if cell != player.pos and BoardUtils.can_unit_attack_cell(player, state, cell, Constants.ATTACK_RANGE):
				if blocking != null and blocking.is_indestructible() and unit == null:
					lines.append("→ 点击射击（静物不受伤害）")
				elif tile.has_tile_tag(Constants.TAG_TILE_WATER) and GemEffects.unit_has_red_arc(state, player):
					lines.append("→ 点击电击水域（相连水域及边缘潮湿单位导电）")
				else:
					lines.append("→ 点击射击（%d 伤害）" % CombatRules.attack_damage(state, player))
				if unit != null:
					lines.append_array(_death_gem_preview_lines(state, unit))
		Constants.ACTION_EXTRACT:
			if unit != null and ctrl.can_use_action(Constants.ACTION_EXTRACT):
				var valid := _valid_slot_indices(ctrl, unit)
				if not valid.is_empty():
					lines.append("→ 可拔出: %s（免费）" % ", ".join(valid))
			elif tile.has_slots() and ctrl.can_use_action(Constants.ACTION_EXTRACT):
				var tile_valid := _valid_tile_slot_indices(ctrl, tile)
				if not tile_valid.is_empty():
					lines.append("→ 可从地块拔出: %s（免费）" % ", ".join(tile_valid))
		Constants.ACTION_INSERT:
			if unit != null and ctrl.can_use_action(Constants.ACTION_INSERT):
				var insert_valid := _valid_slot_indices(ctrl, unit)
				if not insert_valid.is_empty():
					lines.append("→ 可嵌入: %s（免费）" % ", ".join(insert_valid))
			elif tile.has_slots() and ctrl.can_use_action(Constants.ACTION_INSERT):
				var tile_insert_valid := _valid_tile_slot_indices(ctrl, tile)
				if not tile_insert_valid.is_empty():
					lines.append("→ 可嵌入地块: %s（免费）" % ", ".join(tile_insert_valid))
	return {"title": lines[0] if not lines.is_empty() else "", "body": "\n".join(lines)}


func get_action_hint() -> String:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleQueryService: _ctrl is null in get_action_hint")
		return "请选择操作"
	match ctrl.selected_action:
		Constants.ACTION_MOVE:
			if ctrl.state != null:
				var player: UnitState = ctrl.state.get_player()
				if player != null and not StatusRules.can_move(player):
					var block_reason := StatusRules.move_block_reason(player)
					if block_reason.is_empty():
						return "移动：暂时无法移动"
					return "移动：%s" % block_reason
			return "移动：点击白色边框格（悬浮为浅绿，每回合 1 次）"

		Constants.ACTION_ATTACK:
			return "射击：点击 %d 格内任意格（不含自己，消耗行动）" % Constants.ATTACK_RANGE
		Constants.ACTION_EXTRACT:
			return "拔出：点击目标 → 选槽位（免费）"
		Constants.ACTION_INSERT:
			if ctrl.state != null and ctrl.state.overload_pending:
				return "过载预兆：结束回合后生效；切换/取消嵌入可避免"
			if ctrl.state != null \
				and ctrl.state.overload_last_action == Constants.ACTION_INSERT \
				and ctrl.state.overload_last_insert_turn == ctrl.state.turn_index:
				return "嵌入：再次嵌入会触发过载，可强行跨色入槽"
			return "嵌入：点击目标 → 选槽位（免费，替换时原宝石回到手中）"
	return "请选择操作"


func get_tutorial_hint() -> String:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleQueryService: _ctrl is null in get_tutorial_hint")
		return ""
	if ctrl.state == null:
		return ""
	var state: GameState = ctrl.state
	if state.encounter_id != "tutorial_001" or state.phase != Constants.PHASE_PLAYER:
		return ""
	if state.phase == Constants.PHASE_ENDED:
		return ""
	var held := ctrl.get_held_gem()
	if held == null and not state.player_acted:
		return "① 拔出：点击炸弹鼠 → 选红槽偷走爆炸（免费）"
	if held != null and not state.player_acted:
		var player: UnitState = state.get_player()
		var guard_near := false
		for unit in state.get_alive_enemies():
			if unit.has_tag(Constants.TAG_UNIT_PATROL_GUARD) and BoardUtils.manhattan(player.pos, unit.pos) <= Constants.INSERT_RANGE:
				guard_near = true
				break
		if guard_near:
			return "② 嵌入：点击巡路甲兵 → 选黑槽塞入爆炸（免费）\n③ 攻击：点击巡路甲兵补刀 → 触发死亡爆炸"
		else:
			return "② 移动靠近巡路甲兵 → 嵌入黑槽 → 攻击补刀"
	if held == null and state.player_acted:
		return "行动已用，点「结束回合」"
	return "目标：偷爆炸 → 塞死亡槽 → 补刀引爆"


# ═══════════════════════════════════════════════════════════════════════════
# 有效槽位标签
# ═══════════════════════════════════════════════════════════════════════════

func _valid_slot_indices(ctrl, unit: UnitState) -> Array[String]:
	var labels: Array[String] = []
	for i in range(unit.slots.size()):
		var check: Dictionary = ctrl.check_slot_action(unit.uid, i)
		if check.get("ok", false):
			var slot: SlotState = unit.slots[i]
			labels.append(_slot_short_label(slot))
	return labels


func _unit_has_gem_slot_target(ctrl, state: GameState, player: UnitState, unit: UnitState) -> bool:
	if not _valid_slot_indices(ctrl, unit).is_empty():
		return true
	for slot in unit.slots:
		if _is_viewable_gem_slot(state, player, unit, slot, ctrl.selected_action):
			return true
	return false


func _is_viewable_gem_slot(state: GameState, player: UnitState, unit: UnitState, slot: SlotState, action: String) -> bool:
	if slot.gem_uid.is_empty() or slot.is_split_disabled():
		return false
	var max_range := Constants.EXTRACT_RANGE
	match action:
		Constants.ACTION_INSERT:
			max_range = Constants.INSERT_RANGE
	return BoardUtils.distance_between_units(player, unit) <= max_range


func _valid_tile_slot_indices(ctrl, tile: TileState) -> Array[String]:
	var labels: Array[String] = []
	for i in range(tile.slots.size()):
		var check: Dictionary = ctrl.check_tile_slot_action(tile.pos, i)
		if check.get("ok", false):
			var slot: SlotState = tile.slots[i]
			labels.append(_slot_short_label(slot))
	return labels


# ═══════════════════════════════════════════════════════════════════════════
# 攻击/宝石目标格计算
# ═══════════════════════════════════════════════════════════════════════════

func _attack_target_cells(state: GameState, player: UnitState) -> Array:
	var cells: Array = []
	var max_range := Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y if GemEffects.unit_has_red_light(state, player) else Constants.ATTACK_RANGE
	for x in range(Constants.BOARD_SIZE.x):
		for y in range(Constants.BOARD_SIZE.y):
			var pos := Vector2i(x, y)
			if pos == player.pos:
				continue
			if not BoardUtils.can_unit_attack_cell(player, state, pos, max_range):
				continue
			cells.append(pos)
	return cells


func _gem_target_cells(ctrl, state: GameState, player: UnitState) -> Array:
	var cells: Array = []
	for unit in state.units.values():
		if not unit.alive:
			continue
		if not _unit_has_gem_slot_target(ctrl, state, player, unit):
			continue
		for cell in unit.occupied_cells():
			if not cell in cells:
				cells.append(cell)
	for key in state.tiles.keys():
		var tile: TileState = state.tiles[key]
		if not tile.has_slots():
			continue
		if not _valid_tile_slot_indices(ctrl, tile).is_empty():
			if not tile.pos in cells:
				cells.append(tile.pos)
	return cells


# ═══════════════════════════════════════════════════════════════════════════
# 死亡宝石预览
# ═══════════════════════════════════════════════════════════════════════════

func _attack_hit_preview_cells(state: GameState, player: UnitState, target_pos: Vector2i) -> Array:
	if target_pos == player.pos:
		return []
	var max_range := Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y if GemEffects.unit_has_red_light(state, player) else Constants.ATTACK_RANGE
	if not BoardUtils.can_unit_attack_cell(player, state, target_pos, max_range):
		return []
	if GemEffects.unit_has_red_light(state, player):
		var beam_cells := _light_preview_cells(state, player, target_pos)
		if not beam_cells.is_empty():
			return beam_cells
	var has_split: bool = GemEffects.unit_has_red_split(state, player)
	var cells: Array = []
	if has_split:
		var gem_ctx := GemTagResolver.build_context(state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
		var shot_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "split"))
		var shot := _SplitShotRules.resolve_shot(player, target_pos, shot_level)
		for cell in shot.cells:
			if BoardUtils.in_bounds(state, cell) and not cell in cells:
				cells.append(cell)
	else:
		cells.append(target_pos)
	if GemEffects.unit_has_red_explosion(state, player):
		var blast_anchors: Array = cells.duplicate()
		if not has_split:
			blast_anchors = [target_pos]
		for anchor in blast_anchors:
			for cell in GemEffects.cross_explosion_cells(anchor):
				if BoardUtils.in_bounds(state, cell) and not cell in cells:
					cells.append(cell)
	var victim: UnitState = state.get_unit_at(target_pos)
	if victim != null and victim.alive and victim.hp <= 1:
		for slot in victim.slots:
			if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null:
				continue
			for cell in _death_gem_preview_cells(state, victim.pos, gem):
				if not cell in cells:
					cells.append(cell)
	return cells


func _light_preview_cells(state: GameState, player: UnitState, target_pos: Vector2i) -> Array:
	var cells: Array = []
	var from_cell := BoardUtils.projectile_origin_cell(player, target_pos)
	var dx := signi(target_pos.x - from_cell.x)
	var dy := signi(target_pos.y - from_cell.y)
	if dx == 0 and dy == 0:
		return cells
	var gem_ctx := GemTagResolver.build_context(state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
	var pierce_blockers := GemTagResolver.tag_level(gem_ctx, "light") >= 3
	var current := from_cell + Vector2i(dx, dy)
	while BoardUtils.in_bounds(state, current):
		cells.append(current)
		var entity := state.get_entity_at(current)
		if not pierce_blockers and entity != null and entity.alive and entity.blocks_projectile():
			break
		current += Vector2i(dx, dy)
	return cells


func _attack_effect_preview(state: GameState, player: UnitState) -> Array:
	var cells: Array = []
	for unit in state.units.values():
		if not unit.alive or unit.uid == player.uid:
			continue
		if not BoardUtils.can_unit_reach_unit(player, unit, Constants.ATTACK_RANGE):
			continue
		if unit.hp > 1:
			continue
		for slot in unit.slots:
			if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null:
				continue
			for cell in _death_gem_preview_cells(state, unit.pos, gem):
				if not cell in cells:
					cells.append(cell)
	return cells


func _death_gem_preview_lines(state: GameState, unit: UnitState) -> Array[String]:
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


func _death_gem_preview_cells(state: GameState, origin: Vector2i, gem_ref: Variant) -> Array:
	var cells: Array = []
	match _data_registry().get_gem_ability_profile(gem_ref, "black_death"):
		"explosion":
			for cell in BoardUtils.cells_in_radius(origin, Constants.EXPLOSION_RADIUS):
				if BoardUtils.in_bounds(state, cell):
					cells.append(cell)
	return cells


# ═══════════════════════════════════════════════════════════════════════════
# 槽位预览文本
# ═══════════════════════════════════════════════════════════════════════════

func _slot_short_label(slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "红"
		Constants.SLOT_BLUE:
			return "蓝"
		Constants.SLOT_BLACK:
			return "黑"
	return "?"


func _slot_preview_line(state: GameState, unit: UnitState, slot: SlotState) -> String:
	var label := _slot_short_label(slot)
	if slot.is_split_disabled():
		return "%s槽: 分裂已失效" % label
	if slot.locked:
		return "%s槽: 锁定" % label
	if slot.gem_uid.is_empty():
		return "%s槽: 空" % label
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return "%s槽: ?" % label
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	var effect := GemEffects.get_slot_effect_description(gem, slot.slot_type, RulesIndex.slot_inspect_context(unit, slot))
	if effect.is_empty():
		return "%s槽: ◆%s" % [label, gem_name]
	return "%s槽: ◆%s — %s" % [label, gem_name, effect]


func _slot_preview_line_tile(state: GameState, tile: TileState, slot: SlotState) -> String:
	var label := _slot_short_label(slot)
	if slot.locked:
		return "地块%s槽: 锁定" % label
	if slot.gem_uid.is_empty():
		return "地块%s槽: 空" % label
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return "地块%s槽: ?" % label
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	var effect := GemEffects.get_slot_effect_description(gem, slot.slot_type, RulesIndex.tile_inspect_context(tile))
	if effect.is_empty():
		return "地块%s槽: ◆%s" % [label, gem_name]
	return "地块%s槽: ◆%s — %s" % [label, gem_name, effect]


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
