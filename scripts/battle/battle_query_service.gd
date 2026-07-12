class_name BattleQueryService
extends RefCounted

const _StatusUi = preload("res://scripts/ui/status_ui.gd")
const GemEffects = preload("res://scripts/rules/gem_effects.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const IntentPreviewRules = preload("res://scripts/rules/intent_preview_rules.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")

var _ctrl_ref: WeakRef
var _ctrl: BattleController:
	get:
		return _ctrl_ref.get_ref() as BattleController if _ctrl_ref != null else null
var _reachable_cache: Array = []
var _reachable_cache_key: Array = []
var _attack_range_cache: Array = []
var _attack_range_cache_key: Array = []


func setup(controller: BattleController) -> void:
	_ctrl_ref = weakref(controller)
	invalidate_highlight_cache()


func invalidate_highlight_cache() -> void:
	_reachable_cache.clear()
	_reachable_cache_key.clear()
	_attack_range_cache.clear()
	_attack_range_cache_key.clear()


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
		"overlays": [],
		"routes": [],
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
	var unlimited := ctrl.editor_unlimited_actions_enabled()
	var manual_blocked := OverloadRules.blocks_player_manual_actions(state) and not unlimited
	if manual_blocked:
		action = ""
	var move_budget := ctrl.player_move_budget(player)
	if action == Constants.ACTION_MOVE and (unlimited or ((not state.player_moved or StatusRules.has_extra_move(player)) and StatusRules.can_move(player))):
		var reachable := _cached_reachable_cells(state, player, move_budget, unlimited)
		result["reachable"] = reachable
		_append_overlay(result, "move", reachable)
		if hover_cell in reachable and hover_cell != player.pos:
			var move_path := BoardUtils.astar_path(
				state,
				player.pos,
				hover_cell,
				move_budget,
				player.uid,
				{"allow_partial_path": false},
				{},
				player
			)
			if not move_path.is_empty() and move_path[-1] == hover_cell:
				var route: Array = [player.pos]
				route.append_array(move_path)
				_append_route(result, "move", route, {"arrow_reverse": false})
	elif action == Constants.ACTION_ATTACK \
		and (unlimited or StatusRules.can_attack(player)) \
		and (unlimited or not state.player_acted or StatusRules.has_extra_attack(player)):
		var attack_range := _cached_attack_target_cells(state, player, unlimited)
		result["attack_range"] = attack_range
		_append_overlay(result, "attack_range", attack_range)
		if hover_cell.x >= 0 and BoardUtils.in_bounds(state, hover_cell):
			var hit_preview := _attack_hit_preview_cells(state, player, hover_cell)
			result["effect_preview"] = hit_preview
			_append_overlay(result, "effect", hit_preview, {"source_uid": player.uid, "target_cell": hover_cell})
		else:
			var effect_preview := _attack_effect_preview(state, player)
			result["effect_preview"] = effect_preview
			_append_overlay(result, "effect", effect_preview, {"source_uid": player.uid})
	elif action == Constants.ACTION_EXTRACT and ctrl.can_use_action(Constants.ACTION_EXTRACT):
		var targets := _gem_target_cells(ctrl, state, player)
		result["targets"] = targets
		_append_overlay(result, "target", targets, {"action": action})
	elif action == Constants.ACTION_INSERT and ctrl.can_use_action(Constants.ACTION_INSERT):
		var targets := _gem_target_cells(ctrl, state, player)
		result["targets"] = targets
		_append_overlay(result, "target", targets, {"action": action})
	var selected_uid: String = ctrl.selected_unit_uid
	if not selected_uid.is_empty():
		var selected_unit: UnitState = state.units.get(selected_uid, null)
		if selected_unit != null and selected_unit.alive and selected_unit.intent != null:
			var intent_path: Array = selected_unit.intent.path.duplicate()
			result["paths"] = intent_path
			if not intent_path.is_empty():
				_append_overlay(result, "intent_path", intent_path, {"unit_uid": selected_unit.uid})
				var route: Array = [selected_unit.pos]
				route.append_array(intent_path)
				_append_route(result, "intent", route, {"unit_uid": selected_unit.uid, "arrow_reverse": false})
			if not selected_unit.intent.affected_cells.is_empty():
				var danger_cells: Array = selected_unit.intent.affected_cells.duplicate()
				result["danger"] = danger_cells
				_append_overlay(result, "danger", danger_cells, {"unit_uid": selected_unit.uid})
	return result


func _append_overlay(result: Dictionary, kind: String, cells: Array, options: Dictionary = {}) -> void:
	if cells.is_empty():
		return
	var unique_cells: Array[Vector2i] = []
	var seen := {}
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if seen.has(cell):
			continue
		seen[cell] = true
		unique_cells.append(cell)
	if unique_cells.is_empty():
		return
	var overlay := {
		"kind": kind,
		"cells": unique_cells,
	}
	for key in options.keys():
		overlay[key] = options[key]
	result["overlays"].append(overlay)


func _append_route(result: Dictionary, kind: String, path: Array, options: Dictionary = {}) -> void:
	if path.size() < 2:
		return
	var clean_path: Array[Vector2i] = []
	for raw_cell in path:
		clean_path.append(raw_cell)
	var route := {
		"kind": kind,
		"path": clean_path,
	}
	for key in options.keys():
		route[key] = options[key]
	result["routes"].append(route)


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
	var title: String = _data_registry().get_tile_display_name(tile.tile_id)
	if ctrl.editor_unlimited_actions_enabled():
		title = "%s (%d, %d)" % [title, cell.x, cell.y]
	var lines: Array[String] = [title]
	var spike := BoardUtils.spike_entity_at(state, cell)
	if spike != null:
		lines.append("地刺：踏入受 %d 伤害；被推入时易伤并受 %d 伤害" % [
			CombatConfig.spike_damage(), CombatConfig.spike_collision_damage()
		])
	var blocking := BoardUtils.blocking_entity_at(state, cell)
	if blocking != null and blocking.is_indestructible():
		lines.append("障碍物：阻挡移动与射击")
	match tile.tile_id:
		Constants.TILE_WATER:
			lines.append("水洼：导电连锁区域")
		Constants.TILE_PILLAR:
			lines.append("机关柱：嵌入宝石产生持续光环")
	if tile.has_modifier("poison_fog"):
		lines.append("毒雾：进入叠毒；回合结束仍在其中会继续叠毒（每层 %d 伤害）" % CombatConfig.poison_fog_damage())
	if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		lines.append("毒烟：同时视为火焰与毒雾，持续 1 回合")
	if tile.has_slots():
		for i in range(tile.slots.size()):
			var tslot: SlotState = tile.slots[i]
			lines.append(_slot_preview_line_tile(state, tile, tslot))
	if unit != null:
		lines.append("%s 生命 %d/%d" % [_data_registry().get_unit_display_name(unit.unit_def_id), unit.hp, unit.max_hp])
		for status_line in _StatusUi.preview_lines(unit):
			lines.append(status_line)
		if unit.intent != null and unit.team == Constants.TEAM_ENEMY and ctrl.selected_unit_uid == unit.uid:
			lines.append("意图：%s" % unit.intent.preview_text)
		for i in range(unit.slots.size()):
			var slot: SlotState = unit.slots[i]
			lines.append(_slot_preview_line(state, unit, slot))
	match ctrl.selected_action:
		Constants.ACTION_MOVE:
			var move_budget := ctrl.player_move_budget(player)
			var can_move_now := ctrl.editor_unlimited_actions_enabled() or ((not state.player_moved or StatusRules.has_extra_move(player)) and StatusRules.can_move(player))
			if can_move_now and cell in BoardUtils.reachable_cells(state, player.pos, move_budget):
				lines.append("落点可达")
		Constants.ACTION_ATTACK:
			var can_attack_now := ctrl.editor_unlimited_actions_enabled() \
				or (StatusRules.can_attack(player) and (not state.player_acted or StatusRules.has_extra_attack(player)))
			var attack_range := GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
			if can_attack_now and cell != player.pos and BoardUtils.can_unit_attack_cell(player, state, cell, attack_range):
				if blocking != null and blocking.is_indestructible() and unit == null:
					lines.append("射击会被障碍挡下")
				elif tile.has_tile_tag(Constants.TAG_TILE_WATER) and GemEffects.unit_has_red_arc(state, player):
					lines.append("水面导电：相连水域与潮湿单位会连锁")
				else:
					lines.append("射击预览：%d 伤害" % CombatRules.attack_damage(state, player))
				if unit != null:
					lines.append_array(_death_gem_preview_lines(state, unit))
		Constants.ACTION_EXTRACT:
			if unit != null and ctrl.can_use_action(Constants.ACTION_EXTRACT):
				var valid := _valid_slot_indices(ctrl, unit)
				if not valid.is_empty():
					lines.append("可拔出：%s（免费）" % ", ".join(valid))
			elif tile.has_slots() and ctrl.can_use_action(Constants.ACTION_EXTRACT):
				var tile_valid := _valid_tile_slot_indices(ctrl, tile)
				if not tile_valid.is_empty():
					lines.append("可从地块拔出：%s（免费）" % ", ".join(tile_valid))
		Constants.ACTION_INSERT:
			if unit != null and ctrl.can_use_action(Constants.ACTION_INSERT):
				var insert_valid := _valid_slot_indices(ctrl, unit)
				if not insert_valid.is_empty():
					lines.append("可嵌入：%s（免费）" % ", ".join(insert_valid))
			elif tile.has_slots() and ctrl.can_use_action(Constants.ACTION_INSERT):
				var tile_insert_valid := _valid_tile_slot_indices(ctrl, tile)
				if not tile_insert_valid.is_empty():
					lines.append("可嵌入地块：%s（免费）" % ", ".join(tile_insert_valid))
	return {"title": lines[0] if not lines.is_empty() else "", "body": "\n".join(lines)}


func get_action_hint() -> String:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleQueryService: _ctrl is null in get_action_hint")
		return "选择指令"
	match ctrl.selected_action:
		Constants.ACTION_MOVE:
			if ctrl.editor_unlimited_actions_enabled():
				return "机动待命 · 编辑模式"
			if ctrl.state != null:
				var player: UnitState = ctrl.state.get_player()
				if player != null and not StatusRules.can_move(player):
					var block_reason := StatusRules.move_block_reason(player)
					if block_reason.is_empty():
						return "机动受阻"
					return "机动受阻：%s" % block_reason
			return "机动待命"

		Constants.ACTION_ATTACK:
			if ctrl.editor_unlimited_actions_enabled():
				return "射击待命 · 编辑模式"
			if ctrl.state != null:
				var player: UnitState = ctrl.state.get_player()
				if player != null and not StatusRules.can_attack(player):
					return StatusRules.attack_block_reason(player)
			return "射击待命 · 射程 %d" % CombatConfig.attack_range()
		Constants.ACTION_EXTRACT:
			return "拔取宝石"
		Constants.ACTION_INSERT:
			if ctrl.state != null and ctrl.state.overload_pending:
				return "过载预兆：结束回合后生效"
			if ctrl.state != null \
				and ctrl.state.overload_last_action == Constants.ACTION_INSERT \
				and ctrl.state.overload_last_insert_turn == ctrl.state.turn_index:
				return "嵌入待命 · 再次嵌入将过载"
			return "嵌入宝石"
	return "选择指令"


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
		return "先夺取炸弹鼠红槽的爆炸宝石"
	if held != null and not state.player_acted:
		var player: UnitState = state.get_player()
		var guard_near := false
		for unit in state.get_alive_enemies():
			if unit.has_tag(Constants.TAG_UNIT_PATROL_GUARD) and BoardUtils.manhattan(player.pos, unit.pos) <= CombatConfig.insert_range():
				guard_near = true
				break
		if guard_near:
			return "把爆炸嵌入巡路甲兵黑槽，再射击引爆"
		return "靠近巡路甲兵，嵌入黑槽后击杀引爆"
	if held == null and state.player_acted:
		return "行动已用，结束回合"
	return "夺爆炸，塞黑槽，击杀引爆"


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
	if slot.gem_uid.is_empty():
		return false
	var max_range := CombatConfig.extract_range()
	match action:
		Constants.ACTION_INSERT:
			max_range = CombatConfig.insert_range()
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
	var max_range := GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
	var uses_light := GemEffects.unit_has_red_light(state, player)
	for x in range(Constants.BOARD_SIZE.x):
		for y in range(Constants.BOARD_SIZE.y):
			var pos := Vector2i(x, y)
			if pos == player.pos:
				continue
			if uses_light and not GemEffects.is_valid_light_aim(player, pos):
				continue
			if not BoardUtils.can_unit_attack_cell(player, state, pos, max_range):
				continue
			cells.append(pos)
	return cells


func _cached_reachable_cells(
	state: GameState,
	player: UnitState,
	move_budget: int,
	unlimited: bool
) -> Array:
	var key := [state.get_instance_id(), player.uid, player.pos, move_budget, unlimited]
	if key != _reachable_cache_key:
		_reachable_cache_key = key
		_reachable_cache = BoardUtils.reachable_cells(state, player.pos, move_budget)
	return _reachable_cache.duplicate()


func _cached_attack_target_cells(state: GameState, player: UnitState, unlimited: bool) -> Array:
	var max_range := GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
	var uses_light := GemEffects.unit_has_red_light(state, player)
	var key := [state.get_instance_id(), player.uid, player.pos, max_range, uses_light, unlimited]
	if key != _attack_range_cache_key:
		_attack_range_cache_key = key
		_attack_range_cache = _attack_target_cells(state, player)
	return _attack_range_cache.duplicate()


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
	if GemEffects.unit_has_red_light(state, player) and not GemEffects.is_valid_light_aim(player, target_pos):
		return []
	var max_range := GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
	if not BoardUtils.can_unit_attack_cell(player, state, target_pos, max_range):
		return []
	var profile := IntentPreviewRules.build_red_attack_profile(
		state,
		player,
		player.pos,
		target_pos,
		CombatRules.attack_damage(state, player)
	)
	var cells: Array = profile.get("affected_cells", []).duplicate()
	var predicted_uids: Dictionary = {}
	for raw_component in profile.get("components", []):
		if not raw_component is IntentDamageComponent:
			continue
		for target_uid in (raw_component as IntentDamageComponent).target_uids:
			predicted_uids[target_uid] = true
	for target_uid in predicted_uids:
		var victim: UnitState = state.units.get(target_uid, null)
		if not IntentPreviewRules.predicts_lethal_damage(state, player, victim, profile):
			continue
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


func _attack_effect_preview(state: GameState, player: UnitState) -> Array:
	var cells: Array = []
	for unit in state.units.values():
		if not unit.alive or unit.uid == player.uid:
			continue
		if not BoardUtils.can_unit_reach_unit(
			player,
			unit,
			GemEffects.red_attack_range(state, player, CombatConfig.attack_range())
		):
			continue
		var profile := IntentPreviewRules.build_red_attack_profile(
			state,
			player,
			player.pos,
			unit.pos,
			CombatRules.attack_damage(state, player)
		)
		if not IntentPreviewRules.predicts_lethal_damage(state, player, unit, profile):
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
		var effect := _slot_effect_summary(state, unit, slot, "")
		if not effect.is_empty():
			lines.append("预判: %s" % effect)
	return lines


func _death_gem_preview_cells(state: GameState, origin: Vector2i, gem_ref: Variant) -> Array:
	var cells: Array = []
	match _data_registry().get_gem_ability_profile(gem_ref, "black_death"):
		"explosion":
			for cell in BoardUtils.cells_in_radius(origin, CombatConfig.explosion_radius()):
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
	var effect := _slot_effect_summary(state, unit, slot, RulesIndex.slot_inspect_context(unit, slot))
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
	var effect := _slot_effect_summary(state, tile, slot, RulesIndex.tile_inspect_context(tile))
	if effect.is_empty():
		return "地块%s槽: ◆%s" % [label, gem_name]
	return "地块%s槽: ◆%s — %s" % [label, gem_name, effect]


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _slot_effect_summary(state: GameState, owner: Variant, slot: SlotState, fallback_context: String) -> String:
	if state == null or owner == null or slot == null or slot.gem_uid.is_empty():
		return ""
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return ""
	var registry := _data_registry()
	if registry != null:
		var gem_ctx := GemTagResolver.build_context(state, owner, slot.slot_type, GemEffects.TIMING_ACTIVE)
		var tag := str(registry.get_gem_tag(gem))
		var level := GemTagResolver.tag_level(gem_ctx, tag)
		var summary := str(registry.get_gem_effect_level_summary(tag, slot.slot_type, level))
		if not summary.is_empty():
			return summary
	return GemEffects.get_slot_effect_description(gem, slot.slot_type, fallback_context)
