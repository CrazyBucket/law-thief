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
var _slot_box: HBoxContainer = null
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
var _held_label: Label = null
var _held_gem_icon: TextureRect = null
var _hint_label: Label = null
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
var _relic_bar_vbox: HFlowContainer = null

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
	_held_label = deps.get("held_label", null)
	_held_gem_icon = deps.get("held_gem_icon", null)
	_hint_label = deps.get("hint_label", null)
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
	match state.phase:
		Constants.PHASE_PLAYER:
			var queue_suffix := ""
			if not state.controllable_queue.is_empty():
				var total := 1 + state.controllable_queue.size()
				var current := total - state.controllable_queue.size()
				queue_suffix = " · %d/%d" % [current, total]
			_phase_badge.text = "你的回合" + turn_suffix + queue_suffix
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_PLAYER)
		Constants.PHASE_ENDED:
			_phase_badge.text = "战斗结束" + turn_suffix
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_END)
		_:
			_phase_badge.text = "敌方回合" + turn_suffix
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_ENEMY)

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
	_hint_label.text = tutorial_hint
	if not tutorial_hint.is_empty():
		_message_label.text = tutorial_hint.split("\n")[0]
	elif _message_label.text.is_empty():
		_message_label.text = _controller.get_action_hint()

	var active_turn_uid := _get_active_turn_uid(state, enemy_phase_running, enemy_turn_queue)
	_refresh_turn_queue(state, active_turn_uid, timeline_hover_uid, enemy_phase_running)
	_refresh_inspect(state, inspect_uid)
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
	if _relic_bar_scroll != null:
		_relic_bar_scroll.custom_minimum_size.x = inner_w


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
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		stat_parts.append(unit.intent.preview_text)
	_inspect_stats.text = "\n".join(stat_parts)
	for slot in unit.slots:
		_slot_box.add_child(_create_slot_chip(state, unit, slot))


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


func _create_slot_chip(state: GameState, unit: UnitState, slot: SlotState) -> Control:
	var chip := PanelContainer.new()
	var color := UnitLooks.slot_color(slot.slot_type)
	var gem: GemState = null
	if not slot.gem_uid.is_empty():
		gem = state.gems.get(slot.gem_uid, null)
		if gem != null:
			color = UnitLooks.gem_color(gem)
	chip.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(color))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	var slot_name := _slot_display_name(slot.slot_type)
	var is_dual := not slot.dual_type.is_empty()
	var dual_name := _slot_display_name(slot.dual_type) if is_dual else ""
	var display_name := ("%s/%s" % [slot_name, dual_name]) if is_dual else slot_name
	if slot.is_split_disabled():
		label.text = "%s×" % display_name
		chip.tooltip_text = "%s槽：分裂已失效" % display_name
	elif slot.locked:
		label.text = "%s🔒" % display_name
		chip.tooltip_text = "%s槽：锁定" % display_name
	elif slot.gem_uid.is_empty():
		label.text = "%s○" % display_name
		var tip := "%s槽：空" % display_name
		if is_dual:
			tip += "（双色槽，可嵌入%s或%s宝石）" % [slot_name, dual_name]
		chip.tooltip_text = tip
	else:
		if gem == null:
			label.text = "%s?" % display_name
			chip.tooltip_text = "%s槽：无宝石数据" % display_name
		else:
			var gem_icon := _make_gem_icon(gem, 14)
			if gem_icon != null:
				row.add_child(gem_icon)
			label.text = display_name
			chip.tooltip_text = _slot_chip_tooltip(gem, slot, unit)
	label.add_theme_font_size_override("font_size", 11)
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


func _slot_chip_tooltip(gem: GemState, slot: SlotState, unit: UnitState) -> String:
	var gem_name: String = DataRegistry.get_gem_display_name(gem)
	var effect: String = GemEffects.get_slot_effect_description(gem, slot.slot_type, _slot_effect_context(unit, slot))
	if effect.is_empty():
		return gem_name
	return "%s\n%s" % [gem_name, effect]


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
	root.custom_minimum_size = Vector2(58, 76)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(44, 44)
	var team_color := BattleUiTheme.PHASE_PLAYER if unit.team == Constants.TEAM_PLAYER else BattleUiTheme.PHASE_ENEMY
	var accent := BattleUiTheme.BORDER
	if is_hovered:
		accent = BattleUiTheme.TEXT_GOLD
	elif is_active:
		accent = team_color
	frame.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent))
	stack.add_child(frame)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	icon.self_modulate = UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	frame.add_child(icon)
	if is_active:
		var arrow := Label.new()
		arrow.text = "▼"
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 12)
		arrow.add_theme_color_override("font_color", team_color)
		stack.add_child(arrow)
	var hp_label := Label.new()
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.text = "%d/%d" % [unit.hp, unit.max_hp]
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	stack.add_child(hp_label)
	var speed_label := Label.new()
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.text = "%d" % unit.speed
	speed_label.add_theme_font_size_override("font_size", 10)
	speed_label.add_theme_color_override(
		"font_color",
		team_color if is_active else (BattleUiTheme.TEXT_GOLD if is_hovered else BattleUiTheme.TEXT_MUTED)
	)
	stack.add_child(speed_label)
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


func _refresh_relic_bar() -> void:
	if _relic_bar_vbox == null or _relic_bar_scroll == null:
		return
	var owned: Array[String] = _string_array_from(RunService.get_owned_relics()) if RunService.is_run_active() else []
	var ids_changed := owned != _relic_bar_ids
	if ids_changed:
		_relic_bar_ids = owned.duplicate()
		for child in _relic_bar_vbox.get_children():
			child.queue_free()
		for relic_id in owned:
			_relic_bar_vbox.add_child(_create_relic_badge(relic_id))
	_relic_bar_scroll.visible = not owned.is_empty()
	if owned.is_empty():
		_relic_bar_scroll.custom_minimum_size = Vector2(0, 0)
		return
	var inner_w := _status_vbox.custom_minimum_size.x
	if inner_w <= 0.0:
		inner_w = _STATUS_PANEL_WIDTH - _status_panel_content_margins().x
	_relic_bar_scroll.custom_minimum_size.x = inner_w
	var content_h := _relic_bar_vbox.get_minimum_size().y
	var max_h := 92.0
	_relic_bar_scroll.custom_minimum_size.y = minf(content_h, max_h)


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
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(40, 40)
	var style := StyleBoxFlat.new()
	style.bg_color = rarity_col.darkened(0.55)
	style.border_color = rarity_col
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(3)
	badge.add_theme_stylebox_override("panel", style)
	var name_str: String = str(def.get("name", relic_id))
	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.add_child(icon)
	var badge_tooltip: String = name_str + "\n" + relic_desc_text(def)
	badge.tooltip_text = badge_tooltip
	return badge


func relic_desc_text(def: Dictionary) -> String:
	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		return desc
	return "（暂无描述）"


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
