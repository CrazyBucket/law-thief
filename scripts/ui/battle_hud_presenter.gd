class_name BattleHudPresenter
extends RefCounted

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const StatusUi = preload("res://scripts/ui/status_ui.gd")

const _STATUS_PANEL_WIDTH := 320.0

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
var _shield_row: HBoxContainer = null
var _shield_bar: ProgressBar = null
var _shield_text: Label = null
var _hp_bar: ProgressBar = null
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

var _select_unit_cb: Callable = Callable()
var _set_timeline_hover_cb: Callable = Callable()
var _clear_timeline_hover_cb: Callable = Callable()

var _relic_bar_ids: Array[String] = []


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
	_shield_row = deps.get("shield_row", null)
	_shield_bar = deps.get("shield_bar", null)
	_shield_text = deps.get("shield_text", null)
	_hp_bar = deps.get("hp_bar", null)
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
	_select_unit_cb = deps.get("select_unit_cb", Callable())
	_set_timeline_hover_cb = deps.get("set_timeline_hover_cb", Callable())
	_clear_timeline_hover_cb = deps.get("clear_timeline_hover_cb", Callable())


func refresh(context: Dictionary) -> Dictionary:
	var state: GameState = context.get("state", null)
	var inspect_uid: String = str(context.get("inspect_uid", ""))
	var tracked_player_uid: String = str(context.get("tracked_player_uid", ""))
	var timeline_hover_uid: String = str(context.get("timeline_hover_uid", ""))
	var enemy_phase_running: bool = bool(context.get("enemy_phase_running", false))
	var enemy_turn_queue: Array[String] = _string_array_from(context.get("enemy_turn_queue", []))
	var editor_compact: bool = bool(context.get("editor_compact", false))
	if state == null:
		return {
			"inspect_uid": inspect_uid,
			"tracked_player_uid": tracked_player_uid,
			"active_turn_uid": "",
		}

	var sync_result := _sync_controlled_player_inspect(state, inspect_uid, tracked_player_uid)
	inspect_uid = str(sync_result.get("inspect_uid", inspect_uid))
	tracked_player_uid = str(sync_result.get("tracked_player_uid", tracked_player_uid))

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
		var gem_name: String = DataRegistry.get_gem_display_name(held)
		if _held_gem_icon != null:
			_held_gem_icon.texture = UnitLooks.get_gem_texture(held)
			_held_gem_icon.self_modulate = UnitLooks.gem_sprite_modulate(held)
			_held_gem_icon.visible = true
		_held_label.text = "手持 %s" % gem_name
		_held_label.add_theme_color_override("font_color", UnitLooks.gem_color(held).lightened(0.15))
	else:
		if _held_gem_icon != null:
			_held_gem_icon.visible = false
		_held_label.text = ""
		_held_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)

	var tutorial_hint: String = _controller.get_tutorial_hint()
	var action_hint: String = _controller.get_action_hint()
	var overload_summary := _overload_summary_text(state)
	_hint_label.text = tutorial_hint if not tutorial_hint.is_empty() else action_hint
	if not overload_summary.is_empty():
		_hint_label.text += "\n" + overload_summary
	if not tutorial_hint.is_empty():
		_message_label.text = tutorial_hint.split("\n")[0]
	elif _message_label.text.is_empty():
		_message_label.text = action_hint

	var active_turn_uid := _get_active_turn_uid(state, enemy_phase_running, enemy_turn_queue)
	_refresh_turn_queue(state, active_turn_uid, timeline_hover_uid, enemy_phase_running)
	_refresh_inspect(state, inspect_uid)
	_apply_editor_compact_layout(editor_compact)
	_refresh_action_buttons(enemy_phase_running)
	_refresh_relic_bar()

	return {
		"inspect_uid": inspect_uid,
		"tracked_player_uid": tracked_player_uid,
		"active_turn_uid": active_turn_uid,
	}


func refresh_economy_chips(state: GameState) -> void:
	if state == null:
		return
	_move_chip.text = "移动 %s" % ("✓" if state.player_moved else "○")
	_act_chip.text = "行动 %s" % ("✓" if state.player_acted else "○")
	var active_count: int = state.overload_active_mutations.size()
	var pending_count: int = 1 if state.overload_pending else 0
	if _overload_chip != null:
		_overload_chip.text = "过载 %d+%d" % [active_count, pending_count] if pending_count > 0 else "过载 %d" % active_count
		_style_chip(_overload_chip, state.overload_pending, BattleUiTheme.TEXT_GOLD)
	_move_chip.tooltip_text = "本回合还能否移动"
	_act_chip.tooltip_text = "本回合还能否行动"
	if _overload_chip != null:
		_overload_chip.tooltip_text = "当前异变 %d 层%s" % [active_count, "，含 1 层待生效" if pending_count > 0 else ""]
	_style_chip(_move_chip, not state.player_moved and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.PHASE_PLAYER)
	_style_chip(_act_chip, not state.player_acted and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.TEXT_GOLD)


func fit_status_panel(panel_visible: bool) -> void:
	var margins := _status_panel_content_margins()
	var panel_w := _STATUS_PANEL_WIDTH
	var inner_w := panel_w - margins.x
	var header_gap := float(_header_row.get_theme_constant("separation", "HBoxContainer"))
	var info_w := inner_w - _portrait.custom_minimum_size.x - header_gap
	_info_col.custom_minimum_size.x = info_w
	_shield_bar.custom_minimum_size.x = maxf(0.0, info_w - 40.0)
	_hp_bar.custom_minimum_size.x = info_w
	_status_clip.custom_minimum_size.x = info_w
	_inspect_status_row.offset_right = info_w
	_apply_status_inner_width(inner_w)
	var panel_h := _status_vbox.get_minimum_size().y + margins.y
	_status_panel.custom_minimum_size = Vector2(panel_w, panel_h)
	_status_panel.size = Vector2(panel_w, panel_h)
	_status_panel.offset_right = _status_panel.offset_left + panel_w
	sync_toggle_btn_x(panel_visible)


func fit_status_panel_height() -> void:
	var margins := _status_panel_content_margins()
	if _slot_box != null and _slot_clip != null:
		_slot_clip.custom_minimum_size.y = maxf(24.0, float(_slot_box.get_minimum_size().y))
	var panel_h := _status_vbox.get_minimum_size().y + margins.y
	if absf(panel_h - _status_panel.size.y) < 0.5:
		return
	_status_panel.custom_minimum_size.y = panel_h
	_status_panel.size.y = panel_h
	_status_panel.offset_bottom = _status_panel.offset_top + panel_h


func sync_toggle_btn_x(panel_visible: bool) -> void:
	if panel_visible:
		_toggle_panel_btn.position.x = _status_panel.position.x + _status_panel.size.x + 8.0


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


func _status_panel_content_margins() -> Vector2:
	var style := _status_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return Vector2(24.0, 20.0)
	return Vector2(
		style.content_margin_left + style.content_margin_right,
		style.content_margin_top + style.content_margin_bottom
	)


func _refresh_inspect(state: GameState, inspect_uid: String) -> void:
	for child in _slot_box.get_children():
		child.queue_free()
	if inspect_uid.is_empty():
		_clear_inspect_header("单位详情")
		_inspect_stats.text = "点击时间轴或棋盘"
		return
	var unit: UnitState = state.units.get(inspect_uid, null)
	if unit == null or not unit.alive:
		_clear_inspect_header("已阵亡")
		_inspect_stats.text = ""
		return
	var unit_name: String = DataRegistry.get_unit_display_name(unit.unit_def_id)
	_portrait.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	_portrait.self_modulate = UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	_inspect_name.text = unit_name
	_hp_bar.max_value = unit.max_hp
	_hp_bar.value = unit.hp
	var ratio := float(unit.hp) / float(maxi(unit.max_hp, 1))
	_hp_bar.add_theme_stylebox_override(
		"fill",
		_flat_style(BattleUiTheme.hp_fill_color(ratio), BattleUiTheme.hp_fill_color(ratio).lightened(0.08))
	)
	_hp_text.text = "%d / %d" % [unit.hp, unit.max_hp]
	_refresh_inspect_shield(state, unit)
	StatusUi.populate_status_row(_inspect_status_row, unit, true, [Constants.STATUS_ARMOR])
	var attack_value := CombatRules.attack_damage(state, unit)
	var stat_parts: Array[String] = ["攻击 %d · 速度 %d" % [attack_value, unit.speed]]
	var stack_lines := _status_stack_lines(unit)
	if not stack_lines.is_empty():
		stat_parts.append("层数：%s" % " · ".join(stack_lines))
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		stat_parts.append(unit.intent.preview_text)
	_inspect_stats.text = "\n".join(stat_parts)
	for slot_index in range(unit.slots.size()):
		_slot_box.add_child(_create_slot_chip(state, unit, unit.slots[slot_index], slot_index))


func _refresh_inspect_shield(state: GameState, unit: UnitState) -> void:
	var shield_value := CombatRules.current_shield(state, unit)
	_shield_row.visible = shield_value > 0
	if shield_value <= 0:
		_shield_bar.value = 0.0
		_shield_text.text = ""
		return
	var shield_max := maxi(unit.max_hp, shield_value)
	_shield_bar.max_value = float(shield_max)
	_shield_bar.value = float(shield_value)
	_shield_text.text = str(shield_value)
	_shield_row.tooltip_text = "护盾 %d" % shield_value


func _clear_inspect_header(title: String) -> void:
	_portrait.texture = null
	_portrait.self_modulate = Color.WHITE
	_inspect_name.text = title
	_hp_bar.max_value = 1.0
	_hp_bar.value = 0.0
	_hp_text.text = ""
	_shield_row.visible = false
	_shield_bar.value = 0.0
	_shield_text.text = ""
	while _inspect_status_row.get_child_count() > 0:
		_inspect_status_row.get_child(0).free()


func _create_slot_chip(state: GameState, unit: UnitState, slot: SlotState, slot_index: int) -> Control:
	var chip := PanelContainer.new()
	var color := UnitLooks.slot_color(slot.slot_type)
	var gem: GemState = null
	if not slot.gem_uid.is_empty():
		gem = state.gems.get(slot.gem_uid, null)
		if gem != null:
			color = UnitLooks.gem_color(gem)
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
		chip.tooltip_text = "%s槽：分裂已失效" % display_name
	elif slot.locked:
		label.text = "%s 🔒" % slot_prefix
		chip.tooltip_text = "%s槽：锁定" % display_name
	elif slot.gem_uid.is_empty():
		label.text = "%s 空" % slot_prefix
		var tip := "%s槽：空" % display_name
		if is_dual:
			tip += "（双色槽，可嵌入%s或%s宝石）" % [slot_name, dual_name]
		chip.tooltip_text = tip
	else:
		if gem == null:
			label.text = "%s ?" % slot_prefix
			chip.tooltip_text = "%s槽：无宝石数据" % display_name
		else:
			var gem_icon := _make_gem_icon(gem, 14)
			if gem_icon != null:
				row.add_child(gem_icon)
			label.text = "%s %s" % [slot_prefix, DataRegistry.get_gem_display_name(gem)]
			chip.tooltip_text = _slot_chip_tooltip(gem, slot, unit, state)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	row.add_child(label)
	chip.add_child(row)
	return chip


func _make_gem_icon(gem: GemState, size_px: int) -> TextureRect:
	var tex := UnitLooks.get_gem_texture(gem)
	if tex == null:
		return null
	var icon := TextureRect.new()
	icon.texture = tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = UnitLooks.gem_sprite_modulate(gem)
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
	var gem_name: String = DataRegistry.get_gem_display_name(gem)
	var lines: Array[String] = [gem_name]
	var effect: String = GemEffects.get_slot_effect_description(gem, slot.slot_type, _slot_effect_context(unit, slot))
	if not effect.is_empty():
		lines.append(effect)
	if state != null:
		var ctx := GemTagResolver.build_context(state, unit, slot.slot_type, GemEffects.TIMING_ACTIVE)
		var tag_levels: Dictionary = ctx.get("tag_levels", {})
		var combo_levels: Dictionary = ctx.get("combo_levels", {})
		if not tag_levels.is_empty():
			for tag in tag_levels.keys():
				var lvl := int(tag_levels[tag])
				if lvl <= 0:
					continue
				var level_key := "gem.level.%s.%d" % [str(tag), lvl]
				var level_desc: String = TranslationServer.translate(level_key)
				if level_desc != level_key:
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
	return "\n".join(lines)


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
	_extract_btn.text = "拔出" if _controller.can_use_action(Constants.ACTION_EXTRACT) else "拔出×"
	_insert_btn.text = "嵌入" if _controller.can_use_action(Constants.ACTION_INSERT) else "嵌入×"


func _refresh_turn_queue(state: GameState, active_uid: String, timeline_hover_uid: String, enemy_phase_running: bool) -> void:
	for child in _queue_row.get_children():
		child.queue_free()
	var focus_uid := timeline_hover_uid if not timeline_hover_uid.is_empty() else active_uid
	var active_unit: UnitState = state.units.get(active_uid, null)
	if active_unit != null:
		var active_name: String = DataRegistry.get_unit_display_name(active_unit.unit_def_id)
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
	var unit_name: String = DataRegistry.get_unit_display_name(unit.unit_def_id)
	root.tooltip_text = "%s\nHP %d/%d · 速 %d" % [unit_name, unit.hp, unit.max_hp, unit.speed]
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
	icon.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	icon.self_modulate = UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
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
	if _inspect_stats != null:
		_inspect_stats.visible = not compact
	if _turn_chips != null:
		_turn_chips.visible = not compact
	if _held_label != null and compact:
		_held_label.visible = not _held_label.text.is_empty()


func _refresh_relic_bar() -> void:
	if _relic_bar_vbox == null or _relic_bar_scroll == null:
		return
	var owned: Array[String] = []
	if RunService.is_run_active():
		owned = _string_array_from(RunService.get_owned_relics())
	var ids_changed := owned != _relic_bar_ids
	if ids_changed:
		_relic_bar_ids = owned.duplicate()
		for child in _relic_bar_vbox.get_children():
			child.queue_free()
		for relic_id in owned:
			_relic_bar_vbox.add_child(_create_relic_badge(relic_id))
	var has_relics := not owned.is_empty()
	if _relic_bar_root != null:
		_relic_bar_root.visible = has_relics
	_relic_bar_scroll.visible = has_relics
	if not has_relics:
		_relic_bar_scroll.custom_minimum_size = Vector2(0, 0)
		return
	var item_h := 36.0
	var gap := 4.0
	var content_h := owned.size() * item_h + maxi(owned.size() - 1, 0) * gap
	var max_h := 180.0
	_relic_bar_scroll.custom_minimum_size = Vector2(_STATUS_PANEL_WIDTH - 8.0, minf(content_h, max_h))


func _string_array_from(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values:
			result.append(str(value))
	return result


func _create_relic_badge(relic_id: String) -> Control:
	var def: Dictionary = DataRegistry.get_relic_def(relic_id)
	var rarity: String = DataRegistry.get_relic_rarity(relic_id)
	var rarity_col := rarity_color(rarity)
	var root := HBoxContainer.new()
	root.custom_minimum_size = Vector2(_STATUS_PANEL_WIDTH - 16.0, 36.0)
	root.add_theme_constant_override("separation", 8)
	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = rarity_col
		root.add_child(icon)
	var name_lbl := Label.new()
	name_lbl.text = str(def.get("name", relic_id))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", rarity_col)
	root.add_child(name_lbl)
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _show_relic_detail_cb.is_valid():
		click_btn.pressed.connect(_show_relic_detail_cb.bind(relic_id))
	root.add_child(click_btn)
	var badge_tooltip: String = str(def.get("name", relic_id)) + "\n" + relic_desc_text(def)
	root.tooltip_text = badge_tooltip
	return root


func relic_desc_text(def: Dictionary) -> String:
	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		return desc
	return "（暂无描述）"


func _overload_summary_text(state: GameState) -> String:
	if state == null:
		return ""
	var active_count: int = state.overload_active_mutations.size()
	if not state.overload_pending and active_count <= 0:
		return ""
	if state.overload_pending:
		return "过载层数 %d + 待生效 1" % active_count
	return "过载层数 %d" % active_count


func _status_stack_lines(unit: UnitState) -> Array[String]:
	var lines: Array[String] = []
	for status in unit.statuses:
		if status == null or status.stacks <= 1:
			continue
		lines.append("%s×%d" % [StatusUi._StatusRegistry.display_name(status.status_id), status.stacks])
	return lines


func rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color("#c8cad4")
		"rare":
			return Color("#6ec6f5")
		"epic":
			return Color("#c77dff")
		"boss":
			return Color("#ff8a5b")
	return Color("#9aa0ad")


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_corner_radius_all(4)
	return box
