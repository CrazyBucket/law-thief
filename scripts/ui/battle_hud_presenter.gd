class_name BattleHudPresenter
extends RefCounted

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const IntentIcons = preload("res://scripts/ui/intent_icons.gd")
const StatusUi = preload("res://scripts/ui/status_ui.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")
const BattleHudRelicBar = preload("res://scripts/ui/battle_hud_relic_bar.gd")
const GemEchoVisuals = preload("res://scripts/ui/gem_echo_visuals.gd")

const _STATUS_PANEL_WIDTH := 320.0
const _RELIC_BAR_FALLBACK_H := 320.0

var _controller: BattleController = null
var _board = null

var _status_panel: PanelContainer = null
var _status_vbox: VBoxContainer = null
var _header_row: HBoxContainer = null
var _info_col: VBoxContainer = null
var _status_clip: Control = null
var _slot_clip: Control = null
var _slot_box: Container = null
var _portrait: TextureRect = null
var _inspect_name: Label = null
var _inspect_stats: Label = null
var _inspect_status_row: HBoxContainer = null
var _hp_bar_row: HBoxContainer = null
var _shield_icon: TextureRect = null
var _combined_hp_bar: CombinedHpBar = null
var _hp_text: Label = null
var _turn_label: Label = null
var _move_chip: Label = null
var _act_chip: Label = null
var _overload_chip: Label = null
var _held_label: Label = null
var _held_gem_icon: TextureRect = null
var _hint_label: Label = null
var _turn_chips: HBoxContainer = null
var _phase_badge: Label = null
var _message_label: Label = null
var _queue_row: HBoxContainer = null
var _queue_hint: Label = null
var _move_btn: Button = null
var _attack_btn: Button = null
var _extract_btn: Button = null
var _insert_btn: Button = null
var _end_turn_btn: Button = null
var _toggle_panel_btn: Button = null
var _relic_bar_scroll: ScrollContainer = null
var _relic_bar_vbox: Container = null
var _relic_bar_root: Control = null
var _show_relic_detail_cb: Callable = Callable()
var _tooltip: Control = null

var _select_unit_cb: Callable = Callable()
var _set_timeline_hover_cb: Callable = Callable()
var _clear_timeline_hover_cb: Callable = Callable()

var _relic_bar: BattleHudRelicBar = null
var _intent_row: HBoxContainer = null
var _intent_icon_wrap: Control = null
var _intent_icon: TextureRect = null
var _intent_label: Label = null
var _overload_detail_label: Label = null


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")


func _run_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RunService")


func _unit_looks() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("UnitLooks")


func _gem_display_name(gem_ref: Variant) -> String:
	var registry := _data_registry()
	if registry != null:
		return registry.get_gem_display_name(gem_ref)
	if gem_ref is GemState:
		return (gem_ref as GemState).gem_id
	return str(gem_ref)


func _unit_display_name(unit_def_id: String) -> String:
	var registry := _data_registry()
	if registry != null:
		return registry.get_unit_display_name(unit_def_id)
	return unit_def_id


func _relic_rarity(relic_id: String) -> String:
	var registry := _data_registry()
	if registry != null:
		return registry.get_relic_rarity(relic_id)
	return "common"


func _gem_texture(gem_ref: Variant) -> Texture2D:
	var looks := _unit_looks()
	return looks.get_gem_texture(gem_ref) if looks != null else null


func _gem_sprite_modulate(gem_ref: Variant) -> Color:
	var looks := _unit_looks()
	return looks.gem_sprite_modulate(gem_ref) if looks != null else Color.WHITE


func _gem_color(gem_ref: Variant) -> Color:
	var looks := _unit_looks()
	return looks.gem_color(gem_ref) if looks != null else BattleUiTheme.TEXT


func _slot_color(slot_type: String) -> Color:
	var looks := _unit_looks()
	return looks.slot_color(slot_type) if looks != null else BattleUiTheme.BORDER


func _unit_texture(unit_def_id: String) -> Texture2D:
	var looks := _unit_looks()
	return looks.get_unit_texture(unit_def_id) if looks != null else null


func _unit_sprite_modulate(team: String, unit_def_id: String) -> Color:
	var looks := _unit_looks()
	return looks.sprite_modulate_for_unit(team, unit_def_id) if looks != null else Color.WHITE


func _relic_texture(relic_id: String) -> Texture2D:
	var looks := _unit_looks()
	return looks.get_relic_texture(relic_id) if looks != null else null


func setup(deps: Dictionary) -> void:
	_controller = deps.get("controller", null)
	_board = deps.get("board", null)
	_status_panel = deps.get("status_panel", null)
	_status_vbox = deps.get("status_vbox", null)
	_header_row = deps.get("header_row", null)
	_info_col = deps.get("info_col", null)
	_status_clip = deps.get("status_clip", null)
	_slot_clip = deps.get("slot_clip", null)
	_slot_box = deps.get("slot_box", null)
	_portrait = deps.get("portrait", null)
	_inspect_name = deps.get("inspect_name", null)
	_inspect_stats = deps.get("inspect_stats", null)
	_inspect_status_row = deps.get("inspect_status_row", null)
	_hp_bar_row = deps.get("hp_bar_row", null)
	_shield_icon = deps.get("shield_icon", null)
	_combined_hp_bar = deps.get("combined_hp_bar", null)
	_hp_text = deps.get("hp_text", null)
	_turn_label = deps.get("turn_label", null)
	_move_chip = deps.get("move_chip", null)
	_act_chip = deps.get("act_chip", null)
	_overload_chip = deps.get("overload_chip", null)
	_held_label = deps.get("held_label", null)
	_held_gem_icon = deps.get("held_gem_icon", null)
	_hint_label = deps.get("hint_label", null)
	_turn_chips = deps.get("turn_chips", null)
	_phase_badge = deps.get("phase_badge", null)
	_message_label = deps.get("message_label", null)
	_queue_row = deps.get("queue_row", null)
	_queue_hint = deps.get("queue_hint", null)
	_move_btn = deps.get("move_btn", null)
	_attack_btn = deps.get("attack_btn", null)
	_extract_btn = deps.get("extract_btn", null)
	_insert_btn = deps.get("insert_btn", null)
	_end_turn_btn = deps.get("end_turn_btn", null)
	_toggle_panel_btn = deps.get("toggle_panel_btn", null)
	_relic_bar_scroll = deps.get("relic_bar_scroll", null)
	_relic_bar_vbox = deps.get("relic_bar_vbox", null)
	_relic_bar_root = deps.get("relic_bar_root", null)
	_show_relic_detail_cb = deps.get("show_relic_detail_cb", Callable())
	_tooltip = deps.get("tooltip", null)
	_select_unit_cb = deps.get("select_unit_cb", Callable())
	_set_timeline_hover_cb = deps.get("set_timeline_hover_cb", Callable())
	_clear_timeline_hover_cb = deps.get("clear_timeline_hover_cb", Callable())
	_relic_bar = BattleHudRelicBar.new()
	_relic_bar.setup({
		"root": _relic_bar_root,
		"scroll": _relic_bar_scroll,
		"grid": _relic_bar_vbox,
		"owned_relics_cb": Callable(self, "_owned_relics"),
		"texture_for_relic_cb": Callable(self, "_relic_texture"),
		"show_detail_cb": _show_relic_detail_cb,
	})


func refresh(context: Dictionary) -> Dictionary:
	var state: GameState = context.get("state", null)
	var inspect_uid: String = str(context.get("inspect_uid", ""))
	var inspect_cell: Vector2i = context.get("inspect_cell", Vector2i(-1, -1))
	var tracked_player_uid: String = str(context.get("tracked_player_uid", ""))
	var timeline_hover_uid: String = str(context.get("timeline_hover_uid", ""))
	var enemy_phase_running: bool = bool(context.get("enemy_phase_running", false))
	var enemy_turn_queue: Array[String] = _string_array_from(context.get("enemy_turn_queue", []))
	var editor_compact: bool = bool(context.get("editor_compact", false))
	if state == null:
		return {
			"inspect_uid": inspect_uid,
			"inspect_cell": inspect_cell,
			"tracked_player_uid": tracked_player_uid,
			"active_turn_uid": "",
		}

	var sync_result := _sync_controlled_player_inspect(state, inspect_uid, tracked_player_uid)
	inspect_uid = str(sync_result.get("inspect_uid", inspect_uid))
	tracked_player_uid = str(sync_result.get("tracked_player_uid", tracked_player_uid))
	if not inspect_uid.is_empty():
		inspect_cell = Vector2i(-1, -1)

	_turn_label.text = "T%d" % state.turn_index
	refresh_economy_chips(state)

	var turn_suffix := " · 第%d回合" % state.turn_index
	var phase_text := ""
	var phase_color := BattleUiTheme.PHASE_ENEMY
	match state.phase:
		Constants.PHASE_PLAYER:
			var queue_suffix := ""
			if not state.controllable_queue.is_empty():
				var total := 1 + state.controllable_queue.size()
				var current := total - state.controllable_queue.size()
				queue_suffix = " · %d/%d" % [current, total]
			phase_text = "你的回合" + turn_suffix + queue_suffix
			phase_color = BattleUiTheme.PHASE_PLAYER
		Constants.PHASE_ENDED:
			phase_text = "战斗结束" + turn_suffix
			phase_color = BattleUiTheme.PHASE_END
		_:
			phase_text = "敌方回合" + turn_suffix
			phase_color = BattleUiTheme.PHASE_ENEMY
	if state.overload_pending and state.phase == Constants.PHASE_PLAYER:
		phase_text += " · 过载预兆"
		phase_color = BattleUiTheme.TEXT_GOLD
	_phase_badge.text = phase_text
	_phase_badge.add_theme_color_override("font_color", phase_color)

	var held := _controller.get_held_gem()
	if held != null:
		var gem_name: String = _gem_display_name(held)
		if _held_gem_icon != null:
			_held_gem_icon.texture = _gem_texture(held)
			_held_gem_icon.self_modulate = _gem_sprite_modulate(held)
			GemEchoVisuals.apply_icon_material(_held_gem_icon, _controller.state, held.uid)
			_held_gem_icon.visible = true
		_held_label.text = "手持 %s" % gem_name
		_held_label.add_theme_color_override("font_color", _gem_color(held).lightened(0.15))
	else:
		if _held_gem_icon != null:
			GemEchoVisuals.apply_icon_material(_held_gem_icon, _controller.state, "")
			_held_gem_icon.visible = false
		_held_label.text = ""
		_held_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)

	var tutorial_hint: String = _controller.get_tutorial_hint()
	var action_hint: String = _controller.get_action_hint()
	_hint_label.text = tutorial_hint if not tutorial_hint.is_empty() else action_hint
	if not tutorial_hint.is_empty():
		_message_label.text = tutorial_hint.split("\n")[0]
	elif _message_label.text.is_empty():
		_message_label.text = action_hint

	_refresh_overload_detail(state)

	var active_turn_uid := _get_active_turn_uid(state, enemy_phase_running, enemy_turn_queue)
	_refresh_turn_queue(state, active_turn_uid, timeline_hover_uid, enemy_phase_running)
	_refresh_inspect(state, inspect_uid, inspect_cell)
	_apply_editor_compact_layout(editor_compact)
	_refresh_action_buttons(enemy_phase_running)
	_refresh_relic_bar(float(context.get("relic_bar_available_height", _RELIC_BAR_FALLBACK_H)))

	return {
		"inspect_uid": inspect_uid,
		"inspect_cell": inspect_cell,
		"tracked_player_uid": tracked_player_uid,
		"active_turn_uid": active_turn_uid,
	}


func refresh_economy_chips(state: GameState) -> void:
	if state == null:
		return
	_move_chip.text = "移动 %s" % ("✓" if state.player_moved else "○")
	_act_chip.text = "行动 %s" % ("✓" if state.player_acted else "○")
	var active_count: int = OverloadRules.overload_gem_count(state)
	var pending_count: int = 1 if state.overload_pending else 0
	if _overload_chip != null:
		_overload_chip.text = "过载 %d+%d" % [active_count, pending_count] if pending_count > 0 else "过载 %d" % active_count
		_style_chip(_overload_chip, state.overload_pending, BattleUiTheme.TEXT_GOLD)
	_set_tooltip(_move_chip, "本回合还能否移动", {
		"title": "移动",
		"subtitle": "回合资源",
		"accent": BattleUiTheme.PHASE_PLAYER,
		"sections": [{"title": "状态", "body": "本回合是否还能执行移动。"}],
	})
	_set_tooltip(_act_chip, "本回合还能否行动", {
		"title": "行动",
		"subtitle": "回合资源",
		"accent": BattleUiTheme.TEXT_GOLD,
		"sections": [{"title": "状态", "body": "本回合是否还能攻击、拔取或嵌入。"}],
	})
	if _overload_chip != null:
		var detail_lines := OverloadRules.panel_detail_lines(state)
		var overload_tip := "过载槽宝石 %d 颗%s" % [
			active_count,
			"，含 1 层待生效" if pending_count > 0 else "",
		]
		var tip_sections: Array = [{"title": "概览", "body": overload_tip}]
		if not detail_lines.is_empty():
			tip_sections.append({"title": "当前效果", "body": "\n".join(detail_lines)})
		_set_tooltip(_overload_chip, overload_tip, {
			"title": "过载",
			"subtitle": "战场状态",
			"accent": BattleUiTheme.TEXT_GOLD,
			"stats": [
				{"label": "已生效", "value": str(active_count)},
				{"label": "待生效", "value": str(pending_count)},
			],
			"sections": tip_sections,
		})
	_style_chip(_move_chip, not state.player_moved and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.PHASE_PLAYER)
	_style_chip(_act_chip, not state.player_acted and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.TEXT_GOLD)


func fit_status_panel(panel_visible: bool) -> void:
	var margins := _status_panel_content_margins()
	var panel_w := _STATUS_PANEL_WIDTH
	var inner_w := panel_w - margins.x
	var header_gap := float(_header_row.get_theme_constant("separation", "HBoxContainer"))
	var info_w := inner_w - _portrait.custom_minimum_size.x - header_gap
	_info_col.custom_minimum_size.x = info_w
	_hp_bar_row.custom_minimum_size.x = info_w
	_combined_hp_bar.custom_minimum_size.x = maxf(0.0, info_w - 18.0)
	_status_clip.custom_minimum_size.x = info_w
	_inspect_status_row.offset_right = info_w
	_apply_status_inner_width(inner_w)
	_status_panel.custom_minimum_size.x = panel_w
	_status_panel.size.x = panel_w
	_status_panel.offset_right = _status_panel.offset_left + panel_w
	_apply_status_panel_height(margins)
	sync_toggle_btn_x(panel_visible)


func fit_status_panel_height() -> void:
	if _status_panel == null or _status_vbox == null:
		return
	_apply_status_panel_height(_status_panel_content_margins())


func _apply_status_panel_height(margins: Vector2) -> void:
	_sync_panel_clip_heights()
	_status_vbox.queue_sort()
	var panel_h := _status_vbox.get_combined_minimum_size().y + margins.y
	_status_panel.custom_minimum_size.y = panel_h
	_status_panel.size.y = panel_h
	_status_panel.offset_bottom = _status_panel.offset_top + panel_h


func _sync_panel_clip_heights() -> void:
	if _status_clip != null and _inspect_status_row != null:
		var status_h := 0.0
		if _inspect_status_row.get_child_count() > 0:
			status_h = float(_inspect_status_row.get_minimum_size().y)
		_status_clip.custom_minimum_size.y = status_h
	if _slot_clip != null and _slot_box != null:
		var slot_h := 0.0
		if _slot_box.get_child_count() > 0:
			var slot_width := maxf(_slot_box.size.x, _slot_clip.size.x)
			if slot_width <= 0.0:
				slot_width = _slot_clip.custom_minimum_size.x
			slot_h = _flow_content_height(_slot_box, slot_width)
		_slot_clip.custom_minimum_size.y = slot_h
		_slot_box.size.y = slot_h
	if _overload_detail_label != null and not _overload_detail_label.visible:
		_overload_detail_label.custom_minimum_size.y = 0.0


func _flow_content_height(flow: Container, available_width: float) -> float:
	## FlowContainer's minimum height describes one unwrapped row. Calculate the
	## wrapped rows from live children so queued-for-deletion slots cannot inflate
	## the panel and the panel follows the actual visible content.
	if flow == null or available_width <= 0.0:
		return 0.0
	var h_gap := float(flow.get_theme_constant("h_separation", "FlowContainer"))
	var v_gap := float(flow.get_theme_constant("v_separation", "FlowContainer"))
	var row_width := 0.0
	var row_height := 0.0
	var content_height := 0.0
	var has_row := false
	for child in flow.get_children():
		if not child is Control or child.is_queued_for_deletion():
			continue
		var child_min := (child as Control).get_combined_minimum_size()
		if child_min.x <= 0.0 and child_min.y <= 0.0:
			continue
		if has_row and row_width + h_gap + child_min.x > available_width + 0.5:
			content_height += row_height + v_gap
			row_width = 0.0
			row_height = 0.0
			has_row = false
		row_width += child_min.x if not has_row else h_gap + child_min.x
		row_height = maxf(row_height, child_min.y)
		has_row = true
	if has_row:
		content_height += row_height
	return content_height


func sync_toggle_btn_x(panel_visible: bool) -> void:
	if _toggle_panel_btn == null or _status_panel == null:
		return
	var button_size := Vector2(40.0, 40.0)
	_toggle_panel_btn.custom_minimum_size = button_size
	_toggle_panel_btn.size = button_size
	var button_y := _status_panel.position.y + 8.0
	if panel_visible:
		_toggle_panel_btn.position = Vector2(_status_panel.position.x + _status_panel.size.x + 8.0, button_y)
	else:
		_toggle_panel_btn.position = Vector2(_status_panel.position.x + 8.0, button_y)


func _sync_controlled_player_inspect(state: GameState, inspect_uid: String, tracked_player_uid: String) -> Dictionary:
	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return {
			"inspect_uid": inspect_uid,
			"tracked_player_uid": tracked_player_uid,
		}
	if player.uid == tracked_player_uid:
		return {
			"inspect_uid": inspect_uid,
			"tracked_player_uid": tracked_player_uid,
		}
	tracked_player_uid = player.uid
	inspect_uid = player.uid
	_controller.selected_unit_uid = player.uid
	return {
		"inspect_uid": inspect_uid,
		"tracked_player_uid": tracked_player_uid,
	}


func _apply_status_inner_width(inner_w: float) -> void:
	_status_vbox.custom_minimum_size.x = inner_w
	_header_row.custom_minimum_size.x = inner_w
	_hint_label.custom_minimum_size.x = inner_w
	_inspect_stats.custom_minimum_size.x = inner_w
	_held_label.custom_minimum_size.x = inner_w
	_slot_clip.custom_minimum_size.x = inner_w
	_slot_box.size.x = inner_w
	if _overload_detail_label != null:
		_overload_detail_label.custom_minimum_size.x = inner_w


func _status_panel_content_margins() -> Vector2:
	var style := _status_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return Vector2(24.0, 20.0)
	return Vector2(
		style.content_margin_left + style.content_margin_right,
		style.content_margin_top + style.content_margin_bottom
	)


func _refresh_inspect(state: GameState, inspect_uid: String, inspect_cell: Vector2i) -> void:
	for child in _slot_box.get_children():
		child.queue_free()
	if inspect_uid.is_empty():
		if _is_valid_inspect_cell(inspect_cell):
			_refresh_cell_inspect(state, inspect_cell)
			return
		_clear_inspect_header("单位详情")
		_inspect_stats.text = "点击时间轴或棋盘"
		return
	var unit: UnitState = state.units.get(inspect_uid, null)
	if unit == null or not unit.alive:
		_clear_inspect_header("已阵亡")
		_inspect_stats.text = ""
		return
	var unit_name: String = _unit_display_name(unit.unit_def_id)
	_portrait.texture = _unit_texture(unit.unit_def_id)
	_portrait.self_modulate = _unit_sprite_modulate(unit.team, unit.unit_def_id)
	_inspect_name.text = unit_name
	_refresh_inspect_hp_bar(state, unit)
	_hp_text.text = "%d / %d" % [unit.hp, unit.max_hp]
	StatusUi.populate_status_row(_inspect_status_row, unit, true, [Constants.STATUS_ARMOR], _tooltip)
	var attack_value := CombatRules.attack_damage(state, unit)
	var stat_parts: Array[String] = ["攻击 %d · 速度 %d" % [attack_value, unit.speed]]
	var stack_lines := _status_stack_lines(unit)
	if not stack_lines.is_empty():
		stat_parts.append("层数：%s" % " · ".join(stack_lines))
	_inspect_stats.text = "\n".join(stat_parts)
	_refresh_intent_row(unit)
	for slot_index in range(unit.slots.size()):
		_slot_box.add_child(_create_slot_chip(state, unit, unit.slots[slot_index], slot_index))


func _refresh_cell_inspect(state: GameState, cell: Vector2i) -> void:
	var tile := state.get_tile(cell)
	var entity := state.get_entity_at(cell)
	var title := _cell_title(tile, entity)
	_clear_inspect_header(title)
	var lines: Array[String] = []
	if entity != null:
		lines.append(_entity_summary(entity))
		if entity.max_hp > 0:
			lines.append("耐久 %d / %d" % [entity.hp, entity.max_hp])
	if tile != null:
		if entity == null:
			lines.append(_tile_display_name(tile))
		if not tile.modifiers.is_empty():
			lines.append("地面：%s" % _overlay_summary(tile.modifiers))
		var traits := _ground_trait_summary(tile)
		if not traits.is_empty():
			lines.append("属性：%s" % traits)
		if tile.has_slots():
			lines.append("槽位：%s" % _tile_slot_summary(state, tile))
	if lines.is_empty():
		lines.append("无特殊状态")
	_inspect_stats.text = "\n".join(lines)


func _cell_title(tile: TileState, entity: EntityState) -> String:
	if entity != null:
		return _entity_display_name(entity)
	if tile != null and not tile.modifiers.is_empty():
		var first: Dictionary = tile.modifiers[0]
		return _overlay_display_name(str(first.get("type", "")))
	if tile != null:
		return _tile_display_name(tile)
	return "地块"


func _entity_display_name(entity: EntityState) -> String:
	match entity.entity_id:
		Constants.ENTITY_ROCK:
			return "石块"
		Constants.ENTITY_PROP:
			return "障碍物"
		Constants.ENTITY_SPIKE:
			return "地刺"
		Constants.ENTITY_BARREL:
			return "油桶"
	return "实体"


func _entity_summary(entity: EntityState) -> String:
	match entity.entity_id:
		Constants.ENTITY_ROCK, Constants.ENTITY_PROP:
			return "阻挡移动与射击"
		Constants.ENTITY_SPIKE:
			return "经过时受伤"
		Constants.ENTITY_BARREL:
			return "可被摧毁，引燃后爆炸"
	return _entity_display_name(entity)


func _tile_display_name(tile: TileState) -> String:
	match tile.tile_id:
		Constants.TILE_WATER:
			return "水面"
		Constants.TILE_ICE:
			return "冰面"
		Constants.TILE_GRASS:
			return "草地"
		Constants.TILE_BUSH:
			return "灌木"
		Constants.TILE_PILLAR:
			return "机关柱"
	return "地面"


func _overlay_summary(modifiers: Array) -> String:
	var parts: Array[String] = []
	for raw_modifier in modifiers:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier
		var label := _overlay_display_name(str(modifier.get("type", "")))
		var duration := int(modifier.get("duration", 0))
		if duration > 0:
			label += " %d回合" % duration
		parts.append(label)
	return " · ".join(parts)


func _overlay_display_name(overlay_id: String) -> String:
	match overlay_id:
		Constants.TILE_MOD_POISON_FOG:
			return "毒雾"
		Constants.TILE_MOD_FIRE:
			return "火焰"
		Constants.TILE_MOD_TOXIC_SMOKE:
			return "毒烟"
		Constants.TILE_MOD_POISON_PUDDLE:
			return "毒水"
	return "地面状态"


func _ground_trait_summary(tile: TileState) -> String:
	var parts: Array[String] = []
	if tile.has_ground_tag(Constants.GROUND_TAG_WATER):
		parts.append("水域")
	if tile.has_ground_tag(Constants.GROUND_TAG_ICE):
		parts.append("冰")
	if tile.has_ground_tag(Constants.GROUND_TAG_FLAMMABLE):
		parts.append("可燃")
	return " · ".join(parts)


func _tile_slot_summary(state: GameState, tile: TileState) -> String:
	var parts: Array[String] = []
	for i in range(tile.slots.size()):
		var slot: SlotState = tile.slots[i]
		if slot == null:
			continue
		var label := "%s槽" % _slot_display_name(slot.slot_type)
		if slot.lock_type == Constants.LOCK_OVERLOAD_SLOT:
			label = "过载" + label
		if slot.gem_uid.is_empty():
			label += " 空"
		else:
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			label += " %s" % (_gem_display_name(gem) if gem != null else "宝石")
		parts.append(label)
	return " · ".join(parts)


func _is_valid_inspect_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0


func _refresh_inspect_hp_bar(state: GameState, unit: UnitState) -> void:
	var shield_value := CombatRules.current_shield(state, unit)
	_shield_icon.visible = shield_value > 0
	_combined_hp_bar.set_values(unit.hp, unit.max_hp, shield_value)
	if shield_value > 0:
		_set_tooltip(_hp_bar_row, "生命 %d / %d · 护盾 %d" % [unit.hp, unit.max_hp, shield_value], {
			"title": "生命与护盾",
			"subtitle": "当前状态",
			"icon": StatusUi.glossary_term_for_status(Constants.STATUS_ARMOR).get("icon", null),
			"accent": UiPalette.ARMOR_STEEL,
			"stats": [
				{"label": "生命", "value": "%d / %d" % [unit.hp, unit.max_hp], "color": BattleUiTheme.TEXT},
				{"label": "护盾", "value": str(shield_value), "color": UiPalette.ARMOR_STEEL.lightened(0.25)},
			],
			"sections": [{"title": "护盾", "body": "先抵挡普通伤害；真实伤害会直接扣除生命。"}],
			"terms": [
				StatusUi.glossary_term_for_status(Constants.STATUS_ARMOR),
				StatusUi.glossary_term_for_key("true_damage"),
			],
		})
	else:
		_set_tooltip(_hp_bar_row, "生命 %d / %d" % [unit.hp, unit.max_hp], {
			"title": "生命",
			"subtitle": "当前状态",
			"stats": [{"label": "生命", "value": "%d / %d" % [unit.hp, unit.max_hp], "color": BattleUiTheme.TEXT}],
		})


func _refresh_intent_row(unit: UnitState) -> void:
	var show := unit.intent != null and unit.team == Constants.TEAM_ENEMY
	if not show:
		if _intent_row != null:
			_intent_row.visible = false
		return
	if _intent_row == null:
		_intent_row = HBoxContainer.new()
		_intent_row.add_theme_constant_override("separation", 6)
		_intent_row.mouse_filter = Control.MOUSE_FILTER_STOP
		_intent_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_intent_icon_wrap = Control.new()
		_intent_icon_wrap.custom_minimum_size = Vector2(18, 18)
		_intent_icon_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_intent_row.add_child(_intent_icon_wrap)
		_intent_icon = TextureRect.new()
		_intent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_intent_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_intent_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_intent_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_intent_icon_wrap.add_child(_intent_icon)
		_intent_label = Label.new()
		_intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_intent_label.add_theme_font_size_override("font_size", BattleUiTheme.FONT_SMALL)
		_intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_intent_row.add_child(_intent_label)
		var parent := _inspect_stats.get_parent()
		parent.add_child(_intent_row)
		parent.move_child(_intent_row, _inspect_stats.get_index() + 1)
	var intent_col := UiPalette.intent_color(unit.intent.type)
	_intent_row.visible = true
	var icon_tex := IntentIcons.get_icon(unit.intent.type)
	_intent_icon.texture = icon_tex
	_intent_icon.visible = icon_tex != null
	_intent_label.text = unit.intent.preview_text if icon_tex != null else "%s %s" % [IntentState.intent_icon(unit.intent.type), unit.intent.preview_text]
	_intent_label.add_theme_color_override("font_color", intent_col.lightened(0.2))
	_set_tooltip(_intent_row, "敌人下回合意图", {
		"title": "意图",
		"subtitle": "敌方行动",
		"icon": icon_tex,
		"accent": intent_col,
		"sections": [{"title": "预告", "body": unit.intent.preview_text}],
	})


func _clear_inspect_header(title: String) -> void:
	if _intent_row != null:
		_intent_row.visible = false
	_portrait.texture = null
	_portrait.self_modulate = Color.WHITE
	_inspect_name.text = title
	_combined_hp_bar.set_values(0, 1, 0)
	_hp_text.text = ""
	_shield_icon.visible = false
	while _inspect_status_row.get_child_count() > 0:
		_inspect_status_row.get_child(0).free()


func _create_slot_chip(state: GameState, unit: UnitState, slot: SlotState, slot_index: int) -> Control:
	var chip := PanelContainer.new()
	var color := _slot_color(slot.slot_type)
	var gem: GemState = null
	if not slot.gem_uid.is_empty():
		gem = state.gems.get(slot.gem_uid, null)
		if gem != null:
			color = _gem_color(gem)
	chip.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(color))
	chip.custom_minimum_size = Vector2(0, 24)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	var slot_name := _slot_display_name(slot.slot_type)
	var is_dual := not slot.dual_type.is_empty()
	var dual_name := _slot_display_name(slot.dual_type) if is_dual else ""
	var display_name := ("%s/%s" % [slot_name, dual_name]) if is_dual else slot_name
	var slot_prefix := "#%d %s" % [slot_index + 1, display_name]
	if slot.is_split_disabled():
		label.text = "%s ×" % slot_prefix
		_set_tooltip(chip, "%s槽：分裂已失效" % display_name, _slot_state_tooltip_spec(display_name, "分裂已失效", color))
	elif slot.locked:
		label.text = "%s 🔒" % slot_prefix
		_set_tooltip(chip, "%s槽：锁定" % display_name, _slot_state_tooltip_spec(display_name, "槽位已锁定", color))
	elif slot.gem_uid.is_empty():
		label.text = "%s 空" % slot_prefix
		var tip := "%s槽：空" % display_name
		if is_dual:
			tip += "（双色槽，可嵌入%s或%s宝石）" % [slot_name, dual_name]
		_set_tooltip(chip, tip, _slot_state_tooltip_spec(display_name, tip, color))
	else:
		if gem == null:
			label.text = "%s ?" % slot_prefix
			_set_tooltip(chip, "%s槽：无宝石数据" % display_name, _slot_state_tooltip_spec(display_name, "宝石数据缺失", color))
		else:
			var gem_icon := _make_gem_icon(gem, 14)
			if gem_icon != null:
				row.add_child(gem_icon)
			label.text = "%s %s" % [slot_prefix, _gem_display_name(gem)]
			_set_tooltip(chip, _slot_chip_tooltip(gem, slot, unit, state), _slot_chip_tooltip_spec(gem, slot, unit, state))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	row.add_child(label)
	chip.add_child(row)
	return chip


func _make_gem_icon(gem: GemState, size_px: int) -> TextureRect:
	var tex := _gem_texture(gem)
	if tex == null:
		return null
	var icon := TextureRect.new()
	icon.texture = tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = _gem_sprite_modulate(gem)
	GemEchoVisuals.apply_icon_material(icon, _controller.state, gem.uid)
	return icon


func _slot_display_name(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED:
			return "红"
		Constants.SLOT_BLUE:
			return "蓝"
		Constants.SLOT_BLACK:
			return "黑"
	return "?"


func _slot_effect_context(unit: UnitState, slot: SlotState) -> String:
	return RulesIndex.slot_inspect_context(unit, slot)


func _slot_chip_tooltip(gem: GemState, slot: SlotState, unit: UnitState, state: GameState = null) -> String:
	var gem_name: String = _gem_display_name(gem)
	var lines: Array[String] = [gem_name]
	lines.append_array(_slot_chip_detail_lines(gem, slot, unit, state))
	return "\n".join(lines)


func _slot_chip_tooltip_spec(gem: GemState, slot: SlotState, unit: UnitState, state: GameState = null) -> Dictionary:
	var display_name := _slot_display_name(slot.slot_type)
	if not slot.dual_type.is_empty():
		display_name = "%s/%s" % [display_name, _slot_display_name(slot.dual_type)]
	var details := _slot_chip_detail_lines(gem, slot, unit, state)
	var detail_text := "\n".join(details)
	return {
		"title": _gem_display_name(gem),
		"subtitle": "%s槽" % display_name,
		"icon": _gem_texture(gem),
		"icon_tint": _gem_sprite_modulate(gem),
		"accent": _gem_color(gem).lightened(0.15),
		"stats": [{"label": "槽位", "value": display_name, "color": _slot_color(slot.slot_type).lightened(0.2)}],
		"sections": [{"title": "效果", "body": detail_text}] if not detail_text.is_empty() else [],
		"terms": StatusUi.terms_for_text(detail_text),
	}


func _slot_state_tooltip_spec(display_name: String, body: String, color: Color) -> Dictionary:
	return {
		"title": "%s槽" % display_name,
		"subtitle": "槽位",
		"accent": color.lightened(0.15),
		"sections": [{"title": "状态", "body": body}],
	}


func _slot_chip_detail_lines(gem: GemState, slot: SlotState, unit: UnitState, state: GameState = null) -> Array[String]:
	var lines: Array[String] = []
	if state == null:
		var effect: String = GemEffects.get_slot_effect_description(gem, slot.slot_type, _slot_effect_context(unit, slot))
		if not effect.is_empty():
			lines.append(effect)
	if state != null:
		var registry := _data_registry()
		var ctx := GemTagResolver.build_context(state, unit, slot.slot_type, GemEffects.TIMING_ACTIVE)
		var tag_levels: Dictionary = ctx.get("tag_levels", {})
		var combo_levels: Dictionary = ctx.get("combo_levels", {})
		if not tag_levels.is_empty():
			for tag in tag_levels.keys():
				var lvl := int(tag_levels[tag])
				if lvl <= 0:
					continue
				var level_desc := ""
				if registry != null:
					level_desc = registry.get_gem_effect_level_summary(str(tag), slot.slot_type, lvl)
				if not level_desc.is_empty():
					lines.append(level_desc)
				else:
					var tag_sym_key := "gem.%s.symbol" % str(tag)
					var sym: String = TranslationServer.translate(tag_sym_key)
					if sym == tag_sym_key:
						sym = str(tag)
					lines.append("%s Lv%d" % [sym, lvl])
		if not combo_levels.is_empty():
			var combo_parts: Array[String] = []
			for combo_id in combo_levels.keys():
				var lvl := int(combo_levels[combo_id])
				if lvl > 0:
					var combo_key := "gem.combo.%s" % str(combo_id)
					var combo_label: String = TranslationServer.translate(combo_key)
					if combo_label == combo_key:
						combo_label = str(combo_id).replace("_", "+")
					combo_parts.append("%s Lv%d" % [combo_label, lvl])
			if not combo_parts.is_empty():
				lines.append("组合：%s" % " · ".join(combo_parts))
	return lines


func _refresh_action_buttons(enemy_phase_running: bool) -> void:
	var current: String = _controller.selected_action
	var can_act: bool = not enemy_phase_running
	_move_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_MOVE)
	_attack_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_ATTACK)
	_extract_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_EXTRACT)
	_insert_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_INSERT)
	_end_turn_btn.disabled = not can_act or _controller.state == null or _controller.state.phase != Constants.PHASE_PLAYER
	BattleUiTheme.apply_button(_move_btn, "move", current == Constants.ACTION_MOVE)
	BattleUiTheme.apply_button(_attack_btn, "combat", current == Constants.ACTION_ATTACK)
	BattleUiTheme.apply_button(_extract_btn, "gem", current == Constants.ACTION_EXTRACT)
	BattleUiTheme.apply_button(_insert_btn, "gem", current == Constants.ACTION_INSERT)
	BattleUiTheme.apply_button(_end_turn_btn, "end", false)
	_move_btn.text = "机动"
	_attack_btn.text = "射击"
	_extract_btn.text = "拔取"
	_insert_btn.text = "嵌入"
	_end_turn_btn.text = "结束回合"


func _refresh_turn_queue(state: GameState, active_uid: String, timeline_hover_uid: String, enemy_phase_running: bool) -> void:
	for child in _queue_row.get_children():
		child.queue_free()
	var focus_uid := timeline_hover_uid if not timeline_hover_uid.is_empty() else active_uid
	var active_unit: UnitState = state.units.get(active_uid, null)
	if active_unit != null:
		var active_name: String = _unit_display_name(active_unit.unit_def_id)
		_queue_hint.text = "当前 %s · 速 %d" % [active_name, active_unit.speed]
	else:
		_queue_hint.text = "当前 —"
	for uid in _build_turn_timeline_uids(state, active_uid, enemy_phase_running, 8):
		var unit: UnitState = state.units.get(uid, null)
		if unit != null and unit.alive:
			_queue_row.add_child(_create_timeline_avatar(unit, uid == active_uid, uid == focus_uid))


func _get_active_turn_uid(state: GameState, enemy_phase_running: bool, enemy_turn_queue: Array[String]) -> String:
	if state.phase == Constants.PHASE_PLAYER:
		var player: UnitState = state.get_player()
		return player.uid if player != null and player.alive else ""
	if enemy_phase_running and not enemy_turn_queue.is_empty():
		return enemy_turn_queue[0]
	return ""


func _build_turn_timeline_uids(state: GameState, active_uid: String, _enemy_phase_running: bool, max_items: int) -> Array[String]:
	var units: Array = []
	for unit in state.units.values():
		if unit.alive:
			units.append(unit)
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		if a.speed == b.speed:
			return a.uid < b.uid
		return a.speed > b.speed
	)
	if units.is_empty():
		return []
	var ordered: Array[String] = []
	for unit in units:
		ordered.append(unit.uid)
	var start_idx: int = 0
	if not active_uid.is_empty():
		var idx: int = ordered.find(active_uid)
		if idx >= 0:
			start_idx = idx
	var timeline: Array[String] = []
	for i in range(max_items):
		timeline.append(ordered[(start_idx + i) % ordered.size()])
	return timeline


func _create_timeline_avatar(unit: UnitState, is_active: bool, is_hovered: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(46, 52)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(40, 40)
	var team_color := BattleUiTheme.PHASE_PLAYER if unit.team == Constants.TEAM_PLAYER else BattleUiTheme.PHASE_ENEMY
	var accent := BattleUiTheme.BORDER
	if is_hovered:
		accent = BattleUiTheme.TEXT_GOLD
	elif is_active:
		accent = team_color
	frame.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent))
	stack.add_child(frame)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _unit_texture(unit.unit_def_id)
	icon.self_modulate = _unit_sprite_modulate(unit.team, unit.unit_def_id)
	frame.add_child(icon)
	if is_active:
		var arrow := Label.new()
		arrow.text = "▼"
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 10)
		arrow.add_theme_color_override("font_color", team_color)
		stack.add_child(arrow)
	var hover_btn := Button.new()
	hover_btn.flat = true
	hover_btn.focus_mode = Control.FOCUS_NONE
	hover_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	hover_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _set_timeline_hover_cb.is_valid():
		hover_btn.mouse_entered.connect(_set_timeline_hover_cb.bind(unit.uid), CONNECT_DEFERRED)
	if _clear_timeline_hover_cb.is_valid():
		hover_btn.mouse_exited.connect(_clear_timeline_hover_cb.bind(unit.uid), CONNECT_DEFERRED)
	if _select_unit_cb.is_valid():
		hover_btn.pressed.connect(_select_unit_cb.bind(unit.uid))
	root.add_child(hover_btn)
	return root


func _style_chip(label: Label, highlight: bool, color: Color) -> void:
	if not highlight:
		label.remove_theme_stylebox_override("normal")
		label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		return
	label.add_theme_stylebox_override("normal", BattleUiTheme.chip_style(color))
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)


func _apply_editor_compact_layout(compact: bool) -> void:
	if _hint_label != null:
		_hint_label.visible = not compact
	if _overload_detail_label != null:
		_overload_detail_label.visible = not compact and not _overload_detail_label.text.is_empty()
	if _inspect_stats != null:
		_inspect_stats.visible = not compact
	if _turn_chips != null:
		_turn_chips.visible = not compact
	if _held_label != null and compact:
		_held_label.visible = not _held_label.text.is_empty()


func _refresh_relic_bar(available_height: float = _RELIC_BAR_FALLBACK_H) -> void:
	if _relic_bar != null:
		_relic_bar.refresh(available_height)


func _owned_relics() -> Array[String]:
	var run_service := _run_service()
	if run_service == null or not run_service.is_run_active():
		return []
	return _string_array_from(run_service.get_owned_relics())


func _relic_bar_layout(count: int, available_height: float = _RELIC_BAR_FALLBACK_H) -> Dictionary:
	return BattleHudRelicBar.layout_for(count, available_height)


func _string_array_from(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values:
			result.append(str(value))
	return result


func _create_relic_badge(relic_id: String, icon_size: float) -> Control:
	if _relic_bar == null:
		var preview_bar := BattleHudRelicBar.new()
		preview_bar.setup({
			"texture_for_relic_cb": Callable(self, "_relic_texture"),
			"show_detail_cb": _show_relic_detail_cb,
		})
		return preview_bar.create_badge(relic_id, icon_size)
	return _relic_bar.create_badge(relic_id, icon_size)


func _set_tooltip(control: Control, fallback_text: String, spec: Dictionary) -> void:
	if control == null:
		return
	if _tooltip != null and _tooltip.has_method("attach"):
		control.tooltip_text = ""
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		_tooltip.call("attach", control, spec)
	else:
		control.tooltip_text = fallback_text


func relic_desc_text(def: Dictionary) -> String:
	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		return desc
	return "（暂无描述）"


func _overload_summary_text(state: GameState) -> String:
	if state == null:
		return ""
	var lines := OverloadRules.panel_detail_lines(state)
	return "\n".join(lines)


func _refresh_overload_detail(state: GameState) -> void:
	_ensure_overload_detail_label()
	var lines := OverloadRules.panel_detail_lines(state)
	if lines.is_empty():
		_overload_detail_label.visible = false
		_overload_detail_label.text = ""
		return
	_overload_detail_label.visible = true
	_overload_detail_label.text = "\n".join(lines)
	_overload_detail_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)


func _ensure_overload_detail_label() -> void:
	if _overload_detail_label != null or _status_vbox == null:
		return
	_overload_detail_label = Label.new()
	_overload_detail_label.name = "OverloadDetail"
	_overload_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overload_detail_label.add_theme_font_size_override("font_size", BattleUiTheme.FONT_SMALL)
	_overload_detail_label.visible = false
	var insert_idx := _turn_chips.get_index() + 1 if _turn_chips != null else 0
	_status_vbox.add_child(_overload_detail_label)
	_status_vbox.move_child(_overload_detail_label, insert_idx)


func _status_stack_lines(unit: UnitState) -> Array[String]:
	var lines: Array[String] = []
	for status in unit.statuses:
		if status == null or status.stacks <= 1:
			continue
		lines.append("%s×%d" % [StatusUi._StatusRegistry.display_name(status.status_id), status.stacks])
	return lines


func rarity_color(rarity: String) -> Color:
	return UiPalette.rarity_color(rarity)


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	return box
